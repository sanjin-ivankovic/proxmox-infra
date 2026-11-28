include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Every command that takes variables loads the host list, so plain terragrunt
# plan/apply/import work without -var-file flags.
terraform {
  extra_arguments "unit_vars" {
    commands = get_terraform_commands_that_need_vars()
    optional_var_files = [
      "${get_terragrunt_dir()}/instances/talos.auto.tfvars",
    ]
  }
}

# Secrets come from HashiCorp Vault, kv/terraform/* (docs/VAULT.md), read with
# the operator's `vault login` token; Terragrunt passes them as TF_VAR_*, so they
# never touch disk. --terragrunt-quiet keeps them out of its logs. A sealed
# Vault or an expired login stops every command here: unseal or log in again.
locals {
  proxmox = jsondecode(run_cmd("--terragrunt-quiet", "--terragrunt-global-cache", "vault", "kv", "get",
  "-address=https://vault.example.com:8200", "-mount=kv", "-format=json", "terraform/proxmox")).data.data
}

inputs = {
  proxmox_api_url          = "https://10.105.0.4:8006/api2/json"
  proxmox_api_token_id     = local.proxmox.api_token_id
  proxmox_api_token_secret = local.proxmox.api_token_secret
}
