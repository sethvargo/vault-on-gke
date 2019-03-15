# This file contains all the interactions with Google Cloud
provider "google" {
  region  = "${var.region}"
  project = "${var.project}"
}

provider "google-beta" {
  region  = "${var.region}"
  project = "${var.project}"
}

# Generate a random id for the project - GCP projects must have globally
# unique names
resource "random_id" "random" {
  prefix      = "${var.project_prefix}"
  byte_length = "8"
}

# Create the project if one isn't specified
resource "google_project" "vault" {
  count           = "${var.project != "" ? 0 : 1}"
  name            = "${random_id.random.hex}"
  project_id      = "${random_id.random.hex}"
  org_id          = "${var.org_id}"
  billing_account = "${var.billing_account}"
}

# Or use an existing project, if defined
data "google_project" "vault" {
  count      = "${var.project != "" ? 1 : 0}"
  project_id = "${var.project}"
}

# Obtain the project_id from either the newly created project resource or existing data project resource
# One will be populated and the other will be null
locals {
  vault_project_id = "${element(concat(data.google_project.vault.*.project_id, google_project.vault.*.project_id),0)}"
}

# Create the vault service account
resource "google_service_account" "vault-server" {
  account_id   = "vault-server"
  display_name = "Vault Server"
  project      = "${local.vault_project_id}"
}

# Create a service account key
resource "google_service_account_key" "vault" {
  service_account_id = "${google_service_account.vault-server.name}"
}

# Add the service account to the project
resource "google_project_iam_member" "service-account" {
  count   = "${length(var.service_account_iam_roles)}"
  project = "${local.vault_project_id}"
  role    = "${element(var.service_account_iam_roles, count.index)}"
  member  = "serviceAccount:${google_service_account.vault-server.email}"
}

# Add user-specified roles
resource "google_project_iam_member" "service-account-custom" {
  count   = "${length(var.service_account_custom_iam_roles)}"
  project = "${local.vault_project_id}"
  role    = "${element(var.service_account_custom_iam_roles, count.index)}"
  member  = "serviceAccount:${google_service_account.vault-server.email}"
}

# Enable required services on the project
resource "google_project_service" "service" {
  count   = "${length(var.project_services)}"
  project = "${local.vault_project_id}"
  service = "${element(var.project_services, count.index)}"

  # Do not disable the service on destroy. On destroy, we are going to
  # destroy the project, but we need the APIs available to destroy the
  # underlying resources.
  disable_on_destroy = false
}

# Create the storage bucket
resource "google_storage_bucket" "vault" {
  name          = "${local.vault_project_id}-vault-storage"
  project       = "${local.vault_project_id}"
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
      num_newer_versions = 1
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

# Generate a random suffix for the KMS keyring.
# Otherwise, deploying into an existing project will work
# only on the first deployment attempt as there would
# have been a keyring by the original name already present.
# See: https://www.terraform.io/docs/providers/google/r/google_kms_key_ring.html
resource "random_id" "kms_random" {
  byte_length = "8"
}

# Create the KMS key ring
resource "google_kms_key_ring" "vault" {
  name     = "vault-${random_id.kms_random.hex}"
  location = "${var.region}"
  project  = "${local.vault_project_id}"

  depends_on = ["google_project_service.service"]
}

# Create the crypto key for encrypting init keys
resource "google_kms_crypto_key" "vault-init" {
  name            = "vault-init"
  key_ring        = "${google_kms_key_ring.vault.id}"
  rotation_period = "604800s"
}

# Create a custom IAM role with the most minimal set of permissions for the
# KMS auto-unsealer. Once hashicorp/vault#5999 is merged, this can be replaced
# with the built-in roles/cloudkms.cryptoKeyEncrypterDecryptor role.
resource "google_project_iam_custom_role" "vault-seal-kms" {
  project     = "${local.vault_project_id}"
  role_id     = "kmsEncrypterDecryptorViewer"
  title       = "KMS Encrypter Decryptor Viewer"
  description = "KMS crypto key permissions to encrypt, decrypt, and view key data"

  permissions = [
    "cloudkms.cryptoKeyVersions.useToEncrypt",
    "cloudkms.cryptoKeyVersions.useToDecrypt",

    # This is required until hashicorp/vault#5999 is merged. The auto-unsealer
    # attempts to read the key, which requires this additional permission.
    "cloudkms.cryptoKeys.get",
  ]
}

# Grant service account access to the key
resource "google_kms_crypto_key_iam_member" "vault-init" {
  crypto_key_id = "${google_kms_crypto_key.vault-init.id}"
  role          = "projects/${local.vault_project_id}/roles/${google_project_iam_custom_role.vault-seal-kms.role_id}"
  member        = "serviceAccount:${google_service_account.vault-server.email}"
}

# Create an external NAT IP
resource "google_compute_address" "vault-nat" {
  count   = 2
  name    = "vault-nat-external-${count.index}"
  project = "${local.vault_project_id}"
  region  = "${var.region}"

  depends_on = [
    "google_project_service.service",
  ]
}

# Create a network for GKE
resource "google_compute_network" "vault-network" {
  name                    = "vault-network"
  project                 = "${local.vault_project_id}"
  auto_create_subnetworks = false

  depends_on = [
    "google_project_service.service",
  ]
}

# Create subnets
resource "google_compute_subnetwork" "vault-subnetwork" {
  name          = "vault-subnetwork"
  project       = "${local.vault_project_id}"
  network       = "${google_compute_network.vault-network.self_link}"
  region        = "${var.region}"
  ip_cidr_range = "${var.kubernetes_network_ipv4_cidr}"

  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "vault-pods"
    ip_cidr_range = "${var.kubernetes_pods_ipv4_cidr}"
  }

  secondary_ip_range {
    range_name    = "vault-svcs"
    ip_cidr_range = "${var.kubernetes_services_ipv4_cidr}"
  }
}

# Create a NAT router so the nodes can reach DockerHub, etc
resource "google_compute_router" "vault-router" {
  name    = "vault-router"
  project = "${local.vault_project_id}"
  region  = "${var.region}"
  network = "${google_compute_network.vault-network.self_link}"

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "vault-nat" {
  name    = "vault-nat-1"
  project = "${local.vault_project_id}"
  router  = "${google_compute_router.vault-router.name}"
  region  = "${var.region}"

  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips                = ["${google_compute_address.vault-nat.*.self_link}"]

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = "${google_compute_subnetwork.vault-subnetwork.self_link}"
    source_ip_ranges_to_nat = ["PRIMARY_IP_RANGE", "LIST_OF_SECONDARY_IP_RANGES"]

    secondary_ip_range_names = [
      "${google_compute_subnetwork.vault-subnetwork.secondary_ip_range.0.range_name}",
      "${google_compute_subnetwork.vault-subnetwork.secondary_ip_range.1.range_name}",
    ]
  }
}

# Get latest cluster version
data "google_container_engine_versions" "versions" {
  project = "${local.vault_project_id}"
  region  = "${var.region}"
}

# Create the GKE cluster
resource "google_container_cluster" "vault" {
  provider = "google-beta"

  name    = "vault"
  project = "${local.vault_project_id}"
  region  = "${var.region}"

  network    = "${google_compute_network.vault-network.self_link}"
  subnetwork = "${google_compute_subnetwork.vault-subnetwork.self_link}"

  initial_node_count = "${var.kubernetes_nodes_per_zone}"

  min_master_version = "${data.google_container_engine_versions.versions.latest_master_version}"
  node_version       = "${data.google_container_engine_versions.versions.latest_node_version}"

  logging_service    = "${var.kubernetes_logging_service}"
  monitoring_service = "${var.kubernetes_monitoring_service}"

  # Disable legacy ACLs. The default is false, but explicitly marking it false
  # here as well.
  enable_legacy_abac = false

  node_config {
    machine_type    = "${var.kubernetes_instance_type}"
    service_account = "${google_service_account.vault-server.email}"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # Set metadata on the VM to supply more entropy
    metadata {
      google-compute-enable-virtio-rng = "true"
    }

    labels {
      service = "vault"
    }

    tags = ["vault"]

    # Protect node metadata
    workload_metadata_config {
      node_metadata = "SECURE"
    }
  }

  # Configure various addons
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
      start_time = "${var.kubernetes_daily_maintenance_window}"
    }
  }

  # Allocate IPs in our subnetwork
  ip_allocation_policy {
    cluster_secondary_range_name  = "${google_compute_subnetwork.vault-subnetwork.secondary_ip_range.0.range_name}"
    services_secondary_range_name = "${google_compute_subnetwork.vault-subnetwork.secondary_ip_range.1.range_name}"
  }

  # Specify the list of CIDRs which can access the master's API
  master_authorized_networks_config {
    cidr_blocks = ["${var.kubernetes_master_authorized_networks}"]
  }

  # Configure the cluster to be private (not have public facing IPs)
  private_cluster_config {
    # This field is misleading. This prevents access to the master API from
    # any external IP. While that might represent the most secure
    # configuration, it is not ideal for most setups. As such, we disable the
    # private endpoint (allow the public endpoint) and restrict which CIDRs
    # can talk to that endpoint.
    enable_private_endpoint = false

    enable_private_nodes   = true
    master_ipv4_cidr_block = "${var.kubernetes_masters_ipv4_cidr}"
  }

  depends_on = [
    "google_project_service.service",
    "google_kms_crypto_key_iam_member.vault-init",
    "google_storage_bucket_iam_member.vault-server",
    "google_project_iam_member.service-account",
    "google_project_iam_member.service-account-custom",
    "google_compute_router_nat.vault-nat",
  ]
}

# Provision IP
resource "google_compute_address" "vault" {
  name    = "vault-lb"
  region  = "${var.region}"
  project = "${local.vault_project_id}"

  depends_on = ["google_project_service.service"]
}

output "address" {
  value = "${google_compute_address.vault.address}"
}

output "project" {
  value = "${local.vault_project_id}"
}

output "region" {
  value = "${var.region}"
}
