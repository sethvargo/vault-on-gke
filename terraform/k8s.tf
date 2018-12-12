# Query the client configuration for our current service account, which shoudl
# have permission to talk to the GKE cluster since it created it.
data "google_client_config" "current" {}

# This file contains all the interactions with Kubernetes
provider "kubernetes" {
  load_config_file = false
  host             = "${google_container_cluster.vault.endpoint}"

  cluster_ca_certificate = "${base64decode(google_container_cluster.vault.master_auth.0.cluster_ca_certificate)}"
  token                  = "${data.google_client_config.current.access_token}"
}

# Write the internal secret
resource "kubernetes_secret" "vault-internal-tls" {
  metadata {
    name = "vault-internal-tls"
  }

  data {
    "vault_internal.crt" = "${tls_locally_signed_cert.vault_internal.cert_pem}\n${tls_self_signed_cert.vault-ca.cert_pem}"
    "vault_internal.key" = "${tls_private_key.vault_internal.private_key_pem}"
  }
}

# Write the external secret
# The GCLB expects the secret data names to be "tls.crt" and "tls.key"
resource "kubernetes_secret" "vault-external-tls" {
  metadata {
    name = "vault-external-tls"
  }

  data {
    "tls.crt" = "${tls_locally_signed_cert.vault_external.cert_pem}\n${tls_self_signed_cert.vault-ca.cert_pem}"
    "tls.key" = "${tls_private_key.vault_external.private_key_pem}"
  }
}

# Render the YAML file
data "template_file" "vault" {
  template = "${file("${path.module}/../k8s/vault.yaml")}"

  vars {
    load_balancer_ip     = "${google_compute_global_address.vault.address}"
    static_ip_name       = "${google_compute_global_address.vault.name}"
    num_vault_pods       = "${var.num_vault_pods}"
    vault_container      = "${var.vault_container}"
    vault_init_container = "${var.vault_init_container}"

    project = "${google_kms_key_ring.vault.project}"

    kms_region     = "${google_kms_key_ring.vault.location}"
    kms_key_ring   = "${google_kms_key_ring.vault.name}"
    kms_crypto_key = "${google_kms_crypto_key.vault-init.name}"

    gcs_bucket_name = "${google_storage_bucket.vault.name}"
  }
}

# Submit the job - Terraform doesn't yet support StatefulSets, so we have to
# shell out.
resource "null_resource" "apply" {
  triggers {
    host                   = "${md5(google_container_cluster.vault.endpoint)}"
  }

  depends_on = [
    "kubernetes_secret.vault-internal-tls",
    "kubernetes_secret.vault-external-tls",
  ]

  provisioner "local-exec" {
    command = <<EOF
gcloud container clusters get-credentials "${google_container_cluster.vault.name}" --region="${google_container_cluster.vault.region}" --project="${google_container_cluster.vault.project}"

CONTEXT="gke_${google_container_cluster.vault.project}_${google_container_cluster.vault.region}_${google_container_cluster.vault.name}"
echo '${data.template_file.vault.rendered}' | kubectl apply --context="$CONTEXT" -f -
EOF
  }
}

# Wait for the Load Balancer and Pods to be ready
resource "null_resource" "wait-for-finish" {
  provisioner "local-exec" {
    command = <<EOF
for i in $(seq -s " " 1 40); do
  sleep $i
  curl -s --cacert ../tls/ca.pem https://${google_compute_global_address.vault.address}/v1/sys/health
  if [[ $? -eq 0 ]]; then
    exit 0
  fi
done

echo "Vault pods and load balancer are not ready after 14m"
exit 1
EOF
  }
  depends_on = ["null_resource.apply"]
}

# Download the encrypted root token to disk
data "google_storage_object_signed_url" "root-token" {
  bucket = "${google_storage_bucket.vault.name}"
  path   = "root-token.enc"

  credentials = "${base64decode(google_service_account_key.vault.private_key)}"
}

# Download the encrypted file
data "http" "root-token" {
  url = "${data.google_storage_object_signed_url.root-token.signed_url}"

  depends_on = ["null_resource.wait-for-finish"]
}

# Decrypt the secret
data "google_kms_secret" "root-token" {
  crypto_key = "${google_kms_crypto_key.vault-init.id}"
  ciphertext = "${data.http.root-token.body}"
}

output "token" {
  value = "${data.google_kms_secret.root-token.plaintext}"
}

# Uncomment this if you want to decrypt the token yourself
# output "token_decrypt_command" {
#   value = "gsutil cat gs://${google_storage_bucket.vault.name}/root-token.enc | base64 --decode | gcloud kms decrypt --project ${google_project.vault.project_id} --location ${var.region} --keyring ${google_kms_key_ring.vault.name} --key ${google_kms_crypto_key.vault-init.name} --ciphertext-file - --plaintext-file -"
# }

