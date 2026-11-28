# ============================================================================
# LXC Containers - Outputs
# ============================================================================
# This file provides outputs for LXC container deployment.
# Outputs are organized by:
#   1. Container Details
#   2. SSH Connection Information
#   3. Ansible Inventory Integration
#   4. Convenience Outputs
# ============================================================================

# ============================================================================
# 1. Container Details
# ============================================================================

output "container_details" {
  description = "Details of all LXC containers"
  value       = length(var.lxc_instances) > 0 ? module.lxc[0].container_details : {}
}

output "container_ips" {
  description = "Map of hostnames to IP addresses for LXC containers"
  value       = length(var.lxc_instances) > 0 ? module.lxc[0].container_ips : {}
}

output "compute_summary" {
  description = "Summary of deployed LXC containers"
  value = {
    total = length(var.lxc_instances)
    lxc   = length(var.lxc_instances)
  }
}

# ============================================================================
# 2. SSH Connection Information
# ============================================================================

output "ssh_commands" {
  description = "SSH commands for all LXC containers"
  value = length(var.lxc_instances) > 0 ? {
    for hostname in keys(module.lxc[0].ssh_key_paths) :
    hostname => "ssh -i ${module.lxc[0].ssh_key_paths[hostname].private} root@${
      contains(keys(module.lxc[0].container_ips), hostname) ? module.lxc[0].container_ips[hostname] : "N/A"
    }"
  } : {}
}

output "ssh_key_paths" {
  description = "Paths to generated SSH keys for LXC containers"
  value       = length(var.lxc_instances) > 0 ? module.lxc[0].ssh_key_paths : {}
}

output "ssh_key_directory" {
  description = "Directory where SSH keys are stored"
  value       = length(var.lxc_instances) > 0 ? module.lxc[0].ssh_key_directory : pathexpand(var.ssh_key_directory)
}

# ============================================================================
# 3. Ansible Inventory Integration
# ============================================================================

output "ansible_info" {
  description = "Inventory data for Ansible consumption"
  value = length(var.lxc_instances) > 0 ? {
    for hostname, inst in local.instances_map :
    hostname => {
      ansible_host                 = split("/", inst.ip)[0]
      ansible_user                 = "root"
      ansible_ssh_private_key_file = module.lxc[0].ssh_key_paths[hostname].private
      type                         = "lxc"
      groups                       = try(inst.tags, [])
    }
  } : {}
}

# ============================================================================
# 4. Convenience Outputs
# ============================================================================

output "quick_ssh" {
  description = "Quick reference: SSH commands (formatted for terminal)"
  value = length(var.lxc_instances) > 0 ? join("\n", [
    for hostname, cmd in {
      for hostname in keys(module.lxc[0].ssh_key_paths) :
      hostname => "ssh -i ${module.lxc[0].ssh_key_paths[hostname].private} root@${
        contains(keys(module.lxc[0].container_ips), hostname) ? module.lxc[0].container_ips[hostname] : "N/A"
      }"
    } :
    "# ${hostname}\n${cmd}"
  ]) : ""
}

output "deployment_summary" {
  description = "Deployment summary with resource counts and next steps"
  value = templatefile("${path.module}/templates/deployment-summary.tftpl", {
    lxc_count         = length(var.lxc_instances)
    ssh_key_directory = length(var.lxc_instances) > 0 ? module.lxc[0].ssh_key_directory : pathexpand(var.ssh_key_directory)
    ssh_key_count     = length(var.lxc_instances) > 0 ? length(keys(module.lxc[0].ssh_key_paths)) : 0
  })
}
