# ============================================================================
# Talos VMs - Outputs
# ============================================================================
# This file provides outputs for Talos VM deployment.
# Outputs are organized by:
#   1. VM Details
#   2. Talos Connection Information (API-based)
#   3. Ansible Inventory Integration
# ============================================================================

# ============================================================================
# 1. VM Details
# ============================================================================

output "vm_details" {
  description = "Details of all Talos VMs"
  value       = length(var.talos_vm_instances) > 0 ? module.talos_vms[0].vm_details : {}
}

output "vm_ips" {
  description = "Map of hostnames to IP addresses for Talos VMs"
  value       = length(var.talos_vm_instances) > 0 ? module.talos_vms[0].vm_ips : {}
}

output "compute_summary" {
  description = "Summary of deployed Talos VMs"
  value = {
    total             = length(var.talos_vm_instances)
    controlplane      = length([for inst in var.talos_vm_instances : inst if inst.talos_role == "controlplane"])
    workers           = length([for inst in var.talos_vm_instances : inst if inst.talos_role == "worker"])
    total_cores       = length(var.talos_vm_instances) > 0 ? sum([for inst in var.talos_vm_instances : inst.cores * inst.sockets]) : 0
    total_memory_mb   = length(var.talos_vm_instances) > 0 ? sum([for inst in var.talos_vm_instances : inst.memory]) : 0
    total_memory_gb   = length(var.talos_vm_instances) > 0 ? ceil(sum([for inst in var.talos_vm_instances : inst.memory]) / 1024) : 0
  }
}

# ============================================================================
# 2. Ansible Inventory Integration
# ============================================================================

output "ansible_info" {
  description = "Inventory data for Ansible consumption"
  value = length(var.talos_vm_instances) > 0 ? {
    for hostname, instance in module.talos_vms[0].vms :
    hostname => {
      ansible_host        = split("/", local.instances_map[hostname].ip)[0]
      ansible_connection  = "local" # Talos uses talosctl API, not SSH
      type                = "talos"
      talos_role          = local.instances_map[hostname].talos_role
      vmid                = local.instances_map[hostname].vmid # Required for shutdown/startup playbooks
      groups              = concat(local.instances_map[hostname].tags, [local.instances_map[hostname].talos_role])
    }
  } : {}
}

# ============================================================================
# 3. Deployment Summary
# ============================================================================

output "deployment_summary" {
  description = "Deployment summary with resource counts and next steps"
  value = templatefile("${path.module}/templates/deployment-summary.tftpl", {
    talos_vm_count     = length(var.talos_vm_instances)
    controlplane_count = length([for inst in var.talos_vm_instances : inst if inst.talos_role == "controlplane"])
    worker_count       = length([for inst in var.talos_vm_instances : inst if inst.talos_role == "worker"])
    total_cores        = length(var.talos_vm_instances) > 0 ? sum([for inst in var.talos_vm_instances : inst.cores * inst.sockets]) : 0
    total_memory_gb    = length(var.talos_vm_instances) > 0 ? ceil(sum([for inst in var.talos_vm_instances : inst.memory]) / 1024) : 0
  })
}
