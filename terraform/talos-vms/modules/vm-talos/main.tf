# ============================================================================
# Talos VM Module (bpg/proxmox)
# ============================================================================
# This module manages Talos Linux VMs on Proxmox VE using the bpg/proxmox
# provider. Talos boots from ISO and is configured via API (talosctl), not
# cloud-init.
#
# Key differences from vm-linux:
#   - Boots from Talos ISO (not cloud-init template)
#   - No SSH keys (API-only management)
#   - No cloud-init disk
#   - UEFI (OVMF) boot with EFI disk
#   - Network configured via talosctl after boot
# ============================================================================

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.instances

  # Core Configuration
  vm_id     = each.value.vmid
  name      = each.key
  node_name = coalesce(try(each.value.target_node, null), var.target_node)

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

  # BIOS and Machine Type (Talos recommends UEFI)
  bios    = try(each.value.bios, "ovmf")
  machine = try(each.value.machine, "q35")

  # EFI Disk (required for UEFI boot)
  efi_disk {
    datastore_id      = coalesce(try(each.value.storage, null), var.default_storage)
    type              = "4m"
    pre_enrolled_keys = false
  }

  # SCSI Controller
  scsi_hardware = "virtio-scsi-single"

  # Guest Agent (Talos has built-in support)
  agent {
    enabled = true
  }

  # Keyboard Layout
  keyboard_layout = "en-us"

  # Boot Configuration (scsi0 primary, ide2 for ISO)
  boot_order = ["scsi0", "ide2"]

  # Startup
  on_boot = each.value.onboot
  started = each.value.start

  # Startup/Shutdown ordering (optional)
  dynamic "startup" {
    for_each = try(each.value.startup, "") != "" ? [1] : []
    content {
      order      = try(tonumber(split(",", each.value.startup)[0]), -1)
      up_delay   = try(tonumber(split(",", each.value.startup)[1]), -1)
      down_delay = try(tonumber(split(",", each.value.startup)[2]), -1)
    }
  }

  # Description
  description = coalesce(try(each.value.description, null), "Managed by Terraform")

  # Tags (bpg uses list natively)
  tags = sort(each.value.tags)

  # OS Disk (scsi0)
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

  # CD-ROM for Talos ISO (ide2)
  cdrom {
    file_id   = "${var.talos_iso_storage}:iso/${var.talos_iso_file}"
    interface = "ide2"
  }

  # Network Configuration
  network_device {
    bridge      = var.default_bridge
    model       = "virtio"
    vlan_id     = try(each.value.tag, 0) > 0 ? each.value.tag : null
    mac_address = try(each.value.mac, null)
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

  # VirtIO RNG (for better entropy)
  dynamic "rng" {
    for_each = [1]
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
      cdrom,
      description,
      disk,
      efi_disk,
      initialization,
      network_device,
      operating_system,
      vga,
      serial_device,
      bios,
      machine,
    ]
  }
}
