# Committed (not generated) so CI can `init -backend=false && validate` this
# unit from a plain checkout; root.hcl skips its Proxmox versions/provider for
# this directory.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    unifi = {
      source  = "filipowm/unifi"
      version = "~> 1.1"
    }
  }
}

provider "unifi" {
  api_url = var.unifi_api_url
  api_key = var.unifi_api_key

  # The UCG Max serves a self-signed certificate on its management address.
  allow_insecure = true
}
