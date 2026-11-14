# Proxmox VE vzdump backup jobs. State: R2 key "backup/terraform.tfstate"
# (from the shared root.hcl remote_state). Providers are declared in
# providers.tf; root.hcl skips its generated versions.tf/provider.tf here.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Guest VMIDs come from the lxc and talos state, so a new or renumbered guest
# joins its backup job on the next apply of this unit. Mocks cover only
# validate on a checkout with no state access; plan and apply always read the
# real outputs.
dependency "lxc" {
  config_path = "../lxc"

  mock_outputs_allowed_terraform_commands = ["validate"]
  mock_outputs = {
    container_details = {}
  }
}

dependency "talos" {
  config_path = "../talos"

  mock_outputs_allowed_terraform_commands = ["validate"]
  mock_outputs = {
    ansible_info = {}
  }
}

# Secrets come from HashiCorp Vault, kv/terraform/* (docs/VAULT.md), read with
# the operator's `vault login` token; Terragrunt passes them as TF_VAR_*, so they
# never touch disk. --terragrunt-quiet keeps them out of its logs. A sealed
# Vault or an expired login stops every command here: unseal or log in again.
locals {
  proxmox = jsondecode(run_cmd("--terragrunt-quiet", "--terragrunt-global-cache", "vault", "kv", "get",
  "-address=https://vault.example.com:8200", "-mount=kv", "-format=json", "terraform/proxmox")).data.data
  backup = jsondecode(run_cmd("--terragrunt-quiet", "--terragrunt-global-cache", "vault", "kv", "get",
  "-address=https://vault.example.com:8200", "-mount=kv", "-format=json", "terraform/backup")).data.data
}

inputs = {
  proxmox_api_url          = "https://10.105.0.4:8006/api2/json"
  proxmox_api_token_id     = local.proxmox.api_token_id
  proxmox_api_token_secret = local.proxmox.api_token_secret
  pbs_storage_password     = local.backup.pbs_storage_password

  lxc_vmids   = sort([for host, c in dependency.lxc.outputs.container_details : tostring(c.vmid)])
  talos_vmids = sort([for host, vm in dependency.talos.outputs.ansible_info : tostring(vm.vmid)])
}
