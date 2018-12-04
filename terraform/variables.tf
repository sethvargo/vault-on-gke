variable "region" {
  type    = "string"
  default = "us-east4"
}

variable "project" {
  type    = "string"
  default = ""
}

variable "project_prefix" {
  type    = "string"
  default = "vault-"
}

variable "billing_account" {
  type = "string"
}

variable "org_id" {
  type = "string"
}

variable "instance_type" {
  type    = "string"
  default = "n1-standard-2"

  description = <<EOF
Instance type to use for the nodes.
EOF
}

variable "num_nodes_per_zone" {
  type    = "string"
  default = "1"

  description = <<EOF
Number of nodes to deploy in each zone of the Kubernetes cluster. For example,
if there are 4 zones in the region and num_nodes_per_zone is 2, 8 total nodes
will be created.
EOF
}

variable "daily_maintenance_window" {
  type    = "string"
  default = "06:00"
}

variable "service_account_iam_roles" {
  type = "list"

  default = [
    "roles/resourcemanager.projectIamAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountKeyAdmin",
    "roles/iam.serviceAccountTokenCreator",
    "roles/iam.serviceAccountUser",
    "roles/viewer",
  ]
}

variable "project_services" {
  type = "list"

  default = [
    "cloudkms.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
  ]
}

variable "storage_bucket_roles" {
  type = "list"

  default = [
    "roles/storage.legacyBucketReader",
    "roles/storage.objectAdmin",
  ]
}

variable "kms_crypto_key_roles" {
  type = "list"

  default = [
    "roles/cloudkms.cryptoKeyEncrypterDecrypter",
  ]
}

variable "kubernetes_logging_service" {
  type    = "string"
  default = "logging.googleapis.com/kubernetes"
}

variable "kubernetes_monitoring_service" {
  type    = "string"
  default = "monitoring.googleapis.com/kubernetes"
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
  default = "vault:0.11.4"

  description = <<EOF
Name of the Vault container image to deploy. This can be specified like
"container:version" or as a full container URL.
EOF
}

variable "vault_init_container" {
  type    = "string"
  default = "sethvargo/vault-init:0.1.1"

  description = <<EOF
Name of the Vault init container image to deploy. This can be specified like
"container:version" or as a full container URL.
EOF
}
