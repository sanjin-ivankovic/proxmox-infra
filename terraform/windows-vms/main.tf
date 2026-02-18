# ============================================================================
# Windows VMs - Main Orchestration
# ============================================================================
# This file orchestrates the deployment of Windows VMs on Proxmox VE.
#
# Architecture:
#   1. compute-base: Generates unique SSH keys for Windows VMs
#   2. vm-windows: Provisions Windows VMs with cloudbase-init
#   3. ansible-inventory: Generates Windows VMs-only Ansible inventory
#
# Usage:
#   terraform init
#   terraform plan
#   terraform apply
# ============================================================================

# Local variables for instance maps
locals {
  # Convert instance list to map (keyed by hostname)
  instances_map = { for inst in var.windows_vm_instances : inst.hostname => inst }

  # Normalize instances for SSH key generation (only hostname needed)
  instances_for_keys = {
    for k, v in local.instances_map : k => { hostname = k }
  }

  # Derive skip_instances from preserve_ssh_key field
  skip_instances = toset([
    for inst in var.windows_vm_instances : inst.hostname
    if try(inst.preserve_ssh_key, false)
  ])

  # Determine which SSH keys should exist (for validation)
  required_ssh_keys = toset([
    for inst in var.windows_vm_instances : inst.hostname
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
# Validates that SSH keys exist for non-imported instances
# This prevents deployment failures due to missing keys
# ============================================================================

check "ssh_keys_exist" {
  assert {
    condition = alltrue([
      for hostname, path in local.expected_ssh_key_paths :
      fileexists(path)
    ])
    error_message = "Some required SSH keys do not exist. Run 'terraform apply' to generate them, or set preserve_ssh_key = true for imported instances."
  }
}

# ============================================================================
# Module 1: Compute Base (SSH Key Generation)
# ============================================================================
# Generates unique ED25519 SSH key pairs for Windows VMs
# Keys are stored in ~/.ssh/<hostname>_id_ed25519
# ============================================================================

module "ssh_keys" {
  source = "./modules/compute-base"

  instances         = local.instances_for_keys
  ssh_key_directory = var.ssh_key_directory
  skip_instances    = local.skip_instances
}

# ============================================================================
# Module 2: Windows VMs (Cloudbase-Init)
# ============================================================================
# Provisions Windows VMs from cloudbase-init templates (Windows Server)
# Conditional deployment: only runs if windows_vm_instances is not empty
# ============================================================================

module "windows_vms" {
  source = "./modules/vm-windows"
  count  = length(var.windows_vm_instances) > 0 ? 1 : 0

  instances       = local.instances_map
  ssh_public_keys = module.ssh_keys.public_keys
  target_node     = var.target_node
  clone_template  = var.windows_vm_template
  default_storage = var.default_storage
  default_bridge  = var.default_bridge
}

# ============================================================================
# Module 3: Ansible Inventory Generation (COMMENTED OUT - Module not implemented)
# ============================================================================
# Generates Windows VMs-only Ansible inventory
# Outputs both YAML (hosts.yml) and INI (hosts.ini) formats
# ============================================================================

# module "ansible_inventory" {
#   source = "./modules/ansible-inventory"
#
#   # Windows VM hosts only
#   windows_vm_hosts = length(var.windows_vm_instances) > 0 ? {
#     for hostname, instance in module.windows_vms[0].vms :
#     hostname => {
#       ansible_host                         = length(regexall("^ip=([^,/]+)", instance.ipconfig0)) > 0 ? regex("^ip=([^,/]+)", instance.ipconfig0)[0] : "N/A"
#       ansible_user                         = "Administrator"
#       ansible_ssh_private_key_file         = module.ssh_keys.ssh_key_paths[hostname].private
#       ansible_connection                   = "winrm"
#       ansible_port                         = 5985
#       ansible_winrm_transport              = "basic"
#       ansible_winrm_server_cert_validation = "ignore"
#       type                                 = "windows-vm"
#     }
#   } : {}
#
#   # Empty maps for other types (not used in this project)
#   lxc_hosts      = {}
#   linux_vm_hosts = {}
#
#   template_path    = "${path.module}/../templates"
#   output_directory = "${path.module}/../../ansible/inventory"
# }
