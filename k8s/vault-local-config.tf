api_addr     = "https://${load_balancer_ip}"
cluster_addr = "https://$(POD_IP_ADDR):8201"

log_level = "warn"

ui = true

seal "gcpckms" {
  project    = "${project}"
  region     = "${kms_region}"
  key_ring   = "${kms_key_ring}"
  crypto_key = "${kms_crypto_key}"
}

storage "gcs" {
  bucket     = "${gcs_bucket_name}"
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
