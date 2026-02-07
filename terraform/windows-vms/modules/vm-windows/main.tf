# ============================================================================
# Windows VM Module (Cloudbase-Init)
# ============================================================================
# This module manages Windows VMs on Proxmox VE using cloudbase-init templates.
# Supports Windows Server 2022 with automated provisioning via cloudbase-init.
#
# Usage:
#   module "windows_vms" {
#     source = "./modules/vm-windows"
#     instances       = { for inst in var.windows_vm_instances : inst.hostname => inst }
#     ssh_public_keys = module.ssh_keys.public_keys
#     target_node     = "pve"
#     clone_template  = "windows-server-2022-std"
#     default_storage = "local-zfs"
#     default_bridge  = "vmbr0"
#   }
# ============================================================================

resource "proxmox_vm_qemu" "vm" {
  for_each = var.instances

  # Core Configuration
  vmid        = each.value.vmid
  name        = each.key
  target_node = coalesce(try(each.value.target_node, null), var.target_node)

  # Clone from cloudbase-init template
  clone      = var.clone_template
  full_clone = try(each.value.full_clone, true)

  # Resource Allocation
  memory = each.value.memory

  # CPU Configuration (Windows benefits from host CPU passthrough)
  cpu {
    cores   = each.value.cores
    sockets = try(each.value.sockets, 1)
    type    = try(each.value.cpu_type, "host")
  }

  # BIOS and Machine Type (Windows Server 2022 requires UEFI)
  bios    = try(each.value.bios, "ovmf")   # UEFI required for Windows Server 2022
  machine = try(each.value.machine, "q35") # Modern chipset

  # SCSI Controller (virtio-scsi-single required for iothread support)
  scsihw = try(each.value.scsihw, "virtio-scsi-single")

  # Guest Agent (QEMU guest agent for Windows)
  agent = 1

  # Boot Configuration
  boot               = "order=scsi0"
  start_at_node_boot = each.value.onboot

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

  # Disk Configuration
  disks {
    scsi {
      scsi0 {
        disk {
          storage = coalesce(try(each.value.storage, null), var.default_storage)
          size    = each.value.disk_size
          # Convert legacy values (1/"on"/"1") to boolean for emulatessd
          emulatessd = can(try(each.value.ssd, null)) ? (
            try(each.value.ssd, true) == true || try(each.value.ssd, true) == 1 || try(each.value.ssd, true) == "1" || try(each.value.ssd, true) == "on"
          ) : true
          # Convert legacy values ("on"/"1"/1) to boolean for discard
          discard = can(try(each.value.discard, null)) ? (
            try(each.value.discard, true) == true || try(each.value.discard, true) == 1 || try(each.value.discard, true) == "1" || try(each.value.discard, true) == "on"
          ) : true
          # Convert legacy values (1/"1"/"on") to boolean for iothread
          iothread = can(try(each.value.iothread, null)) ? (
            try(each.value.iothread, true) == true || try(each.value.iothread, true) == 1 || try(each.value.iothread, true) == "1" || try(each.value.iothread, true) == "on"
          ) : true
          cache = try(each.value.cache, "writeback") # Better for Windows
        }
      }
    }

    # Cloud-Init/Cloudbase-Init disk (required for cloudbase-init)
    ide {
      ide2 {
        cloudinit {
          storage = coalesce(try(each.value.storage, null), var.default_storage)
        }
      }
    }
  }

  # Network Configuration (VirtIO for better performance)
  network {
    id     = 0
    model  = "virtio"
    bridge = var.default_bridge
    # VLAN tag (0 = no tag, or omit tag attribute for no VLAN)
    tag     = try(each.value.tag, 0) > 0 ? try(each.value.tag, 0) : 0
    macaddr = try(each.value.mac, null) # Preserve MAC address if specified (for imports)
  }

  # Cloud-Init/Cloudbase-Init Configuration
  # Note: Cloudbase-Init uses NoCloud datasource (same as cloud-init)
  ipconfig0 = "ip=${each.value.ip},gw=${each.value.gw}"

  # DNS Configuration (only set if explicitly provided and non-empty)
  nameserver   = can(each.value.nameserver) && each.value.nameserver != "" ? each.value.nameserver : null
  searchdomain = can(each.value.searchdomain) && each.value.searchdomain != "" ? each.value.searchdomain : null

  # SSH Key Injection (cloudbase-init + OpenSSH Server)
  sshkeys = var.ssh_public_keys[each.key]

  # Cloudbase-Init User (default: Administrator)
  ciuser = try(each.value.ciuser, "Administrator")

  # Serial Console (for better console access)
  serial {
    id   = 0
    type = "socket"
  }

  # VGA Display (Windows needs proper VGA for installation/console)
  vga {
    type = try(each.value.vga_type, "std") # std/qxl/virtio
  }

  # TPM 2.0 (required for Windows 11/Server 2022 in some cases)
  dynamic "tpm_state" {
    for_each = try(each.value.enable_tpm, true) ? [1] : []
    content {
      storage = coalesce(try(each.value.storage, null), var.default_storage)
      version = "v2.0"
    }
  }

  # Tablet Device (better mouse tracking in console)
  tablet = try(each.value.tablet, true)

  # Lifecycle Management
  # NOTE: prevent_destroy must be a literal boolean (Terraform limitation).
  # To enable for critical VMs, manually change false to true below.
  lifecycle {
    create_before_destroy = false
    prevent_destroy       = false # Change to true for critical VMs (manual edit required)
    ignore_changes = [
      # Ignore changes to template/clone source
      clone,
      # Ignore full_clone changes (prevents unnecessary VM replacement)
      full_clone,
      # Ignore network changes (managed manually if needed)
    #   network,
      # Ignore disk changes after creation
      disks,
      # CRITICAL: Ignore SSH keys changes to prevent VM recreation
      # SSH keys are only applied on first boot via cloudbase-init anyway
      sshkeys,
      # Ignore cloudbase-init user changes (cosmetic, doesn't affect running VMs)
      ciuser,
      # Ignore nameserver changes (doesn't require VM restart, can be changed manually)
      nameserver,
      # CRITICAL: Ignore TPM changes to prevent VM recreation (adding TPM to existing VM forces replacement)
      tpm_state,
      # Windows-specific: Ignore hardware/firmware changes
      vga,     # Display adapter
      smbios,  # UUID and SMBIOS firmware data
      tablet,  # Tablet input device
      bios,    # BIOS type (UEFI vs SeaBIOS)
      machine, # Machine type (q35, etc.)
      serial,  # Serial console
      # Ignore provider default values that don't affect VM functionality
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
