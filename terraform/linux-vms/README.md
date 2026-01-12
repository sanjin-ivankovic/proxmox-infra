# Linux VMs - Terraform Project

This project manages Linux VM deployments on Proxmox VE using cloud-init.

## Overview

This Terraform project provisions and manages Linux VMs (Debian/Ubuntu) on
Proxmox VE. It uses cloud-init for automated configuration, generates unique
SSH keys, and creates Ansible inventory for further automation.

## Project Structure

```text
linux-vms/
├── main.tf                 # Main orchestration
├── variables.tf            # Variable definitions
├── outputs.tf             # Output definitions
├── providers.tf            # Provider configuration
├── versions.tf             # Version constraints
├── Makefile                # Comprehensive Makefile
├── terraform.tfvars.secret # Sensitive variables (DO NOT COMMIT)
├── .gitignore             # Git ignore rules
├── instances/
│   └── linux-vms.auto.tfvars # VM definitions
├── modules/
│   ├── compute-base/        # SSH key generation
│   ├── vm-linux/            # Linux VM module (with cloud-init)
│   └── ansible-inventory/   # Inventory generator
└── generated/
    └── state/               # Terraform state files
```

## Prerequisites

- Terraform >= 1.5.0
- Proxmox VE cluster access
- Proxmox API token with appropriate permissions
- Linux VM template with cloud-init (e.g., `debian-12-cloudinit`,
  `ubuntu-2204-cloudinit`)

## Quick Start

1. **Setup**:

   ```bash
   cd terraform/linux-vms
   make setup
   ```

2. **Configure**:
   - Edit `terraform.tfvars.secret` with your Proxmox credentials
   - Edit `instances/linux-vms.auto.tfvars` with your VM definitions

3. **Deploy**:

   ```bash
   make plan    # Preview changes
   make apply   # Deploy VMs
   ```

## Configuration

### Required Variables

- `proxmox_api_url` - Proxmox API URL
- `proxmox_api_token_id` - API token ID
- `proxmox_api_token_secret` - API token secret
- `linux_vm_template` - Template name (e.g., `debian-12-cloudinit`)
- `linux_vm_instances` - List of VM configurations

### Instance Definition

See `instances/linux-vms.auto.tfvars` for example VM definitions.

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
make import-guide                    # Show import guide
make import-vm-linux HOSTNAME=name VMID=200  # Import VM
```

## Modules

- **compute-base**: Generates SSH keys for VMs
- **vm-linux**: Provisions Linux VMs with cloud-init
- **ansible-inventory**: Generates Ansible inventory

## Cloud-Init

The project uses cloud-init for automated VM configuration:

- Network configuration
- SSH key injection
- User data scripts (via `cicustom` parameter)
- QEMU guest agent installation (optional)

## Outputs

- `vm_details` - Details of all VMs
- `vm_ips` - Map of hostnames to IP addresses
- `ssh_commands` - SSH connection commands
- `ansible_inventory_path` - Path to generated inventory

## Ansible Integration

The project generates Ansible inventory at:

- `../../ansible/inventory/linux-vms-hosts.yml` (YAML format)
- `../../ansible/inventory/linux-vms-hosts.ini` (INI format)

## Troubleshooting

See the Makefile help (`make help`) for all available commands and
troubleshooting options.
