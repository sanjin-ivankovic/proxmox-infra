# ============================================================================
# LXC Instance Module (bpg/proxmox)
# ============================================================================
# This module manages LXC containers on Proxmox VE using the bpg/proxmox
# provider. Supports both privileged and unprivileged containers with
# per-instance configuration overrides.
# ============================================================================

locals {
  ssh_key_path = pathexpand(var.ssh_key_directory)
}

# ── SSH Key Generation ───────────────────────────────────────────────────────
# Keys are generated within this module (same module as the container resource)
# to avoid the bpg/proxmox provider rejecting unknown values that cross module
# boundaries. This matches the official provider example.

resource "tls_private_key" "keys" {
  for_each  = var.instances
  algorithm = "ED25519"
}

resource "terraform_data" "write_ssh_keys" {
  for_each = var.instances

  input = each.key

  provisioner "local-exec" {
    command = <<-EOT
      PRV="${local.ssh_key_path}/${each.key}_id_ed25519"
      PUB="${local.ssh_key_path}/${each.key}_id_ed25519.pub"
      printenv TF_SSH_PRIVATE_KEY > "$PRV"
      chmod 600 "$PRV"
      printenv TF_SSH_PUBLIC_KEY > "$PUB"
      chmod 644 "$PUB"
    EOT

    environment = {
      TF_SSH_PRIVATE_KEY = tls_private_key.keys[each.key].private_key_openssh
      TF_SSH_PUBLIC_KEY  = tls_private_key.keys[each.key].public_key_openssh
    }
  }
}

# ── LXC Container ───────────────────────────────────────────────────────────

resource "proxmox_virtual_environment_container" "container" {
  for_each = var.instances

  # Core Configuration
  vm_id     = each.value.vmid
  node_name = coalesce(try(each.value.target_node, null), var.target_node)

  # Description
  description = coalesce(try(each.value.description, null), "Managed by Terraform.")

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
      mount   = try(each.value.features.mount, null) != null && try(each.value.features.mount, "") != "" ? [each.value.features.mount] : []
      nesting = try(each.value.features.nesting, true)
    }
  }

  # Network Configuration
  network_interface {
    name        = "eth0"
    bridge      = var.default_bridge
    vlan_id     = try(each.value.tag, 0) > 0 ? each.value.tag : null
    mac_address = each.value.mac != "" ? each.value.mac : null
  }

  # Disk (rootfs)
  disk {
    datastore_id = coalesce(try(each.value.storage, null), var.default_storage)
    size         = each.value.disk_size
  }

  # NOTE: WireGuard workloads (e.g. Omni SideroLink) need /dev/net/tun, but it is
  # NOT passed through here. The bpg device_passthrough call — like LXC feature
  # flags beyond `nesting` — requires root@pam, which our non-root API token
  # can't use ("changing feature flags (except nesting) is only allowed for
  # root@pam"). For such hosts, add /dev/net/tun manually on the Proxmox host in
  # /etc/pve/lxc/<vmid>.conf (see services/omni/README.md).

  # Initialization (hostname, IP, DNS, credentials)
  initialization {
    hostname = each.key

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = each.value.gw
      }
    }

    dynamic "dns" {
      for_each = (
        (can(each.value.nameserver) && each.value.nameserver != "") ||
        (can(each.value.searchdomain) && each.value.searchdomain != "")
      ) ? [1] : []
      content {
        servers = can(each.value.nameserver) && each.value.nameserver != "" ? [each.value.nameserver] : null
        domain  = can(each.value.searchdomain) && each.value.searchdomain != "" ? each.value.searchdomain : null
      }
    }

    user_account {
      password = var.password
      # Per-host generated key plus any shared keys from var.deploy_public_keys,
      # authorized on every host.
      keys = concat(
        [trimspace(tls_private_key.keys[each.key].public_key_openssh)],
        var.deploy_public_keys,
      )
    }
  }

  # Operating System
  # Per-instance `ostemplate` overrides the module-level default (var.ostemplate,
  # Debian). Empty string falls back to the default. `type` is derived from the
  # template name so Ubuntu containers (e.g. landscape) get the right OS family.
  operating_system {
    template_file_id = coalesce(each.value.ostemplate, var.ostemplate)
    type             = can(regex("ubuntu", coalesce(each.value.ostemplate, var.ostemplate))) ? "ubuntu" : "debian"
  }

  # Lifecycle Management
  lifecycle {
    create_before_destroy = false
    prevent_destroy       = true
    ignore_changes = [
      operating_system,
      initialization,
      disk[0].datastore_id,
      clone,
    ]
  }
}
