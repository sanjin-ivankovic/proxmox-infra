# ============================================================================
# HCP Terraform Cloud Backend
# ============================================================================
# State is stored remotely in HCP Terraform (app.terraform.io).
# Supports state locking and is independent of GitLab availability.
#
# Prerequisites:
#   terraform login  # authenticate with HCP Terraform
# ============================================================================

terraform {
  cloud {
    organization = "Example"

    workspaces {
      name = "proxmox-talos"
    }
  }
}
