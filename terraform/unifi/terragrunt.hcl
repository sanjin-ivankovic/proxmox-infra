# UniFi network (UCG Max controller) — networks, WLANs, firewall zones and
# zone policies as code. State: R2 key "unifi/terraform.tfstate" (from the
# shared root.hcl remote_state). Providers are declared in providers.tf; root.hcl
# skips its Proxmox versions.tf/provider.tf for this unit.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  extra_arguments "secret_vars" {
    commands           = get_terraform_commands_that_need_vars()
    optional_var_files = ["${get_terragrunt_dir()}/terraform.tfvars.secret"]
  }
}
