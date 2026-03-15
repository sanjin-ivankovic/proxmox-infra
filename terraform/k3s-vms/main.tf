# ============================================================================
# K3s VMs - Main Orchestration
# ============================================================================
# This file orchestrates the deployment of K3s cluster VMs on Proxmox VE.
#
# Architecture:
#   1. compute-base: Generates unique SSH keys for K3s VMs
#   2. vm-k3s: Provisions Linux VMs configured for K3s
#
# Usage:
#   terraform init
#   terraform plan
#   terraform apply
# ============================================================================

locals {
  instances_map = { for inst in var.k3s_vm_instances : inst.hostname => inst }

  instances_for_keys = {
    for k, v in local.instances_map : k => { hostname = k }
  }

  skip_instances = toset([
    for inst in var.k3s_vm_instances : inst.hostname
    if try(inst.preserve_ssh_key, false)
  ])
}

# ============================================================================
# Module 1: Compute Base (SSH Key Generation)
# ============================================================================

module "ssh_keys" {
  source = "../modules/compute-base"

  instances         = local.instances_for_keys
  ssh_key_directory = var.ssh_key_directory
  skip_instances    = local.skip_instances
}

# ============================================================================
# Module 2: K3s VMs (Cloud-Init)
# ============================================================================
# Uses the same vm-linux module as linux-vms project.
# K3s-specific configuration (role assignment, cluster setup) is handled
# by Ansible after Terraform provisioning.
# ============================================================================

# TODO: Uncomment and configure when activating this project
# module "k3s_vms" {
#   source = "../linux-vms/modules/vm-linux"
#   count  = length(var.k3s_vm_instances) > 0 ? 1 : 0
#
#   instances                = local.instances_map
#   ssh_public_keys          = module.ssh_keys.public_keys
#   target_node              = var.target_node
#   clone_template           = var.k3s_vm_template
#   default_storage          = var.default_storage
#   default_bridge           = var.default_bridge
#   install_qemu_guest_agent = var.k3s_vm_install_qemu_guest_agent
#   cicustom                 = var.k3s_vm_cicustom
# }
