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
    "compute.googleapis.com",
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

variable "kubernetes_network_ipv4_cidr" {
  type    = "string"
  default = "10.0.96.0/22"

  description = <<EOF
IP CIDR block for the subnetwork. This must be at least /22 and cannot overlap
with any other IP CIDR ranges.
EOF
}

variable "kubernetes_pods_ipv4_cidr" {
  type    = "string"
  default = "10.0.92.0/22"

  description = <<EOF
IP CIDR block for pods. This must be at least /22 and cannot overlap with any
other IP CIDR ranges.
EOF
}

variable "kubernetes_services_ipv4_cidr" {
  type    = "string"
  default = "10.0.88.0/22"

  description = <<EOF
IP CIDR block for services. This must be at least /22 and cannot overlap with
any other IP CIDR ranges.
EOF
}

variable "kubernetes_masters_ipv4_cidr" {
  type    = "string"
  default = "10.0.82.0/28"

  description = <<EOF
IP CIDR block for the Kubernetes master nodes. This must be exactly /28 and
cannot overlap with any other IP CIDR ranges.
EOF
}

variable "kubernetes_master_authorized_networks" {
  type = "list"

  default = [
    {
      display_name = "Anyone"
      cidr_block   = "0.0.0.0/0"
    },
  ]

  description = <<EOF
List of CIDR blocks to allow access to the master's API endpoint. This is
specified as a slice of objects, where each object has a display_name and
cidr_block attribute:

[
  {
    display_name = "My range"
    cidr_block   = "1.2.3.4/32"
  },
  {
    display_name = "My other range"
    cidr_block   = "5.6.7.0/24"
  }
]

The default behavior is to allow anyone (0.0.0.0/0) access to the endpoint.
You should restrict access to external IPs that need to access the cluster.
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
