# Committed (not generated) so CI can `init -backend=false && validate` this
# unit from a plain checkout; root.hcl skips its versions/provider for this
# directory. Keep the provider constraint in step with root.hcl.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.122"
    }
  }
}

provider "proxmox" {
  endpoint  = replace(var.proxmox_api_url, "/api2/json", "")
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true
}
