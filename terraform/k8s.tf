# Query the client configuration for our current service account, which shoudl
# have permission to talk to the GKE cluster since it created it.
data "google_client_config" "current" {
}

# This file contains all the interactions with Kubernetes
provider "kubernetes" {
  load_config_file = false
  host             = google_container_cluster.vault.endpoint

  cluster_ca_certificate = base64decode(
    google_container_cluster.vault.master_auth[0].cluster_ca_certificate,
  )
  token = data.google_client_config.current.access_token
}

# Write the secret
resource "kubernetes_secret" "vault-tls" {
  metadata {
    name = "vault-tls"
  }

  data = {
    "vault.crt" = "${tls_locally_signed_cert.vault.cert_pem}\n${tls_self_signed_cert.vault-ca.cert_pem}"
    "vault.key" = tls_private_key.vault.private_key_pem
    "ca.crt"    = tls_self_signed_cert.vault-ca.cert_pem
  }
}

# Render the YAML file
data "template_file" "vault" {
  template = file("${path.module}/../k8s/vault.yaml")

  vars = {
    load_balancer_ip         = google_compute_address.vault.address
    num_vault_pods           = var.num_vault_pods
    vault_container          = var.vault_container
    vault_init_container     = var.vault_init_container
    vault_recovery_shares    = var.vault_recovery_shares
    vault_recovery_threshold = var.vault_recovery_threshold
    project                  = google_kms_key_ring.vault.project
    kms_region               = google_kms_key_ring.vault.location
    kms_key_ring             = google_kms_key_ring.vault.name
    kms_crypto_key           = google_kms_crypto_key.vault-init.name
    gcs_bucket_name          = google_storage_bucket.vault.name
  }
}

# Submit the job - Terraform doesn't yet support StatefulSets, so we have to
# shell out.
resource "null_resource" "apply" {
  triggers = {
    host = md5(google_container_cluster.vault.endpoint)
    client_certificate = md5(
      google_container_cluster.vault.master_auth[0].client_certificate,
    )
    client_key = md5(google_container_cluster.vault.master_auth[0].client_key)
    cluster_ca_certificate = md5(
      google_container_cluster.vault.master_auth[0].cluster_ca_certificate,
    )
  }

  depends_on = [kubernetes_secret.vault-tls]

  provisioner "local-exec" {
    command = <<EOF
gcloud container clusters get-credentials "${google_container_cluster.vault.name}" --region="${google_container_cluster.vault.region}" --project="${google_container_cluster.vault.project}"

CONTEXT="gke_${google_container_cluster.vault.project}_${google_container_cluster.vault.region}_${google_container_cluster.vault.name}"
echo '${data.template_file.vault.rendered}' | kubectl apply -n default --context="$CONTEXT" -f -
EOF

  }
}

# Wait for all the servers to be ready
resource "null_resource" "wait-for-finish" {
  provisioner "local-exec" {
    command = <<EOF
for i in $(seq -s " " 1 15); do
  sleep $i
  if [ $(kubectl get pod -n default | grep vault | wc -l) -eq ${var.num_vault_pods} ]; then
    exit 0
  fi
done

echo "Pods are not ready after 2m"
exit 1
EOF

}

depends_on = [null_resource.apply]
}

# Build the URL for the keys on GCS
data "google_storage_object_signed_url" "keys" {
bucket = google_storage_bucket.vault.name
path   = "root-token.enc"

credentials = base64decode(google_service_account_key.vault.private_key)

depends_on = [null_resource.wait-for-finish]
}

# Download the encrypted recovery unseal keys and initial root token from GCS
data "http" "keys" {
  url = data.google_storage_object_signed_url.keys.signed_url
}

# Decrypt the values
data "google_kms_secret" "keys" {
  crypto_key = google_kms_crypto_key.vault-init.id
  ciphertext = data.http.keys.body
}

# Output the initial root token
output "root_token" {
  value = data.google_kms_secret.keys.plaintext
}

# Uncomment this if you want to decrypt the token yourself
# output "root_token_decrypt_command" {
#   value = "gsutil cat gs://${google_storage_bucket.vault.name}/root-token.enc | base64 --decode | gcloud kms decrypt --project ${local.vault_project_id} --location ${var.region} --keyring ${google_kms_key_ring.vault.name} --key ${google_kms_crypto_key.vault-init.name} --ciphertext-file - --plaintext-file -"
# }
