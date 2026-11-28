# ============================================================================
# LXC Instance Module - Outputs
# ============================================================================

output "containers" {
  description = "Map of all deployed LXC containers (projected attributes; excludes deprecated provider fields)"
  value = {
    for hostname, instance in proxmox_virtual_environment_container.container : hostname => {
      id        = instance.id
      vm_id     = instance.vm_id
      node_name = instance.node_name
      tags      = instance.tags
      started   = instance.started
    }
  }
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

output "ssh_key_paths" {
  description = "Map of hostnames to SSH key file paths (private and public)"
  value = {
    for hostname, _ in var.instances :
    hostname => {
      private = "${local.ssh_key_path}/${hostname}_id_ed25519"
      public  = "${local.ssh_key_path}/${hostname}_id_ed25519.pub"
    }
  }
}

output "ssh_key_directory" {
  description = "Resolved SSH key directory path (with ~ expanded)"
  value       = local.ssh_key_path
}
