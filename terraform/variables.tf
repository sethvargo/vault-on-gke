terraform {
  required_version = ">= 0.12"
}

variable "region" {
  type        = string
  default     = "us-east4"
  description = "Region in which to create the cluster and run Atlantis."
}

variable "project" {
  type        = string
  default     = ""
  description = "Project ID where Terraform is authenticated to run to create additional projects. If provided, Terraform will great the GKE and Vault cluster inside this project. If not given, Terraform will generate a new project."
}

variable "project_prefix" {
  type        = string
  default     = "vault-"
  description = "String value to prefix the generated project ID with."
}

variable "billing_account" {
  type        = string
  description = "Billing account ID."
}

variable "org_id" {
  type        = string
  description = "Organization ID."
}

variable "kubernetes_instance_type" {
  type        = string
  default     = "n1-standard-2"
  description = "Instance type to use for the nodes."
}

variable "service_account_iam_roles" {
  type = list(string)
  default = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
  ]
  description = "List of IAM roles to assign to the service account."
}

variable "service_account_custom_iam_roles" {
  type        = list(string)
  default     = []
  description = "List of arbitrary additional IAM roles to attach to the service account on the Vault nodes."
}

variable "project_services" {
  type = list(string)
  default = [
    "cloudkms.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "container.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]
  description = "List of services to enable on the project."
}

variable "storage_bucket_roles" {
  type = list(string)
  default = [
    "roles/storage.legacyBucketReader",
    "roles/storage.objectAdmin",
  ]
  description = "List of storage bucket roles."
}

#
# KMS options
# ------------------------------

variable "kms_key_ring_prefix" {
  type        = string
  default     = "vault-"
  description = "String value to prefix the generated key ring with."
}

variable "kms_key_ring" {
  type        = string
  default     = ""
  description = "String value to use for the name of the KMS key ring. This exists for backwards-compatability for users of the existing configurations. Please use kms_key_ring_prefix instead."
}

variable "kms_crypto_key" {
  type        = string
  default     = "vault-init"
  description = "String value to use for the name of the KMS crypto key."
}

#
# Kubernetes options
# ------------------------------

variable "kubernetes_nodes_per_zone" {
  type        = number
  default     = 1
  description = "Number of nodes to deploy in each zone of the Kubernetes cluster. For example, if there are 4 zones in the region and num_nodes_per_zone is 2, 8 total nodes will be created."
}

variable "kubernetes_daily_maintenance_window" {
  type        = string
  default     = "06:00"
  description = "Maintenance window for GKE."
}

variable "kubernetes_logging_service" {
  type        = string
  default     = "logging.googleapis.com/kubernetes"
  description = "Name of the logging service to use. By default this uses the new Stackdriver GKE beta."
}

variable "kubernetes_monitoring_service" {
  type        = string
  default     = "monitoring.googleapis.com/kubernetes"
  description = "Name of the monitoring service to use. By default this uses the new Stackdriver GKE beta."
}

variable "kubernetes_network_ipv4_cidr" {
  type        = string
  default     = "10.0.96.0/22"
  description = "IP CIDR block for the subnetwork. This must be at least /22 and cannot overlap with any other IP CIDR ranges."
}

variable "kubernetes_pods_ipv4_cidr" {
  type        = string
  default     = "10.0.92.0/22"
  description = "IP CIDR block for pods. This must be at least /22 and cannot overlap with any other IP CIDR ranges."
}

variable "kubernetes_services_ipv4_cidr" {
  type        = string
  default     = "10.0.88.0/22"
  description = "IP CIDR block for services. This must be at least /22 and cannot overlap with any other IP CIDR ranges."
}

variable "kubernetes_masters_ipv4_cidr" {
  type        = string
  default     = "10.0.82.0/28"
  description = "IP CIDR block for the Kubernetes master nodes. This must be exactly /28 and cannot overlap with any other IP CIDR ranges."
}

variable "kubernetes_master_authorized_networks" {
  type = list(object({
    display_name = string
    cidr_block   = string
  }))

  default = [
    {
      display_name = "Anyone"
      cidr_block   = "0.0.0.0/0"
    },
  ]

  description = "List of CIDR blocks to allow access to the master's API endpoint. This is specified as a slice of objects, where each object has a display_name and cidr_block attribute. The default behavior is to allow anyone (0.0.0.0/0) access to the endpoint. You should restrict access to external IPs that need to access the cluster."
}

#
# Vault options
# ------------------------------

variable "num_vault_pods" {
  type        = number
  default     = 3
  description = "Number of Vault pods to run. Anti-affinity rules spread pods across available nodes. Please use an odd number for better availability."
}

variable "vault_container" {
  type        = string
  default     = "vault:1.1.3"
  description = "Name of the Vault container image to deploy. This can be specified like \"container:version\" or as a full container URL."
}

variable "vault_init_container" {
  type        = string
  default     = "sethvargo/vault-init:1.0.0"
  description = "Name of the Vault init container image to deploy. This can be specified like \"container:version\" or as a full container URL."
}

variable "vault_recovery_shares" {
  type        = string
  default     = "1"
  description = "Number of recovery keys to generate."
}

variable "vault_recovery_threshold" {
  type        = string
  default     = "1"
  description = "Number of recovery keys required for quorum. This must be less than or equal to \"vault_recovery_keys\"."
}
