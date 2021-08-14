##############################
# Creating the following from this linked yaml file
# https://github.com/hashicorp/vault-k8s/blob/master/deploy/injector-leader-extras.yaml
# This is to help enable secret injection via sidecar
######################################
resource "kubernetes_endpoints" "vault-agent-injector-leader" {
  depends_on = [kubernetes_namespace.vault]

  metadata {
    name = "vault-agent-injector-leader"
    namespace = var.vault_namespace
  }
}

resource "kubernetes_secret" "vault-injector-certs" {
  depends_on = [kubernetes_namespace.vault]

  metadata {
    name = "vault-injector-certs"
    namespace = var.vault_namespace
  }
}
######################################

######################################
# MutatingWebhookConfiguration
# Creating the following from this linked yaml file
# https://github.com/hashicorp/vault-k8s/blob/master/deploy/injector-mutating-webhook.yaml
# This is to help enable secret injection via sidecar
######################################
resource "kubernetes_mutating_webhook_configuration" "vault-agent-injector-cfg" {
  depends_on = [kubernetes_namespace.vault]

  metadata {
    name = "vault-agent-injector-cfg"
    labels = {
      "app.kubernetes.io/name": "vault-injector"
      "app.kubernetes.io/instance": "vault"
    }
  }

  webhook {
    name = "vault.hashicorp.com"
    side_effects = "None"
    admission_review_versions = ["v1beta1"]

    client_config {
      service {
        namespace = var.vault_namespace
        name      = "vault-agent-injector-svc"
        path      = "/mutate"
      }
      ca_bundle = ""
    }

    rule {
      api_groups   = [""]
      api_versions = ["v1"]
      operations   = ["CREATE", "UPDATE"]
      resources    = ["deployments", "jobs", "pods", "statefulsets"]
    }

    namespace_selector {}
    object_selector {}
    failure_policy = "Ignore"
  }
}
######################################

######################################
# Vault Injector Service Account
# Creating the following from this linked yaml file
# https://github.com/hashicorp/vault-k8s/blob/master/deploy/injector-rbac.yaml
# kubernetes_service_account
# kubernetes_cluster_role
# kubernetes_cluster_role_binding
# kubernetes_role
# kubernetes_role_binding
# This is to help enable secret injection via sidecar
######################################
resource "kubernetes_service_account" "vault-injector" {
  depends_on = [kubernetes_namespace.vault]

  metadata {
    name = "vault-injector"
    namespace = var.vault_namespace
    labels = {
      "app.kubernetes.io/name": "vault-injector"
      "app.kubernetes.io/instance": "vault"
    }
  }
}

resource "kubernetes_cluster_role" "vault-injector-clusterrole" {
  metadata {
    name = "vault-injector-clusterrole"
    labels = {
      "app.kubernetes.io/name": "vault-injector"
      "app.kubernetes.io/instance": "vault"
    }
  }

  rule {
    api_groups = ["admissionregistration.k8s.io"]
    resources  = ["mutatingwebhookconfigurations"]
    verbs      = ["get", "list", "watch", "patch"]
  }
}

resource "kubernetes_cluster_role_binding" "vault-injector-binding" {
  depends_on = [kubernetes_namespace.vault]

  metadata {
    name = "vault-injector-binding"
    labels = {
      "app.kubernetes.io/name": "vault-injector"
      "app.kubernetes.io/instance": "vault"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "vault-injector-clusterrole"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "vault-injector"
    namespace = var.vault_namespace
  }
}

resource "kubernetes_role" "vault-injector-role" {
  depends_on = [kubernetes_namespace.vault]

  metadata {
    name = "vault-injector-role"
    namespace = var.vault_namespace
    labels = {
      "app.kubernetes.io/name": "vault-injector"
      "app.kubernetes.io/instance": "vault"
    }
  }

  rule {
    api_groups     = [""]
    resources      = ["endpoints", "secrets"]
    verbs          = ["create", "get", "watch", "list", "update"]
  }
}

resource "kubernetes_role_binding" "vault-injector-rolebinding" {
  depends_on = [kubernetes_namespace.vault]

  metadata {
    name      = "vault-injector-rolebinding"
    namespace = var.vault_namespace
    labels = {
      "app.kubernetes.io/name": "vault-injector"
      "app.kubernetes.io/instance": "vault"
    }
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "vault-injector-role"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "vault-injector"
    namespace = var.vault_namespace
  }
}
######################################

######################################
# Vault Injector Service
# Creating the following from this linked yaml file
# https://github.com/hashicorp/vault-k8s/blob/master/deploy/injector-service.yaml
######################################
resource "kubernetes_service" "vault-agent-injector-svc" {
  depends_on = [kubernetes_namespace.vault]

  metadata {
    name      = "vault-agent-injector-svc"
    namespace = var.vault_namespace
    labels    = {
      "app.kubernetes.io/name": "vault-injector"
      "app.kubernetes.io/instance": "vault"
    }
  }
  spec {
    selector = {
      "app.kubernetes.io/name": "vault-injector"
      "app.kubernetes.io/instance": "vault"
    }
    port {
      port        = 443
      target_port = 8080
    }
  }
}
######################################

######################################
# Vault Injector Deployment
# Creating the following from this linked yaml file
# https://github.com/hashicorp/vault-k8s/blob/master/deploy/injector-deployment.yaml
######################################
resource "kubernetes_deployment" "vault-injector" {
  depends_on = [kubernetes_namespace.vault]

  metadata {
    name = "vault-injector"
    namespace = var.vault_namespace
    labels = {
      "app.kubernetes.io/name": "vault-injector"
      "app.kubernetes.io/instance": "vault"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        "app.kubernetes.io/name": "vault-injector"
        "app.kubernetes.io/instance": "vault"
      }
    }

    template {
      metadata {
        namespace = var.vault_namespace
        
        labels = {
          "app.kubernetes.io/name": "vault-injector"
          "app.kubernetes.io/instance": "vault"
        }
      }

      spec {
        service_account_name = "vault-injector"
        container {
          image = "k8s.gcr.io/leader-elector:0.4"
          name  = "leader-elector"
          args  = [
            "--election=vault-agent-injector-leader", 
            "--election-namespace=$(NAMESPACE)",
            "--http=0.0.0.0:4040",
            "--ttl=60s"
          ]

          env {
            name = "NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 4040
              scheme = "HTTP"
            }
            failure_threshold = 2
            initial_delay_seconds = 1
            period_seconds = 2
            success_threshold = 1
            timeout_seconds = 5
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 4040
              scheme = "HTTP"
            }
            failure_threshold = 2
            initial_delay_seconds = 2
            period_seconds = 2
            success_threshold = 1
            timeout_seconds = 5
          }
        }
        container {
          name  = "sidecar-injector"
          image = "hashicorp/vault-k8s:0.11.0"
          image_pull_policy = "IfNotPresent"

          env {
            name = "NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }
          env {
            name  = "AGENT_INJECT_LISTEN"
            value = ":8080"
          }
          env {
            name  = "AGENT_INJECT_LOG_LEVEL"
            value = "debug"
          }
          env {
            name  = "AGENT_INJECT_LOG_FORMAT"
            value = "standard"
          }
          env {
            name  = "AGENT_INJECT_VAULT_ADDR"
            value = "https://${google_compute_address.vault.address}"
          }
          env {
            name  = "AGENT_INJECT_VAULT_IMAGE"
            value = "${var.vault_container}"
          }
          env {
            name  = "AGENT_INJECT_TLS_AUTO"
            value = "vault-agent-injector-cfg"
          }
          env {
            name  = "AGENT_INJECT_TLS_AUTO_HOSTS"
            value = "vault-agent-injector-svc,vault-agent-injector-svc.$(NAMESPACE),vault-agent-injector-svc.$(NAMESPACE).svc"
          }
          env {
            name  = "AGENT_INJECT_USE_LEADER_ELECTOR"
            value = "true"
          }
          env {
            name  = "AGENT_INJECT_DEFAULT_TEMPLATE"
            value = "map"
          }
          env {
            name  = "AGENT_INJECT_CPU_REQUEST"
            value = "250m"
          }
          env {
            name  = "AGENT_INJECT_MEM_REQUEST"
            value = "64Mi"
          }
          env {
            name  = "AGENT_INJECT_CPU_LIMIT"
            value = "500m"
          }
          env {
            name  = "AGENT_INJECT_MEM_LIMIT"
            value = "128Mi"
          }

          args = ["agent-inject", "2>&1"]

          liveness_probe {
            http_get {
              path = "/health/ready"
              port = 8080
              scheme = "HTTPS"
            }
            failure_threshold = 2
            initial_delay_seconds = 1
            period_seconds = 2
            success_threshold = 1
            timeout_seconds = 5
          }

          readiness_probe {
            http_get {
              path = "/health/ready"
              port = 8080
              scheme = "HTTPS"
            }
            failure_threshold = 2
            initial_delay_seconds = 2
            period_seconds = 2
            success_threshold = 1
            timeout_seconds = 5
          }
        }
      }
    }
  }
}
######################################

######################################
# This firewall rule allows the injector to subscribe properly
# to all the relevant Kubernetes events.
# More on this:
# https://github.com/hashicorp/vault-k8s/issues/46#issuecomment-574134564
resource "google_compute_firewall" "vault-injector-hook-access" {
  depends_on = [google_container_cluster.vault]
  
  name    = "vault-injector-hook-access"
  network = google_compute_network.vault-network.name

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = [var.kubernetes_masters_ipv4_cidr]
}
