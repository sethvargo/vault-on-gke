# Query the client configuration for our current service account, which should
# have permission to talk to the GKE cluster since it created it.
data "google_client_config" "current" {}

# This file contains all the interactions with Kubernetes
provider "kubernetes" {
  host = google_container_cluster.vault.endpoint

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

resource "kubernetes_service_account" "vault-server" {
  metadata {
    name = "vault-server"
  }
}

resource "kubernetes_role" "vault-server" {
  metadata {
    name = "vault-server"
  }

  rule {
    api_groups     = [""]
    resources      = ["pods"]
    resource_names = [for i in range(var.num_vault_pods) : "vault-${i}"]
    verbs          = ["get", "patch", "update"]
  }
}

resource "kubernetes_role_binding" "vault-server" {
  metadata {
    name = "vault-server"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.vault-server.metadata.0.name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.vault-server.metadata.0.name
    namespace = kubernetes_service_account.vault-server.metadata.0.namespace
  }
}

resource "kubernetes_service" "vault-lb" {
  metadata {
    name = "vault"
    labels = {
      app = "vault"
    }
  }

  spec {
    type                        = "LoadBalancer"
    load_balancer_ip            = google_compute_address.vault.address
    load_balancer_source_ranges = var.vault_source_ranges
    external_traffic_policy     = "Local"

    selector = {
      app          = "vault"
      vault-active = "true"
    }

    port {
      name        = "vault-port"
      port        = 443
      target_port = 8200
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_stateful_set" "vault" {
  metadata {
    name = "vault"
    labels = {
      app = "vault"
    }
  }

  spec {
    service_name = "vault"
    replicas     = var.num_vault_pods

    selector {
      match_labels = {
        app = "vault"
      }
    }

    template {
      metadata {
        labels = {
          app = "vault"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.vault-server.metadata.0.name

        termination_grace_period_seconds = 10

        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 50

              pod_affinity_term {
                topology_key = "kubernetes.io/hostname"

                label_selector {
                  match_expressions {
                    key      = "app"
                    operator = "In"
                    values   = ["vault"]
                  }
                }
              }
            }
          }
        }

        container {
          name              = "vault-init"
          image             = var.vault_init_container
          image_pull_policy = "IfNotPresent"

          resources {
            requests = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }

          env {
            name  = "GCS_BUCKET_NAME"
            value = google_storage_bucket.vault.name
          }

          env {
            name  = "KMS_KEY_ID"
            value = google_kms_crypto_key.vault-init.self_link
          }

          env {
            name  = "VAULT_ADDR"
            value = "http://127.0.0.1:8200"
          }

          env {
            name  = "VAULT_SECRET_SHARES"
            value = var.vault_recovery_shares
          }

          env {
            name  = "VAULT_SECRET_THRESHOLD"
            value = var.vault_recovery_threshold
          }
        }

        container {
          name              = "vault"
          image             = var.vault_container
          image_pull_policy = "IfNotPresent"

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
            requests = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }

          volume_mount {
            name       = "vault-tls"
            mount_path = "/etc/vault/tls"
          }

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
            name = "VAULT_K8S_POD_NAME"
            value_from {
              field_ref {
                api_version = "v1"
                field_path  = "metadata.name"
              }
            }
          }

          env {
            name = "VAULT_K8S_NAMESPACE"
            value_from {
              field_ref {
                api_version = "v1"
                field_path  = "metadata.namespace"
              }
            }
          }

          env {
            name  = "VAULT_LOCAL_CONFIG"
            value = <<EOF
              api_addr     = "https://${google_compute_address.vault.address}"
              cluster_addr = "https://$(POD_IP_ADDR):8201"

              service_registration "kubernetes" {}

              log_level = "warn"

              ui = true

              seal "gcpckms" {
                project    = "${google_kms_key_ring.vault.project}"
                region     = "${google_kms_key_ring.vault.location}"
                key_ring   = "${google_kms_key_ring.vault.name}"
                crypto_key = "${google_kms_crypto_key.vault-init.name}"
              }

              storage "gcs" {
                bucket     = "${google_storage_bucket.vault.name}"
                ha_enabled = "true"
              }

              listener "tcp" {
                address     = "127.0.0.1:8200"
                tls_disable = "true"
              }

              listener "tcp" {
                address       = "$(POD_IP_ADDR):8200"
                tls_cert_file = "/etc/vault/tls/vault.crt"
                tls_key_file  = "/etc/vault/tls/vault.key"

                tls_disable_client_certs = true
              }
            EOF
          }

          readiness_probe {
            initial_delay_seconds = 5
            period_seconds        = 5

            http_get {
              path   = "/v1/sys/health?standbyok=true"
              port   = 8200
              scheme = "HTTPS"
            }
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

output "root_token_decrypt_command" {
  value = "gsutil cat gs://${google_storage_bucket.vault.name}/root-token.enc | base64 --decode | gcloud kms decrypt --key ${google_kms_crypto_key.vault-init.self_link} --ciphertext-file - --plaintext-file -"
}
