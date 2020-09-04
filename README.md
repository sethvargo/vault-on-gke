# HashiCorp Vault on GKE with Terraform

This tutorial walks through provisioning a highly-available [HashiCorp
Vault][vault] cluster on [Google Kubernetes Engine][gke] using [HashiCorp
Terraform][terraform] as the provisioning tool.

This tutorial is based on [Kelsey Hightower's Vault on Google Kubernetes
Engine][kelseys-tutorial], but focuses on codifying the steps in Terraform
instead of teaching you them individually. If you would like to know how to
provision HashiCorp Vault on Kuberenetes step-by-step (aka "the hard way"),
please follow Kelsey's repository instead.

**These configurations require Terraform 0.12+!** For support with Terraform
0.11, please use the git tag v0.1.2 series.


## Feature Highlights

- **Vault HA** - The Vault cluster is deployed in HA mode backed by [Google
  Cloud Storage][gcs]

- **Production Hardened** - Vault is deployed according to the [production
  hardening
  guide](https://www.vaultproject.io/guides/operations/production.html). Please
  see the [security section](#security) for more information.

- **Auto-Init and Unseal** - Vault is automatically initialized and unsealed
  at runtime. The unseal keys are encrypted with [Google Cloud KMS][kms] and
  stored in [Google Cloud Storage][gcs]

- **Full Isolation** - The Vault cluster is provisioned in its own Kubernetes
  cluster in a dedicated GCP project that is provisioned dynamically at
  runtime. Clients connect to Vault using **only** the load balancer and Vault
  is treated as a managed external service.

- **Audit Logging** - Audit logging to [Cloud Logging][cloud-logging] (formerly Stackdriver) can be optionally enabled
  with minimal additional configuration.


## Tutorial

1. Download and install [Terraform][terraform].

1. Download, install, and configure the [Google Cloud SDK][sdk]. You will need
   to configure your default application credentials so Terraform can run. It
   will run against your default project, but all resources are created in the
   (new) project that it creates.

1. Run Terraform:

    ```text
    $ cd terraform/
    $ terraform init
    $ terraform apply
    ```

    This operation will take some time as it:

    1. Creates a new project
    1. Enables the required services on that project
    1. Creates a bucket for storage
    1. Creates a KMS key for encryption
    1. Creates a service account with the most restrictive permissions to those resources
    1. Creates a GKE cluster with the configured service account attached
    1. Creates a public IP
    1. Generates a self-signed certificate authority (CA)
    1. Generates a certificate signed by that CA
    1. Configures Terraform to talk to Kubernetes
    1. Creates a Kubernetes secret with the TLS file contents
    1. Configures your local system to talk to the GKE cluster by getting the cluster credentials and kubernetes context
    1. Submits the StatefulSet and Service to the Kubernetes API


## Interact with Vault

1. Export environment variables:

    Vault reads these environment variables for communication. Set Vault's
    address, the CA to use for validation, and the initial root token.

    ```text
    # Make sure you're in the terraform/ directory
    # $ cd terraform/

    $ export VAULT_ADDR="https://$(terraform output address)"
    $ export VAULT_TOKEN="$(eval `terraform output root_token_decrypt_command`)"
    $ export VAULT_CAPATH="$(cd ../ && pwd)/tls/ca.pem"
    ```

1. Run some commands:

    ```text
    $ vault secrets enable -path=secret -version=2 kv
    $ vault kv put secret/foo a=b
    ```

## Audit Logging

Audit logging is not enabled in a default Vault installation. To enable audit
logging to [Cloud Logging][cloud-logging] on Google Cloud, enable the `file` audit
device on `stdout`:

```text
$ vault audit enable file file_path=stdout
```

That's it! Vault will now log all audit requests to Cloud Logging. Additionally,
because the configuration uses an L4 load balancer, Vault does not need to
parse `X-Forwarded-For` headers to extract the client IP, as requests are
passed directly to the node.

## Additional Permissions

You may wish to grant the Vault service account additional permissions. This
service account is attached to the GKE nodes and will be the "default
application credentials" for Vault.

To specify additional permissions, create a `terraform.tfvars` file with the
following:

```terraform
service_account_custom_iam_roles = [
  "roles/...",
]
```

### GCP Auth Method

To use the [GCP auth method][vault-gcp-auth] with the default application
credentials, the Vault server needs the following role:

```text
roles/iam.serviceAccountKeyAdmin
```

Alternatively you can create and upload a dedicated service account for the
GCP auth method during configuration and restrict the node-level default
application credentials.

### GCP Secrets Engine

To use the [GCP secrets engine][vault-gcp-secrets] with the default
application credentials, the Vault server needs the following roles:

```text
roles/iam.serviceAccountKeyAdmin
roles/iam.serviceAccountAdmin
```

Additionally, Vault needs the superset of any permissions it will grant. For
example, if you want Vault to generate GCP access tokens with access to
compute, you must also grant Vault access to compute.

Alternatively you can create and upload a dedicated service account for the
GCP auth method during configuration and restrict the node-level default
application credentials.


## Cleaning Up

```text
$ terraform destroy
```


## Security

### Root Token

This set of Terraform configurations is designed to make your life easy. It's
a best-practices setup for Vault, but also aids in the retrieval of the initial
root token.

As such, you should **use a Terraform state backend with encryption enabled,
such as Cloud Storage**. To access the root token

```text
$ $(terraform output root_token_decrypt_command)
```

### TLS Keys, Service Accounts, etc

Just like the Vault root token, additional information is stored in plaintext in
the Terraform state. This is not a bug and is the fundamental design of
Terraform. You are ultimately responsible for securing access to your Terraform
state. As such, you should **use a Terraform state backend with encryption
enabled, such as Cloud Storage**.

- Vault TLS keys - the Vault TLS keys, including the private key, are stored in
  Terraform state. Terraform created the resources and thus maintains their
  data.

- Service Account Key - Terraform generates a Google Cloud Service Account key
  in order to download the initial root token from Cloud Storage. This service
  account key is stored in the Terraform state.

- OAuth Access Token - In order to communicate with the Kubernetes cluster,
  Terraform gets an OAuth2 access token. This access token is stored in the
  Terraform state.

You may be seeing a theme, which is that the Terraform state includes a wealth
of information. This is fundamentally part of Terraform's architecture, and you
should **use a Terraform state backend with encryption enabled, such as Cloud
Storage**.

### Private Cluster

The Kubernetes cluster is a "private" cluster, meaning nodes do not have
publicly exposed IP addresses, and pods are only publicly accessible if exposed
through a load balancer service. Additionally, only authorized IP CIDR blocks
are able to communicate with the Kubernetes master nodes.

The default allowed CIDR is `0.0.0.0/0 (anyone)`. **You should restrict this
CIDR to the IP address(es) which will access the nodes!**.


## FAQ

**Q: How is this different than [kelseyhightower/vault-on-google-kubernetes-engine][kelseys-tutorial]?**
<br>
Kelsey's tutorial walks through the manual steps of provisioning a cluster,
creating all the components, etc. This captures those steps as
[Terraform](https://www.terraform.io) configurations, so it's a single command
to provision the cluster, service account, ip address, etc. Instead of using
cfssl, it uses the built-in Terraform functions.

**Q: Why are you using StatefulSets instead of Deployments?**
<br>
A: StatefulSets ensure that each pod is deployed in order. This is important for
the initial bootstrapping process, otherwise there's a race for which Vault
server initializes first with auto-init.

[gcs]: https://cloud.google.com/storage
[gke]: https://cloud.google.com/kubernetes-engine
[kms]: https://cloud.google.com/kms
[sdk]: https://cloud.google.com/sdk
[kelseys-tutorial]: https://github.com/kelseyhightower/vault-on-google-kubernetes-engine
[cloud-logging]: https://cloud.google.com/logging
[terraform]: https://www.terraform.io
[vault]: https://www.vaultproject.io
[vault-gcp-auth]: https://www.vaultproject.io/docs/auth/gcp.html
[vault-gcp-secrets]: https://www.vaultproject.io/docs/secrets/gcp/index.html
