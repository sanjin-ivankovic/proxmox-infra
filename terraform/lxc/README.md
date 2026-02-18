# LXC Containers - Terraform Project

This project manages LXC container deployments on Proxmox VE.

## Overview

This Terraform project provisions and manages LXC containers on Proxmox VE.
It generates unique SSH keys for each container, configures networking, and
generates Ansible inventory for automated provisioning.

## Project Structure

```text
lxc/
├── main.tf                 # Main orchestration
├── variables.tf            # Variable definitions
├── outputs.tf             # Output definitions
├── providers.tf            # Provider configuration
├── versions.tf             # Version constraints
├── Makefile                # Comprehensive Makefile
├── terraform.tfvars.secret # Sensitive variables (DO NOT COMMIT)
├── .gitignore             # Git ignore rules
├── instances/
│   └── lxc.auto.tfvars     # Container definitions
├── modules/
│   ├── compute-base/        # SSH key generation
│   ├── lxc-instance/        # LXC container module
│   └── ansible-inventory/   # Inventory generator
└── generated/
    └── state/               # Terraform state files
```

## Prerequisites

- Terraform >= 1.5.0
- Proxmox VE cluster access
- Proxmox API token with appropriate permissions
- LXC OS template uploaded to Proxmox

## Quick Start

1. **Setup**:

   ```bash
   cd terraform/lxc
   make setup
   ```

2. **Configure**:
   - Edit `terraform.tfvars.secret` with your Proxmox credentials
   - Edit `instances/lxc.auto.tfvars` with your container definitions

3. **Deploy**:

   ```bash
   make plan    # Preview changes
   make apply   # Deploy containers
   ```

## Configuration

### Required Variables

- `proxmox_api_url` - Proxmox API URL
- `proxmox_api_token_id` - API token ID
- `proxmox_api_token_secret` - API token secret
- `lxc_instances` - List of container configurations

### Instance Definition

See `instances/lxc.auto.tfvars` for example container definitions.

## Usage

### Common Commands

```bash
make help          # Show all available commands
make plan          # Preview changes
make apply         # Apply changes
make destroy       # Destroy all containers
make inventory     # Generate Ansible inventory
make status        # Show deployment summary
```

### Importing Existing Containers

```bash
make import-guide              # Show import guide
make import-lxc HOSTNAME=name VMID=100  # Import container
```

## Modules

- **compute-base**: Generates SSH keys for containers
- **lxc-instance**: Provisions LXC containers
- **ansible-inventory**: Generates Ansible inventory

## Outputs

- `container_details` - Details of all containers
- `container_ips` - Map of hostnames to IP addresses
- `ssh_commands` - SSH connection commands
- `ansible_inventory_path` - Path to generated inventory

## Ansible Integration

The project generates Ansible inventory at:

- `../../ansible/inventory/lxc-hosts.yml` (YAML format)
- `../../ansible/inventory/lxc-hosts.ini` (INI format)

## Troubleshooting

See the Makefile help (`make help`) for all available commands and
troubleshooting options.
