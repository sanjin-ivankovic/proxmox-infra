# Windows Server 2022 Template with Cloudbase-Init for Proxmox

## Overview

This comprehensive guide provides a complete, step-by-step process for
creating a Windows Server 2022 Standard template with Cloudbase-Init for
automated provisioning on Proxmox VE. This template enables automated network
configuration, SSH key injection, hostname setting, and seamless VM deployment
via Terraform.

**What Cloudbase-Init Does:**

- Configures network interfaces (IP, gateway, DNS)
- Sets hostname from VM name
- Injects SSH public keys
- Executes user data scripts
- Sets timezone and other settings

**What Cloudbase-Init Does NOT Do:**

- Regenerate SID (Security Identifier) - **This requires sysprep**
- Clear machine-specific registry entries
- Generalize Windows for cloning

**Therefore:** Sysprep is **required** before converting to template.
Cloudbase-Init runs on first boot after cloning and configures the VM, but it
cannot regenerate the SID.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Step 1: Create Base VM in Proxmox](#step-1-create-base-vm-in-proxmox)
3. [Step 2: Install Windows Server 2022](#step-2-install-windows-server-2022)
4. [Step 3: Install VirtIO Drivers](#step-3-install-virtio-drivers)
5. [Step 4: Install Cloudbase-Init](#step-4-install-cloudbase-init)
6. [Step 5: Configure Cloudbase-Init](#step-5-configure-cloudbase-init)
7. [Step 6: Install OpenSSH Server](#step-6-install-openssh-server)
8. [Step 7: Install QEMU Guest Agent](#step-7-install-qemu-guest-agent)
9. [Step 8: Finalize Template](#step-8-finalize-template)
10. [Step 9: Test Template](#step-9-test-template)
11. [Troubleshooting](#troubleshooting)
12. [Configuration Reference](#configuration-reference)
13. [Best Practices](#best-practices)
14. [References](#references)
15. [Quick Reference Commands](#quick-reference-commands)

---

## Prerequisites

Before starting, ensure you have:

- **Proxmox VE 7.0+** with UEFI support
- **Windows Server 2022 Standard ISO** (Desktop Experience recommended)
- **VirtIO drivers ISO** (download from
  <!-- markdownlint-disable MD013 -->
  [Fedora VirtIO](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/)
  <!-- markdownlint-enable MD013 -->
- **Cloudbase-Init installer** (latest stable from
  [Cloudbase Solutions](https://cloudbase.it/cloudbase-init/))
- **Administrative access** to Proxmox host (SSH or Web UI)
- **Administrative access** to Windows VM
- **Network connectivity** from Windows VM to download Cloudbase-Init

---

## Step 1: Create Base VM in Proxmox

### 1.1 Create New VM

1. **Log into Proxmox Web UI**
2. **Click "Create VM"** (top right)
3. **Configure General Settings**:
   - **VM ID**: Choose a high number (e.g., `9000`) - this will become your
     template
   - **Name**: `windows-server-2022-std-template`
   - **Resource Pool**: (optional)
   - **Notes**: "Windows Server 2022 Standard Template with Cloudbase-Init"

### 1.2 Configure OS

- **OS Type**: Microsoft Windows
- **Version**: 10/2016/2019/2022 (64-bit)
- **ISO Image**: Select your Windows Server 2022 ISO from storage
- **Guest OS**: Windows

### 1.3 Configure System

**CRITICAL**: Windows Server 2022 requires UEFI boot!

- **Graphic Card**: Default (VGA)
- **Machine**: `q35` (Modern chipset - required)
- **BIOS**: `ovmf` (UEFI - **REQUIRED** for Windows Server 2022)
- **SCSI Controller**: `VirtIO SCSI single` (for iothread support)
- **QEMU Agent**: ✅ Enable (check this box)
- **Add TPM**: ✅ Enable (TPM 2.0 - recommended for Windows Server 2022)

### 1.4 Configure Hard Disk

- **Bus/Device**: SCSI
- **Storage**: Choose your storage backend (e.g., `local-lvm`)
- **Disk size**: `60G` (minimum, adjust as needed)
- **Cache**: `Writeback` (if storage has battery backup) or `None`
- **Discard**: ✅ Enable (for TRIM support)
- **SSD Emulation**: ✅ Enable
- **IO Thread**: ✅ Enable

### 1.5 Configure CPU

- **Cores**: `2` (minimum for template creation - can be increased per VM later)
- **Type**: `host` (best performance) or `x86-64-v2-AES` (portable)
- **Sockets**: `1`

**Note**: CPU and memory are configured per VM instance in Terraform, not
locked by the template.

### 1.6 Configure Memory

- **Memory**: `4096` MB (4 GB minimum, 8 GB recommended for template)
- **Ballooning**: ✅ Enable (allows memory overcommitment)

**Note**: Ballooning is recommended for templates. Individual VMs can have
different memory allocations.

### 1.7 Configure Network

- **Bridge**: Select your network bridge (e.g., `vmbr0`)
- **Model**: `VirtIO` (paravirtualized - best performance)
- **VLAN Tag**: (optional, leave empty for no VLAN)
- **Firewall**: (optional, configure as needed)

### 1.8 Add Serial Port (Recommended for Cloudbase-Init Logging)

**IMPORTANT**: Adding a serial port enables Cloudbase-Init logging to COM1,
which is helpful for debugging.

1. **Select the VM** you just created
2. **Go to "Hardware" tab**
3. **Click "Add" → "Serial Port"**
4. **Configure Serial Port**:
   - **Port**: `0` (COM1 in Windows)
   - **Type**: `Socket` (recommended for Proxmox)
5. **Click "Add"**

**Note**: This is optional but recommended. Cloudbase-Init will work without
it, but serial port logging helps with troubleshooting.

### 1.9 Attach VirtIO Drivers ISO

1. **Select the VM** you just created
2. **Go to "Hardware" tab**
3. **Click "Add" → "CD/DVD Drive"**
4. **Select "Use CD/DVD disc image file (iso)"**
5. **Browse and select** your VirtIO drivers ISO
6. **Click "Add"**

### 1.10 Review and Create

- Review all settings
- **Click "Finish"** to create the VM
- **DO NOT START** the VM yet

---

## Step 2: Install Windows Server 2022

### 2.1 Start VM and Boot from ISO

1. **Select your VM**
2. **Click "Start"**
3. **Click "Console"** to open VNC console
4. **VM should boot** from Windows Server 2022 ISO

### 2.2 Windows Installation Process

1. **Select Language, Time, Keyboard**: Choose your preferences
2. **Click "Next"**
3. **Click "Install Now"**
4. **Enter Product Key**: **SKIP** (Windows will run in evaluation mode)
5. **Select Edition**:
   - Choose **"Windows Server 2022 Standard (Desktop Experience)"**
   - Desktop Experience is recommended for easier management
6. **Accept License Terms**: Check the box and click "Next"

### 2.3 Load VirtIO Drivers During Installation

**IMPORTANT**: When you reach the disk selection screen:

1. **Click "Load Driver"**
2. **Browse to**: `E:\` (or the VirtIO ISO drive letter)
3. **Navigate to**: `E:\vioscsi\w11\amd64\` (or `w10` for Windows 10 drivers)
4. **Select the driver** and click "Next"
5. **Repeat** for network drivers if needed:
   - `E:\NetKVM\w11\amd64\`

### 2.4 Complete Installation

1. **Select disk** (should now show your VirtIO disk)
2. **Click "Next"** to begin installation
3. **Wait for installation** to complete (15-30 minutes)
4. **VM will restart** automatically

### 2.5 Post-Installation Setup

1. **Set Administrator Password**:
   - Create a **temporary password** (will be used for template)
   - **Remember this password** (needed until Cloudbase-Init runs on cloned VMs)
   - **Note**: Password is NOT set via Cloudbase-Init (use template default)
2. **Complete initial setup**:
   - Accept default settings
   - Skip optional features for now
   - Complete Windows setup

### 2.6 Verify Installation

1. **Log in** as Administrator
2. **Open PowerShell as Administrator**
3. **Verify Windows version**:

```text
Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion
```

1. **Should show**: Windows Server 2022 Standard

---

## Step 3: Install VirtIO Drivers

### 3.1 Mount VirtIO ISO

1. **In Proxmox**: Ensure VirtIO ISO is still attached
2. **In Windows VM**: Open File Explorer
3. **VirtIO ISO should appear** as a CD/DVD drive (usually `E:\`)

### 3.2 Install VirtIO Guest Tools

**Option A: Install Individual Drivers** (Recommended)

1. **Open Device Manager**:
   - Press `Win + X`
   - Select "Device Manager"
2. **Look for devices** with yellow warning icons
3. **Right-click** each device → "Update Driver"
4. **Browse** to VirtIO ISO drive (`E:\`)
5. **Let Windows search** for drivers automatically

**Option B: Install Complete Package** (Faster)

1. **Navigate to VirtIO ISO** in File Explorer (`E:\`)
2. **Run installer**:
   - `virtio-win-gt-x64.msi` (Guest Tools)
   - Or `virtio-win-guest-tools.exe`
3. **Follow installation wizard**
4. **Restart VM** when prompted

### 3.3 Verify VirtIO Drivers

```text
# Check VirtIO devices
Get-PnpDevice | Where-Object {$_.FriendlyName -like "*VirtIO*"} `
  | Format-Table FriendlyName, Status

# Should show devices like:
# - Red Hat VirtIO SCSI Disk Device
# - Red Hat VirtIO Ethernet Adapter
```

### 3.4 Verify Network Adapter

```text
# Check network adapter
Get-NetAdapter | Format-Table Name, InterfaceDescription, Status

# Should show: "Ethernet" with "Red Hat VirtIO Ethernet Adapter"
```

---

## Step 4: Install Cloudbase-Init

### 4.1 Download Cloudbase-Init

#### Method 1: Using PowerShell (Recommended)

**Open PowerShell as Administrator** and run:

```text
# Download latest stable Cloudbase-Init installer
$url = "https://cloudbase.it/downloads/CloudbaseInitSetup_Stable_x64.msi"
Invoke-WebRequest -Uri $url -OutFile "C:\CloudbaseInitSetup.msi"

# Verify download
Test-Path "C:\CloudbaseInitSetup.msi"
```

#### Method 2: Using Web Browser

1. **Open web browser** in Windows VM
2. **Navigate to**: <https://cloudbase.it/cloudbase-init/>
3. **Download**: Latest stable MSI installer
   - Example: `CloudbaseInitSetup_1.1.3_x64.msi`
4. **Save to**: `C:\CloudbaseInitSetup.msi`

### 4.2 Install Cloudbase-Init

**Open PowerShell as Administrator** and run:

```text
# Install Cloudbase-Init with recommended parameters
msiexec /i C:\CloudbaseInitSetup.msi /qn /l*v C:\cloudbase-init-install.log `
  RUN_SERVICE_AS_LOCAL_SYSTEM=1 `
  LOGGINGSERIALPORTNAME=COM1

# Wait for installation to complete (check Task Manager for msiexec process)
# Or wait 30-60 seconds
```

**Parameters Explained**:

- `/qn`: Quiet installation (no UI)
- `/l*v`: Verbose logging to specified file
- `RUN_SERVICE_AS_LOCAL_SYSTEM=1`: **CRITICAL** - Runs service as Local
  System (required for sysprep)
- `LOGGINGSERIALPORTNAME=COM1`: Enables serial port logging for debugging

### 4.3 Verify Installation

```text
# Check Cloudbase-Init service
Get-Service cloudbase-init

# Should show:
# Status: Stopped (normal for template)
# StartType: Automatic (required)

# Verify installation directory exists
Test-Path "C:\Program Files\Cloudbase Solutions\Cloudbase-Init"

# Check installation log for errors
Get-Content C:\cloudbase-init-install.log | Select-String -Pattern "error|fail" -Context 2
```

---

## Step 5: Configure Cloudbase-Init

### 5.1 Locate Configuration File

The configuration file is located at:

```text
C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init.conf
```

### 5.2 Edit Configuration File

**Open PowerShell as Administrator**:

```text
# Open configuration file in Notepad
notepad "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\"`
  "cloudbase-init.conf"
```

### 5.3 Complete Configuration

**Replace the entire `[DEFAULT]` section** with the following configuration:

**IMPORTANT**: The `plugins` line must be on a **single line** without any
backticks (`). Do NOT copy backticks into the INI file - they are only for
readability in this documentation.

```text
[DEFAULT]
# ============================================================================
# User Configuration
# ============================================================================
username=Administrator
groups=Administrators
# Password is NOT set via cloud-init (use template default or set manually)

# ============================================================================
# Metadata Services (CRITICAL: Use ConfigDriveService for Proxmox)
# ============================================================================
# IMPORTANT: Use ConfigDriveService, NOT NoCloudService!
metadata_services=cloudbaseinit.metadata.services.configdrive.ConfigDriveService

# ============================================================================
# Plugins (Enable required functionality)
# ============================================================================
plugins=cloudbaseinit.plugins.common.mtu.MTUPlugin,cloudbaseinit.plugins.common.sethostname.SetHostNamePlugin,cloudbaseinit.plugins.common.networkconfig.NetworkConfigPlugin,cloudbaseinit.plugins.common.sshpublickeys.SetUserSSHPublicKeysPlugin,cloudbaseinit.plugins.common.userdata.UserDataPlugin,cloudbaseinit.plugins.common.localscripts.LocalScriptsPlugin

# ============================================================================
# Config Drive Detection (Proxmox uses ISO9660/CD-ROM)
# ============================================================================
config_drive_raw_hdd=true
config_drive_cdrom=true
config_drive_vfat=true
config_drive_cdrom_strict_mode=false

# ============================================================================
# Paths
# ============================================================================
bsdtar_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\bin\bsdtar.exe
mtools_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\bin\

# ============================================================================
# Logging
# ============================================================================
verbose=true
debug=true
log_dir=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\
log_file=cloudbase-init.log
default_log_levels=comtypes=INFO,suds=INFO,iso8601=WARN,requests=WARN
logging_serial_port_settings=COM1,115200,N,8

# ============================================================================
# Network Configuration
# ============================================================================
mtu_use_dhcp_config=true
ntp_use_dhcp_config=true

# ============================================================================
# Local Scripts
# ============================================================================
local_scripts_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\LocalScripts\

# ============================================================================
# Updates
# ============================================================================
check_latest_version=true

# ============================================================================
# Retry Configuration
# ============================================================================
retry_count=30
retry_count_interval=10
```

### 5.4 Save Configuration

1. **Save the file** (Ctrl+S)
2. **Close Notepad**
3. **Verify configuration**:

```text
# Verify metadata service is correct
Get-Content "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\"`
  "cloudbase-init.conf" | Select-String "metadata_services"

# Should show: ConfigDriveService (NOT NoCloudService)
```

### 5.5 Verify Plugins

```text
# Verify all required plugins are enabled
$conf = "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\"`
  "cloudbase-init.conf"
Get-Content $conf | Select-String "plugins"

# Should include:
# - SetHostNamePlugin (for hostname)
# - NetworkConfigPlugin (for network)
# - SetUserSSHPublicKeysPlugin (for SSH keys)
```

---

## Step 6: Install OpenSSH Server

### 6.1 Install OpenSSH Server

**Open PowerShell as Administrator**:

```text
# Install OpenSSH Server feature
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Verify installation
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
```

### 6.2 Configure OpenSSH Server

```text
# Start OpenSSH Server service
Start-Service sshd

# Set OpenSSH Server to start automatically
Set-Service -Name sshd -StartupType 'Automatic'

# Verify service is running
Get-Service sshd

# Should show:
# Status: Running
# StartType: Automatic
```

### 6.3 Configure Windows Firewall

```text
# Allow SSH through Windows Firewall (should be automatic, but verify)
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' `
  -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 `
  -ErrorAction SilentlyContinue

# Verify firewall rule exists
Get-NetFirewallRule -Name sshd
```

### 6.4 Verify SSH Access

**From your workstation** (after VM is deployed):

```bash
# Test SSH connection
ssh Administrator@<vm-ip-address>

# If prompted, type "yes" to accept host key
# Exit with: exit
```

---

## Step 7: Install QEMU Guest Agent

### 7.1 Download QEMU Guest Agent

**Option A: From VirtIO ISO** (if included)

1. **Mount VirtIO ISO** (if not already mounted)
2. **Navigate to**: `E:\guest-agent\`
3. **Run**: `qemu-ga-x86_64.msi`

#### Option B: Download Separately

1. **Open web browser** in Windows VM
2. **Download from**:
   <!-- markdownlint-disable MD013 -->
   <https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/>
   <!-- markdownlint-enable MD013 -->
3. **Extract** and run `qemu-ga-x86_64.msi`

### 7.2 Install QEMU Guest Agent

1. **Run the MSI installer**
2. **Follow installation wizard**
3. **Complete installation**

### 7.3 Verify Installation

```text
# Check QEMU Guest Agent service
Get-Service QEMU-GA

# Should show:
# Status: Running
# StartType: Automatic

# If not running, start it
Start-Service QEMU-GA
Set-Service -Name QEMU-GA -StartupType 'Automatic'
```

---

## Step 8: Finalize Template

### 8.1 Clean Up Installation Files

**Open PowerShell as Administrator**:

```text
# Remove installation files
Remove-Item C:\CloudbaseInitSetup.msi -ErrorAction SilentlyContinue
Remove-Item C:\cloudbase-init-install.log -ErrorAction SilentlyContinue

# Optional: Clear Windows event logs (reduces template size)
wevtutil el | ForEach-Object {wevtutil cl "$_"}
```

### 8.2 Remove Installation ISOs

**IMPORTANT**: Remove ISOs from template before conversion.

1. **In Proxmox Web UI**, select your VM
2. **Go to "Hardware" tab**
3. **Remove both ISOs**:
   - Windows Server 2022 ISO (ide0 or ide2)
   - VirtIO drivers ISO (ide0 or ide2)
4. **Keep the serial port** (do not remove)

**Note**: ISOs should be removed before converting to template. The serial
port should remain.

### 8.3 Final Verification Checklist

**Run these commands to verify everything is ready**:

```text
# 1. Verify Cloudbase-Init service
Get-Service cloudbase-init | Select-Object Name, Status, StartType
# Expected: Status=Stopped, StartType=Automatic

# 2. Verify Cloudbase-Init configuration
Test-Path "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init.conf"
Get-Content "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\"`
  "cloudbase-init.conf" | Select-String "metadata_services"
# Expected: ConfigDriveService (NOT NoCloudService)

# 3. Verify OpenSSH Server
Get-Service sshd | Select-Object Name, Status, StartType
# Expected: Status=Running, StartType=Automatic

# 4. Verify QEMU Guest Agent
Get-Service QEMU-GA | Select-Object Name, Status, StartType
# Expected: Status=Running, StartType=Automatic

# 5. Verify VirtIO drivers
Get-PnpDevice | Where-Object {$_.FriendlyName -like "*VirtIO*"} `
  | Select-Object FriendlyName, Status
# Expected: Multiple VirtIO devices showing "OK" status

# 6. Verify network adapter
Get-NetAdapter | Format-Table Name, InterfaceDescription, Status
# Expected: Ethernet adapter with VirtIO description
```

### 8.4 Run Sysprep (REQUIRED)

**CRITICAL**: You **MUST** run sysprep before converting to template!

**Why sysprep is required:**

- **Regenerates SID**: Each cloned VM needs a unique Security Identifier (SID)
- **Clears machine-specific settings**: Removes hostname, network config, etc.
- **Prepares for cloning**: Windows needs to be "generalized" before cloning
- **Domain join requires unique SID**: Without sysprep, cloned VMs share the
  same SID, which prevents domain join

**What Cloudbase-Init does vs doesn't do:**

**Cloudbase-Init DOES:**

- Configure network interfaces (IP, gateway, DNS)
- Set hostname
- Inject SSH public keys
- Execute user data scripts
- Set timezone and other settings

**Cloudbase-Init DOES NOT:**

- Regenerate SID (Security Identifier)
- Clear machine-specific registry entries
- Generalize Windows for cloning

**Therefore:** Sysprep is **required** before converting to template.
Cloudbase-Init runs on first boot after cloning and configures the VM, but it
cannot regenerate the SID.

**Run sysprep:**

```text
# Navigate to sysprep directory
cd C:\Windows\System32\Sysprep

# Run sysprep to generalize Windows
.\sysprep.exe /generalize /oobe /shutdown

# Parameters explained:
# /generalize - Removes machine-specific information (SID, hostname, etc.)
# /oobe      - Starts Windows in "Out of Box Experience" mode on next boot
# /shutdown  - Shuts down the VM after sysprep completes
```

**What happens:**

1. Sysprep generalizes Windows (regenerates SID, clears settings)
2. VM automatically shuts down
3. Windows will boot in OOBE mode on next start
4. Cloudbase-Init will run on first boot and configure the VM

**Important Notes:**

- **Do NOT log back in** after sysprep - the VM will shut down automatically
- **Do NOT cancel sysprep** - let it complete fully
- **This is a one-way operation** - after sysprep, you cannot undo it
- **After sysprep, the VM is ready** to be converted to a template

### 8.5 Convert to Template

**After sysprep completes and VM shuts down**, convert to template:

**On Proxmox host** (via SSH or Web UI):

```bash
# Convert VM to template
qm template <vmid>

# Example:
qm template 9000

# Verify template was created
qm config <vmid> | grep template
# Should show: template: 1
```

**Or via Web UI**:

1. **Select VM**
2. **Right-click** → "Convert to Template"
3. **Confirm** conversion

---

## Step 9: Test Template

**IMPORTANT**: This step is **OPTIONAL** and only for **manual testing**
without Terraform.

If you're using Terraform (which you are), you **DO NOT need to do this
manually**. Terraform automatically:

- Clones the template
- Configures `ipconfig0` from your `windows-vms.auto.tfvars` file
- Sets `nameserver` from your configuration
- Sets `ciuser` (defaults to Administrator)
- Injects SSH keys automatically
- Configures all cloud-init settings

**Skip to Step 9.3** if you want to test via Terraform instead.

### 9.1 Clone Test VM (Manual Testing Only)

**On Proxmox host** (only if testing manually without Terraform):

```bash
# Clone template to test VM
qm clone <template-vmid> <test-vmid> --name test-windows-vm

# Example:
qm clone 9000 9100 --name test-windows-vm
```

### 9.2 Configure Cloud-Init Settings (Manual Testing Only)

**On Proxmox host** (only if testing manually without Terraform):

```bash
# Configure cloud-init settings manually
qm set <test-vmid> --ipconfig0 ip=10.10.0.100/24,gw=10.10.0.1
qm set <test-vmid> --nameserver 8.8.8.8
qm set <test-vmid> --ciuser Administrator

# Note: Password is NOT set via cloud-init (use template default)

# Add SSH public key (if you have one)
qm set <test-vmid> --sshkeys ~/.ssh/test_key.pub

# Or generate one for testing
ssh-keygen -t ed25519 -f ~/.ssh/test_windows -N ""
qm set <test-vmid> --sshkeys ~/.ssh/test_windows.pub
```

**OR use Terraform** (recommended - automatic configuration):

When you define your VM in `windows-vms.auto.tfvars`:

```text
windows_vm_instances = [
  {
    hostname   = "dc01"
    vmid       = 100
    ip         = "10.10.0.10/24"      # ← Automatically sets ipconfig0
    gw         = "10.10.0.1"          # ← Automatically sets gateway
    nameserver = "1.1.1.1"            # ← Automatically sets nameserver
    ciuser     = "Administrator"     # ← Automatically sets ciuser
    # Note: Password is NOT set via cloud-init (use template default)
    # ... other settings
  }
]
```

Terraform automatically applies all these settings - **no manual `qm set`
commands needed!**

### 9.3 Start Test VM

```bash
# Start test VM
qm start <test-vmid>

# Monitor boot process
qm monitor <test-vmid>
```

### 9.4 Verify Cloudbase-Init Execution

**Wait 5-15 minutes** for first boot, then check:

1. **Open VM Console** in Proxmox
2. **Log in** as Administrator (use template default password)
3. **Check Cloudbase-Init logs**:

```text
# View recent logs
Get-Content "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\"`
  "cloudbase-init.log" -Tail 50

# Look for successful execution
Get-Content "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\"`
  "cloudbase-init.log" | Select-String -Pattern "success|complete|configured" `
  -Context 2
```

### 9.5 Verify Network Configuration

```text
# Check IP configuration
ipconfig

# Should show:
# IPv4 Address: 10.10.0.100 (or your configured IP)
# Subnet Mask: 255.255.255.0
# Default Gateway: 10.10.0.1

# Check hostname
hostname
# Should show: test-windows-vm (or your configured hostname)
```

### 9.6 Verify SSH Access

**From your workstation**:

```bash
# SSH to Windows VM
ssh -i ~/.ssh/test_windows Administrator@10.10.0.100

# Should connect successfully
```

### 9.7 Clean Up Test VM

**After successful testing**:

```bash
# Stop and delete test VM
qm stop <test-vmid>
qm destroy <test-vmid>
```

---

## Troubleshooting

### Issue 1: Cloudbase-Init Not Detecting Config Drive

**Symptom**: Logs show "No metadata service found" or "AttributeError: module
has no attribute 'NoCloudService'"

**Solution**:

1. **Verify metadata service** is correct:

```text
Get-Content "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\"`
  "cloudbase-init.conf" | Select-String "metadata_services"
```

- **Must be**: `ConfigDriveService`
- **NOT**: `NoCloudService` (this is wrong!)

1. **Fix configuration**:

```text
# Backup config
$conf = "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\"`
  "cloudbase-init.conf"
Copy-Item $conf "$conf.backup"

# Fix metadata service
$old = 'cloudbaseinit\.metadata\.services\.nocloudservice\.NoCloudService'
$new = 'cloudbaseinit.metadata.services.configdrive.ConfigDriveService'
(Get-Content $conf) -replace $old, $new | Set-Content $conf
```

1. **Verify Proxmox VM has cloud-init disk**:

```bash
# On Proxmox host
qm config <vmid> | grep ide2
# Should show: ide2: local-lvm:cloudinit,size=4M
```

### Issue 2: Network Not Configured

**Symptom**: VM boots but network adapter still uses DHCP

**Solution**:

1. **Check Cloudbase-Init logs**:

```text
$log = "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\"`
  "cloudbase-init.log"
Get-Content $log | Select-String -Pattern "network|NetworkConfig" -Context 5
```

1. **Verify NetworkConfigPlugin is enabled**:

```text
$conf = "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\"`
  "cloudbase-init.conf"
Get-Content $conf | Select-String "NetworkConfigPlugin"
```

1. **Manually trigger Cloudbase-Init** (if it didn't run):

```text
# Reset cloudbase-init
Remove-Item "C:\ProgramData\Cloudbase Solutions\Cloudbase-Init\*" `
  -Recurse -Force -ErrorAction SilentlyContinue

# Run manually
$exe = "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\Python\"`
  "Scripts\cloudbase-init.exe"
$conf = "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\"`
  "cloudbase-init.conf"
& $exe --config-file $conf --debug
```

1. **Manually configure network** (temporary fix):

```text
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 10.10.0.10 `
  -PrefixLength 24 -DefaultGateway 10.10.0.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" `
  -ServerAddresses 1.1.1.1
```

### Issue 3: Hostname Not Set

**Symptom**: Hostname remains as default (e.g., `WIN-XXXXX`)

**Solution**:

1. **Verify SetHostNamePlugin is enabled**:

```text
$conf = "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\"`
  "cloudbase-init.conf"
Get-Content $conf | Select-String "SetHostNamePlugin"
```

1. **Verify VM name is set in Proxmox**:

```bash
# On Proxmox host
qm config <vmid> | grep name
# Should show: name: <your-hostname>
```

1. **Manually set hostname** (temporary fix):

```text
Rename-Computer -NewName "dc01" -Restart
```

### Issue 4: SSH Keys Not Injected

**Symptom**: Cannot SSH to Windows VM

**Solution**:

1. **Verify OpenSSH Server is running**:

```text
Get-Service sshd
Start-Service sshd
```

1. **Check authorized_keys file**:

```text
Get-Content "$env:ProgramData\ssh\administrators_authorized_keys"
```

1. **Verify SetUserSSHPublicKeysPlugin is enabled**:

```text
$conf = "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\"`
  "cloudbase-init.conf"
Get-Content $conf | Select-String "SetUserSSHPublicKeysPlugin"
```

1. **Check firewall rule**:

```text
Get-NetFirewallRule -Name sshd
```

### Issue 5: Cloudbase-Init Already Ran (One-Time Execution)

**Symptom**: Cloudbase-Init won't run again after first boot

**Solution**: This is normal behavior. Cloudbase-Init runs once per VM. To
reset:

```text
# Delete marker files
Remove-Item "C:\ProgramData\Cloudbase Solutions\Cloudbase-Init\*" `
  -Recurse -Force -ErrorAction SilentlyContinue

# Run manually
& "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\Python\"`
  "Scripts\cloudbase-init.exe" --config-file "C:\Program Files\"`
  "Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init.conf" --debug
```

### Issue 6: VM Won't Start After Cloning

**Symptom**: VM fails to start with UEFI/TPM errors

**Solution**:

1. **Verify template has EFI disk**:

```bash
qm config <template-vmid> | grep efidisk0
```

1. **Verify template has TPM** (if enabled):

```bash
qm config <template-vmid> | grep tpmstate0
```

1. **Check Proxmox logs**:

```bash
journalctl -u pve-cluster -f
```

### Issue 7: VirtIO Drivers Not Working

**Symptom**: Network or disk not recognized

**Solution**:

1. **Reinstall VirtIO drivers** from ISO
2. **Check Device Manager** for devices with warnings
3. **Update drivers manually** pointing to VirtIO ISO

### Issue 8: Identical SID Error During Domain Join

**Symptom**: Error message: "The domain join cannot be completed because the
SID of the domain you attempted to join was identical to the SID of this
machine."

**Root Cause**: Template was not sysprepped before converting to template,
causing all cloned VMs to share the same SID.

**Solution**:

#### Option 1: Fix existing VM (Quick Fix)

```text
# On the VM that cannot join domain, run sysprep
cd C:\Windows\System32\Sysprep
.\sysprep.exe /generalize /oobe /shutdown

# After reboot, the VM will have a new SID and can join the domain
```

#### Option 2: Recreate template (Recommended)

1. **Delete the incorrectly prepared template**
2. **Follow this guide from scratch**, ensuring Step 8.4 (Run Sysprep) is
   completed
3. **Recreate VMs** from the properly sysprepped template

**Prevention**: Always run sysprep (`/generalize /oobe /shutdown`) before
converting a Windows VM to a template.

### Issue 9: YAML Parsing Error with Password

**Symptom**: Cloudbase-Init fails with `yaml.constructor.ConstructorError:
could not determine a constructor for the tag '!...'`

**Root Cause**: Password starts with `!`, which YAML interprets as a tag.

**Solution**:

- **Do NOT set password via Cloudbase-Init** (use template default)
- If you must set a password, ensure it does NOT start with `!` or other
  YAML special characters
- Use the template's default Administrator password instead

---

## Configuration Reference

### Cloudbase-Init Configuration Explained

#### Metadata Services

- **`ConfigDriveService`**: ✅ Correct service for Proxmox (reads from
  ISO9660 config drive)
- **`NoCloudService`**: ❌ **DO NOT USE** - This is incorrect and will cause
  errors

#### Plugins

- **`MTUPlugin`**: Configures MTU from DHCP
- **`SetHostNamePlugin`**: **REQUIRED** - Sets Windows hostname from VM name
- **`NetworkConfigPlugin`**: **REQUIRED** - Configures network interfaces
- **`SetUserSSHPublicKeysPlugin`**: **REQUIRED** - Injects SSH public keys
- **`UserDataPlugin`**: Executes user data scripts
- **`LocalScriptsPlugin`**: Runs local scripts from LocalScripts directory

#### Config Drive Detection

- **`config_drive_cdrom=true`**: Check CD-ROM (Proxmox default)
- **`config_drive_vfat=true`**: Check VFAT filesystem
- **`config_drive_cdrom_strict_mode=false`**: Don't require strict CD-ROM
  format

### Proxmox Cloud-Init Parameters

When deploying VMs via Terraform, these parameters are automatically set:

- **`ipconfig0`**: Network configuration (IP, gateway)
- **`nameserver`**: DNS servers
- **`ciuser`**: Cloud-init user (defaults to Administrator)
- **`sshkeys`**: SSH public keys (injected automatically)
- **`cipassword`**: **NOT USED** - Password is not set via Cloudbase-Init

---

## Best Practices

1. **Always use ConfigDriveService** for Proxmox (not NoCloudService)
2. **Always run sysprep** before converting to template (`/generalize /oobe
/shutdown`)
3. **Test template** before using in production
4. **Keep Cloudbase-Init updated** to latest stable version
5. **Document your template** with notes in Proxmox
6. **Use descriptive VM names** for templates
7. **Backup template** before major changes
8. **Verify all services** are set to Automatic startup
9. **Clean up installation files** before creating template
10. **Remove ISOs** from template before conversion (keep serial port)
11. **Enable ballooning** on template for memory flexibility
12. **Use template default password** instead of setting via Cloudbase-Init

---

## References

- **Cloudbase-Init Documentation**:
  <https://cloudbase-init.readthedocs.io/>
- **Proxmox Cloud-Init Support**:
  <https://pve.proxmox.com/wiki/Cloud-Init_Support>
- **VirtIO Drivers**:
  <!-- markdownlint-disable MD013 -->
  <https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/>
  <!-- markdownlint-enable MD013 -->
- **Cloudbase-Init Download**:
  <https://cloudbase.it/cloudbase-init/>
- **Windows Sysprep Documentation**:
  <!-- markdownlint-disable MD013 -->
  <https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep--system-preparation--overview>
  <!-- markdownlint-enable MD013 -->

---

## Quick Reference Commands

### On Windows VM (Template)

```text
# Check Cloudbase-Init service
Get-Service cloudbase-init

# View Cloudbase-Init logs
Get-Content "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\"`
  "cloudbase-init.log" -Tail 50

# Verify configuration
Get-Content "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\"`
  "cloudbase-init.conf" | Select-String "metadata_services"

# Check SSH service
Get-Service sshd

# Check QEMU Guest Agent
Get-Service QEMU-GA

# Run sysprep (before converting to template)
cd C:\Windows\System32\Sysprep
.\sysprep.exe /generalize /oobe /shutdown
```

### On Proxmox Host

```bash
# Convert VM to template
qm template <vmid>

# Clone template
qm clone <template-vmid> <new-vmid> --name <name>

# Configure cloud-init (manual - Terraform does this automatically)
qm set <vmid> --ipconfig0 ip=10.10.0.10/24,gw=10.10.0.1
qm set <vmid> --nameserver 8.8.8.8
qm set <vmid> --ciuser Administrator
# Note: Password is NOT set via cloud-init (use template default)

# Check VM config
qm config <vmid>

# Verify template status
qm config <vmid> | grep template
```

### Terraform Configuration

In `windows-vms.auto.tfvars`:

```text
windows_vm_instances = [
  {
    hostname   = "dc01"
    vmid       = 100
    ip         = "10.10.0.10/24"
    gw         = "10.10.0.1"
    tag        = 10
    cores      = 4
    memory     = 8192
    disk_size  = "60G"
    nameserver = "1.1.1.1 1.0.0.1"
    # Note: Password is NOT set via cloud-init (use template default)
  }
]
```

---

**Last Updated**: 2024-11-25
**Template Version**: Windows Server 2022 Standard with Cloudbase-Init
**Proxmox Version**: 7.0+
**Cloudbase-Init Version**: Latest Stable
