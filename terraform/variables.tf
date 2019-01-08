variable "region" {
  type    = "string"
  default = "us-east4"

  description = <<EOF
Region in which to create the cluster and run Atlantis.
EOF
}

variable "project" {
  type    = "string"
  default = ""

  description = <<EOF
Project ID where Terraform is authenticated to run to create additional
projects.
EOF
}

variable "project_prefix" {
  type    = "string"
  default = "vault-"

  description = <<EOF
String value to prefix the generated project ID with.
EOF
}

variable "billing_account" {
  type = "string"

  description = <<EOF
Billing account ID.
EOF
}

variable "org_id" {
  type = "string"

  description = <<EOF
Organization ID.
EOF
}

variable "kubernetes_instance_type" {
  type    = "string"
  default = "n1-standard-2"

  description = <<EOF
Instance type to use for the nodes.
EOF
}

variable "kubernetes_nodes_per_zone" {
  type    = "string"
  default = "1"

  description = <<EOF
Number of nodes to deploy in each zone of the Kubernetes cluster. For example,
if there are 4 zones in the region and num_nodes_per_zone is 2, 8 total nodes
will be created.
EOF
}

variable "kubernetes_daily_maintenance_window" {
  type    = "string"
  default = "06:00"

  description = <<EOF
Maintenance window for GKE.
EOF
}

variable "service_account_iam_roles" {
  type = "list"

  default = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
  ]
}

variable "service_account_custom_iam_roles" {
  type    = "list"
  default = []

  description = <<EOF
List of arbitrary additional IAM roles to attach to the service account on
the Vault nodes.
EOF
}

variable "service_account_adfd" {
  type = "list"

  default = []
}

variable "project_services" {
  type = "list"

  default = [
    "cloudkms.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]
}

variable "storage_bucket_roles" {
  type = "list"

  default = [
    "roles/storage.legacyBucketReader",
    "roles/storage.objectAdmin",
  ]
}

variable "kubernetes_logging_service" {
  type    = "string"
  default = "logging.googleapis.com/kubernetes"

  description = <<EOF
Name of the logging service to use. By default this uses the new Stackdriver
GKE beta.
EOF
}

variable "kubernetes_monitoring_service" {
  type    = "string"
  default = "monitoring.googleapis.com/kubernetes"

  description = <<EOF
Name of the monitoring service to use. By default this uses the new
Stackdriver GKE beta.
EOF
}

variable "num_vault_pods" {
  type    = "string"
  default = "3"

  description = <<EOF
Number of Vault pods to run. Anti-affinity rules spread pods across available
nodes. Please use an odd number for better availability.
EOF
}

variable "vault_container" {
  type    = "string"
  default = "vault:1.0.1"

  description = <<EOF
Name of the Vault container image to deploy. This can be specified like
"container:version" or as a full container URL.
EOF
}

variable "vault_init_container" {
  type    = "string"
  default = "sethvargo/vault-init:1.0.0"

  description = <<EOF
Name of the Vault init container image to deploy. This can be specified like
"container:version" or as a full container URL.
EOF
}

variable "vault_recovery_shares" {
  type    = "string"
  default = "1"

  description = <<EOF
Number of recovery keys to generate.
EOF
}

variable "vault_recovery_threshold" {
  type    = "string"
  default = "1"

  description = <<EOF
Number of recovery keys required for quorum. This must be less than or equal
to "vault_recovery_keys".
EOF
}
