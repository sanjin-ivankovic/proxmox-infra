#!/usr/bin/env python3
"""
Proxmox to Terraform Import Helper (bpg/proxmox provider)

Fetches configuration from Proxmox API and generates:
1. Terraform tfvars block (appended to the appropriate .auto.tfvars file)
2. Terraform import command for the bpg/proxmox provider

Supported resource types:
  - lxc:        LXC containers  → proxmox_virtual_environment_container
  - vm:         Linux VMs       → proxmox_virtual_environment_vm
  - windows-vm: Windows VMs     → proxmox_virtual_environment_vm
  - talos-vm:   Talos K8s VMs   → proxmox_virtual_environment_vm

Usage:
  python3 import_proxmox.py \\
    --vmid 200 \\
    --type vm \\
    --node pve \\
    --api-url https://proxmox.example.com:8006/api2/json \\
    --api-token-id user@pam!token \\
    --api-token-secret UUID
"""

import argparse
import json
import os
import ssl
import sys
import urllib.request

# Relative paths from this script to each Terraform project
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

RESOURCE_CONFIG = {
    "lxc": {
        "tf_dir": os.path.join(SCRIPT_DIR, "..", "lxc"),
        "tfvars_file": "instances/lxc.auto.tfvars",
        "proxmox_api_type": "lxc",
        "bpg_resource": "proxmox_virtual_environment_container.container",
        "module_path": "module.lxc[0]",
        "var_files": ["-var-file=terraform.tfvars.secret"],
    },
    "vm": {
        "tf_dir": os.path.join(SCRIPT_DIR, "..", "linux-vms"),
        "tfvars_file": "instances/linux-vms.auto.tfvars",
        "proxmox_api_type": "qemu",
        "bpg_resource": "proxmox_virtual_environment_vm.vm",
        "module_path": "module.linux_vms[0]",
        "var_files": [
            "-var-file=terraform.tfvars.secret",
            "-var-file=instances/linux-vms.auto.tfvars",
        ],
    },
    "windows-vm": {
        "tf_dir": os.path.join(SCRIPT_DIR, "..", "windows-vms"),
        "tfvars_file": "instances/windows-vms.auto.tfvars",
        "proxmox_api_type": "qemu",
        "bpg_resource": "proxmox_virtual_environment_vm.vm",
        "module_path": "module.windows_vms[0]",
        "var_files": [
            "-var-file=terraform.tfvars.secret",
            "-var-file=instances/windows-vms.auto.tfvars",
        ],
    },
    "talos-vm": {
        "tf_dir": os.path.join(SCRIPT_DIR, "..", "talos-vms"),
        "tfvars_file": "instances/talos.auto.tfvars",
        "proxmox_api_type": "qemu",
        "bpg_resource": "proxmox_virtual_environment_vm.vm",
        "module_path": "module.talos_vms[0]",
        "var_files": [
            "-var-file=terraform.tfvars.secret",
            "-var-file=instances/talos.auto.tfvars",
        ],
    },
}


# ---------------------------------------------------------------------------
# Proxmox API
# ---------------------------------------------------------------------------

def fetch_config(api_url, token_id, token_secret, node, vmid, api_type):
    """Fetch resource configuration from Proxmox API.

    Args:
        api_url: Full API URL (e.g. https://host:8006/api2/json)
        token_id: API token ID (user@realm!tokenname)
        token_secret: API token secret (UUID)
        node: Proxmox node name
        vmid: VM/container ID
        api_type: 'lxc' or 'qemu'

    Returns:
        dict: Resource configuration from Proxmox API
    """
    base_url = api_url.rstrip("/")
    url = f"{base_url}/nodes/{node}/{api_type}/{vmid}/config"

    headers = {
        "Authorization": f"PVEAPIToken={token_id}={token_secret}",
        "Content-Type": "application/json",
    }

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, context=ctx) as resp:
            data = json.loads(resp.read().decode())
            return data.get("data", {})
    except urllib.error.HTTPError as e:
        sys.stderr.write(f"HTTP Error: {e.code} {e.reason}\n")
        sys.exit(1)
    except urllib.error.URLError as e:
        sys.stderr.write(f"URL Error: {e.reason}\n")
        sys.exit(1)
    except json.JSONDecodeError:
        sys.stderr.write("Error decoding JSON from API response\n")
        sys.exit(1)


# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------

def parse_disk_size_gb(size_str):
    """Convert Proxmox disk size string to integer GB.

    Examples:
        '100G' → 100, '512M' → 1, '1T' → 1024, '50' → 50
    """
    if not size_str:
        return 0
    s = size_str.upper().strip()
    try:
        if s.endswith("T"):
            return int(float(s[:-1]) * 1024)
        if s.endswith("G"):
            return int(float(s[:-1]))
        if s.endswith("M"):
            return max(1, int(float(s[:-1]) / 1024))
        if s.endswith("K"):
            return 1
        return int(float(s))
    except (ValueError, TypeError):
        return 0


def parse_net_field(net_str, field):
    """Extract a named field from a Proxmox net0/net1 string.

    Example net_str: 'name=eth0,bridge=vmbr0,gw=10.10.0.1,hwaddr=BC:...,ip=10.10.0.14/24,tag=10'
    """
    if not net_str or f"{field}=" not in net_str:
        return None
    return net_str.split(f"{field}=")[1].split(",")[0]


def parse_tags(config):
    """Parse Proxmox tags string into a Python list."""
    raw = config.get("tags", "")
    if not raw:
        return []
    sep = ";" if ";" in raw else ","
    return [t.strip() for t in raw.split(sep) if t.strip()]


def find_largest_disk(config):
    """Find the largest disk attached to a QEMU VM and return its size in GB."""
    max_gb = 0
    for key, value in config.items():
        if not any(key.startswith(p) for p in ("scsi", "virtio", "sata", "ide")):
            continue
        if "size=" not in value:
            continue
        size_str = value.split("size=")[1].split(",")[0]
        gb = parse_disk_size_gb(size_str)
        if gb > max_gb:
            max_gb = gb
    return max_gb or 32  # fallback


# ---------------------------------------------------------------------------
# HCL generators — each returns a tfvars block string
# ---------------------------------------------------------------------------

def generate_lxc_hcl(config, vmid, hostname):
    """Generate tfvars block for an LXC container."""
    net0 = config.get("net0", "")
    ip = parse_net_field(net0, "ip") or "dhcp"
    gw = parse_net_field(net0, "gw") or ""
    mac = parse_net_field(net0, "hwaddr") or ""
    vlan_tag = parse_net_field(net0, "tag")

    rootfs = config.get("rootfs", "")
    disk_gb = 8
    if "size=" in rootfs:
        disk_gb = parse_disk_size_gb(rootfs.split("size=")[1].split(",")[0])

    tags = parse_tags(config)
    onboot = config.get("onboot", 0) == 1

    lines = [
        "  {",
        f'    hostname         = "{hostname}"',
        f"    vmid             = {vmid}",
        f'    ip               = "{ip}"',
    ]
    if gw:
        lines.append(f'    gw               = "{gw}"')
    if mac:
        lines.append(f'    mac              = "{mac}"')
    lines += [
        f"    cores            = {config.get('cores', 1)}",
        f"    memory           = {config.get('memory', 512)}",
        f"    swap             = {config.get('swap', 512)}",
        f"    disk_size        = {disk_gb}",
        f"    unprivileged     = true",
        f"    start            = {str(onboot).lower()}",
        f"    onboot           = {str(onboot).lower()}",
    ]
    if vlan_tag:
        lines.append(f"    tag              = {vlan_tag}")
    lines.append(f"    tags             = {json.dumps(tags)}")
    lines.append("    preserve_ssh_key = true  # Imported host")
    lines.append("    features = {")
    lines.append("      nesting = true")
    lines.append("    }")
    lines.append("  },")
    return "\n".join(lines)


def generate_linux_vm_hcl(config, vmid, hostname):
    """Generate tfvars block for a Linux VM."""
    net0 = config.get("net0", "")
    ipconfig0 = config.get("ipconfig0", "")

    ip = parse_net_field(ipconfig0, "ip") or "dhcp"
    gw = parse_net_field(ipconfig0, "gw") or ""
    mac = _parse_qemu_mac(net0)
    vlan_tag = parse_net_field(net0, "tag")
    disk_gb = find_largest_disk(config)
    tags = parse_tags(config)
    onboot = config.get("onboot", 0) == 1

    lines = [
        "  {",
        f'    hostname          = "{hostname}"',
        f"    vmid              = {vmid}",
        f'    ip                = "{ip}"',
        f'    gw                = "{gw}"',
    ]
    if mac:
        lines.append(f'    mac               = "{mac}"')
    lines += [
        f"    cores             = {config.get('cores', 2)}",
        f"    memory            = {config.get('memory', 2048)}",
        f"    disk_size         = {disk_gb}",
        f"    onboot            = {str(onboot).lower()}",
        f"    start             = {str(onboot).lower()}",
        f"    tags              = {json.dumps(tags)}",
    ]
    if vlan_tag:
        lines.append(f"    tag               = {vlan_tag}")
    lines.append("    preserve_ssh_key  = true  # Imported host")
    lines.append("  },")
    return "\n".join(lines)


def generate_windows_vm_hcl(config, vmid, hostname):
    """Generate tfvars block for a Windows VM."""
    net0 = config.get("net0", "")
    ipconfig0 = config.get("ipconfig0", "")

    ip = parse_net_field(ipconfig0, "ip") or "dhcp"
    gw = parse_net_field(ipconfig0, "gw") or ""
    mac = _parse_qemu_mac(net0)
    vlan_tag = parse_net_field(net0, "tag")
    disk_gb = find_largest_disk(config)
    tags = parse_tags(config)
    onboot = config.get("onboot", 0) == 1

    lines = [
        "  {",
        f'    hostname          = "{hostname}"',
        f"    vmid              = {vmid}",
        f'    ip                = "{ip}"',
        f'    gw                = "{gw}"',
    ]
    if mac:
        lines.append(f'    mac               = "{mac}"')
    lines += [
        f"    cores             = {config.get('cores', 4)}",
        f"    memory            = {config.get('memory', 8192)}",
        f"    disk_size         = {disk_gb}",
        f"    onboot            = {str(onboot).lower()}",
        f"    start             = {str(onboot).lower()}",
        f"    tags              = {json.dumps(tags)}",
    ]
    if vlan_tag:
        lines.append(f"    tag               = {vlan_tag}")
    lines.append("    preserve_ssh_key  = true  # Imported host")
    lines.append("  },")
    return "\n".join(lines)


def generate_talos_vm_hcl(config, vmid, hostname):
    """Generate tfvars block for a Talos VM."""
    net0 = config.get("net0", "")
    ipconfig0 = config.get("ipconfig0", "")

    # Talos VMs may not have ipconfig0 (no cloud-init), fall back to manual entry
    ip = parse_net_field(ipconfig0, "ip") or "FIXME/24"
    gw = parse_net_field(ipconfig0, "gw") or "FIXME"
    mac = _parse_qemu_mac(net0)
    vlan_tag = parse_net_field(net0, "tag")
    disk_gb = find_largest_disk(config)
    tags = parse_tags(config)
    onboot = config.get("onboot", 0) == 1

    lines = [
        "  {",
        f'    hostname     = "{hostname}"',
        f"    vmid         = {vmid}",
        f'    ip           = "{ip}"',
        f'    gw           = "{gw}"',
    ]
    if mac:
        lines.append(f'    mac          = "{mac}"')
    lines += [
        f"    cores        = {config.get('cores', 2)}",
        f"    memory       = {config.get('memory', 6144)}",
        f"    disk_size    = {disk_gb}",
        f"    onboot       = {str(onboot).lower()}",
        f"    start        = {str(onboot).lower()}",
        f"    tags         = {json.dumps(tags)}",
    ]
    if vlan_tag:
        lines.append(f"    tag          = {vlan_tag}")
    lines.append('    talos_role   = "worker"  # VERIFY: set to "controlplane" if applicable')
    lines.append('    bios         = "ovmf"')
    lines.append(f'    description  = "{hostname}"')
    lines.append("  },")
    return "\n".join(lines)


def _parse_qemu_mac(net0):
    """Extract MAC address from a QEMU net0 config string.

    net0 format: 'virtio=BC:24:11:AA:BB:CC,bridge=vmbr0,...'
    """
    if not net0 or "=" not in net0:
        return None
    mac_part = net0.split("=")[1].split(",")[0]
    if ":" in mac_part:
        return mac_part.upper()
    return None


# ---------------------------------------------------------------------------
# File manipulation
# ---------------------------------------------------------------------------

def append_to_tfvars(filepath, content):
    """Append a new instance block before the closing ']' of the list variable."""
    try:
        with open(filepath, "r") as f:
            lines = f.readlines()
    except FileNotFoundError:
        sys.stderr.write(f"File not found: {filepath}\n")
        return False

    # Find last ']'
    bracket_idx = -1
    for i in range(len(lines) - 1, -1, -1):
        if "]" in lines[i]:
            bracket_idx = i
            break

    if bracket_idx == -1:
        sys.stderr.write(f"Could not find closing ']' in {filepath}\n")
        return False

    # Expand single-line empty list: 'var = []' → 'var = [\n]\n'
    if "[]" in lines[bracket_idx]:
        parts = lines[bracket_idx].split("[]")
        lines[bracket_idx] = parts[0] + "[\n"
        lines.insert(bracket_idx + 1, "]\n")
        bracket_idx += 1

    # Ensure trailing comma on previous item
    if bracket_idx > 0:
        prev = lines[bracket_idx - 1].strip()
        if prev and not prev.endswith(",") and not prev.endswith("["):
            lines[bracket_idx - 1] = lines[bracket_idx - 1].rstrip() + ",\n"

    lines.insert(bracket_idx, content + "\n")

    with open(filepath, "w") as f:
        f.writelines(lines)

    return True


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Import existing Proxmox resources into Terraform (bpg/proxmox provider)"
    )
    parser.add_argument("--vmid", required=True, type=int, help="VMID to import")
    parser.add_argument(
        "--type",
        choices=["lxc", "vm", "windows-vm", "talos-vm"],
        default="vm",
        help="Resource type (default: vm)",
    )
    parser.add_argument("--node", default="pve", help="Proxmox node name (default: pve)")
    parser.add_argument("--api-url", required=True, help="Proxmox API URL")
    parser.add_argument("--api-token-id", required=True, help="API token ID (user@realm!token)")
    parser.add_argument("--api-token-secret", required=True, help="API token secret")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print generated HCL and import command without modifying files",
    )

    args = parser.parse_args()
    rc = RESOURCE_CONFIG[args.type]

    print(f"Fetching config for VMID {args.vmid} ({args.type}) from node {args.node}...")

    config = fetch_config(
        args.api_url,
        args.api_token_id,
        args.api_token_secret,
        args.node,
        args.vmid,
        rc["proxmox_api_type"],
    )

    if not config:
        print(f"No configuration found for VMID {args.vmid}")
        sys.exit(1)

    # Determine hostname
    if args.type == "lxc":
        hostname = config.get("hostname", f"ct-{args.vmid}")
    else:
        hostname = config.get("name", f"vm-{args.vmid}")

    print(f"Found: {hostname} (VMID {args.vmid})")

    # Generate HCL
    generators = {
        "lxc": generate_lxc_hcl,
        "vm": generate_linux_vm_hcl,
        "windows-vm": generate_windows_vm_hcl,
        "talos-vm": generate_talos_vm_hcl,
    }
    hcl = generators[args.type](config, args.vmid, hostname)

    # Build import command
    resource_addr = f'{rc["module_path"]}.{rc["bpg_resource"]}["{hostname}"]'
    import_id = f"{args.node}/{args.vmid}"
    var_file_args = " ".join(rc["var_files"])
    import_cmd = f"terraform import {var_file_args} '{resource_addr}' {import_id}"

    # Build target file path
    tfvars_path = os.path.join(rc["tf_dir"], rc["tfvars_file"])

    if args.dry_run:
        print("\n=== GENERATED TFVARS BLOCK ===")
        print(hcl)
        print(f"\n=== IMPORT COMMAND ===")
        print(f"cd {rc['tf_dir']}")
        print(import_cmd)
        print("terraform plan " + var_file_args)
        return

    # Append to tfvars
    print(f"\nAppending to {tfvars_path}...")
    if not append_to_tfvars(tfvars_path, hcl):
        print("Failed to append configuration.")
        sys.exit(1)
    print("Done.")

    # Print import instructions
    print(f"\n{'=' * 60}")
    print("IMPORT INSTRUCTIONS")
    print(f"{'=' * 60}")
    print(f"\n1. Review the new entry in:\n   {tfvars_path}")
    if args.type == "talos-vm":
        print("   - Set talos_role to 'controlplane' or 'worker' as appropriate")
        print("   - Set ip and gw manually (Talos VMs don't use cloud-init)")
    print(f"\n2. Run the import:")
    print(f"   cd {rc['tf_dir']}")
    print(f"   {import_cmd}")
    print(f"\n3. Verify zero drift:")
    print(f"   terraform plan {var_file_args}")
    print(f"\n{'=' * 60}")


if __name__ == "__main__":
    main()
