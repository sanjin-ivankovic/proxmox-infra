# HashiCorp Vault server configuration (services/vault/docker-compose.yml).
# Mounted read-only at /vault/config/vault.hcl. A change here takes effect
# only on the next manual redeploy, which seals Vault (docs/VAULT.md).

ui = true

# Required for integrated storage since Vault 1.20; mlock does not mix with
# the memory-mapped BoltDB files Raft uses.
disable_mlock = true

api_addr     = "https://vault.example.com:8200"
cluster_addr = "https://127.0.0.1:8201"

storage "raft" {
  path    = "/vault/file"
  node_id = "vault-1"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "127.0.0.1:8201"
  tls_cert_file   = "/vault/tls/fullchain.pem"
  tls_key_file    = "/vault/tls/privkey.pem"
  tls_min_version = "tls12"
  # By default the listener asks every client for a certificate, and browsers
  # then prompt for one from the OS keychain. No auth method here uses certs.
  tls_disable_client_certs = "true"

  # Prometheus scrapes /v1/sys/metrics without a token; it exposes metrics
  # only, and the sealed state is what alerting needs most.
  telemetry {
    unauthenticated_metrics_access = true
  }
}

telemetry {
  prometheus_retention_time = "24h"
  disable_hostname          = true
}
