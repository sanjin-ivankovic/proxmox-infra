# Windows VM Module (Cloudbase-Init)

## Overview

This module provisions and manages Windows VMs on Proxmox VE using
cloudbase-init templates. Supports Windows Server 2022 with automated
configuration via cloudbase-init.

## Features

- ✅ **Cloudbase-Init Support**: Automated provisioning (hostname, network,
  SSH keys, Windows activation)
- ✅ **Template Cloning**: Fast VM deployment from prepared Windows templates
- ✅ **SSH Key Injection**: Automatic SSH key deployment via cloudbase-init +
  OpenSSH Server
- ✅ **Windows Activation**: Automatic activation via MAK or KMS product keys
- ✅ **VirtIO Performance**: Optimized disk and network drivers
- ✅ **UEFI & TPM 2.0**: Modern Windows Server 2022 support
- ✅ **QEMU Guest Agent**: IP reporting, graceful shutdown, snapshots

## Usage

```text
module "windows_vms" {
  source = "./modules/vm-windows"

  instances = {
    "ad-dc" = {
      vmid       = 400
      ip         = "10.10.0.50/24"
      gw         = "10.10.0.1"
      cores      = 4
      memory     = 8192
      disk_size  = "80G"
      onboot     = true
      start      = true
      tags       = ["windows", "active-directory"]
    }
  }

  ssh_public_keys = module.ssh_keys.public_keys
  target_node     = "pve"
  clone_template  = "windows-server-2022-std"
  default_storage = "local-zfs"
  default_bridge  = "vmbr0"
}
```

## Inputs

<!-- markdownlint-disable MD060 MD013 -->

| Name              | Description                      | Type          | Default       | Required |
| ----------------- | -------------------------------- | ------------- | ------------- | -------- |
| `instances`       | Map of Windows VM configurations | `map(any)`    | n/a           | yes      |
| `ssh_public_keys` | SSH public keys map              | `map(string)` | n/a           | yes      |
| `target_node`     | Default Proxmox node             | `string`      | `"pve"`       | no       |
| `clone_template`  | Windows template to clone        | `string`      | n/a           | yes      |
| `product_key`     | Windows MAK/KMS product key      | `string`      | `""`          | no       |
| `default_storage` | Default storage backend          | `string`      | `"local-zfs"` | no       |
| `default_bridge`  | Default network bridge           | `string`      | `"vmbr0"`     | no       |

<!-- markdownlint-enable MD060 MD013 -->

## Instance Object Schema

```text
{
  hostname     = string           # VM hostname
  vmid         = number           # Proxmox VMID (100-999999999)
  ip           = string           # IP in CIDR notation (e.g., "10.0.0.1/24")
  gw           = string           # Gateway IP
  cores        = number           # CPU cores
  memory       = number           # RAM in MB
  disk_size    = string           # Disk size (e.g., "80G")
  onboot       = bool             # Start on Proxmox boot
  start        = bool             # Start after creation
  tags         = list(string)     # Tags for organization

  # Optional overrides
  target_node   = optional(string)   # Override default node
  storage       = optional(string)   # Override default storage
  tag           = optional(number)   # VLAN tag (-1 = no tag)
  sockets       = optional(number)   # CPU sockets (default: 1)
  cpu_type      = optional(string)   # CPU type (default: "host")
  bios          = optional(string)   # BIOS type (default: "ovmf" for UEFI)
  machine       = optional(string)   # Machine type (default: "q35")
  ssd           = optional(number)   # SSD emulation (default: 1)
  discard       = optional(string)   # TRIM support (default: "on")
  iothread      = optional(number)   # I/O thread (default: 1)
  cache         = optional(string)   # Cache mode (default: "writeback")
  nameserver    = optional(string)   # DNS servers (default: "8.8.8.8 8.8.4.4")
  searchdomain  = optional(string)   # DNS search domain
  ciuser        = optional(string)   # Cloudbase-init user (default: "Administrator")
  full_clone    = optional(bool)     # Full clone vs linked clone (default: true)
  enable_tpm    = optional(bool)     # Enable TPM 2.0 (default: true)
  tablet        = optional(bool)     # Tablet device for mouse (default: true)
  vga_type      = optional(string)   # VGA type (default: "std")
  startup       = optional(string)   # Startup/shutdown order
  description   = optional(string)   # VM description
}
```

## Outputs

<!-- markdownlint-disable MD060 -->

| Name         | Description                            |
| ------------ | -------------------------------------- |
| `vms`        | Full Proxmox VM resource objects       |
| `vm_details` | Simplified VM details (IP, VMID, etc.) |
| `vm_ips`     | Map of hostnames to IP addresses       |

<!-- markdownlint-enable MD060 -->

## Examples

### Basic Windows Server VM

```text
{
  hostname   = "file-server"
  vmid       = 400
  ip         = "10.10.0.50/24"
  gw         = "10.10.0.1"
  cores      = 4
  memory     = 8192
  disk_size  = "80G"
  onboot     = true
  start      = true
  tags       = ["windows", "file-server"]
}
```

### Active Directory Domain Controller

```text
{
  hostname   = "ad-dc-01"
  vmid       = 401
  ip         = "10.10.0.10/24"
  gw         = "10.10.0.1"
  cores      = 4
  memory     = 8192
  disk_size  = "100G"
  onboot     = true
  start      = true
  nameserver = "127.0.0.1"  # Will be DNS after AD promotion
  tags       = ["windows", "active-directory", "dns"]
}
```

### High-Performance SQL Server

```text
{
  hostname   = "sql-server"
  vmid       = 500
  ip         = "10.20.0.10/24"
  gw         = "10.20.0.1"
  cores      = 8
  sockets    = 2          # 16 total vCPUs (8 cores × 2 sockets)
  memory     = 65536      # 64 GB RAM
  disk_size  = "500G"
  onboot     = true
  start      = true
  cpu_type   = "host"     # Best performance
  cache      = "writeback" # Better write performance (requires battery backup)
  iothread   = 1
  ssd        = 1
  tags       = ["windows", "database", "sql-server"]
}
```

### Multi-Node Windows Cluster Member

```text
{
  hostname      = "cluster-node-01"
  vmid          = 450
  ip            = "10.30.0.10/24"
  gw            = "10.30.0.1"
  target_node   = "pve2"              # Deploy on specific node
  storage       = "fast-nvme"         # Use faster storage
  cores         = 8
  memory        = 32768
  disk_size     = "200G"
  onboot        = true
  start         = true
  nameserver    = "10.10.0.10"        # AD DNS
  searchdomain  = "internal.local"
  tags          = ["windows", "cluster"]
}
```

## Supported Templates

This module works with cloudbase-init enabled Windows templates:

- **windows-server-2022-std** (Windows Server 2022 Standard)
- **windows-server-2022-dc** (Windows Server 2022 Datacenter)

See `/docs/templates/windows-server-2022-cloudinit.md` for template creation
guide.

## Cloudbase-Init Behavior

### First Boot

On first boot, cloudbase-init will:

1. Set hostname from `name` parameter
2. Configure network with static IP from `ipconfig0`
3. Inject SSH public key from `sshkeys` parameter (for OpenSSH Server)
4. Configure the `ciuser` account (default: Administrator)
5. Activate Windows with product key (if provided)
6. Expand disk to match configured size
7. Execute any custom PowerShell scripts (if configured)

### Administrator Password Configuration

**Password is NOT set via cloud-init.** Use one of the following methods:

1. **Template Default Password**: Use the password set during template
   creation
2. **Manual Password Change**: Set password manually after VM deployment
3. **Group Policy**: Configure password via Active Directory Group Policy
   (for domain-joined VMs)
4. **Ansible**: Use Ansible to set password after deployment

**Note:** The template's default Administrator password will be used until
manually changed.

### SSH Access

After first boot, you can SSH to Windows VMs using OpenSSH Server:

```text
# SSH with generated key
ssh -i ~/.ssh/<hostname>_id_ed25519 Administrator@<vm-ip>

# Or if using custom ciuser
ssh -i ~/.ssh/<hostname>_id_ed25519 <ciuser>@<vm-ip>
```

## UEFI and TPM 2.0

### UEFI Boot

Windows Server 2022 requires UEFI boot (BIOS type `ovmf`):

- **Enabled by default** in this module
- Provides Secure Boot support
- Required for modern Windows features

### TPM 2.0

TPM 2.0 is **enabled by default** for:

- BitLocker encryption support
- Windows 11/Server 2022 compliance
- Enhanced security features

Disable if not needed:

```text
enable_tpm = false
```

## CPU and Performance Options

### CPU Types

<!-- markdownlint-disable MD060 -->

| Type            | Description                   | Use Case                   |
| --------------- | ----------------------------- | -------------------------- |
| `host`          | Exposes all host CPU features | Best performance (default) |
| `x86-64-v2-AES` | Portable CPU model            | Better for VM migration    |
| `kvm64`         | Basic emulation               | Maximum compatibility      |

<!-- markdownlint-enable MD060 -->

### Machine Types

<!-- markdownlint-disable MD060 -->

| Type     | Description              | Use Case               |
| -------- | ------------------------ | ---------------------- |
| `q35`    | Modern chipset (default) | Windows Server 2016+   |
| `i440fx` | Legacy chipset           | Older Windows versions |

<!-- markdownlint-enable MD060 -->

## Storage Options

### Cache Modes

<!-- markdownlint-disable MD060 MD013 -->

| Mode           | Description            | Performance | Data Safety             | Use Case            |
| -------------- | ---------------------- | ----------- | ----------------------- | ------------------- |
| `writeback`    | Cache writes (default) | Excellent   | Requires battery backup | Production with UPS |
| `writethrough` | Cache reads only       | Good        | Excellent               | General use         |

<!-- markdownlint-enable MD060 MD013 -->

| `none` | No caching | Good | Excellent | Testing/dev |

**Recommendation**: Use `writeback` for production Windows VMs if storage has
battery backup.

### Disk Optimizations

- `ssd = 1`: Enables TRIM/discard, improves SSD lifespan
- `discard = "on"`: Enables TRIM passthrough to storage
- `iothread = 1`: Dedicated I/O thread, reduces latency

## Networking

### VLAN Tagging

```text
tag = -1   # No VLAN (default)
tag = 10   # VLAN 10
tag = 100  # VLAN 100
```

### DNS Configuration

```text
nameserver   = "10.10.0.10 10.10.0.11"  # Primary and secondary DNS
searchdomain = "internal.local"          # DNS search domain
```

## Ansible Integration (WinRM)

For Ansible to manage Windows VMs, configure WinRM:

**In Windows VM** (via cloudbase-init user-data or manually):

```text
# Enable WinRM
Enable-PSRemoting -Force

# Configure WinRM for Ansible
winrm quickconfig -quiet
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'

# Add firewall rule
New-NetFirewallRule -Name "WinRM-HTTP" -DisplayName "WinRM-HTTP" -Protocol TCP -LocalPort 5985 -Action Allow
```

**In Ansible inventory** (generated by ansible-inventory module):

```text
windows_hosts:
  hosts:
    ad-dc:
      ansible_host: 10.10.0.50
      ansible_user: Administrator
      ansible_password: !vault |
        ...
      ansible_connection: winrm
      ansible_port: 5985
      ansible_winrm_transport: basic
      ansible_winrm_server_cert_validation: ignore
```

## Troubleshooting

### Cloudbase-Init Not Running

**Symptom**: VM boots but hostname/SSH keys not configured

**Solutions**:

1. Check cloudbase-init service:

   ```text
   Get-Service cloudbase-init
   ```

2. View logs:

   ```text
   Get-Content "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\cloudbase-init.log" -Tail 50
   ```

3. Manually trigger cloudbase-init:

   ```text
   & "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\bin\cloudbase-init.exe"
   ```

### SSH Not Working

**Symptom**: Cannot SSH to Windows VM

**Solutions**:

1. Verify OpenSSH Server is running:

   ```text
   Get-Service sshd
   Start-Service sshd
   ```

2. Check SSH logs:

   ```text
   Get-Content C:\ProgramData\ssh\logs\sshd.log -Tail 20
   ```

3. Test SSH locally:

   ```text
   ssh Administrator@localhost
   ```

4. Verify firewall allows SSH (port 22):

   ```text
   Get-NetFirewallRule -Name sshd
   New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
   ```

### Windows Not Activated

**Symptom**: Windows shows "Not Activated"

**Solutions**:

1. Manually activate with MAK key:

   ```text
   slmgr /ipk XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
   slmgr /ato
   ```

2. Check activation status:

   ```text
   slmgr /xpr
   slmgr /dli
   ```

3. Verify product key in cloudbase-init config:

   ```text
   # C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init.conf
   [DEFAULT]
   product_key=XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
   ```

### Guest Agent Not Reporting IP

**Symptom**: Proxmox shows "N/A" for IP address

**Solutions**:

1. Verify QEMU guest agent is running:

   ```text
   Get-Service QEMU-GA
   Start-Service QEMU-GA
   ```

2. Reinstall guest agent (if needed):
   - Mount virtio-win ISO to VM
   - Run `E:\guest-agent\qemu-ga-x86_64.msi`
   - Restart service

### VM Slow Performance

**Symptom**: Windows VM is slow

**Solutions**:

1. Verify VirtIO drivers installed:

   ```text
   Get-PnpDevice | Where-Object {$_.FriendlyName -like "*VirtIO*"}
   ```

2. Enable disk optimizations:

   ```text
   ssd      = 1
   discard  = "on"
   iothread = 1
   cache    = "writeback"  # If storage has battery backup
   ```

3. Use `cpu = "host"` for best performance

4. Increase resources:

   ```text
   cores  = 8
   memory = 16384
   ```

### VM Won't Start After Cloning

**Symptom**: VM fails to start with UEFI error

**Solutions**:

1. Verify template has EFI disk:

   ```text
   qm config <template-vmid> | grep efidisk0
   ```

2. Verify template has TPM (if enabled):

   ```text
   qm config <template-vmid> | grep tpmstate0
   ```

3. Check Proxmox logs:

   ```text
   journalctl -u pve-cluster -f
   ```

## Windows Server 2022 Requirements

### Minimum Resources

- **CPU**: 2 cores (4 recommended)
- **RAM**: 2048 MB minimum (4096 recommended, 8192 for production)
- **Disk**: 60 GB minimum (80+ recommended)
- **BIOS**: UEFI (ovmf)
- **TPM**: 2.0 (optional but recommended)

### Recommended Production Settings

```text
{
  cores      = 4
  sockets    = 1
  memory     = 8192
  disk_size  = "100G"
  cpu_type   = "host"
  bios       = "ovmf"
  machine    = "q35"
  cache      = "writeback"  # With battery-backed storage
  ssd        = 1
  iothread   = 1
  enable_tpm = true
}
```

## Security Considerations

### Hardening Recommendations

1. **Disable password authentication** (SSH keys only):

   ```text
   # Edit C:\ProgramData\ssh\sshd_config
   PasswordAuthentication no
   PubkeyAuthentication yes
   ```

2. **Enable Windows Firewall**:

   ```text
   Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
   ```

3. **Keep Windows updated**:

   ```text
   Install-Module PSWindowsUpdate
   Get-WindowsUpdate
   Install-WindowsUpdate -AcceptAll -AutoReboot
   ```

4. **Use Ansible** for post-provisioning hardening (GPO, WinRM over HTTPS, etc.)

### Cloudbase-Init Security

- **Never hardcode passwords** in cloudbase-init config
- Use **SSH keys only** for authentication
- Store **product keys** in `terraform.tfvars.secret` (gitignored,
  sensitive)
- Use **Ansible Vault** for WinRM passwords

## Requirements

- Terraform >= 1.5.0
- Providers:
  - `Telmate/proxmox` 3.0.2-rc05
- Proxmox templates with cloudbase-init (see
  `/docs/templates/windows-server-2022-cloudinit.md`)
- Windows Server license (MAK or KMS)

## License

MIT License - See root LICENSE file for details
