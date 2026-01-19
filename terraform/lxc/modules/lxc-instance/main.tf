# ============================================================================
# LXC Instance Module
# ============================================================================
# This module manages LXC containers on Proxmox VE with full lifecycle support.
# Supports both privileged and unprivileged containers with per-instance
# configuration overrides.
#
# Usage:
#   module "lxc" {
#     source = "./modules/lxc-instance"
#     instances       = { for inst in var.lxc_instances : inst.hostname => inst }
#     ssh_public_keys = module.ssh_keys.public_keys
#     target_node     = "pve"
#     ostemplate      = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
#     password        = var.lxc_password
#     default_storage = "local-zfs"
#     default_bridge  = "vmbr0"
#   }
# ============================================================================

resource "proxmox_lxc" "container" {
  for_each = var.instances

  # Core Configuration
  vmid         = each.value.vmid
  hostname     = each.key
  target_node  = coalesce(try(each.value.target_node, null), var.target_node)
  ostemplate   = var.ostemplate
  password     = var.password
  unprivileged = each.value.unprivileged

  # Resource Allocation
  cores  = each.value.cores
  memory = each.value.memory
  swap   = each.value.swap

  # Tags and Lifecycle
  tags   = join(";", each.value.tags)
  start  = each.value.start
  onboot = each.value.onboot

  # Container Features (only for unprivileged containers)
  # Privileged containers have full capabilities by default
  dynamic "features" {
    for_each = each.value.unprivileged ? [1] : []
    content {
      fuse    = try(each.value.features.fuse, false)
      keyctl  = try(each.value.features.keyctl, false)
      mknod   = try(each.value.features.mknod, false)
      mount   = try(each.value.features.mount, "")
      nesting = try(each.value.features.nesting, true)
    }
  }

  # Network Configuration
  network {
    name   = "eth0"
    bridge = var.default_bridge
    gw     = each.value.gw
    ip     = each.value.ip
    tag    = try(each.value.tag, 0)    # VLAN tag (0 = no VLAN tagging)
    hwaddr = try(each.value.mac, null) # Preserve MAC address if specified (for imports)
  }

  # Storage Configuration
  rootfs {
    storage = coalesce(try(each.value.storage, null), var.default_storage)
    size    = each.value.disk_size
  }

  # DNS Configuration (only set if explicitly provided and non-empty)
  nameserver   = can(each.value.nameserver) && each.value.nameserver != "" ? each.value.nameserver : null
  searchdomain = can(each.value.searchdomain) && each.value.searchdomain != "" ? each.value.searchdomain : null

  # SSH Public Key Injection
  ssh_public_keys = var.ssh_public_keys[each.key]

  # Lifecycle Management
  # NOTE: prevent_destroy must be a literal boolean (Terraform limitation).
  # To enable for critical containers, manually change false to true below.
  # The prevent_destroy field in variables is for documentation only.
  lifecycle {
    create_before_destroy = false
    prevent_destroy       = true # Change to true for critical containers (manual edit required)
    ignore_changes = [
      # CRITICAL: Template is only used during creation, changing it would recreate the container
      ostemplate,

      # IMPORTED CONTAINERS: Prevent overwriting existing credentials/keys
      # These are ignored to allow importing existing containers without forcing password/key changes
      password,        # Don't change passwords on imported containers
      ssh_public_keys, # Don't overwrite SSH keys on imported containers

      # STORAGE: RootFS storage location cannot be changed after creation (would require migration)
      # Changing this would force container recreation, which is destructive
      rootfs[0].storage,

      # CONFIG MODE: Proxmox internal setting, changes shouldn't trigger recreation
      # This is set by Proxmox and may drift, but shouldn't affect container functionality
      cmode,
    ]
  }
}
