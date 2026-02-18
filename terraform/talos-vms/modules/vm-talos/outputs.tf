# ============================================================================
# Talos VM Module - Outputs
# ============================================================================

output "vms" {
  description = "Map of all deployed Talos VMs (full Proxmox resource objects)"
  value       = proxmox_vm_qemu.vm
}

output "vm_details" {
  description = "Simplified map of VM details (VMID, IP, node, resources)"
  value = {
    for hostname, instance in proxmox_vm_qemu.vm : hostname => {
      vmid        = instance.vmid
      ip          = try(split("/", var.instances[hostname].ip)[0], "N/A")
      cidr        = try(var.instances[hostname].ip, "N/A")
      gateway     = try(var.instances[hostname].gw, "N/A")
      tag         = length(instance.network) > 0 ? try(instance.network[0].tag, 0) : try(var.instances[hostname].tag, 0)
      target_node = instance.target_node
      cores       = instance.cpu[0].cores
      sockets     = try(instance.cpu[0].sockets, 1)
      memory      = instance.memory
      tags        = instance.tags
      talos_role  = var.instances[hostname].talos_role
      type        = "vm-talos"
    }
  }
}

output "vm_ips" {
  description = "Map of hostnames to IP addresses (without CIDR)"
  value = {
    for hostname, instance in var.instances :
    hostname => try(split("/", instance.ip)[0], "N/A")
  }
}

output "controlplane_nodes" {
  description = "List of control plane node IPs"
  value = [
    for hostname, instance in var.instances :
    split("/", instance.ip)[0] if instance.talos_role == "controlplane"
  ]
}

output "worker_nodes" {
  description = "List of worker node IPs"
  value = [
    for hostname, instance in var.instances :
    split("/", instance.ip)[0] if instance.talos_role == "worker"
  ]
}
