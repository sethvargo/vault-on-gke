# HashiCorp Vault on GKE with Terraform

This tutorial walks through provisioning a highly-available [HashiCorp Vault][vault] cluster on [Google Kubernetes Engine][gke] using [HashiCorp Terraform][terraform] as the provisioning tool.

This tutorial is based on [Kelsey Hightower's Vault on Google Kubernetes
Engine](https://github.com/kelseyhightower/vault-on-google-kubernetes-engine), but focuses on codifying the steps in Terraform instead of teaching you them individually. If you would like to know how to provision HashiCorp Vault on Kuberenetes step-by-step (aka "the hard way"), please follow Kelsey's repository instead.

## Feature Highlights

- **Vault HA** - The Vault cluster is deployed in HA mode backed by [Google Cloud Storage][gcs]

- **Production Hardened** - Vault is deployed according to the [production hardening guide](https://www.vaultproject.io/guides/operations/production.html).

- **Auto-Init and Unseal** - Vault is automatically initialized and unsealed at runtime. The unseal keys are encrypted with [Google Cloud KMS][kms] and stored in [Google Cloud Storage][gcs]

- **Full Isolation** - The Vault cluster is provisioned in it's own Kubernetes cluster in a dedicated GCP project that is provisioned dynamically at runtime. Clients connect to Vault using **only** the load balancer and Vault is treated as a managed external service.

## Tutorial

1. Download and install [Terraform][terraform]

1. Download, install, and configure the [Google Cloud SDK][sdk]. You will need to configure your default application credentials so Terraform can run. It will run against your default project, but all resources are created in the (new) project that it creates.

1. Run Terraform:

    ```
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

1. Export the Vault variables:

    ```
    # Make sure you're in the terraform/ directory
    # $ cd terraform/

    $ export VAULT_ADDR="https://$(terraform output address)"
    $ export VAULT_TOKEN="$(terraform output token)"
    $ export VAULT_CAPATH="$(cd ../ && pwd)/tls/ca.pem"
    ```

1. Run some commands

    ```
    $ vault kv put secret/foo a=b
    ```

## Cleaning Up

```
$ terraform destroy
```

Note that this can sometimes fail. Re-run it and it should succeed. If things get into a bad state, you can always just delete the project.

## Security

This set of Terraform configurations is designed to make your life easy. It's
a best-practices setup for Vault, but also aids in the retrieval of the initial
root token. **The decrypted initial root token will be stored in your state file!**

As such, you should use a Terraform state backend that supports encryption.
Alternatively you can remove the decryption calls in `k8s.tf` and manually
decrypt the root token using `gcloud`. Terraform auto-generates the command, but
you will need to setup the permissions for your local default application
credentials.

```
$ $(terraform output token_decrypt_command)
```

## FAQ

**Q: How is this different than [kelseyhightower/vault-on-google-kubernetes-engine](https://github.com/kelseyhightower/vault-on-google-kubernetes-engine)?**
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
[terraform]: https://www.terraform.io
[vault]: https://www.vaultproject.io
