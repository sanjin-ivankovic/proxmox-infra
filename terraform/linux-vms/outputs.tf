# ============================================================================
# Linux VMs - Outputs
# ============================================================================
# This file provides outputs for Linux VM deployment.
# Outputs are organized by:
#   1. VM Details
#   2. SSH Connection Information
#   3. Ansible Inventory Integration
# ============================================================================

# ============================================================================
# 1. VM Details
# ============================================================================

output "vm_details" {
  description = "Details of all Linux VMs"
  value       = length(var.linux_vm_instances) > 0 ? module.linux_vms[0].vm_details : {}
}

output "vm_ips" {
  description = "Map of hostnames to IP addresses for Linux VMs"
  value       = length(var.linux_vm_instances) > 0 ? module.linux_vms[0].vm_ips : {}
}

output "compute_summary" {
  description = "Summary of deployed Linux VMs"
  value = {
    total     = length(var.linux_vm_instances)
    linux_vms = length(var.linux_vm_instances)
  }
}

# ============================================================================
# 2. SSH Connection Information
# ============================================================================

output "ssh_commands" {
  description = "SSH commands for all Linux VMs"
  value = {
    for hostname in keys(module.ssh_keys.ssh_key_paths) :
    hostname => "ssh -i ${module.ssh_keys.ssh_key_paths[hostname].private} root@${
      length(var.linux_vm_instances) > 0 && contains(keys(module.linux_vms[0].vm_ips), hostname) ? module.linux_vms[0].vm_ips[hostname] : "N/A"
    }"
  }
}

output "ssh_key_paths" {
  description = "Paths to generated SSH keys for Linux VMs"
  value       = module.ssh_keys.ssh_key_paths
}

output "ssh_key_directory" {
  description = "Directory where SSH keys are stored"
  value       = module.ssh_keys.ssh_key_directory
}

# ============================================================================
# 3. Ansible Inventory Integration
# ============================================================================

output "ansible_info" {
  description = "Inventory data for Ansible consumption"
  value = length(var.linux_vm_instances) > 0 ? {
    for hostname, inst in local.instances_map :
    hostname => {
      ansible_host                 = split("/", inst.ip)[0]
      ansible_user                 = "root"
      ansible_ssh_private_key_file = module.ssh_keys.ssh_key_paths[hostname].private
      groups                       = try(inst.tags, [])
    }
  } : {}
}

# ============================================================================
# 4. Convenience Outputs
# ============================================================================

output "quick_ssh" {
  description = "Quick reference: SSH commands (formatted for terminal)"
  value = join("\n", [
    for hostname, cmd in {
      for hostname in keys(module.ssh_keys.ssh_key_paths) :
      hostname => "ssh -i ${module.ssh_keys.ssh_key_paths[hostname].private} root@${
        length(var.linux_vm_instances) > 0 && contains(keys(module.linux_vms[0].vm_ips), hostname) ? module.linux_vms[0].vm_ips[hostname] : "N/A"
      }"
    } :
    "# ${hostname}\n${cmd}"
  ])
}

output "deployment_summary" {
  description = "Deployment summary with resource counts and next steps"
  value = templatefile("${path.module}/templates/deployment-summary.tftpl", {
    linux_vm_count    = length(var.linux_vm_instances)
    ssh_key_directory = module.ssh_keys.ssh_key_directory
    ssh_key_count     = length(keys(module.ssh_keys.ssh_key_paths))
  })
}
