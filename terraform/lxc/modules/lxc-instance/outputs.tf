# ============================================================================
# LXC Instance Module - Outputs
# ============================================================================

output "containers" {
  description = "Map of all deployed LXC containers (full resource objects)"
  value       = proxmox_virtual_environment_container.container
}

output "container_details" {
  description = "Simplified map of container details (VMID, IP, node, resources)"
  value = {
    for hostname, instance in proxmox_virtual_environment_container.container : hostname => {
      vmid        = instance.vm_id
      ip          = split("/", var.instances[hostname].ip)[0]
      cidr        = var.instances[hostname].ip
      gateway     = var.instances[hostname].gw
      tag         = try(var.instances[hostname].tag, 0)
      target_node = instance.node_name
      cores       = var.instances[hostname].cores
      memory      = var.instances[hostname].memory
      swap        = var.instances[hostname].swap
      tags        = instance.tags
      type        = "lxc"
    }
  }
}

output "container_ips" {
  description = "Map of hostnames to IP addresses (without CIDR)"
  value = {
    for hostname, inst in var.instances :
    hostname => split("/", inst.ip)[0]
  }
}
