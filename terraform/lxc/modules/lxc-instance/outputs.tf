# ============================================================================
# LXC Instance Module - Outputs
# ============================================================================

output "containers" {
  description = "Map of all deployed LXC containers (full Proxmox resource objects)"
  value       = proxmox_lxc.container
}

output "container_details" {
  description = "Simplified map of container details (VMID, IP, node, resources)"
  value = {
    for hostname, instance in proxmox_lxc.container : hostname => merge(
      {
        # Read from resource state (source of truth) - ensures type consistency
        vmid        = instance.vmid
        ip          = length(instance.network) > 0 ? split("/", instance.network[0].ip)[0] : "N/A"
        cidr        = length(instance.network) > 0 ? instance.network[0].ip : "N/A"
        gateway     = length(instance.network) > 0 ? instance.network[0].gw : "N/A"
        tag         = length(instance.network) > 0 ? try(instance.network[0].tag, 0) : 0
        target_node = instance.target_node
        cores       = instance.cores
        memory      = instance.memory
        swap        = instance.swap
        tags        = instance.tags
        type        = "lxc"
      },
      # Conditionally include nameserver only if not null
      try(instance.nameserver, null) != null ? { nameserver = instance.nameserver } : {},
      # Conditionally include searchdomain only if not null
      try(instance.searchdomain, null) != null ? { searchdomain = instance.searchdomain } : {}
    )
  }
}

output "container_ips" {
  description = "Map of hostnames to IP addresses (without CIDR)"
  value = {
    for hostname, instance in proxmox_lxc.container :
    hostname => length(instance.network) > 0 ? split("/", instance.network[0].ip)[0] : "N/A"
  }
}
