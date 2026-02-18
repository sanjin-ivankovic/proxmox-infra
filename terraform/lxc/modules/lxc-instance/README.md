# LXC Instance Module

## Overview

This module provisions and manages LXC containers on Proxmox VE. It supports
both privileged and unprivileged containers with full configuration
flexibility.

## Features

- ✅ **Flexible Configuration**: Per-instance overrides for node, storage,
  resources
- ✅ **Privileged & Unprivileged**: Supports both container types
- ✅ **Network Configuration**: Static IP, VLAN tagging, MAC preservation
- ✅ **SSH Key Injection**: Automatic SSH key deployment
- ✅ **Import Support**: Preserve MAC addresses for existing containers
- ✅ **Lifecycle Management**: Ignore template/password changes after creation

## Usage

```text
module "lxc" {
  source = "./modules/lxc-instance"

  instances = {
    "pihole-1" = {
      vmid         = 100
      ip           = "10.10.0.10/24"
      gw           = "10.10.0.1"
      cores        = 2
      memory       = 2048
      swap         = 512
      disk_size    = "20G"
      unprivileged = true
      start        = true
      onboot       = true
      tags         = ["infrastructure", "dns"]
      features     = { nesting = true }
    }
  }

  ssh_public_keys = module.ssh_keys.public_keys
  target_node     = "pve"
  ostemplate      = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
  password        = var.lxc_password
  default_storage = "local-zfs"
  default_bridge  = "vmbr0"
}
```

## Inputs

<!-- markdownlint-disable MD013 -->

| Name              | Description               | Type          | Default       | Required |
| ----------------- | ------------------------- | ------------- | ------------- | -------- |
| `instances`       | Map of LXC configurations | `map(any)`    | n/a           | yes      |
| `ssh_public_keys` | SSH public keys map       | `map(string)` | n/a           | yes      |
| `target_node`     | Default Proxmox node      | `string`      | `"pve"`       | no       |
| `ostemplate`      | LXC OS template           | `string`      | n/a           | yes      |
| `password`        | Root password             | `string`      | n/a           | yes      |
| `default_storage` | Default storage backend   | `string`      | `"local-zfs"` | no       |
| `default_bridge`  | Default network bridge    | `string`      | `"vmbr0"`     | no       |

<!-- markdownlint-enable MD013 -->

## Instance Object Schema

```text
{
  hostname     = string           # Container hostname
  vmid         = number           # Proxmox VMID (100-999999999)
  ip           = string           # IP in CIDR notation (e.g., "10.0.0.1/24")
  gw           = string           # Gateway IP
  cores        = number           # CPU cores
  memory       = number           # RAM in MB
  swap         = number           # Swap in MB
  disk_size    = string           # Disk size (e.g., "20G")
  unprivileged = bool             # true = unprivileged, false = privileged
  start        = bool             # Start after creation
  onboot       = bool             # Start on Proxmox boot
  tags         = list(string)     # Tags for organization

  # Optional overrides
  target_node  = optional(string)  # Override default node
  storage      = optional(string)  # Override default storage
  mac          = optional(string)  # MAC address (for imports)
  tag          = optional(number)  # VLAN tag (-1 = no tag)

  # Features (unprivileged only)
  features = optional(object({
    fuse    = optional(bool)
    keyctl  = optional(bool)
    mknod   = optional(bool)
    mount   = optional(string)
    nesting = optional(bool)
  }))
}
```

## Outputs

| Name                | Description                                   |
| ------------------- | --------------------------------------------- |
| `containers`        | Full Proxmox LXC resource objects             |
| `container_details` | Simplified container details (IP, VMID, etc.) |
| `container_ips`     | Map of hostnames to IP addresses              |

## Examples

### Basic Unprivileged Container

```text
{
  hostname     = "web-01"
  vmid         = 100
  ip           = "10.10.0.10/24"
  gw           = "10.10.0.1"
  cores        = 4
  memory       = 4096
  swap         = 512
  disk_size    = "30G"
  unprivileged = true
  start        = true
  onboot       = true
  tags         = ["web", "production"]
  features     = { nesting = true }
}
```

### Privileged Container (No Features)

```text
{
  hostname     = "router"
  vmid         = 101
  ip           = "10.10.0.1/24"
  gw           = "10.10.0.254"
  cores        = 2
  memory       = 2048
  swap         = 512
  disk_size    = "10G"
  unprivileged = false  # Privileged
  start        = true
  onboot       = true
  tags         = ["network"]
  # No features block for privileged containers
}
```

### Imported Container with MAC Preservation

```text
{
  hostname     = "existing-server"
  vmid         = 102
  ip           = "10.10.0.20/24"
  gw           = "10.10.0.1"
  mac          = "BC:24:11:E9:33:E6"  # CRITICAL for imports
  cores        = 2
  memory       = 2048
  swap         = 512
  disk_size    = "20G"
  unprivileged = true
  start        = true
  onboot       = true
  tags         = ["imported"]
  features     = { nesting = true }
}
```

### Multi-Node with Storage Override

```text
{
  hostname     = "database"
  vmid         = 200
  ip           = "10.20.0.10/24"
  gw           = "10.20.0.1"
  target_node  = "pve2"           # Override default node
  storage      = "local-lvm"      # Override default storage
  cores        = 8
  memory       = 16384
  swap         = 2048
  disk_size    = "100G"
  unprivileged = true
  start        = true
  onboot       = true
  tags         = ["database", "critical"]
  features     = { nesting = true }
}
```

## Important Notes

### Privileged vs Unprivileged

- **Unprivileged** (recommended): More secure, requires `features` block
- **Privileged**: Full root access, no `features` allowed (API token limitation)

### MAC Address Preservation

When importing existing containers, **ALWAYS** include the `mac` parameter:

```bash
# Get existing MAC
pct config <vmid> | grep hwaddr

# Add to instance config
mac = "BC:24:11:E9:33:E6"
```

### Features Block

Only valid for **unprivileged** containers:

- `nesting`: Enable Docker/nested containers
- `fuse`: Enable FUSE filesystems
- `keyctl`: Enable kernel keyring
- `mknod`: Allow device node creation
- `mount`: Mount flags (e.g., "nfs;cifs")

### VLAN Tagging

- `tag = -1`: No VLAN tag (default)
- `tag = 10`: VLAN 10
- `tag = 100`: VLAN 100

## Lifecycle Behavior

This module ignores changes to:

- `ostemplate`: Template path changes don't recreate containers
- `password`: Password changes don't force recreation
- `ssh_public_keys`: SSH key changes don't force recreation
- `rootfs[0].storage`: Storage changes don't force recreation

This prevents accidental container recreation when these values change.

## Requirements

- Terraform >= 1.5.0
- Providers:
  - `Telmate/proxmox` 3.0.2-rc05

## License

MIT License - See root LICENSE file for details
