# ============================================================================
# Windows VMs - Outputs
# ============================================================================
# This file provides outputs for Windows VM deployment.
# Outputs are organized by:
#   1. VM Details
#   2. SSH Connection Information
#   3. Ansible Inventory Integration
# ============================================================================

# ============================================================================
# 1. VM Details
# ============================================================================

output "vm_details" {
  description = "Details of all Windows VMs"
  value       = length(var.windows_vm_instances) > 0 ? module.windows_vms[0].vm_details : {}
}

output "vm_ips" {
  description = "Map of hostnames to IP addresses for Windows VMs"
  value       = length(var.windows_vm_instances) > 0 ? module.windows_vms[0].vm_ips : {}
}

output "compute_summary" {
  description = "Summary of deployed Windows VMs"
  value = {
    total       = length(var.windows_vm_instances)
    windows_vms = length(var.windows_vm_instances)
  }
}

# ============================================================================
# 2. SSH Connection Information
# ============================================================================

output "ssh_commands" {
  description = "SSH commands for all Windows VMs"
  value = {
    for hostname in keys(module.ssh_keys.ssh_key_paths) :
    hostname => "ssh -i ${module.ssh_keys.ssh_key_paths[hostname].private} Administrator@${
      length(var.windows_vm_instances) > 0 && contains(keys(module.windows_vms[0].vm_ips), hostname) ? module.windows_vms[0].vm_ips[hostname] : "N/A"
    }"
  }
}

output "ssh_key_paths" {
  description = "Paths to generated SSH keys for Windows VMs"
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
  value = length(var.windows_vm_instances) > 0 ? {
    for hostname, instance in module.windows_vms[0].vms :
    hostname => {
      ansible_host                         = instance.ipconfig0 != null && length(regexall("^ip=([^,/]+)", instance.ipconfig0)) > 0 ? regex("^ip=([^,/]+)", instance.ipconfig0)[0] : "N/A"
      ansible_user                         = "Administrator"
      ansible_ssh_private_key_file         = module.ssh_keys.ssh_key_paths[hostname].private
      ansible_connection                   = "winrm"
      ansible_port                         = 5985
      ansible_winrm_transport              = "basic"
      ansible_winrm_server_cert_validation = "ignore"
      type                                 = "windows-vm"
      groups                               = try(local.instances_map[hostname].tags, [])
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
      hostname => "ssh -i ${module.ssh_keys.ssh_key_paths[hostname].private} Administrator@${
        length(var.windows_vm_instances) > 0 && contains(keys(module.windows_vms[0].vm_ips), hostname) ? module.windows_vms[0].vm_ips[hostname] : "N/A"
      }"
    } :
    "# ${hostname}\n${cmd}"
  ])
}

output "deployment_summary" {
  description = "Deployment summary with resource counts and next steps"
  value = templatefile("${path.module}/templates/deployment-summary.tftpl", {
    windows_vm_count    = length(var.windows_vm_instances)
    ssh_key_directory   = module.ssh_keys.ssh_key_directory
    ssh_key_count       = length(keys(module.ssh_keys.ssh_key_paths))
    inventory_yaml_path = "../../ansible/inventory/windows-vms-hosts.yml"
    inventory_ini_path  = "../../ansible/inventory/windows-vms-hosts.ini"
    host_count          = length(var.windows_vm_instances)
  })
}
