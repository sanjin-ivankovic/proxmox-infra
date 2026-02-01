# Makefile Reference - Linux VMs

## Overview

This document provides a comprehensive reference for all Makefile commands
available in the Linux VMs Terraform project. The Makefile automates Terraform
operations for managing Proxmox Linux virtual machines, including provisioning,
configuration, state management, and integration with Ansible.

**Project**: Linux Virtual Machines on Proxmox VE
**Ansible Inventory**: `../../ansible/inventory/linux-vms-hosts.yml`
**State Directory**: `generated/state/`

## Quick Start

```bash
# Complete initial setup
make setup

# Deploy infrastructure
make deploy

# View status
make status
```

## Requirements

- Terraform >= 1.5.0
- jq (for JSON processing)
- Optional: tfsec, tflint, terraform-docs, infracost, checkov

---

## Quick Reference Tables

### Setup & Initialization

| Command                 | Description                                        |
| ----------------------- | -------------------------------------------------- |
| `make secrets`          | Create terraform.tfvars.secret from example        |
| `make init`             | Initialize Terraform (download providers, modules) |
| `make init-backend`     | Initialize Terraform with backend configuration    |
| `make init-migrate`     | Initialize and migrate state to new backend        |
| `make init-reconfigure` | Reconfigure backend (ignore existing state)        |
| `make upgrade`          | Upgrade Terraform providers to latest versions     |
| `make modules-update`   | Update all Terraform modules to latest versions    |
| `make setup`            | Complete initial setup (secrets + init)            |

### Validation & Quality

| Command                   | Description                                   |
| ------------------------- | --------------------------------------------- |
| `make fmt`                | Format all Terraform files                    |
| `make fmt-check`          | Check if files are formatted (CI mode)        |
| `make validate`           | Validate Terraform configuration              |
| `make validate-json`      | Validate and output as JSON                   |
| `make lint`               | Run tflint on configuration (requires tflint) |
| `make security-scan`      | Run all security scanners                     |
| `make security-tfsec`     | Run tfsec security scanner                    |
| `make security-checkov`   | Run Checkov security scanner                  |
| `make security-terrascan` | Run Terrascan security scanner                |

### Planning & Deployment

<!-- markdownlint-disable MD013 -->

| Command                        | Description                                             |
| ------------------------------ | ------------------------------------------------------- |
| `make plan`                    | Create Terraform execution plan                         |
| `make plan-detailed`           | Create detailed execution plan with all changes         |
| `make plan-target TARGET=...`  | Plan specific resource                                  |
| `make plan-destroy`            | Create destruction plan                                 |
| `make plan-out`                | Create and save execution plan to file                  |
| `make apply`                   | Apply Terraform changes (deploy infrastructure)         |
| `make apply-auto`              | Apply changes without confirmation (CI mode)            |
| `make apply-target TARGET=...` | Apply specific resource                                 |
| `make refresh`                 | Refresh Terraform state (sync with real infrastructure) |

<!-- markdownlint-enable MD013 -->

### Import Helpers (Linux VM-Specific)

| Command                           | Description                        |
| --------------------------------- | ---------------------------------- |
| `make import RESOURCE=... ID=...` | Import existing resource (generic) |

<!-- markdownlint-disable MD013 -->

| **`make import-vm-linux HOSTNAME=... VMID=... [NODE=...]`** | **Import existing Linux VM** |

<!-- markdownlint-enable MD013 -->

| **`make import-guide`** | **Show guide for importing existing Linux VMs** |

### Destruction

<!-- markdownlint-disable MD013 -->

| Command                          | Description                                        |
| -------------------------------- | -------------------------------------------------- |
| `make destroy`                   | Destroy all infrastructure (with confirmation)     |
| `make destroy-auto`              | Destroy without confirmation (DANGEROUS - CI mode) |
| `make destroy-target TARGET=...` | Destroy specific resource                          |

<!-- markdownlint-enable MD013 -->

### State Management

<!-- markdownlint-disable MD013 -->

| Command                                       | Description                            |
| --------------------------------------------- | -------------------------------------- |
| `make state-list`                             | List all resources in state            |
| `make state-show RESOURCE=...`                | Show resource details                  |
| `make state-rm RESOURCE=...`                  | Remove resource from state             |
| `make state-mv FROM=... TO=...`               | Move/rename resource in state          |
| `make state-pull`                             | Pull remote state to stdout            |
| `make state-push FILE=...`                    | Push local state to remote (DANGEROUS) |
| `make state-replace-provider FROM=... TO=...` | Replace provider in state              |

<!-- markdownlint-enable MD013 -->

### Backup & Restore

| Command                       | Description                         |
| ----------------------------- | ----------------------------------- |
| `make backup-state`           | Backup current Terraform state      |
| `make restore-state FILE=...` | Restore Terraform state from backup |
| `make backup-all`             | Backup state and configuration      |

### Workspace Management

| Command                          | Description            |
| -------------------------------- | ---------------------- |
| `make workspace-list`            | List all workspaces    |
| `make workspace-show`            | Show current workspace |
| `make workspace-new NAME=...`    | Create new workspace   |
| `make workspace-select NAME=...` | Switch to workspace    |
| `make workspace-delete NAME=...` | Delete workspace       |

### Outputs & Reports

<!-- markdownlint-disable MD013 -->

| Command                     | Description                                       |
| --------------------------- | ------------------------------------------------- |
| `make output`               | Show all Terraform outputs                        |
| `make output-json`          | Show outputs as JSON                              |
| `make output-raw NAME=...`  | Show specific output raw                          |
| `make show [FILE=...]`      | Show current state or saved plan                  |
| `make show-json [FILE=...]` | Show state or plan as JSON                        |
| `make inventory`            | Generate Ansible inventory from Terraform state   |
| `make inventory-ini`        | Generate Ansible inventory in INI format          |
| `make ssh-commands`         | Show SSH commands for all hosts                   |
| `make status`               | Show current infrastructure status                |
| `make graph`                | Generate dependency graph (requires graphviz)     |
| `make graph-plan`           | Generate graph of planned changes                 |
| `make cost`                 | Estimate infrastructure cost (requires infracost) |
| `make cost-diff`            | Show cost difference for planned changes          |
| `make docs`                 | Generate documentation (requires terraform-docs)  |

<!-- markdownlint-enable MD013 -->

### Testing & Drift Detection

| Command             | Description                                     |
| ------------------- | ----------------------------------------------- |
| `make test`         | Run Terraform tests (requires Terraform >= 1.6) |
| `make drift-detect` | Detect configuration drift                      |

### Maintenance

<!-- markdownlint-disable MD013 -->

| Command                 | Description                                          |
| ----------------------- | ---------------------------------------------------- |
| `make lock`             | Update provider lock file for multiple platforms     |
| `make clean`            | Clean temporary files and caches                     |
| `make clean-all`        | Clean everything including state backups (DANGEROUS) |
| `make providers`        | Show required providers and versions                 |
| `make providers-schema` | Show provider schemas as JSON                        |
| `make console`          | Open Terraform console for debugging                 |

<!-- markdownlint-enable MD013 -->

### Workflows (Combined Commands)

| Command            | Description                                           |
| ------------------ | ----------------------------------------------------- |
| `make quick`       | Quick workflow: format + validate + plan              |
| `make full-check`  | Full quality check (CI mode)                          |
| `make deploy`      | Deploy workflow: init + plan (then prompts for apply) |
| `make full-deploy` | Full deployment: init + plan + apply + inventory      |
| `make ci-plan`     | CI workflow: init + format check + validate + plan    |
| `make ci-apply`    | CI workflow: init + auto-apply + inventory            |
| `make ci-destroy`  | CI workflow: init + auto-destroy                      |

### Version & Info

| Command        | Description                          |
| -------------- | ------------------------------------ |
| `make version` | Show Terraform and provider versions |
| `make info`    | Show environment information         |
| `make help`    | Show this help message               |

---

## Project-Specific Commands

### Importing Existing Linux VMs

#### `make import-vm-linux`

Import an existing Linux VM into Terraform state.

**Usage:**

```bash
make import-vm-linux HOSTNAME=vm-name VMID=200 [NODE=pve]
```

**Parameters:**

- `HOSTNAME` (required): VM hostname as it appears in Proxmox
- `VMID` (required): Proxmox VMID of the VM
- `NODE` (optional): Proxmox node name (defaults to `pve`)

**Example:**

```bash
make import-vm-linux HOSTNAME=web-01 VMID=200 NODE=pve
```

**What it does:**

1. Checks for existing SSH keys at `~/.ssh/<hostname>_id_ed25519`
2. Imports the VM resource into Terraform state
3. Preserves existing SSH keys if found

**Resource Path:**

```text
module.linux_vms[0].proxmox_vm_qemu.vm["hostname"]
```

**Proxmox Resource Type:**

```text
pve/qemu/VMID
```

**Cloud-Init Considerations:**

- Linux VMs use cloud-init for initial configuration
- Ensure cloud-init is properly configured on the VM before import
- Network configuration is managed via cloud-init snippets

#### `make import-guide`

Display a comprehensive guide for importing existing Linux VMs.

**Usage:**

```bash
make import-guide
```

**Steps outlined:**

1. Define the VM in `instances/linux-vms.auto.tfvars`
2. Add hostname to `imported.auto.tfvars` (if preserving SSH keys)
3. Import the VM using `make import-vm-linux`
4. Verify import with `make plan`

## Common Workflows

### Initial Setup

```bash
# 1. Create secrets file
make secrets

# 2. Edit terraform.tfvars.secret with your credentials

# 3. Initialize Terraform
make init

# 4. Define VMs in instances/linux-vms.auto.tfvars

# 5. Preview changes
make plan

# 6. Deploy infrastructure
make apply
```

### Deploying Infrastructure

```bash
# Quick deployment (interactive)
make deploy

# Full automated deployment
make full-deploy

# After deployment, generate Ansible inventory
make inventory
```

### Importing Existing VMs

```bash
# 1. View import guide
make import-guide

# 2. Add VM definition to instances/linux-vms.auto.tfvars

# 3. Import the VM
make import-vm-linux HOSTNAME=existing-vm VMID=200

# 4. Verify import
make plan
```

### Updating Infrastructure

```bash
# 1. Modify instances/linux-vms.auto.tfvars

# 2. Preview changes
make plan

# 3. Apply changes
make apply

# 4. Update Ansible inventory
make inventory
```

### Destroying Infrastructure

```bash
# Destroy specific VM
make destroy-target TARGET='module.linux_vms[0].proxmox_vm_qemu.vm["hostname"]'

# Destroy all infrastructure (with confirmation)
make destroy

# Auto-destroy (CI mode, no confirmation)
make destroy-auto
```

---

## Examples

### Example 1: Create and Deploy a New Linux VM

```bash
# 1. Setup
make setup

# 2. Edit terraform.tfvars.secret with credentials

# 3. Add VM to instances/linux-vms.auto.tfvars
cat >> instances/linux-vms.auto.tfvars <<EOF
linux_vm_instances = [
  {
    hostname   = "web-01"
    vmid       = 200
    ip         = "10.20.0.50/24"
    gw         = "10.20.0.1"
    tag        = 20
    cores      = 4
    memory     = 4096
    disk_size  = "40G"
  }
]
EOF

# 4. Plan and apply
make plan
make apply

# 5. Generate inventory
make inventory
```

### Example 2: Import Existing Linux VM

```bash
# 1. Add VM definition
cat >> instances/linux-vms.auto.tfvars <<EOF
linux_vm_instances = [
  {
    hostname   = "existing-vm"
    vmid       = 250
    ip         = "10.20.0.30/24"
    gw         = "10.20.0.1"
    tag        = 20
    cores      = 2
    memory     = 2048
    disk_size  = "30G"
  }
]
EOF

# 2. Import (preserving existing SSH keys)
make import-vm-linux HOSTNAME=existing-vm VMID=250

# 3. Verify
make plan
```

### Example 3: Update VM Resources

```bash
# 1. Edit instances/linux-vms.auto.tfvars to change memory from 2048 to 4096

# 2. Plan changes
make plan

# 3. Apply changes
make apply
```

### Example 4: CI/CD Workflow

```bash
# In CI pipeline
make ci-plan          # Validate and plan
make ci-apply         # Auto-apply and generate inventory
```

---

## Troubleshooting

### "terraform.tfvars.secret not found"

**Error:**

```text
terraform.tfvars.secret not found. Run 'make secrets' first.
```

**Solution:**

```bash
make secrets
# Then edit terraform.tfvars.secret with your credentials
```

### Import Fails with "Resource not found"

**Error:**

```text
Error: resource not found
```

**Solution:**

1. Verify the VMID exists: `pvesh get /nodes/pve/qemu`
2. Check the hostname matches exactly
3. Ensure the VM is defined in `instances/linux-vms.auto.tfvars` before
   importing

### State Locked

**Error:**

```text
Error: Error acquiring the state lock
```

**Solution:**

```bash
# Check for stale locks
terraform force-unlock <LOCK_ID>

# Or wait for the lock to be released
```

### SSH Keys Not Found During Import

**Warning:**

```text
SSH keys not found at ~/.ssh/hostname_id_ed25519
```

**Solution:**

- Terraform will generate new keys automatically
- Or create keys manually before import:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/hostname_id_ed25519 -N ""
```

### Cloud-Init Not Working

**Issue:** VM doesn't get configured on first boot

**Solution:**

1. Verify cloud-init is installed: `cloud-init --version`
2. Check cloud-init logs: `/var/log/cloud-init-output.log`
3. Ensure cloud-init snippets are properly formatted
4. Verify network configuration in cloud-init snippets

### Ansible Inventory Not Generated

**Issue:** `make inventory` fails or produces empty file

**Solution:**

1. Ensure infrastructure is deployed: `make status`
2. Verify outputs exist: `make output`
3. Check state file exists: `ls generated/state/terraform.tfstate`

## Related Documentation

- [Terraform Linux VMs Project README](../README.md)
- [Linux VM Module](../../modules/vm-linux/README.md)
- [Ansible Inventory Module](../../modules/ansible-inventory/README.md)

## Command Reference Details

### Variable Files

The Makefile automatically loads variable files in this order:

1. `terraform.tfvars.secret` (required)
2. All `*.auto.tfvars` files in `instances/` directory

### Environment Variables

- `TF_PARALLELISM`: Number of parallel operations (default: 10)
- `TF_LOG`: Terraform log level (optional)
- `TF_LOG_PATH`: Terraform log file path (optional)

### File Locations

- **Secrets**: `terraform.tfvars.secret`
- **Instances**: `instances/*.auto.tfvars`
- **State**: `generated/state/terraform.tfstate`
- **Backups**: `generated/backups/`
- **Plans**: `generated/plans/*.tfplan`
- **Ansible Inventory**: `../../ansible/inventory/linux-vms-hosts.yml`

## Best Practices

1. **Always run `make plan` before `make apply`** to review changes
2. **Backup state before major changes**: `make backup-state`
3. **Use `make import-guide`** before importing existing VMs
4. **Keep `terraform.tfvars.secret`** out of version control (already in
   .gitignore)
5. **Run `make inventory`** after every deployment to sync with Ansible
6. **Use `make full-check`** before committing changes in CI/CD
7. **Review `make status`** output regularly to track infrastructure state
8. **Ensure cloud-init is properly configured** on Linux VMs before import

## Getting Help

```bash
# Show all available commands
make help

# Show environment information
make info

# Show Terraform version
make version
```
