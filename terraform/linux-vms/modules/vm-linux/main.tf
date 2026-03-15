# ============================================================================
# Linux VM Module (bpg/proxmox)
# ============================================================================
# This module manages Linux VMs on Proxmox VE using the bpg/proxmox provider.
# Supports Debian and Ubuntu cloud images with automated provisioning via
# cloud-init.
# ============================================================================

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.instances

  # Core Configuration
  vm_id     = each.value.vmid
  name      = each.key
  node_name = coalesce(try(each.value.target_node, null), var.target_node)

  # Clone from template (only for new VMs, not imported ones)
  dynamic "clone" {
    for_each = try(each.value.preserve_ssh_key, false) ? [] : [1]
    content {
      vm_id   = var.clone_template_id
      full    = try(each.value.full_clone, true)
      retries = 3
    }
  }

  # CPU Configuration
  cpu {
    cores   = each.value.cores
    sockets = try(each.value.sockets, 1)
    type    = try(each.value.cpu_type, "host")
  }

  # Memory
  memory {
    dedicated = each.value.memory
  }

  # BIOS and Machine Type
  bios    = try(each.value.bios, "seabios")
  machine = try(each.value.machine, "q35")

  # SCSI Controller
  scsi_hardware = "virtio-scsi-single"

  # Guest Agent
  agent {
    enabled = true
  }

  # Keyboard Layout
  keyboard_layout = "en-us"

  # Boot Configuration
  boot_order = ["scsi0"]

  # Startup
  on_boot = each.value.onboot
  started = each.value.start

  # Description
  description = try(each.value.description, "")

  # Tags (bpg uses list natively)
  tags = sort(each.value.tags)

  # Disk Configuration
  disk {
    interface    = "scsi0"
    datastore_id = coalesce(try(each.value.storage, null), var.default_storage)
    size         = each.value.disk_size
    ssd          = try(each.value.ssd, true)
    discard      = try(each.value.discard, true) ? "on" : "ignore"
    iothread     = try(each.value.iothread, true)
    cache        = try(each.value.cache, "none")
    file_format  = "raw"
  }

  # Network Configuration
  network_device {
    bridge      = var.default_bridge
    model       = "virtio"
    vlan_id     = try(each.value.tag, 0) > 0 ? each.value.tag : null
    mac_address = try(each.value.mac, null)
  }

  # Cloud-Init Configuration
  initialization {
    datastore_id = coalesce(try(each.value.storage, null), var.default_storage)

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = each.value.gw
      }
    }

    dns {
      servers = try(each.value.nameserver, null) != null && each.value.nameserver != "" ? split(" ", each.value.nameserver) : null
      domain  = try(each.value.searchdomain, null) != null && each.value.searchdomain != "" ? each.value.searchdomain : null
    }

    user_account {
      username = try(each.value.ciuser, "root")
      keys     = [var.ssh_public_keys[each.key]]
    }

    # Cloud-init vendor snippet (for qemu-guest-agent install, etc.)
    vendor_data_file_id = var.install_qemu_guest_agent && var.cicustom != "" ? replace(var.cicustom, "vendor=", "") : null
  }

  # Serial Console
  serial_device {}

  # VGA Display
  vga {
    type = "std"
  }

  # Operating System Type
  operating_system {
    type = "l26"
  }

  # VirtIO RNG (optional, for better entropy)
  dynamic "rng" {
    for_each = try(each.value.enable_rng, true) ? [1] : []
    content {
      source    = "/dev/urandom"
      max_bytes = 1024
      period    = 1000
    }
  }

  # Lifecycle Management
  lifecycle {
    create_before_destroy = false
    prevent_destroy       = false
    ignore_changes = [
      clone,
      description,
      disk,
      initialization,
      operating_system,
      vga,
      serial_device,
      bios,
      machine,
    ]
  }
}
