# ============================================================================
# Talos VM Module - Provider Version Requirements
# ============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Proxmox Provider for VM management
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.98"
    }
  }
}
