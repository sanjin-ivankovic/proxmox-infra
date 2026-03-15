# Linux VM Module (Cloud-Init)

## Overview

This module provisions and manages Linux VMs on Proxmox VE using cloud-init
templates. Supports Debian and Ubuntu cloud images with automated configuration
via cloud-init.

## Features

- ✅ **Cloud-Init Support**: Automated provisioning (hostname, network, SSH keys)
- ✅ **Template Cloning**: Fast VM deployment from prepared templates
- ✅ **SSH Key Injection**: Automatic SSH key deployment via cloud-init
- ✅ **VirtIO Performance**: Optimized disk and network drivers
- ✅ **Flexible Configuration**: Per-instance overrides for resources, storage
- ✅ **QEMU Guest Agent**: IP reporting, graceful shutdown, snapshots

## Usage

```text
module "linux_vms" {
  source = "./modules/vm-linux"

  instances = {
    "k8s-master" = {
      vmid       = 300
      ip         = "10.10.0.50/24"
      gw         = "10.10.0.1"
      cores      = 4
      memory     = 8192
      disk_size  = "50G"
      onboot     = true
      start      = true
      tags       = ["kubernetes", "master"]
    }
  }

  ssh_public_keys = module.ssh_keys.public_keys
  target_node     = "pve"
  clone_template  = "debian-12-cloudinit"
  default_storage = "local-zfs"
  default_bridge  = "vmbr0"
}
```

## Inputs

<!-- markdownlint-disable MD013 -->

| Name              | Description             | Type          | Default       | Required |
| ----------------- | ----------------------- | ------------- | ------------- | -------- |
| `instances`       | Map of Linux VM configs | `map(any)`    | n/a           | yes      |
| `ssh_public_keys` | SSH public keys map     | `map(string)` | n/a           | yes      |
| `target_node`     | Default Proxmox node    | `string`      | `"pve"`       | no       |
| `clone_template`  | VM template to clone    | `string`      | n/a           | yes      |
| `default_storage` | Default storage backend | `string`      | `"local-zfs"` | no       |
| `default_bridge`  | Default network bridge  | `string`      | `"vmbr0"`     | no       |

<!-- markdownlint-enable MD013 -->

## Instance Object Schema

```text
{
  hostname     = string           # VM hostname
  vmid         = number           # Proxmox VMID (100-999999999)
  ip           = string           # IP in CIDR notation (e.g., "10.0.0.1/24")
  gw           = string           # Gateway IP
  cores        = number           # CPU cores
  memory       = number           # RAM in MB
  disk_size    = string           # Disk size (e.g., "50G")
  onboot       = bool             # Start on Proxmox boot
  start        = bool             # Start after creation
  tags         = list(string)     # Tags for organization

  # Optional overrides
  target_node   = optional(string)   # Override default node
  storage       = optional(string)   # Override default storage
  tag           = optional(number)   # VLAN tag (-1 = no tag)
  sockets       = optional(number)   # CPU sockets (default: 1)
  cpu_type      = optional(string)   # CPU type (default: "host")
  bios          = optional(string)   # BIOS type (default: "seabios", or "ovmf" for UEFI)
  machine       = optional(string)   # Machine type (default: "q35")
  ssd           = optional(number)   # SSD emulation (default: 1)
  discard       = optional(string)   # TRIM support (default: "on")
  iothread      = optional(number)   # I/O thread (default: 1)
  cache         = optional(string)   # Cache mode (default: "none")
  nameserver    = optional(string)   # DNS servers (default: "8.8.8.8 8.8.4.4")
  searchdomain  = optional(string)   # DNS search domain
  ciuser        = optional(string)   # Cloud-init user (default: "root")
  full_clone    = optional(bool)     # Full clone vs linked clone (default: true)
  enable_rng    = optional(bool)     # Enable VirtIO RNG (default: true)
  startup       = optional(string)   # Startup/shutdown order
  description   = optional(string)   # VM description
}
```

## Outputs

| Name         | Description                            |
| ------------ | -------------------------------------- |
| `vms`        | Full Proxmox VM resource objects       |
| `vm_details` | Simplified VM details (IP, VMID, etc.) |
| `vm_ips`     | Map of hostnames to IP addresses       |

## Examples

### Basic Debian VM

```text
{
  hostname   = "web-server"
  vmid       = 300
  ip         = "10.10.0.50/24"
  gw         = "10.10.0.1"
  cores      = 2
  memory     = 4096
  disk_size  = "32G"
  onboot     = true
  start      = true
  tags       = ["web", "production"]
}
```

### Ubuntu VM with UEFI

```text
{
  hostname   = "docker-host"
  vmid       = 301
  ip         = "10.10.0.51/24"
  gw         = "10.10.0.1"
  cores      = 4
  memory     = 8192
  disk_size  = "100G"
  onboot     = true
  start      = true
  bios       = "ovmf"      # UEFI boot
  tags       = ["docker", "containers"]
}
```

### High-Performance VM

```text
{
  hostname   = "database"
  vmid       = 400
  ip         = "10.20.0.10/24"
  gw         = "10.20.0.1"
  cores      = 8
  sockets    = 2          # 16 total vCPUs (8 cores × 2 sockets)
  memory     = 32768      # 32 GB RAM
  disk_size  = "500G"
  onboot     = true
  start      = true
  cpu_type   = "host"     # Best performance
  machine    = "q35"      # Modern chipset
  cache      = "writeback" # Better write performance
  iothread   = 1          # Dedicated I/O thread
  ssd        = 1          # SSD optimization
  tags       = ["database", "critical"]
}
```

### Multi-Node with Custom DNS

```text
{
  hostname      = "app-server"
  vmid          = 302
  ip            = "10.10.0.52/24"
  gw            = "10.10.0.1"
  target_node   = "pve2"              # Deploy on different node
  storage       = "fast-nvme"         # Use faster storage
  cores         = 4
  memory        = 8192
  disk_size     = "80G"
  onboot        = true
  start         = true
  nameserver    = "10.10.0.10"        # Custom DNS
  searchdomain  = "internal.local"    # Search domain
  tags          = ["application"]
}
```

## Supported Templates

This module works with cloud-init enabled templates:

- **debian-12-cloudinit** (Debian 12 Bookworm)
- **debian-13-cloudinit** (Debian 13 Trixie)
- **ubuntu-2204-cloudinit** (Ubuntu 22.04 LTS Jammy)
- **ubuntu-2404-cloudinit** (Ubuntu 24.04 LTS Noble)

See `/docs/templates/` for template creation guides.

## Cloud-Init Behavior

### First Boot

On first boot, cloud-init will:

1. Set hostname to `name` parameter
2. Configure network with static IP from `ipconfig0`
3. Inject SSH public key from `sshkeys` parameter
4. Create/configure the `ciuser` account
5. Expand root filesystem to match disk size
6. Execute any custom user-data scripts (if configured)

### SSH Access

```bash
# After first boot, SSH with generated key
ssh -i ~/.ssh/<hostname>_id_ed25519 root@<vm-ip>

# Or if using custom ciuser
ssh -i ~/.ssh/<hostname>_id_ed25519 <ciuser>@<vm-ip>
```

## CPU and BIOS Options

### CPU Types

| Type            | Description          | Use Case                  |
| --------------- | -------------------- | ------------------------- |
| `host`          | Exposes all host CPU | Best performance, ties to |
|                 | features             | host CPU                  |
| `x86-64-v2-AES` | Portable CPU model   | Better for VM migration   |
| `kvm64`         | Basic emulation      | Maximum compatibility     |

### BIOS Types

| Type      | Description   | Use Case                         |
| --------- | ------------- | -------------------------------- |
| `seabios` | Legacy BIOS   | Default, maximum compatibility   |
| `ovmf`    | UEFI firmware | Modern OSes, Secure Boot support |

## Storage Options

### Cache Modes

<!-- markdownlint-disable MD013 -->

| Mode           | Description          | Performance | Data Safety                    |
| -------------- | -------------------- | ----------- | ------------------------------ |
| `none`         | No caching (default) | Good        | Excellent                      |
| `writeback`    | Cache writes         | Excellent   | Good (requires battery backup) |
| `writethrough` | Cache reads only     | Good        | Excellent                      |

<!-- markdownlint-enable MD013 -->

### SSD Optimizations

- `ssd = 1`: Enables TRIM/discard, improves SSD lifespan
- `discard = "on"`: Enables TRIM passthrough to storage
- `iothread = 1`: Dedicated I/O thread, reduces CPU overhead

## Networking

### VLAN Tagging

```text
tag = -1   # No VLAN (default)
tag = 10   # VLAN 10
tag = 100  # VLAN 100
```

### Multiple Network Interfaces

This module currently supports one network interface. For multiple NICs,
extend the `network` block in the module.

## Troubleshooting

### VM Won't Start

**Symptom**: VM fails to start after cloning

**Solutions**:

1. Verify template exists: `qm list | grep <template-name>`
2. Check storage has space: `pvesm status`
3. Verify QEMU guest agent is installed in template

### No IP Address Reported

**Symptom**: Proxmox shows "N/A" for IP address

**Solutions**:

1. Verify QEMU guest agent is running in VM:

   ```bash
   ssh root@<vm-ip>
   systemctl status qemu-guest-agent
   ```

2. Enable agent in VM: `apt install qemu-guest-agent`

### Cloud-Init Not Running

**Symptom**: Hostname/SSH keys not configured

**Solutions**:

1. Check cloud-init logs in VM:

   ```bash
   sudo cloud-init status --long
   sudo cat /var/log/cloud-init.log
   ```

2. Verify cloud-init drive exists in template: `qm config <template-vmid> |
grep ide2`

### Slow Performance

**Symptom**: VM is slow compared to LXC

**Solutions**:

1. Enable SSD optimizations: `ssd = 1, discard = "on", iothread = 1`
2. Use `cpu = "host"` for best performance
3. Use `cache = "writeback"` (if storage has battery backup)
4. Verify VirtIO drivers are used (should be default with cloud-init images)

## Requirements

- Terraform >= 1.5.0
- Providers:
  - `Telmate/proxmox` 3.0.2-rc05
- Proxmox templates with cloud-init (see `/docs/templates/`)

## License

MIT License - See root LICENSE file for details
