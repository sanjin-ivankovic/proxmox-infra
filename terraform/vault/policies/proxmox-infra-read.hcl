# Read the secrets the proxmox-infra playbooks use, kv/proxmox-infra/*.
path "kv/data/proxmox-infra/*" {
  capabilities = ["read"]
}

# The Komodo webhook secret, shared with proxmox-infra's CI.
path "kv/data/ci/komodo" {
  capabilities = ["read"]
}
