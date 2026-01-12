# ============================================================================
# Linux VM Module - Outputs
# ============================================================================

output "vms" {
  description = "Map of all deployed Linux VMs (full Proxmox resource objects)"
  value       = proxmox_vm_qemu.vm
}

output "vm_details" {
  description = "Simplified map of VM details (VMID, IP, node, resources)"
  value = {
    for hostname, instance in proxmox_vm_qemu.vm : hostname => merge(
      {
        # Read from resource state (source of truth) - ensures type consistency
        vmid        = instance.vmid
        ip          = instance.ipconfig0 != null && length(regexall("^ip=([^,]+)", instance.ipconfig0)) > 0 ? regex("^ip=([^,]+)", instance.ipconfig0)[0] : (instance.ipconfig0 != null ? try(split("/", regex("^ip=([^,]+)", instance.ipconfig0)[0])[0], "N/A") : try(split("/", var.instances[hostname].ip)[0], "N/A"))
        cidr        = instance.ipconfig0 != null && length(regexall("^ip=([^,]+)", instance.ipconfig0)) > 0 ? regex("^ip=([^,]+)", instance.ipconfig0)[0] : (instance.ipconfig0 != null ? "N/A" : try(var.instances[hostname].ip, "N/A"))
        gateway     = instance.ipconfig0 != null && length(regexall(",gw=([^,]+)", instance.ipconfig0)) > 0 ? regex(",gw=([^,]+)", instance.ipconfig0)[0] : (instance.ipconfig0 != null ? "N/A" : try(var.instances[hostname].gw, "N/A"))
        tag         = length(instance.network) > 0 ? try(instance.network[0].tag, 0) : try(var.instances[hostname].tag, 0)
        target_node = instance.target_node
        cores       = instance.cpu[0].cores
        sockets     = try(instance.cpu[0].sockets, 1)
        memory      = instance.memory
        tags        = instance.tags
        type        = "vm-linux"
      },
      # Conditionally include nameserver only if not null
      try(var.instances[hostname].nameserver, null) != null ? { nameserver = var.instances[hostname].nameserver } : {},
      # Conditionally include searchdomain only if not null
      try(var.instances[hostname].searchdomain, null) != null ? { searchdomain = var.instances[hostname].searchdomain } : {}
    )
  }
}

output "vm_ips" {
  description = "Map of hostnames to IP addresses (without CIDR)"
  value = {
    for hostname, instance in proxmox_vm_qemu.vm :
    hostname => instance.ipconfig0 != null && length(regexall("^ip=([^,/]+)", instance.ipconfig0)) > 0 ? regex("^ip=([^,/]+)", instance.ipconfig0)[0] : (instance.ipconfig0 != null ? try(split("/", regex("^ip=([^,]+)", instance.ipconfig0)[0])[0], "N/A") : try(split("/", var.instances[hostname].ip)[0], "N/A"))
  }
}
