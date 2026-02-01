# Terraform Projects - Proxmox Infrastructure

This directory contains three completely independent Terraform projects for
managing Proxmox infrastructure:

- **`lxc/`** - LXC containers deployment
- **`linux-vms/`** - Linux VMs deployment (Debian/Ubuntu with
  cloud-init)
- **`windows-vms/`** - Windows VMs deployment (Windows Server with
  cloudbase-init)

## Project Structure

Each project is completely independent with:

- Isolated Terraform configuration (main.tf, variables.tf, outputs.tf,
  providers.tf, versions.tf)
- Comprehensive Makefile (project-specific, all standard operations)
- Project-specific terraform.tfvars.secret (only relevant variables)
- Isolated state files (generated/state/terraform.tfstate)
- Self-contained modules (compute-base, ansible-inventory,
  project-specific module)
- Instance definitions (instances/\*.auto.tfvars)
- Project-specific Ansible inventory generation

## Quick Start

### LXC Containers

```bash
cd terraform/lxc
make setup      # Create secrets file and initialize
make plan       # Preview changes
make apply      # Deploy containers
```

### Linux VMs

```bash
cd terraform/linux-vms
make setup      # Create secrets file and initialize
make plan       # Preview changes
make apply      # Deploy VMs
```

### Windows VMs

```bash
cd terraform/windows-vms
make setup      # Create secrets file and initialize
make plan       # Preview changes
make apply      # Deploy VMs
```

## Project Organization

### Why Three Separate Projects?

1. **Isolation**: Each project manages its own state, reducing risk of
   accidental changes
2. **Independence**: Projects can be deployed, updated, or destroyed
   independently
3. **Clarity**: Clear separation of concerns makes the codebase easier to
   understand
4. **Scalability**: Teams can work on different projects without conflicts
5. **CI/CD**: Projects can be integrated into separate pipelines

### Shared Resources

- **Templates**: Shared Ansible inventory templates in `terraform/templates/`
- **SSH Keys**: All projects use the same SSH key directory (`~/.ssh/` by
  default)
- **Ansible Inventory**: Each project generates its own inventory file:
  - `ansible/inventory/lxc-hosts.yml`
  - `ansible/inventory/linux-vms-hosts.yml`
  - `ansible/inventory/windows-vms-hosts.yml`

## Migration from terraform.old/

The original monolithic Terraform project has been split into three independent
projects. To migrate:

1. **State Migration**: If you have existing state in
   `terraform.old/generated/state/`, you'll need to:
   - Import resources into the appropriate project, OR
   - Manually split the state file (advanced)

2. **SSH Keys**: Existing SSH keys in `~/.ssh/` will continue to work

3. **Ansible Inventory**: Update Ansible to read from three separate inventory
   files or create a merger script

4. **CI/CD**: Update automation to work with three separate projects (can run
   in parallel)

## Documentation

Each project has its own README.md with detailed documentation:

- [LXC Containers README](lxc/README.md)
- [Linux VMs README](linux-vms/README.md)
- [Windows VMs README](windows-vms/README.md)

## Common Operations

All projects support the same Makefile operations:

```bash
make help          # Show all available commands
make setup         # Complete initial setup
make plan          # Preview changes
make apply         # Apply changes
make destroy       # Destroy infrastructure
make inventory     # Generate Ansible inventory
make status        # Show deployment summary
```

See each project's README.md for project-specific details.
