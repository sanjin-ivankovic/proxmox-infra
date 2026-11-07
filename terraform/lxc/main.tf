# ============================================================================
# LXC Containers - Main Orchestration
# ============================================================================
# This file orchestrates the deployment of LXC containers on Proxmox VE.
#
# Architecture:
#   1. lxc-instance: Provisions LXC containers with SSH key generation
#
# Usage:
#   terraform init
#   terraform plan
#   terraform apply
# ============================================================================

# Local variables for instance maps
locals {
  # Convert instance list to map (keyed by hostname)
  instances_map = { for inst in var.lxc_instances : inst.hostname => inst }

}

# ============================================================================
# LXC Containers
# ============================================================================
# Provisions LXC containers (if any are defined)
# Conditional deployment: only runs if lxc_instances is not empty
# ============================================================================

module "lxc" {
  source = "./modules/lxc-instance"
  count  = length(var.lxc_instances) > 0 ? 1 : 0

  instances          = local.instances_map
  ssh_key_directory  = var.ssh_key_directory
  target_node        = var.target_node
  ostemplate         = var.lxc_ostemplate
  password           = var.lxc_password
  default_storage    = var.default_storage
  default_bridge     = var.default_bridge
  deploy_public_keys = var.deploy_public_keys
}
