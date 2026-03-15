# ============================================================================
# Talos VM Module - Outputs
# ============================================================================

output "vms" {
  description = "Map of all deployed Talos VMs (full resource objects)"
  value       = proxmox_virtual_environment_vm.vm
}

output "vm_details" {
  description = "Simplified map of VM details (VMID, IP, node, resources)"
  value = {
    for hostname, instance in proxmox_virtual_environment_vm.vm : hostname => {
      vmid        = instance.vm_id
      ip          = split("/", var.instances[hostname].ip)[0]
      cidr        = var.instances[hostname].ip
      gateway     = var.instances[hostname].gw
      tag         = try(var.instances[hostname].tag, 0)
      target_node = instance.node_name
      cores       = var.instances[hostname].cores
      sockets     = try(var.instances[hostname].sockets, 1)
      memory      = var.instances[hostname].memory
      tags        = instance.tags
      talos_role  = var.instances[hostname].talos_role
      type        = "vm-talos"
    }
  }
}

output "vm_ips" {
  description = "Map of hostnames to IP addresses (without CIDR)"
  value = {
    for hostname, inst in var.instances :
    hostname => split("/", inst.ip)[0]
  }
}

output "controlplane_nodes" {
  description = "List of control plane node IPs"
  value = [
    for hostname, inst in var.instances :
    split("/", inst.ip)[0] if inst.talos_role == "controlplane"
  ]
}

output "worker_nodes" {
  description = "List of worker node IPs"
  value = [
    for hostname, inst in var.instances :
    split("/", inst.ip)[0] if inst.talos_role == "worker"
  ]
}
