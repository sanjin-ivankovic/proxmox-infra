# ============================================================================
# Talos VMs - Main Configuration
# ============================================================================
# This configuration manages Talos Linux VM deployment on Proxmox.
# Talos VMs boot from ISO and are managed via API (talosctl), not SSH.
#
# Key differences from linux-vms:
#   - No SSH key generation (API-only access)
#   - Boot from Talos ISO instead of cloud-init templates
#   - UEFI (OVMF) boot recommended
#   - Minimum 2GB RAM requirement
# ============================================================================

# ============================================================================
# Local Variables
# ============================================================================

locals {
  # Map instances by hostname for easier lookups
  instances_map = {
    for inst in var.talos_vm_instances :
    inst.hostname => inst
  }

  # Separate control plane and worker nodes for inventory
  controlplane_nodes = {
    for hostname, inst in local.instances_map :
    hostname => inst if inst.talos_role == "controlplane"
  }

  worker_nodes = {
    for hostname, inst in local.instances_map :
    hostname => inst if inst.talos_role == "worker"
  }
}

# ============================================================================
# Talos VM Deployment Module
# ============================================================================

module "talos_vms" {
  source = "./modules/vm-talos"
  count  = length(var.talos_vm_instances) > 0 ? 1 : 0

  # VM instances
  instances = local.instances_map

  # Infrastructure defaults
  target_node     = var.target_node
  default_storage = var.default_storage
  default_bridge  = var.default_bridge

  # Talos-specific configuration
  talos_iso_storage = var.talos_iso_storage
  talos_iso_file    = var.talos_iso_file
}

# ============================================================================
# Ansible Inventory Generation
# ============================================================================

resource "local_file" "ansible_inventory" {
  count = length(var.talos_vm_instances) > 0 ? 1 : 0

  filename        = "${path.module}/../../ansible/talos/inventory/hosts.yml"
  file_permission = "0644"

  content = templatefile("${path.module}/templates/ansible-inventory.yml.tftpl", {
    controlplane_nodes = local.controlplane_nodes
    worker_nodes       = local.worker_nodes
  })
}
