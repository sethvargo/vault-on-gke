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

# Write the secret
resource "kubernetes_secret" "vault-tls" {
  metadata {
    name = "vault-tls"
  }

  data {
    "vault.crt" = "${tls_locally_signed_cert.vault.cert_pem}\n${tls_self_signed_cert.vault-ca.cert_pem}"
    "vault.key" = "${tls_private_key.vault.private_key_pem}"
    "ca.crt"    = "${tls_self_signed_cert.vault-ca.cert_pem}"
  }
}

# Create the StatefulSet

resource "kubernetes_stateful_set" "vault" {
  metadata {
    labels {
      app = "vault"
    }
    name = "vault"
  }

  spec {
    replicas = "${var.num_vault_pods}"

    selector {
      match_labels {
        app = "vault"
      }
    }

    service_name = "vault"

    template {
      metadata {
        labels {
          app = "vault"
        }
      }

      spec {
        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              pod_affinity_term {
                label_selector {
                  matchExpressions = [{
                    key      = "app",
                    operator = "In",
                    values   = ["vault"]
                  }]
                }
                topology_key = "kubernetes.io/hostname"
              }
              weight = 60
            }
          }
        }
        init_container {
          name              = "vault-init"
          image             = "${var.vault_init_container}"
          image_pull_policy = "IfNotPresent"
          env {
            name  = "GCS_BUCKET_NAME"
            value = "${google_storage_bucket.vault.name}"
          }
          env {
            name  = "KMS_KEY_ID"
            value = "projects/${google_kms_key_ring.vault.project}/locations/${google_kms_key_ring.vault.location}/keyRings/${google_kms_key_ring.vault.name}/cryptoKeys/${google_kms_crypto_key.vault-init.name}"
          }
          env {
            name  = "VAULT_ADDR"
            value = "http://127.0.0.1:8200"
          }
          env {
            name  = "VAULT_SECRET_SHARES"
            value = "${var.vault_recovery_shares}"
          }
          env {
            name  = "VAULT_SECRET_THRESHOLD"
            value = "${var.vault_recovery_threshold}"
          }
          resources {
            requests {
              cpu    = "100m"
              memory = "64Mi"
            }
          }
        }

        container {
          name              = "vault"
          image             = "${var.vault_container}"
          image_pull_policy = "IfNotPresent"

          args = ["server"]

          env {
            name  = "VAULT_ADDR"
            value = "http://127.0.0.1:8200"
          }
          env {
            name = "POD_IP_ADDR"
            value_from {
              field_ref {
                field_path = "status.podIP"
              }
            }
          }
          env {
            name  = "VAULT_LOCAL_CONFIG"
            value = file("k8s/vault-local-config.tf")
          }
          port {
            container_port = 8200
            name           = "vault-port"
          }
          port {
            container_port = 8201
            name           = "cluster-port"
          }
          volume_mount {
            name       = "vault-tls"
            mount_path = "/etc/vault/tls"
          }
          security_context {
            capabilities {
              add = ["IPC_LOCK"]
            }
          }
          resources {
            requests {
              cpu    = "500m"
              memory = "256Mi"
            }
          }
          readiness_probe {
            http_get {
              path = "/v1/sys/health?standbyok=true"
              port = 8200
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "vault-tls"

          secret {
            secret_name = "vault-tls"
          }
        }
      }
    }
  }
}

# Create the Service

resource "kubernetes_service" "vault" {
  metadata {
    name = "vault"
    labels {
      app = "vault"
    }
  }
  spec {
    selector {
      app = "vault"
    }
    external_traffic_policy = "local"
    port {
      port = 443
      target_port = 8200
    }

    load_balancer_ip = "${google_compute_address.vault.address}"
    type = "LoadBalancer"
  }
}

# Build the URL for the keys on GCS
data "google_storage_object_signed_url" "keys" {
  bucket = "${google_storage_bucket.vault.name}"
  path   = "root-token.enc"

  credentials = "${base64decode(google_service_account_key.vault.private_key)}"

  depends_on = ["null_resource.wait-for-finish"]
}

# Download the encrypted recovery unseal keys and initial root token from GCS
data "http" "keys" {
  url = "${data.google_storage_object_signed_url.keys.signed_url}"
}

# Decrypt the values
data "google_kms_secret" "keys" {
  crypto_key = "${google_kms_crypto_key.vault-init.id}"
  ciphertext = "${data.http.keys.body}"
}

# Output the initial root token
output "root_token" {
  value = "${data.google_kms_secret.keys.plaintext}"
}

# Uncomment this if you want to decrypt the token yourself
# output "root_token_decrypt_command" {
#   value = "gsutil cat gs://${google_storage_bucket.vault.name}/root-token.enc | base64 --decode | gcloud kms decrypt --project ${local.vault_project_id} --location ${var.region} --keyring ${google_kms_key_ring.vault.name} --key ${google_kms_crypto_key.vault-init.name} --ciphertext-file - --plaintext-file -"
# }

