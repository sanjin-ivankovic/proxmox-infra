# ============================================================================
# Talos VM Module
# ============================================================================
# This module manages Talos Linux VMs on Proxmox VE.
# Talos boots from ISO and is configured via API (talosctl), not cloud-init.
#
# Key differences from vm-linux:
#   - Boots from Talos ISO (not cloud-init template)
#   - No SSH keys (API-only management)
#   - No cloud-init disk
#   - Network configured via talosctl after boot
#
# Usage:
#   module "talos_vms" {
#     source          = "./modules/vm-talos"
#     instances       = { for inst in var.talos_vm_instances : inst.hostname => inst }
#     target_node     = "pve"
#     default_storage = "local-zfs"
#     default_bridge  = "vmbr0"
#     talos_iso_storage = "local"
#     talos_iso_file    = "talos-amd64.iso"
#   }
# ============================================================================

resource "proxmox_vm_qemu" "vm" {
  for_each = var.instances

  # Core Configuration
  vmid        = each.value.vmid
  name        = each.key
  target_node = coalesce(try(each.value.target_node, null), var.target_node)

  # Resource Allocation
  memory = each.value.memory

  # CPU Configuration
  cpu {
    cores   = each.value.cores
    sockets = try(each.value.sockets, 1)
    type    = try(each.value.cpu_type, "host")
  }

  # BIOS and Machine Type (Talos recommends UEFI)
  bios    = try(each.value.bios, "ovmf")
  machine = try(each.value.machine, "q35")

  # EFI Disk (required for UEFI boot)
  efidisk {
    efitype            = "4m"
    pre_enrolled_keys  = false
    storage            = coalesce(try(each.value.storage, null), var.default_storage)
  }

  # SCSI Controller
  scsihw = "virtio-scsi-single"

  # Guest Agent (enabled - Talos has built-in support)
  agent         = 1
  agent_timeout = 90

  # Skip IPv6 detection to avoid waiting for addresses that won't be configured
  skip_ipv6 = true

  # Don't wait for guest agent during refresh/apply
  define_connection_info = false

  # Boot Configuration
  boot               = "order=scsi0;ide2"
  start_at_node_boot = each.value.onboot
  vm_state           = each.value.start ? "running" : "stopped"

  # Startup/Shutdown Configuration (optional)
  dynamic "startup_shutdown" {
    for_each = try(each.value.startup, "") != "" ? [1] : []
    content {
      order            = try(tonumber(split(",", each.value.startup)[0]), -1)
      startup_delay    = try(tonumber(split(",", each.value.startup)[1]), -1)
      shutdown_timeout = try(tonumber(split(",", each.value.startup)[2]), -1)
    }
  }

  # Tags
  tags = join(";", each.value.tags)

  # Description / Notes field in Proxmox UI
  description = coalesce(try(each.value.description, null), "Managed by Terraform")

  # Disk Configuration
  disks {
    scsi {
      scsi0 {
        disk {
          storage    = coalesce(try(each.value.storage, null), var.default_storage)
          size       = each.value.disk_size
          emulatessd = lookup(each.value, "ssd", 1) == 1
          discard    = lookup(each.value, "discard", "on") == "on"
          iothread   = lookup(each.value, "iothread", 1) == 1
          cache      = try(each.value.cache, "none")
        }
      }
    }

    # IDE2 for Talos ISO (boot media)
    ide {
      ide2 {
        cdrom {
          iso = "${var.talos_iso_storage}:iso/${var.talos_iso_file}"
        }
      }
    }
  }

  # Network Configuration
  network {
    id      = 0
    model   = "virtio"
    bridge  = var.default_bridge
    tag     = try(each.value.tag, 0) > 0 ? try(each.value.tag, 0) : 0
    macaddr = try(each.value.mac, null)
  }

  # Serial Console (for better console access)
  serial {
    id   = 0
    type = "socket"
  }

  # VirtIO RNG for better entropy
  rng {
    source = "/dev/urandom"
  }

  # Lifecycle Management
  lifecycle {
    create_before_destroy = false
    prevent_destroy       = false
    ignore_changes = [
      # Ignore network changes
      network,
      # Ignore disk changes after creation (includes ISO in cdrom)
      disks,
      # Ignore provider default values
      additional_wait,
      agent_timeout,
      automatic_reboot,
      automatic_reboot_severity,
      clone_wait,
      skip_ipv4,
      skip_ipv6,
      define_connection_info,
      target_node,
      target_nodes
    ]
  }
}
