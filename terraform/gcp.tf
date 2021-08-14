# This file contains all the interactions with Google Cloud
provider "google" {
  region  = var.region
  project = var.project
}

provider "google-beta" {
  region  = var.region
  project = var.project
}

# Generate a random id for the project - GCP projects must have globally
# unique names
resource "random_id" "project_random" {
  prefix      = var.project_prefix
  byte_length = "8"
}

# Create the project if one isn't specified
resource "google_project" "vault" {
  count           = var.project != "" ? 0 : 1
  name            = random_id.project_random.hex
  project_id      = random_id.project_random.hex
  org_id          = var.org_id
  billing_account = var.billing_account
}

# Or use an existing project, if defined
data "google_project" "vault" {
  project_id = var.project != "" ? var.project : google_project.vault[0].project_id
}

# Create the vault service account
resource "google_service_account" "vault-server" {
  account_id   = "vault-server"
  display_name = "Vault Server"
  project      = data.google_project.vault.project_id
}

# Add the service account to the project
resource "google_project_iam_member" "service-account" {
  count   = length(var.service_account_iam_roles)
  project = data.google_project.vault.project_id
  role    = element(var.service_account_iam_roles, count.index)
  member  = "serviceAccount:${google_service_account.vault-server.email}"
}

# Add user-specified roles
resource "google_project_iam_member" "service-account-custom" {
  count   = length(var.service_account_custom_iam_roles)
  project = data.google_project.vault.project_id
  role    = element(var.service_account_custom_iam_roles, count.index)
  member  = "serviceAccount:${google_service_account.vault-server.email}"
}

# Enable required services on the project
resource "google_project_service" "service" {
  count   = length(var.project_services)
  project = data.google_project.vault.project_id
  service = element(var.project_services, count.index)

  # Do not disable the service on destroy. On destroy, we are going to
  # destroy the project, but we need the APIs available to destroy the
  # underlying resources.
  disable_on_destroy = false
}

# Create the storage bucket
resource "google_storage_bucket" "vault" {
  name          = "${data.google_project.vault.project_id}-vault-storage"
  project       = data.google_project.vault.project_id
  force_destroy = true
  storage_class = "MULTI_REGIONAL"

  uniform_bucket_level_access = true

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

  depends_on = [google_project_service.service]
}

# Grant service account access to the storage bucket
resource "google_storage_bucket_iam_member" "vault-server" {
  count  = length(var.storage_bucket_roles)
  bucket = google_storage_bucket.vault.name
  role   = element(var.storage_bucket_roles, count.index)
  member = "serviceAccount:${google_service_account.vault-server.email}"
}

# Generate a random suffix for the KMS keyring. Like projects, key rings names
# must be globally unique within the project. A key ring also cannot be
# destroyed, so deleting and re-creating a key ring will fail.
#
# This uses a random_id to prevent that from happening.
resource "random_id" "kms_random" {
  prefix      = var.kms_key_ring_prefix
  byte_length = "8"
}

# Obtain the key ring ID or use a randomly generated on.
locals {
  kms_key_ring = var.kms_key_ring != "" ? var.kms_key_ring : random_id.kms_random.hex
}

# Create the KMS key ring
resource "google_kms_key_ring" "vault" {
  name     = local.kms_key_ring
  location = var.region
  project  = data.google_project.vault.project_id

  depends_on = [google_project_service.service]
}

# Create the crypto key for encrypting init keys
resource "google_kms_crypto_key" "vault-init" {
  name            = var.kms_crypto_key
  key_ring        = google_kms_key_ring.vault.id
  rotation_period = "604800s"
}

# Grant service account access to the key
resource "google_kms_crypto_key_iam_member" "vault-init" {
  crypto_key_id = google_kms_crypto_key.vault-init.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.vault-server.email}"
}

# Create the crypto key for encrypting Kubernetes secrets
resource "google_kms_crypto_key" "kubernetes-secrets" {
  name            = var.kubernetes_secrets_crypto_key
  key_ring        = google_kms_key_ring.vault.id
  rotation_period = "604800s"
}

# Grant GKE access to the key
resource "google_kms_crypto_key_iam_member" "kubernetes-secrets-gke" {
  crypto_key_id = google_kms_crypto_key.kubernetes-secrets.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.vault.number}@container-engine-robot.iam.gserviceaccount.com"
}

# Create an external NAT IP
resource "google_compute_address" "vault-nat" {
  count   = 2
  name    = "vault-nat-external-${count.index}"
  project = data.google_project.vault.project_id
  region  = var.region

  depends_on = [google_project_service.service]
}

# Create a network for GKE
resource "google_compute_network" "vault-network" {
  name                    = "vault-network"
  project                 = data.google_project.vault.project_id
  auto_create_subnetworks = false

  depends_on = [google_project_service.service]
}

# Create subnets
resource "google_compute_subnetwork" "vault-subnetwork" {
  name          = "vault-subnetwork"
  project       = data.google_project.vault.project_id
  network       = google_compute_network.vault-network.self_link
  region        = var.region
  ip_cidr_range = var.kubernetes_network_ipv4_cidr

  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "vault-pods"
    ip_cidr_range = var.kubernetes_pods_ipv4_cidr
  }

  secondary_ip_range {
    range_name    = "vault-svcs"
    ip_cidr_range = var.kubernetes_services_ipv4_cidr
  }
}

# Create a NAT router so the nodes can reach DockerHub, etc
resource "google_compute_router" "vault-router" {
  name    = "vault-router"
  project = data.google_project.vault.project_id
  region  = var.region
  network = google_compute_network.vault-network.self_link

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "vault-nat" {
  name    = "vault-nat-1"
  project = data.google_project.vault.project_id
  router  = google_compute_router.vault-router.name
  region  = var.region

  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips                = google_compute_address.vault-nat.*.self_link

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.vault-subnetwork.self_link
    source_ip_ranges_to_nat = ["PRIMARY_IP_RANGE", "LIST_OF_SECONDARY_IP_RANGES"]

    secondary_ip_range_names = [
      google_compute_subnetwork.vault-subnetwork.secondary_ip_range[0].range_name,
      google_compute_subnetwork.vault-subnetwork.secondary_ip_range[1].range_name,
    ]
  }
}

# Create the GKE cluster
resource "google_container_cluster" "vault" {
  provider = google-beta

  name     = "vault"
  project  = data.google_project.vault.project_id
  location = var.region

  network    = google_compute_network.vault-network.self_link
  subnetwork = google_compute_subnetwork.vault-subnetwork.self_link

  initial_node_count = var.kubernetes_nodes_per_zone

  release_channel {
    channel = var.kubernetes_release_channel
  }

  logging_service    = var.kubernetes_logging_service
  monitoring_service = var.kubernetes_monitoring_service

  # Disable legacy ACLs. The default is false, but explicitly marking it false
  # here as well.
  enable_legacy_abac = false

  database_encryption {
    state    = "ENCRYPTED"
    key_name = google_kms_crypto_key.kubernetes-secrets.self_link
  }

  node_config {
    machine_type    = var.kubernetes_instance_type
    service_account = google_service_account.vault-server.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # Set metadata on the VM to supply more entropy
    metadata = {
      google-compute-enable-virtio-rng = "true"
      disable-legacy-endpoints         = "true"
    }

    labels = {
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
      start_time = var.kubernetes_daily_maintenance_window
    }
  }

  # Allocate IPs in our subnetwork
  ip_allocation_policy {
    cluster_secondary_range_name  = google_compute_subnetwork.vault-subnetwork.secondary_ip_range[0].range_name
    services_secondary_range_name = google_compute_subnetwork.vault-subnetwork.secondary_ip_range[1].range_name
  }

  # Specify the list of CIDRs which can access the master's API
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.kubernetes_master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
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
    master_ipv4_cidr_block = var.kubernetes_masters_ipv4_cidr
  }

  depends_on = [
    google_project_service.service,
    google_kms_crypto_key_iam_member.vault-init,
    google_kms_crypto_key_iam_member.kubernetes-secrets-gke,
    google_storage_bucket_iam_member.vault-server,
    google_project_iam_member.service-account,
    google_project_iam_member.service-account-custom,
    google_compute_router_nat.vault-nat,
  ]
}

# Provision IP
resource "google_compute_address" "vault" {
  name    = "vault-lb"
  region  = var.region
  project = data.google_project.vault.project_id

  depends_on = [google_project_service.service]
}

output "address" {
  value = google_compute_address.vault.address
}

output "project" {
  value = data.google_project.vault.project_id
}

output "region" {
  value = var.region
}
