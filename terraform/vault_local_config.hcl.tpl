
api_addr     = "https://${vault_address}"
cluster_addr = "https://$(POD_IP_ADDR):8201"

log_level = "warn"

ui = true

seal "gcpckms" {
  project    = "${project}"
  region     = "${region}"
  key_ring   = "${key_ring}"
  crypto_key = "${crypto_key}"
}

storage "gcs" {
  bucket     = "${bucket_name}"
  ha_enabled = "true"
}

listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = "true"
}

listener "tcp" {
  address       = "$(POD_IP_ADDR):8200"
  tls_cert_file = "/etc/vault/tls/vault.crt"
  tls_key_file  = "/etc/vault/tls/vault.key"

  tls_disable_client_certs = true
}
