# This file contains all the interactions with Google Cloud
provider "google" {
  region  = "${var.region}"
  project = "${var.project}"
}

# Generate a random id for the project - GCP projects must have globally
# unique names
resource "random_id" "random" {
  prefix      = "${var.project_prefix}"
  byte_length = "8"
}

# Create the project
resource "google_project" "vault" {
  name            = "${random_id.random.hex}"
  project_id      = "${random_id.random.hex}"
  org_id          = "${var.org_id}"
  billing_account = "${var.billing_account}"
}

# Create the vault service account
resource "google_service_account" "vault-server" {
  account_id   = "vault-server"
  display_name = "Vault Server"
  project      = "${google_project.vault.project_id}"
}

# Create a service account key
resource "google_service_account_key" "vault" {
  service_account_id = "${google_service_account.vault-server.name}"
}

# Add the service account to the project
resource "google_project_iam_member" "service-account" {
  count   = "${length(var.service_account_iam_roles)}"
  project = "${google_project.vault.project_id}"
  role    = "${element(var.service_account_iam_roles, count.index)}"
  member  = "serviceAccount:${google_service_account.vault-server.email}"
}

# Enable required services on the project
resource "google_project_service" "service" {
  count   = "${length(var.project_services)}"
  project = "${google_project.vault.project_id}"
  service = "${element(var.project_services, count.index)}"

  # Do not disable the service on destroy. On destroy, we are going to
  # destroy the project, but we need the APIs available to destroy the
  # underlying resources.
  disable_on_destroy = false
}

# Create the storage bucket
resource "google_storage_bucket" "vault" {
  name          = "${google_project.vault.project_id}-vault-storage"
  project       = "${google_project.vault.project_id}"
  force_destroy = true
  storage_class = "MULTI_REGIONAL"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }

    condition {
      num_newer_versions = 3
    }
  }

  depends_on = ["google_project_service.service"]
}

# Grant service account access to the storage bucket
resource "google_storage_bucket_iam_member" "vault-server" {
  count  = "${length(var.storage_bucket_roles)}"
  bucket = "${google_storage_bucket.vault.name}"
  role   = "${element(var.storage_bucket_roles, count.index)}"
  member = "serviceAccount:${google_service_account.vault-server.email}"
}

# Create the KMS key ring
resource "google_kms_key_ring" "vault" {
  name     = "vault"
  location = "${var.region}"
  project  = "${google_project.vault.project_id}"

  depends_on = ["google_project_service.service"]
}

# Create the crypto key for encrypting init keys
resource "google_kms_crypto_key" "vault-init" {
  name            = "vault-init"
  key_ring        = "${google_kms_key_ring.vault.id}"
  rotation_period = "604800s"
}

# Grant service account access to the key
resource "google_kms_crypto_key_iam_member" "vault-init" {
  count         = "${length(var.kms_crypto_key_roles)}"
  crypto_key_id = "${google_kms_crypto_key.vault-init.id}"
  role          = "${element(var.kms_crypto_key_roles, count.index)}"
  member        = "serviceAccount:${google_service_account.vault-server.email}"
}

# Get latest cluster version
data "google_container_engine_versions" "versions" {
  project = "${google_project.vault.project_id}"
  region  = "${var.region}"
}

# Create the GKE cluster
resource "google_container_cluster" "vault" {
  name    = "vault"
  project = "${google_project.vault.project_id}"
  region  = "${var.region}"

  initial_node_count = "${var.num_nodes_per_zone}"

  min_master_version = "${data.google_container_engine_versions.versions.latest_master_version}"
  node_version       = "${data.google_container_engine_versions.versions.latest_node_version}"

  logging_service    = "${var.kubernetes_logging_service}"
  monitoring_service = "${var.kubernetes_monitoring_service}"

  # Disable legacy ACLs. The default is false, but explicitly marking it false
  # here as well.
  enable_legacy_abac = false

  node_config {
    machine_type    = "${var.instance_type}"
    service_account = "${google_service_account.vault-server.email}"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    labels {
      service = "vault"
    }

    tags = ["vault"]

    # Protect node metadata
    workload_metadata_config {
      node_metadata = "SECURE"
    }
  }

  addons_config {
    # Disable the Kubernetes dashboard, which is often an attack vector. The
    # cluster can still be managed via the GKE UI.
    kubernetes_dashboard {
      disabled = true
    }

    # Enable network policy configurations (like Calico).
    network_policy_config {
      disabled = false
    }
  }

  # Disable basic authentication and cert-based authentication.
  master_auth {
    username = ""
    password = ""

    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Enable network policy configurations (like Calico) - for some reason this
  # has to be in here twice.
  network_policy {
    enabled = true
  }

  # Set the maintenance window.
  maintenance_policy {
    daily_maintenance_window {
      start_time = "${var.daily_maintenance_window}"
    }
  }

  depends_on = [
    "google_project_service.service",
    "google_kms_crypto_key_iam_member.vault-init",
    "google_storage_bucket_iam_member.vault-server",
    "google_project_iam_member.service-account",
  ]
}

# Provision IP
resource "google_compute_address" "vault" {
  name    = "vault-lb"
  region  = "${var.region}"
  project = "${google_project.vault.project_id}"

  depends_on = ["google_project_service.service"]
}

output "address" {
  value = "${google_compute_address.vault.address}"
}

output "project" {
  value = "${google_project.vault.project_id}"
}

output "region" {
  value = "${var.region}"
}
