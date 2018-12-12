# Generate self-signed TLS certificates. Unlike @kelseyhightower's original
# demo, this does not use cfssl and uses Terraform's internals instead.
resource "tls_private_key" "vault-ca" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "tls_self_signed_cert" "vault-ca" {
  key_algorithm   = "${tls_private_key.vault-ca.algorithm}"
  private_key_pem = "${tls_private_key.vault-ca.private_key_pem}"

  subject {
    common_name  = "vault-ca.local"
    organization = "HashiCorp Vault"
  }

  validity_period_hours = 8760
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "digital_signature",
    "key_encipherment",
  ]

  provisioner "local-exec" {
    command = "echo '${self.cert_pem}' > ../tls/ca.pem && chmod 0600 ../tls/ca.pem"
  }
}

# Create the Internal Vault server certificates
resource "tls_private_key" "vault_internal" {
  algorithm = "RSA"
  rsa_bits  = "2048"

  provisioner "local-exec" {
    command = "echo '${self.private_key_pem}' > ../tls/vault_internal.key && chmod 0600 ../tls/vault_internal.key"
  }
}

# Create the request to sign the internal cert with our CA
resource "tls_cert_request" "vault_internal" {
  key_algorithm   = "${tls_private_key.vault_internal.algorithm}"
  private_key_pem = "${tls_private_key.vault_internal.private_key_pem}"

  dns_names = ["${concat(var.vault_hostnames, var.custom_vault_hostnames)}"]

  ip_addresses = [
    "127.0.0.1",
    "${google_compute_global_address.vault.address}",
  ]

  subject {
    common_name  = "vault.local"
    organization = "HashiCorp Vault"
  }
}

# Sign the internal cert
resource "tls_locally_signed_cert" "vault_internal" {
  cert_request_pem = "${tls_cert_request.vault_internal.cert_request_pem}"

  ca_key_algorithm   = "${tls_private_key.vault-ca.algorithm}"
  ca_private_key_pem = "${tls_private_key.vault-ca.private_key_pem}"
  ca_cert_pem        = "${tls_self_signed_cert.vault-ca.cert_pem}"

  validity_period_hours = 8760

  allowed_uses = [
    "cert_signing",
    "client_auth",
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]

  provisioner "local-exec" {
    command = "echo '${self.cert_pem}' > ../tls/vault_internal.pem && echo '${tls_self_signed_cert.vault-ca.cert_pem}' >> ../tls/vault_internal.pem && chmod 0600 ../tls/vault_internal.pem"
  }
}

# Create the External Vault server certificates
resource "tls_private_key" "vault_external" {
  algorithm = "RSA"
  rsa_bits  = "2048"

  provisioner "local-exec" {
    command = "echo '${self.private_key_pem}' > ../tls/vault_external.key && chmod 0600 ../tls/vault_external.key"
  }
}

# Create the request to sign the external facing cert with our CA
resource "tls_cert_request" "vault_external" {
  key_algorithm   = "${tls_private_key.vault_external.algorithm}"
  private_key_pem = "${tls_private_key.vault_external.private_key_pem}"

  dns_names = ["${var.custom_vault_hostnames}"]

  ip_addresses = [
    "${google_compute_global_address.vault.address}",
  ]

  subject {
    common_name  = "vault.local"
    organization = "HashiCorp Vault"
  }
}

# Sign the external facing cert
resource "tls_locally_signed_cert" "vault_external" {
  cert_request_pem = "${tls_cert_request.vault_external.cert_request_pem}"

  ca_key_algorithm   = "${tls_private_key.vault-ca.algorithm}"
  ca_private_key_pem = "${tls_private_key.vault-ca.private_key_pem}"
  ca_cert_pem        = "${tls_self_signed_cert.vault-ca.cert_pem}"

  validity_period_hours = 8760

  allowed_uses = [
    "cert_signing",
    "client_auth",
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]

  provisioner "local-exec" {
    command = "echo '${self.cert_pem}' > ../tls/vault_external.pem && echo '${tls_self_signed_cert.vault-ca.cert_pem}' >> ../tls/vault_external.pem && chmod 0600 ../tls/vault_external.pem"
  }
}
