# UniFi network (UCG Max controller) — networks, WLANs, firewall zones and
# zone policies as code. State: R2 key "unifi/terraform.tfstate" (from the
# shared root.hcl remote_state). Providers are declared in providers.tf; root.hcl
# skips its Proxmox versions.tf/provider.tf for this unit.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Secrets come from HashiCorp Vault, kv/terraform/* (docs/VAULT.md), read with
# the operator's `vault login` token; Terragrunt passes them as TF_VAR_*, so they
# never touch disk. --terragrunt-quiet keeps them out of its logs. A sealed
# Vault or an expired login stops every command here: unseal or log in again.
locals {
  unifi = jsondecode(run_cmd("--terragrunt-quiet", "--terragrunt-global-cache", "vault", "kv", "get",
  "-address=https://vault.example.com:8200", "-mount=kv", "-format=json", "terraform/unifi")).data.data
}

inputs = {
  unifi_api_key    = local.unifi.api_key
  wlan_passphrases = local.unifi.wlan_passphrases
}
