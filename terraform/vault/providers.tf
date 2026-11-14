# Committed (not generated) so CI can `init -backend=false && validate` this
# unit from a plain checkout; root.hcl skips its versions/provider for this
# directory.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.13"
    }
  }
}

# Address and token come from VAULT_ADDR and VAULT_TOKEN (README,
# Credentials). The provider works with a 20-minute child token of the one
# given, so the login token never sits in state.
provider "vault" {}
