# Terraform version requirements
# Defines minimum versions for Terraform and required providers

terraform {
  # Require Terraform 1.5.0+ for modern check blocks
  required_version = ">= 1.5.0"

  # Backend configuration - GitLab HTTP backend (active)
  # See backend.tf for GitLab configuration

  # Backup option: Local backend (commented out)
  # Uncomment this and remove backend.tf to use local state storage
  # backend "local" {
  #   path = "generated/state/terraform.tfstate"
  # }

  required_providers {
    # Proxmox Provider for VM management
    proxmox = {
      source  = "Telmate/proxmox"
      version = "3.0.2-rc07" # Using RC version for specific features
    }

    # Local Provider for file operations (inventory generation)
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
