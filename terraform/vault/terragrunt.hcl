# Vault configuration as code: mounts, audit, policies and auth methods.
# State: R2 key "vault/terraform.tfstate" (from the shared root.hcl
# remote_state). Providers are declared in providers.tf; root.hcl skips its
# generated versions.tf/provider.tf here.
#
# No secret values live in this unit, only structure. Secrets are written
# with `vault kv put` and passwords with the CLI, so they never reach state.
include "root" {
  path = find_in_parent_folders("root.hcl")
}
