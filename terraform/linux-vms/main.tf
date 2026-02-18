# ============================================================================
# Linux VMs - Main Orchestration
# ============================================================================
# This file orchestrates the deployment of Linux VMs on Proxmox VE.
#
# Architecture:
#   1. compute-base: Generates unique SSH keys for Linux VMs
#   2. vm-linux: Provisions Linux VMs with cloud-init
#   3. ansible-inventory: Generates Linux VMs-only Ansible inventory
#
# Usage:
#   terraform init
#   terraform plan
#   terraform apply
# ============================================================================

# Local variables for instance maps
locals {
  # Convert instance list to map (keyed by hostname)
  instances_map = { for inst in var.linux_vm_instances : inst.hostname => inst }

  # Normalize instances for SSH key generation (only hostname needed)
  instances_for_keys = {
    for k, v in local.instances_map : k => { hostname = k }
  }

  # Derive skip_instances from preserve_ssh_key field
  skip_instances = toset([
    for inst in var.linux_vm_instances : inst.hostname
    if try(inst.preserve_ssh_key, false)
  ])

  # Determine which SSH keys should exist (for validation)
  required_ssh_keys = toset([
    for inst in var.linux_vm_instances : inst.hostname
    if !try(inst.preserve_ssh_key, false)
  ])

  # Build expected SSH key paths for validation
  expected_ssh_key_paths = {
    for hostname in local.required_ssh_keys :
    hostname => "${pathexpand(var.ssh_key_directory)}/${hostname}_id_ed25519"
  }
}

# ============================================================================
# Pre-flight Checks: SSH Key Availability
# ============================================================================
# Validates that SSH keys exist for non-preserved instances
# This prevents deployment failures due to missing keys
# ============================================================================

check "ssh_keys_exist" {
  assert {
    condition = alltrue([
      for hostname, path in local.expected_ssh_key_paths :
      fileexists(path)
    ])
    error_message = "Some required SSH keys do not exist. Run 'terraform apply' to generate them, or set preserve_ssh_key=true for imported hosts."
  }
}

# ============================================================================
# Module 1: Compute Base (SSH Key Generation)
# ============================================================================
# Generates unique ED25519 SSH key pairs for Linux VMs
# Keys are stored in ~/.ssh/<hostname>_id_ed25519
# ============================================================================

module "ssh_keys" {
  source = "./modules/compute-base"

  instances         = local.instances_for_keys
  ssh_key_directory = var.ssh_key_directory
  skip_instances    = local.skip_instances
}

# ============================================================================
# Module 2: Linux VMs (Cloud-Init)
# ============================================================================
# Provisions Linux VMs from cloud-init templates (Debian/Ubuntu)
# Conditional deployment: only runs if linux_vm_instances is not empty
# ============================================================================

module "linux_vms" {
  source = "./modules/vm-linux"
  count  = length(var.linux_vm_instances) > 0 ? 1 : 0

  instances                = local.instances_map
  ssh_public_keys          = module.ssh_keys.public_keys
  target_node              = var.target_node
  clone_template           = var.linux_vm_template
  default_storage          = var.default_storage
  default_bridge           = var.default_bridge
  install_qemu_guest_agent = var.linux_vm_install_qemu_guest_agent
  cicustom                 = var.linux_vm_cicustom
}
