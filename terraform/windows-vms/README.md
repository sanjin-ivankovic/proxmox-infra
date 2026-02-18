# Windows VMs - Terraform Project

This project manages Windows VM deployments on Proxmox VE using cloudbase-init.

## Overview

This Terraform project provisions and manages Windows VMs (Windows Server) on
Proxmox VE. It uses cloudbase-init for automated configuration, generates
unique SSH keys, and creates Ansible inventory for further automation.

## Project Structure

```text
windows-vms/
├── main.tf                 # Main orchestration
├── variables.tf            # Variable definitions
├── outputs.tf             # Output definitions
├── providers.tf            # Provider configuration
├── versions.tf             # Version constraints
├── Makefile                # Comprehensive Makefile
├── terraform.tfvars.secret # Sensitive variables (DO NOT COMMIT)
├── .gitignore             # Git ignore rules
├── instances/
│   └── windows-vms.auto.tfvars # VM definitions
├── modules/
│   ├── compute-base/        # SSH key generation
│   ├── vm-windows/          # Windows VM module (with cloudbase-init)
│   └── ansible-inventory/   # Inventory generator
└── generated/
    └── state/               # Terraform state files
```

## Prerequisites

- Terraform >= 1.5.0
- Proxmox VE cluster access
- Proxmox API token with appropriate permissions
- Windows VM template with cloudbase-init (e.g., `windows-server-2022-std`)

## Quick Start

1. **Setup**:

   ```text
   cd terraform/windows-vms
   make setup
   ```

2. **Configure**:
   - Edit `terraform.tfvars.secret` with your Proxmox credentials
   - Edit `instances/windows-vms.auto.tfvars` with your VM definitions

3. **Deploy**:

   ```text
   make plan    # Preview changes
   make apply   # Deploy VMs
   ```

## Configuration

### Required Variables

- `proxmox_api_url` - Proxmox API URL
- `proxmox_api_token_id` - API token ID
- `proxmox_api_token_secret` - API token secret
- `windows_vm_template` - Template name (e.g., `windows-server-2022-std`)
- `windows_vm_instances` - List of VM configurations

### Instance Definition

See `instances/windows-vms.auto.tfvars` for example VM definitions.

## Usage

### Common Commands

```bash
make help          # Show all available commands
make plan          # Preview changes
make apply         # Apply changes
make destroy       # Destroy all VMs
make inventory     # Generate Ansible inventory
make status        # Show deployment summary
```

### Importing Existing VMs

```bash
make import-guide                      # Show import guide
make import-vm-windows HOSTNAME=name VMID=300  # Import VM
```

## Modules

- **compute-base**: Generates SSH keys for VMs
- **vm-windows**: Provisions Windows VMs with cloudbase-init
- **ansible-inventory**: Generates Ansible inventory

## Cloudbase-Init

The project uses cloudbase-init for automated VM configuration:

- Network configuration
- Hostname setting
- SSH key injection
- User data scripts

**Note**: Password is NOT set via cloudbase-init. Use the template's default
password or set it manually.

## Outputs

- `vm_details` - Details of all VMs
- `vm_ips` - Map of hostnames to IP addresses
- `ssh_commands` - SSH connection commands
- `ansible_inventory_path` - Path to generated inventory

## Ansible Integration

The project generates Ansible inventory at:

- `../../ansible/inventory/windows-vms-hosts.yml` (YAML format)
- `../../ansible/inventory/windows-vms-hosts.ini` (INI format)

Windows VMs use WinRM for Ansible connectivity (configured in inventory).

## Troubleshooting

See the Makefile help (`make help`) for all available commands and
troubleshooting options.
