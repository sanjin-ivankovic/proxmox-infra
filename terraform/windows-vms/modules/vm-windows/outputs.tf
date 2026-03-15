# ============================================================================
# Windows VM Module - Outputs
# ============================================================================

output "vms" {
  description = "Map of all deployed Windows VMs (full resource objects)"
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
      cores       = instance.cpu[0].cores
      sockets     = try(instance.cpu[0].sockets, 1)
      memory      = instance.memory[0].dedicated
      tags        = instance.tags
      type        = "vm-windows"
      os          = "Windows Server 2022"
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
