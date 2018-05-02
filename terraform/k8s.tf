# This file contains all the interactions with Kubernetes
provider "kubernetes" {
  host     = "${google_container_cluster.vault.endpoint}"
  username = "${google_container_cluster.vault.master_auth.0.username}"
  password = "${google_container_cluster.vault.master_auth.0.password}"

  client_certificate     = "${base64decode(google_container_cluster.vault.master_auth.0.client_certificate)}"
  client_key             = "${base64decode(google_container_cluster.vault.master_auth.0.client_key)}"
  cluster_ca_certificate = "${base64decode(google_container_cluster.vault.master_auth.0.cluster_ca_certificate)}"
}

# Write the secret
resource "kubernetes_secret" "vault-tls" {
  metadata {
    name = "vault-tls"
  }

  data {
    "vault.crt" = "${tls_locally_signed_cert.vault.cert_pem}\n${tls_self_signed_cert.vault-ca.cert_pem}"
    "vault.key" = "${tls_private_key.vault.private_key_pem}"
  }
}

# Write the configmap
resource "kubernetes_config_map" "vault" {
  metadata {
    name = "vault"
  }

  data {
    load_balancer_address = "${google_compute_address.vault.address}"
    gcs_bucket_name       = "${google_storage_bucket.vault.name}"
    kms_key_id            = "${google_kms_crypto_key.vault-init.id}"
  }
}

# Render the YAML file
data "template_file" "vault" {
  template = "${file("${path.module}/../k8s/vault.yaml")}"

  vars {
    load_balancer_ip = "${google_compute_address.vault.address}"
  }
}

# Submit the job
resource "null_resource" "apply" {
  triggers {
    host                   = "${google_container_cluster.vault.endpoint}"
    username               = "${google_container_cluster.vault.master_auth.0.username}"
    password               = "${google_container_cluster.vault.master_auth.0.password}"
    client_certificate     = "${base64decode(google_container_cluster.vault.master_auth.0.client_certificate)}"
    client_key             = "${base64decode(google_container_cluster.vault.master_auth.0.client_key)}"
    cluster_ca_certificate = "${base64decode(google_container_cluster.vault.master_auth.0.cluster_ca_certificate)}"
  }

  provisioner "local-exec" {
    command = <<EOF
gcloud container clusters get-credentials "${google_container_cluster.vault.name}" --zone="${google_container_cluster.vault.zone}" --project="${google_container_cluster.vault.project}"
kubectl config set-context "gke_${google_container_cluster.vault.project}_${google_container_cluster.vault.zone}_${google_container_cluster.vault.name}"

echo '${data.template_file.vault.rendered}' | kubectl apply -f -
EOF
  }
}

resource "null_resource" "wait-for-finish" {
  provisioner "local-exec" {
    command = <<EOF
for i in {1..5}; do
  sleep $i
  if [ $(kubectl get pod | grep vault | wc -l) -eq 5 ]; then
    exit 0
  fi
done

echo "Pods are not ready after 15s"
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

output "token_decrypt_command" {
  value = "gsutil cat gs://${google_storage_bucket.vault.name}/root-token.enc | base64 --decode | gcloud kms decrypt --project ${google_project.vault.project_id} --location ${var.region} --keyring ${google_kms_key_ring.vault.name} --key ${google_kms_crypto_key.vault-init.name} --ciphertext-file - --plaintext-file -"
}
