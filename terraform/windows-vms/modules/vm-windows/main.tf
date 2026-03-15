# ============================================================================
# Windows VM Module (bpg/proxmox)
# ============================================================================
# This module manages Windows VMs on Proxmox VE using the bpg/proxmox provider.
# Supports Windows Server 2022 with automated provisioning via cloudbase-init.
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
  bios    = try(each.value.bios, "ovmf")
  machine = try(each.value.machine, "q35")

  # SCSI Controller
  scsi_hardware = "virtio-scsi-single"

  # Guest Agent
  agent {
    enabled = true
    type    = "virtio"
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
    cache        = try(each.value.cache, "writeback")
    file_format  = "raw"
  }

  # Network Configuration
  network_device {
    bridge      = var.default_bridge
    model       = "virtio"
    vlan_id     = try(each.value.tag, 0) > 0 ? each.value.tag : null
    mac_address = try(each.value.mac, null)
  }

  # Cloud-Init / Cloudbase-Init Configuration
  initialization {
    datastore_id = coalesce(try(each.value.storage, null), var.default_storage)

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = each.value.gw
      }
    }

    user_account {
      username = try(each.value.ciuser, "Administrator")
      keys     = [var.ssh_public_keys[each.key]]
    }
  }

  # Serial Console
  serial_device {}

  # VGA Display
  vga {
    type = try(each.value.vga_type, "std")
  }

  # TPM 2.0 (optional, for Windows Server 2022)
  dynamic "tpm_state" {
    for_each = try(each.value.enable_tpm, true) ? [1] : []
    content {
      datastore_id = coalesce(try(each.value.storage, null), var.default_storage)
      version      = "v2.0"
    }
  }

  # EFI Disk (required for OVMF/UEFI boot)
  efi_disk {
    datastore_id      = coalesce(try(each.value.storage, null), var.default_storage)
    type              = "4m"
    pre_enrolled_keys = true
  }

  # Operating System Type
  operating_system {
    type = "win11"
  }

  # Tablet Device (better mouse tracking)
  tablet_device = try(each.value.tablet, true)

  # Lifecycle Management
  lifecycle {
    create_before_destroy = false
    prevent_destroy       = false
    ignore_changes = [
      clone,
      description,
      disk,
      efi_disk,
      initialization,
      tpm_state,
      vga,
      serial_device,
      bios,
      machine,
      operating_system,
    ]
  }
}
