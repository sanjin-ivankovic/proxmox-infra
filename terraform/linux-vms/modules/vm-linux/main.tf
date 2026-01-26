# ============================================================================
# Linux VM Module (Cloud-Init)
# ============================================================================
# This module manages Linux VMs on Proxmox VE using cloud-init templates.
# Supports Debian and Ubuntu cloud images with automated provisioning.
#
# Usage:
#   module "linux_vms" {
#     source = "./modules/vm-linux"
#     instances       = { for inst in var.linux_vm_instances : inst.hostname => inst }
#     ssh_public_keys = module.ssh_keys.public_keys
#     target_node     = "pve"
#     clone_template  = "debian-13-cloudinit"
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

  # Clone from cloud-init template (use instance-level linux_vm_template if provided, otherwise module-level clone_template)
  clone      = try(each.value.linux_vm_template, var.clone_template)
  full_clone = try(each.value.full_clone, true)

  # Resource Allocation
  memory = each.value.memory

  # CPU Configuration
  cpu {
    cores   = each.value.cores
    sockets = try(each.value.sockets, 1)
    type    = try(each.value.cpu_type, "host")
  }

  # BIOS and Machine Type
  bios    = try(each.value.bios, "seabios") # Use "ovmf" for UEFI
  machine = try(each.value.machine, "q35")  # Modern chipset

  # SCSI Controller (virtio-scsi-single required for iothread support)
  scsihw = try(each.value.scsihw, "virtio-scsi-single")

  # Guest Agent (for IP reporting, graceful shutdown)
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
          cache = try(each.value.cache, "none") # Cache mode (none/writeback/writethrough)
        }
      }
    }

    # Cloud-Init disk (required for cloud-init)
    ide {
      ide2 {
        cloudinit {
          storage = coalesce(try(each.value.storage, null), var.default_storage)
        }
      }
    }
  }

  # Network Configuration
  network {
    id     = 0
    model  = "virtio"
    bridge = var.default_bridge
    # VLAN tag (0 = no tag, or omit tag attribute for no VLAN)
    tag     = try(each.value.tag, 0) > 0 ? try(each.value.tag, 0) : 0
    macaddr = try(each.value.mac, null) # Preserve MAC address if specified (for imports)
  }

  # Cloud-Init Configuration
  ipconfig0 = "ip=${each.value.ip},gw=${each.value.gw}"

  # DNS Configuration (only set if explicitly provided and non-empty)
  nameserver   = can(each.value.nameserver) && each.value.nameserver != "" ? each.value.nameserver : null
  searchdomain = can(each.value.searchdomain) && each.value.searchdomain != "" ? each.value.searchdomain : null

  # Custom Cloud-Init snippet (for installing qemu-guest-agent, etc.)
  # Use instance-level cicustom if provided, otherwise use module-level if install_qemu_guest_agent is enabled
  cicustom = try(
    each.value.cicustom,
    var.install_qemu_guest_agent && var.cicustom != "" ? var.cicustom : ""
  )

  # SSH Key Injection (cloud-init)
  sshkeys = var.ssh_public_keys[each.key]

  # Cloud-Init User (default: root for cloud images)
  ciuser = try(each.value.ciuser, "root")

  # Optional: Set temporary password (will be overridden by SSH keys)
  # cipassword = "changeme"  # Not recommended, use SSH keys only

  # Serial Console (for better console access)
  serial {
    id   = 0
    type = "socket"
  }

  # Optional: VirtIO RNG for better entropy (cryptography performance)
  dynamic "rng" {
    for_each = try(each.value.enable_rng, true) ? [1] : []
    content {
      source = "/dev/urandom"
    }
  }

  # Lifecycle Management
  # NOTE: prevent_destroy must be a literal boolean (Terraform limitation).
  # To enable for critical VMs, manually change false to true below.
  # The prevent_destroy field in variables is for documentation only.
  lifecycle {
    create_before_destroy = false
    prevent_destroy       = false # Change to true for critical VMs (manual edit required)
    ignore_changes = [
      # Ignore changes to template/clone source
      clone,
      # Ignore full_clone changes (prevents unnecessary VM replacement)
      full_clone,
      # Ignore network changes (managed manually if needed)
      network,
      # Ignore disk changes after creation
      disks,
      # CRITICAL: Ignore SSH keys changes to prevent VM recreation
      # SSH keys are only applied on first boot via cloud-init anyway
      sshkeys,
      # Ignore cloud-init user changes (cosmetic, doesn't affect running VMs)
      ciuser,
      # Ignore cloud-init upgrade flag (cosmetic, doesn't affect running VMs)
      ciupgrade,
      # Ignore nameserver changes (doesn't require VM restart, can be changed manually)
      nameserver,
      # Ignore RNG device changes (requires VM restart, can be added manually if needed)
      rng,
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
