# ============================================================================
# Linux VM Module - Outputs
# ============================================================================

output "vms" {
  description = "Map of all deployed Linux VMs (full resource objects)"
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
      type        = "vm-linux"
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
