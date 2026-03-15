# ============================================================================
# LXC Instance Module (bpg/proxmox)
# ============================================================================
# This module manages LXC containers on Proxmox VE using the bpg/proxmox
# provider. Supports both privileged and unprivileged containers with
# per-instance configuration overrides.
# ============================================================================

resource "proxmox_virtual_environment_container" "container" {
  for_each = var.instances

  # Core Configuration
  vm_id     = each.value.vmid
  node_name = coalesce(try(each.value.target_node, null), var.target_node)

  # Unprivileged
  unprivileged = each.value.unprivileged

  # CPU Configuration
  cpu {
    cores = each.value.cores
  }

  # Memory
  memory {
    dedicated = each.value.memory
    swap      = each.value.swap
  }

  # Tags (bpg uses list natively)
  tags = sort(each.value.tags)

  # Startup
  started       = each.value.start
  start_on_boot = each.value.onboot

  # Container Features (only for unprivileged containers)
  dynamic "features" {
    for_each = each.value.unprivileged ? [1] : []
    content {
      fuse    = try(each.value.features.fuse, false)
      keyctl  = try(each.value.features.keyctl, false)
      mount   = try(each.value.features.mount, null) != null && try(each.value.features.mount, "") != "" ? [each.value.features.mount] : null
      nesting = try(each.value.features.nesting, true)
    }
  }

  # Network Configuration
  network_interface {
    name        = "eth0"
    bridge      = var.default_bridge
    vlan_id     = try(each.value.tag, 0) > 0 ? each.value.tag : null
    mac_address = try(each.value.mac, null)
  }

  # Disk (rootfs)
  disk {
    datastore_id = coalesce(try(each.value.storage, null), var.default_storage)
    size         = each.value.disk_size
  }

  # Initialization (hostname, IP, DNS, credentials)
  initialization {
    hostname = each.key

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = each.value.gw
      }
    }

    dns {
      servers = can(each.value.nameserver) && each.value.nameserver != "" ? [each.value.nameserver] : null
      domain  = can(each.value.searchdomain) && each.value.searchdomain != "" ? each.value.searchdomain : null
    }

    user_account {
      password = var.password
      keys     = [var.ssh_public_keys[each.key]]
    }
  }

  # Operating System
  operating_system {
    template_file_id = var.ostemplate
    type             = "debian"
  }

  # Lifecycle Management
  lifecycle {
    create_before_destroy = false
    prevent_destroy       = true
    ignore_changes = [
      description,
      operating_system,
      initialization,
      disk[0].datastore_id,
      clone,
    ]
  }
}
