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
  }
}

# Create the service
resource "kubernetes_service" "vault-lb" {
  metadata {
    name = "vault"

    labels {
      app = "vault"
    }
  }

  spec {
    type             = "LoadBalancer"
    load_balancer_ip = "${google_compute_address.vault.address}"

    selector {
      app = "vault"
    }

    port {
      name        = "vault-https"
      port        = 443
      target_port = 8200
      protocol    = "TCP"
    }
  }
}

# Deploy stateful set
resource "kubernetes_stateful_set" "vault" {
  metadata {
    name = "vault"

    labels {
      app = "vault"
    }
  }

  spec {
    service_name = "vault"
    replicas     = "${var.num_vault_servers}"

    selector {
      match_labels {
        app = "vault"
      }
    }

    template {
      metadata {
        labels {
          app = "vault"
        }
      }

      spec {
        termination_grace_period_seconds = 10

        volume {
          name = "vault-tls"

          secret {
            secret_name = "vault-tls"
          }
        }

        # vault-init container
        container {
          name              = "vault-init"
          image             = "sethvargo/vault-init:0.1.1"
          image_pull_policy = "Always"

          resources {
            requests {
              cpu    = "100m"
              memory = "64Mi"
            }
          }

          env {
            name  = "CHECK_INTERVAL"
            value = "30"
          }

          env {
            name  = "GCS_BUCKET_NAME"
            value = "${google_storage_bucket.vault.name}"
          }

          env {
            name  = "KMS_KEY_ID"
            value = "${google_kms_crypto_key.vault-init.id}"
          }
        }

        # vault container
        container {
          name              = "vault"
          image             = "vault:0.11.4"
          image_pull_policy = "Always"

          args = ["server"]

          security_context {
            capabilities {
              add = ["IPC_LOCK"]
            }
          }

          port {
            name           = "vault-port"
            container_port = 8200
            protocol       = "TCP"
          }

          port {
            name           = "cluster-port"
            container_port = 8201
            protocol       = "TCP"
          }

          resources {
            requests {
              cpu    = "500m"
              memory = "256Mi"
            }
          }

          volume_mount {
            name       = "vault-tls"
            mount_path = "/etc/vault/tls"
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
            name = "VAULT_LOCAL_CONFIG"

            value = <<EOF
api_addr     = "https://${google_compute_address.vault.address}"
cluster_addr = "https://$(POD_IP_ADDR):8201"

ui = true

storage "gcs" {
  bucket     = "${google_storage_bucket.vault.name}"
  ha_enabled = "true"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/etc/vault/tls/vault.crt"
  tls_key_file  = "/etc/vault/tls/vault.key"

  tls_disable_client_certs = true
}
>>>>>>> efa90be... Switch to pure Terraform
EOF
          }

          readiness_probe {
            http_get {
              path   = "/v1/sys/health?standbyok=true"
              port   = 8200
              scheme = "HTTPS"
            }

            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }

        // affinity {
        //   pod_anti_affinity {
        //     required_during_scheduling_ignored_during_execution {
        //       topology_key = "kubernetes.io/hostname"
        //
        //       label_selector {
        //         match_expression {
        //           key      = "app"
        //           operator = "In"
        //           values   = ["vault"]
        //         }
        //       }
        //     }
        //   }
        // }
      }
    }

    update_strategy {
      type = "RollingUpdate"

      rolling_update {
        partition = 1
      }
    }
  }
}

# Download the encrypted root token to disk
data "google_storage_object_signed_url" "root-token" {
  bucket = "${google_storage_bucket.vault.name}"
  path   = "root-token.enc"

  credentials = "${base64decode(google_service_account_key.vault.private_key)}"

  depends_on = ["kubernetes_stateful_set.vault"]
}

# Download the encrypted file
data "http" "root-token" {
  url = "${data.google_storage_object_signed_url.root-token.signed_url}"
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

