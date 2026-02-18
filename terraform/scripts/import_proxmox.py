#!/usr/bin/env python3
"""
Proxmox to Terraform Import Helper
Fetches configuration from Proxmox (via API) and generates:
1. Terraform configuration block (appended to imported.auto.tfvars)
2. Terraform import command
"""

import argparse
import json
import sys
import os
import urllib.request
import ssl

# Configuration
# Path to Terraform directories relative to script location
TF_LXC_DIR = "../lxc"
TF_VM_DIR = "../linux-vms"
TF_WINDOWS_VM_DIR = "../windows-vms"

def parse_size_to_bytes(size_str: str) -> int:
    """Convert Proxmox disk size string to bytes for comparison.

    Supports binary (base-1024) units commonly used in storage systems:
    - T/TiB: Tebibytes (1024^4 bytes)
    - G/GiB: Gibibytes (1024^3 bytes)
    - M/MiB: Mebibytes (1024^2 bytes)
    - K/KiB: Kibibytes (1024 bytes)

    Args:
        size_str: Size string from Proxmox (e.g., "100G", "4M", "500G")

    Returns:
        int: Size in bytes

    Examples:
        >>> parse_size_to_bytes("100G")
        107374182400
        >>> parse_size_to_bytes("4M")
        4194304
        >>> parse_size_to_bytes("")
        0
    """
    # Binary multipliers (IEC standard: KiB, MiB, GiB, TiB)
    KIB = 1024
    MIB = 1024 ** 2
    GIB = 1024 ** 3
    TIB = 1024 ** 4

    if not size_str:
        return 0

    size_str = size_str.upper().strip()

    try:
        if size_str.endswith('T'):
            return int(float(size_str[:-1]) * TIB)
        elif size_str.endswith('G'):
            return int(float(size_str[:-1]) * GIB)
        elif size_str.endswith('M'):
            return int(float(size_str[:-1]) * MIB)
        elif size_str.endswith('K'):
            return int(float(size_str[:-1]) * KIB)
        else:
            # Assume bytes if no unit specified
            return int(float(size_str))
    except (ValueError, TypeError) as e:
        print(f"Warning: Invalid size string '{size_str}': {e}. Returning 0.")
        return 0

def get_resource_config_api(api_url, token_id, token_secret, node, vmid, resource_type):
    """Fetch resource configuration from Proxmox API."""
    # resource_type: 'lxc' or 'qemu'

    # Construct URL
    # api_url example: https://10.10.0.4:8006/api2/json
    base_url = api_url.rstrip("/")
    endpoint = f"/nodes/{node}/{resource_type}/{vmid}/config"
    url = f"{base_url}{endpoint}"

    # Construct Auth Header
    # Authorization: PVEAPIToken=USER@REALM!TOKENID=UUID
    auth_header = f"PVEAPIToken={token_id}={token_secret}"

    headers = {
        "Authorization": auth_header,
        "Content-Type": "application/json"
    }

    # Create context to ignore self-signed certs (common in Proxmox)
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, context=ctx) as response:
            data = json.loads(response.read().decode())
            return data.get("data", {})
    except urllib.error.HTTPError as e:
        sys.stderr.write(f"HTTP Error fetching config: {e.code} {e.reason}\n")
        sys.exit(1)
    except urllib.error.URLError as e:
        sys.stderr.write(f"URL Error: {e.reason}\n")
        sys.exit(1)
    except json.JSONDecodeError:
        sys.stderr.write("Error decoding JSON from API response\n")
        sys.exit(1)

def generate_lxc_hcl(config, vmid, hostname):
    """Generate HCL block for LXC container."""
    # Map Proxmox config to Terraform variables
    # This is a best-effort mapping; user should verify.

    # Network: net0: name=eth0,bridge=vmbr0,firewall=1,gw=10.10.0.1,hwaddr=BC:24:11:BB:0B:17,ip=10.10.0.14/24,tag=10,type=veth
    net0 = config.get("net0", "")
    ip = "dhcp"
    gw = ""
    mac = ""
    vlan_tag = None

    if "ip=" in net0:
        ip_part = net0.split("ip=")[1].split(",")[0]
        if ip_part != "dhcp":
            ip = ip_part

    if "gw=" in net0:
        gw = net0.split("gw=")[1].split(",")[0]

    if "hwaddr=" in net0:
        mac = net0.split("hwaddr=")[1].split(",")[0]

    if "tag=" in net0:
        vlan_tag = net0.split("tag=")[1].split(",")[0]

    # Disk: rootfs: local-zfs:subvol-114-disk-0,size=8G
    rootfs = config.get("rootfs", "")
    disk_size = "8G" # Default
    if "size=" in rootfs:
        disk_size = rootfs.split("size=")[1].split(",")[0]

    hcl = "  {\n"
    hcl += f'    hostname         = "{hostname}"\n'
    hcl += f'    vmid             = {vmid}\n'
    hcl += f'    ip               = "{ip}"\n'
    if gw:
        hcl += f'    gw               = "{gw}"\n'
    if mac:
        hcl += f'    mac              = "{mac}"\n'
    hcl += f'    cores            = {config.get("cores", 1)}\n'
    hcl += f'    memory           = {config.get("memory", 512)}\n'
    hcl += f'    swap             = {config.get("swap", 512)}\n'
    hcl += f'    disk_size        = "{disk_size}"\n'
    hcl += '    unprivileged     = true\n'
    hcl += f'    start            = {str(config.get("onboot", 0) == 1).lower()}\n'
    hcl += f'    onboot           = {str(config.get("onboot", 0) == 1).lower()}\n'
    if vlan_tag:
        hcl += f'    tag              = {vlan_tag}\n'
    hcl += '    preserve_ssh_key = true  # Imported host - preserve existing SSH keys\n'

    tags = config.get("tags", "")
    if tags:
        # Proxmox can use either semicolons or commas as tag separators
        separator = ";" if ";" in tags else ","
        tag_list = [t.strip() for t in tags.split(separator) if t.strip()]
        hcl += f'    tags             = {json.dumps(tag_list)}\n'
    else:
        hcl += '    tags             = []\n'

    hcl += "    features = {\n"
    hcl += "      nesting = true\n"
    hcl += "    }\n"
    hcl += "  },"
    return hcl

def generate_vm_hcl(config, vmid, hostname):
    """Generate HCL block for Linux VM (QEMU)."""
    # Map Proxmox config to Terraform variables
    # This is a best-effort mapping; user should verify.

    # Network: net0: virtio=BC:24:11:AA:BB:CC,bridge=vmbr0,firewall=1,tag=10
    # ipconfig0: ip=10.10.0.20/24,gw=10.10.0.1
    net0 = config.get("net0", "")
    ipconfig0 = config.get("ipconfig0", "")

    ip = "dhcp"
    gw = "10.10.0.1"
    mac = None
    vlan_tag = None

    # Parse IP configuration
    if "ip=" in ipconfig0:
        ip_part = ipconfig0.split("ip=")[1].split(",")[0]
        if ip_part != "dhcp":
            ip = ip_part

    if "gw=" in ipconfig0:
        gw = ipconfig0.split("gw=")[1].split(",")[0]

    # Parse MAC address from net0
    if "=" in net0:
        mac_part = net0.split("=")[1].split(",")[0]
        if ":" in mac_part:  # Validate it looks like a MAC
            mac = mac_part.upper()

    # Parse VLAN tag from net0
    if "tag=" in net0:
        vlan_tag = net0.split("tag=")[1].split(",")[0]

    # Disk: scsi0: local-zfs:vm-200-disk-0,discard=on,iothread=1,size=32G,ssd=1
    # Find the largest disk (to avoid reading 4M cloud-init drives)
    disk_size = "32G"  # Default
    max_size_bytes = 0

    for key in config:
        if key.startswith("scsi") or key.startswith("virtio") or key.startswith("sata") or key.startswith("ide"):
            disk_value = config[key]
            if "size=" in disk_value:
                size_str = disk_value.split("size=")[1].split(",")[0]
                size_bytes = parse_size_to_bytes(size_str)
                if size_bytes > max_size_bytes:
                    max_size_bytes = size_bytes
                    disk_size = size_str

    # Build HCL following variables.tf order exactly
    hcl = "  {\n"
    hcl += f'    hostname          = "{hostname}"\n'
    hcl += f'    vmid              = {vmid}\n'
    hcl += f'    ip                = "{ip}"\n'
    hcl += f'    gw                = "{gw}"\n'
    if mac:
        hcl += f'    mac               = "{mac}"\n'
    hcl += f'    cores             = {config.get("cores", 2)}\n'
    hcl += f'    memory            = {config.get("memory", 2048)}\n'
    hcl += f'    disk_size         = "{disk_size}"\n'
    hcl += f'    onboot            = {str(config.get("onboot", 0) == 1).lower()}\n'
    hcl += f'    start             = {str(config.get("onboot", 0) == 1).lower()}\n'

    # Tags (metadata)
    tags = config.get("tags", "")
    if tags:
        # Handle both semicolon and comma separators
        separator = ";" if ";" in tags else ","
        tag_list = [t.strip() for t in tags.split(separator) if t.strip()]
        hcl += f'    tags              = {json.dumps(tag_list)}\n'
    else:
        hcl += '    tags              = []\n'

    # Optional fields that should be included for imported VMs
    if vlan_tag:
        hcl += f'    tag               = {vlan_tag}\n'

    # Note: sockets, cpu_type, bios, machine have defaults and are usually omitted
    # Only include if they differ from defaults
    # nameserver should be specified if known
    # hcl += f'    nameserver        = "10.10.0.10 10.10.0.11"\n'

    hcl += '    preserve_ssh_key  = true  # Imported host - preserve existing SSH keys\n'

    hcl += "  },"
    return hcl

def generate_windows_vm_hcl(config, vmid, hostname):
    """Generate HCL block for Windows VM (QEMU)."""
    # Map Proxmox config to Terraform variables
    # Similar to Linux VM but with Windows-specific defaults

    # Network: net0: virtio=BC:24:11:AA:BB:CC,bridge=vmbr0,firewall=1,tag=10
    # ipconfig0: ip=10.10.0.20/24,gw=10.10.0.1
    net0 = config.get("net0", "")
    ipconfig0 = config.get("ipconfig0", "")

    ip = "dhcp"
    gw = "10.10.0.1"
    mac = None
    vlan_tag = None

    # Parse IP configuration
    if "ip=" in ipconfig0:
        ip_part = ipconfig0.split("ip=")[1].split(",")[0]
        if ip_part != "dhcp":
            ip = ip_part

    if "gw=" in ipconfig0:
        gw = ipconfig0.split("gw=")[1].split(",")[0]

    # Parse MAC address from net0
    if "=" in net0:
        mac_part = net0.split("=")[1].split(",")[0]
        if ":" in mac_part:  # Validate it looks like a MAC
            mac = mac_part.upper()

    # Parse VLAN tag from net0
    if "tag=" in net0:
        vlan_tag = net0.split("tag=")[1].split(",")[0]

    # Disk: scsi0: local-zfs:vm-200-disk-0,discard=on,iothread=1,size=100G,ssd=1
    # Find the largest disk (to avoid reading 4M cloud-init drives)
    disk_size = "100G"  # Default for Windows
    max_size_bytes = 0

    for key in config:
        if key.startswith("scsi") or key.startswith("virtio") or key.startswith("sata") or key.startswith("ide"):
            disk_value = config[key]
            if "size=" in disk_value:
                size_str = disk_value.split("size=")[1].split(",")[0]
                size_bytes = parse_size_to_bytes(size_str)
                if size_bytes > max_size_bytes:
                    max_size_bytes = size_bytes
                    disk_size = size_str

    # Build HCL following variables.tf order exactly
    hcl = "  {\n"
    hcl += f'    hostname          = "{hostname}"\n'
    hcl += f'    vmid              = {vmid}\n'
    hcl += f'    ip                = "{ip}"\n'
    hcl += f'    gw                = "{gw}"\n'
    if mac:
        hcl += f'    mac               = "{mac}"\n'
    hcl += f'    cores             = {config.get("cores", 4)}\n'
    hcl += f'    memory            = {config.get("memory", 8192)}\n'
    hcl += f'    disk_size         = "{disk_size}"\n'
    hcl += f'    onboot            = {str(config.get("onboot", 0) == 1).lower()}\n'
    hcl += f'    start             = {str(config.get("onboot", 0) == 1).lower()}\n'

    # Tags (metadata)
    tags = config.get("tags", "")
    if tags:
        # Handle both semicolon and comma separators
        separator = ";" if ";" in tags else ","
        tag_list = [t.strip() for t in tags.split(separator) if t.strip()]
        hcl += f'    tags              = {json.dumps(tag_list)}\n'
    else:
        hcl += '    tags              = []\n'

    # Optional fields
    if vlan_tag:
        hcl += f'    tag               = {vlan_tag}\n'

    hcl += '    preserve_ssh_key  = true  # Imported host - preserve existing SSH keys\n'

    hcl += "  },"
    return hcl

def append_to_file(filepath, content):
    """Append content to file, handling the closing bracket of the list."""

    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        sys.stderr.write(f"File not found: {filepath}\n")
        return False

    # Find the last closing bracket
    last_bracket_idx = -1
    for i in range(len(lines) - 1, -1, -1):
        if "]" in lines[i]:
            last_bracket_idx = i
            break

    if last_bracket_idx == -1:
        sys.stderr.write(f"Could not find closing bracket ']' in {filepath}\n")
        return False

    # Handle single-line empty list: "variable = []"
    line_content = lines[last_bracket_idx].strip()
    if "[]" in line_content:
        # Split into multiple lines
        # e.g. "imported_instances = []" ->
        # "imported_instances = [\n"
        # "]"
        parts = lines[last_bracket_idx].split("[]")
        prefix = parts[0] + "[\n"
        suffix = "]\n"

        lines[last_bracket_idx] = prefix
        lines.insert(last_bracket_idx + 1, suffix)
        last_bracket_idx += 1 # Now the bracket is on the next line

    # Insert content before the bracket
    # Ensure there is a comma on the previous item if needed
    if last_bracket_idx > 0:
        prev_line = lines[last_bracket_idx - 1].strip()
        # Ignore lines that are just the opening bracket or empty
        if prev_line and not prev_line.endswith(",") and not prev_line.endswith("["):
             lines[last_bracket_idx - 1] = lines[last_bracket_idx - 1].rstrip() + ",\n"

    lines.insert(last_bracket_idx, content + "\n")

    with open(filepath, 'w') as f:
        f.writelines(lines)

    return True

def main():
    parser = argparse.ArgumentParser(description="Import Proxmox Resource to Terraform")
    parser.add_argument("--vmid", required=True, help="VMID to import")
    parser.add_argument("--type", choices=["lxc", "vm", "windows-vm"], default="lxc", help="Resource type")
    parser.add_argument("--node", default="pve", help="Proxmox node name")
    parser.add_argument("--api-url", required=True, help="Proxmox API URL")
    parser.add_argument("--api-token-id", required=True, help="Proxmox API Token ID")
    parser.add_argument("--api-token-secret", required=True, help="Proxmox API Token Secret")

    args = parser.parse_args()

    print(f"Fetching config for VMID {args.vmid} from {args.node} via API...")

    proxmox_type = "lxc" if args.type == "lxc" else "qemu"
    config = get_resource_config_api(args.api_url, args.api_token_id, args.api_token_secret, args.node, args.vmid, proxmox_type)

    if not config:
        print(f"No configuration found for VMID {args.vmid}")
        sys.exit(1)

    hostname = config.get("hostname", f"vm-{args.vmid}")
    if args.type in ["vm", "windows-vm"]:
        hostname = config.get("name", hostname)

    print(f"Found host: {hostname}")

    if args.type == "lxc":
        hcl = generate_lxc_hcl(config, args.vmid, hostname)
        target_def_file = os.path.join(os.path.dirname(__file__), TF_LXC_DIR, "instances/lxc.auto.tfvars")

        print(f"Appending configuration to {target_def_file}...")
        if append_to_file(target_def_file, hcl):
            print("Success.")
        else:
            print("Failed to append configuration.")
            sys.exit(1)

        print("\n=== IMPORT INSTRUCTIONS ===")
        print(f"1. Verify the changes in {target_def_file}")
        print(f"   Note: preserve_ssh_key=true was set to preserve existing SSH keys")
        print(f"2. Run the following command:")
        print(f"   cd {TF_LXC_DIR}")
        print(f"   terraform import -var-file=terraform.tfvars.secret 'module.lxc[0].proxmox_lxc.container[\"{hostname}\"]' {args.node}/lxc/{args.vmid}")
        print("3. Run 'terraform plan' to verify 0 changes.")

    elif args.type == "windows-vm":  # Windows VM import
        hcl = generate_windows_vm_hcl(config, args.vmid, hostname)
        target_def_file = os.path.join(os.path.dirname(__file__), TF_WINDOWS_VM_DIR, "instances/windows-vms.auto.tfvars")

        print(f"Appending configuration to {target_def_file}...")
        if append_to_file(target_def_file, hcl):
            print("Success.")
        else:
            print("Failed to append configuration.")
            sys.exit(1)

        print("\n=== IMPORT INSTRUCTIONS ===")
        print(f"1. Verify the changes in {target_def_file}")
        print(f"   Note: preserve_ssh_key=true was set to preserve existing SSH keys")
        print(f"2. Run the following command:")
        print(f"   cd {TF_WINDOWS_VM_DIR}")
        print(f"   terraform import -var-file=terraform.tfvars.secret 'module.windows_vms[0].proxmox_vm_qemu.vm[\"{hostname}\"]' {args.node}/qemu/{args.vmid}")
        print("3. Run 'terraform plan' to verify 0 changes.")

    else:  # Linux VM import
        hcl = generate_vm_hcl(config, args.vmid, hostname)
        target_def_file = os.path.join(os.path.dirname(__file__), TF_VM_DIR, "instances/linux-vms.auto.tfvars")

        print(f"Appending configuration to {target_def_file}...")
        if append_to_file(target_def_file, hcl):
            print("Success.")
        else:
            print("Failed to append configuration.")
            sys.exit(1)

        print("\n=== IMPORT INSTRUCTIONS ===")
        print(f"1. Verify the changes in {target_def_file}")
        print(f"   Note: preserve_ssh_key=true was set to preserve existing SSH keys")
        print(f"2. Run the following command:")
        print(f"   cd {TF_VM_DIR}")
        print(f"   terraform import -var-file=terraform.tfvars.secret 'module.linux_vms[0].proxmox_vm_qemu.vm[\"{hostname}\"]' {args.node}/qemu/{args.vmid}")
        print("3. Run 'terraform plan' to verify 0 changes.")


if __name__ == "__main__":
    main()
