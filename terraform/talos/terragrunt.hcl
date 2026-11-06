include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Every command that takes variables loads the secret and the host list, so
# plain terragrunt plan/apply/import work without -var-file flags.
terraform {
  extra_arguments "unit_vars" {
    commands = get_terraform_commands_that_need_vars()
    optional_var_files = [
      "${get_terragrunt_dir()}/terraform.tfvars.secret",
      "${get_terragrunt_dir()}/instances/talos.auto.tfvars",
    ]
  }
}
