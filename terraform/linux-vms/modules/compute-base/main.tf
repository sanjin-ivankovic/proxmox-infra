# ============================================================================
# Compute Base Module - Shared SSH Key Generation
# ============================================================================
# This module generates unique ED25519 SSH key pairs for each compute resource
# (LXC containers, Linux VMs, Windows VMs). Keys are stored in the configured
# SSH directory (default: ~/.ssh) and are used for automated provisioning.
#
# Usage:
#   module "ssh_keys" {
#     source = "./modules/compute-base"
#     instances = {
#       "dns-1"  = { type = "lxc" }
#       "web-01" = { type = "vm-linux" }
#       "ad-dc"  = { type = "vm-windows" }
#     }
#     ssh_key_directory = "~/.ssh"
#   }
# ============================================================================

locals {
  ssh_key_path = pathexpand(var.ssh_key_directory)

  # Filter out instances that should skip SSH key generation (imported containers)
  instances_needing_keys = {
    for k, v in var.instances : k => v
    if !contains(var.skip_instances, k)
  }

  # Instances that already have SSH keys (imported containers)
  instances_with_existing_keys = {
    for k, v in var.instances : k => v
    if contains(var.skip_instances, k)
  }
}

# Read existing SSH public keys for imported containers
data "local_file" "existing_public_keys" {
  for_each = local.instances_with_existing_keys
  filename = "${local.ssh_key_path}/${each.key}_id_ed25519.pub"
}

# Generate unique ED25519 SSH key pair for each compute resource
# IMPORTANT: Only generates keys for NEW resources, not imported ones
resource "tls_private_key" "keys" {
  for_each  = local.instances_needing_keys
  algorithm = "ED25519"
}

# Store private keys in SSH directory with 0600 permissions
# IMPORTANT: Only creates files for NEW resources, not imported ones
resource "local_file" "private_keys" {
  for_each        = local.instances_needing_keys
  filename        = "${local.ssh_key_path}/${each.key}_id_ed25519"
  content         = tls_private_key.keys[each.key].private_key_openssh
  file_permission = "0600"
}

# Store public keys in SSH directory with 0644 permissions
# IMPORTANT: Only creates files for NEW resources, not imported ones
resource "local_file" "public_keys" {
  for_each        = local.instances_needing_keys
  filename        = "${local.ssh_key_path}/${each.key}_id_ed25519.pub"
  content         = tls_private_key.keys[each.key].public_key_openssh
  file_permission = "0644"
}
