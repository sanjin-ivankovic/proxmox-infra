# Talos VMs - Terraform Module

Terraform configuration for deploying and managing Talos Linux clusters on
Proxmox VE.

## Overview

This module manages complete Talos Linux Kubernetes clusters on Proxmox using
a **two-provider architecture**:

- **Telmate/proxmox**: VM provisioning (compute, storage, network)
- **siderolabs/talos**: Cluster lifecycle (secrets, config, bootstrap,
  kubeconfig)

Talos is an immutable, minimal, and secure Kubernetes operating system that
is configured entirely via API (no SSH access).

**Key Features:**

- **API-Only Management**: Talos uses talosctl for all configuration (no SSH)
- **Immutable OS**: System files are read-only, configured at boot
- **Minimal Attack Surface**: No shell, no package manager, no SSH
- **Resource Efficient**: 30% less RAM than traditional K8s distributions
- **GitOps-Ready**: Configuration stored in version control
- **Full Terraform Lifecycle**: VM creation, Talos config, cluster bootstrap,
  kubeconfig retrieval

## Prerequisites

1. **Proxmox VE 7.0+** with API access
2. **Talos ISO** uploaded to Proxmox storage:

   ```bash
   # Download latest Talos ISO (v1.12.3)
   wget https://github.com/siderolabs/talos/releases/download/v1.12.3/metal-amd64.iso

   # Upload to Proxmox (from Proxmox node)
   mv metal-amd64.iso /var/lib/vz/template/iso/talos-amd64.iso
   ```

3. **Terraform 1.5.0+**
4. **GitLab API Token** (for state storage)
5. **talosctl** (optional, for manual operations)

## Quick Start

### 1. Initial Setup

```bash
# Create secrets file from example
make secrets

# Edit terraform.tfvars.secret and add your credentials
nano terraform.tfvars.secret

# Initialize Terraform
make init

# Validate configuration
make validate
```

### 2. Configure VMs

Edit [instances/talos.auto.tfvars](instances/talos.auto.tfvars) to define
your Talos cluster:

```text
talos_vm_instances = [
  {
    hostname     = "talos-cp-1"
    vmid         = 460
    ip           = "10.40.0.60/24"
    gw           = "10.40.0.1"
    cores        = 2
    memory       = 4096  # 4GB minimum for control plane
    disk_size    = "50G"
    onboot       = true
    start        = false
    tags         = ["talos", "kubernetes", "controlplane"]
    tag          = 40
    talos_role   = "controlplane"
    bios         = "ovmf"  # UEFI recommended
  },
  # Add more nodes...
]
```

### 3. Deploy

```bash
# Plan changes
make plan

# Apply changes (creates VMs, generates secrets, applies config, bootstraps cluster)
make apply

# Export cluster credentials
make post-apply

# Verify cluster health
make cluster-health
```

### 4. Access Cluster

After deployment, cluster credentials are automatically exported:

```bash
# Talosconfig location
../../ansible/talos/configs/talosconfig

# Kubeconfig location
../../ansible/talos/configs/kubeconfig

# Use kubeconfig
export KUBECONFIG=../../ansible/talos/configs/kubeconfig
kubectl get nodes
```

## Architecture

### Terraform Providers

This module uses a **dual-provider architecture**:

1. **Telmate/proxmox 3.0.2-rc07**: VM lifecycle management
   - Creates/destroys VMs
   - Manages compute resources (CPU, RAM, disk)
   - Configures network interfaces
   - Handles UEFI/BIOS settings

2. **siderolabs/talos 0.10.1**: Cluster lifecycle management
   - Generates cluster PKI (talos_machine_secrets)
   - Creates machine configurations (data.talos_machine_configuration)
   - Applies configs to nodes (talos_machine_configuration_apply)
   - Bootstraps Kubernetes (talos_machine_bootstrap)
   - Retrieves kubeconfig (talos_cluster_kubeconfig)

**Why two providers?**

- **Separation of concerns**: Infrastructure (Proxmox) vs Platform
  (Talos/Kubernetes)
- **Idempotency**: Talos provider handles configuration drift automatically
- **GitOps-native**: Cluster config lives in Terraform state
- **Migration-friendly**: Existing clusters can import secrets without rebuild

### Directory Structure

```text
talos-vms/
├── main.tf                      # VM module instantiation
├── talos.tf                     # Talos cluster lifecycle (NEW)
├── variables.tf                 # Input variables
├── outputs.tf                   # Outputs (IPs, inventory, configs)
├── versions.tf                  # Terraform/provider versions
├── providers.tf                 # Proxmox + Talos provider config
├── backend.tf                   # GitLab HTTP backend
├── Makefile                     # Management commands
├── README.md                    # This file
├── instances/
│   └── talos.auto.tfvars       # VM definitions
├── modules/
│   └── vm-talos/               # Talos VM module
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── templates/
│   ├── ansible-inventory.yml.tftpl  # Ansible inventory template
│   └── deployment-summary.tftpl     # Post-deployment summary
└── generated/
    ├── state/                   # Local state backup
    └── backups/                 # State backups
```

### Resource Allocation

**Default 6-node cluster (3 CP + 3 Workers):**

- **Total VMs**: 6
- **Total CPU**: 18 cores (6 + 12)
- **Total RAM**: 30 GB (12 + 18)
- **Total Disk**: 450 GB (150 + 300)

**Compared to K3s (3 masters + 3 workers):**

- K3s: 42 GB RAM (18 + 24)
- Talos: 30 GB RAM (12 + 18)
- **Savings**: 12 GB RAM (29% reduction)

## Terraform Outputs

### VM Details

```bash
make output
```

**Key outputs:**

- `vm_details` - Complete VM information
- `vm_ips` - Hostname to IP mapping
- `controlplane_endpoints` - Control plane IPs
- `talosconfig` - Talos API credentials (sensitive)
- `kubeconfig` - Kubernetes cluster access (sensitive)
- `ansible_info` - Ansible inventory data
- `compute_summary` - Resource summary

### Export Cluster Credentials

```bash
# Export talosconfig to file
make talosconfig

# Export kubeconfig to file
make kubeconfig

# Export both + verify health
make post-apply
```

### Ansible Inventory

The module automatically generates an Ansible inventory at:

```text
../../ansible/talos/inventory/hosts.yml
```

**Example inventory:**

```text
all:
  children:
    talos:
      children:
        controlplane:
          hosts:
            talos-cp-1:
              ansible_host: 10.40.0.60
              ansible_connection: local
              talos_role: controlplane
        workers:
          hosts:
            talos-worker-1:
              ansible_host: 10.40.0.70
              ansible_connection: local
              talos_role: worker
```

## Common Operations

### View Current Status

```bash
make status
```

### Format Code

```bash
make fmt
```

### List Resources

```bash
make state-list
```

### Taint a Resource (Force Recreation)

```bash
# List resources
make state-list

# Taint a specific VM
make taint RESOURCE='module.talos_vms[0].proxmox_vm_qemu.vm["talos-cp-1"]'

# Apply to recreate
make apply
```

### Destroy Infrastructure

```bash
# WARNING: This destroys all VMs!
make destroy
```

## Talos-Specific Considerations

### Terraform-Managed Lifecycle

- **Secrets**: Generated by `talos_machine_secrets` resource
- **Configuration**: Applied via `talos_machine_configuration_apply` resource
- **Bootstrap**: Automated via `talos_machine_bootstrap` resource
- **Kubeconfig**: Retrieved via `talos_cluster_kubeconfig` resource

**All cluster management happens in Terraform** - no separate Ansible
playbooks needed for initial setup.

### No SSH Access

- Talos does **not** support SSH
- All management via `talosctl` CLI
- Ansible compatibility: `ansible_connection: local` with talosctl delegation

### Network Configuration

- **Static IPs**: Configured via Talos machine config patches in Terraform
- **DHCP reservations**: Required for initial boot (ISO doesn't support
  cloud-init)
- **No cloud-init**: All config applied via Talos API after boot
- **Config apply**: Happens automatically during `terraform apply`

**Network config workflow:**

1. VM boots from ISO (DHCP)
2. Terraform waits for Talos API (port 50000)
3. Terraform applies machine config with static IP
4. Node reboots with static IP

### UEFI Boot

- Talos recommends UEFI (OVMF) boot
- Default `bios = "ovmf"` in configuration
- Ensure Proxmox has OVMF firmware available

### Minimum Requirements

- **Control Plane**: 2 GB RAM, 2 CPU cores (4 GB recommended)
- **Worker**: 4 GB RAM, 2 CPU cores (6 GB recommended)
- **Disk**: 10 GB minimum (50-100 GB recommended)

### Cluster Secrets Management

**New cluster (recommended):**

- Terraform generates secrets: `talos_machine_secrets.this`
- Secrets stored in Terraform state (encrypted by GitLab backend)
- No manual secret management needed

**Existing cluster (migration):**

- Import existing secrets into Terraform state
- See **Migration from Ansible** section below

**WARNING**: Changing secrets will destroy and recreate the cluster!

## Migration from Ansible-Managed Talos

If you have an existing Talos cluster managed by Ansible:

### Option 1: Import Secrets (Zero Downtime)

1. **Extract secrets from Ansible:**

   ```bash
   cd ../../ansible/talos/configs
   # Secrets are in secrets.yaml (if exists)
   ```

2. **Import into Terraform state:**

   ```bash
   # This requires manual state manipulation
   # See: https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_secrets
   terraform import talos_machine_secrets.this <cluster-id>
   ```

3. **Verify no changes:**

   ```bash
   make plan
   # Should show no changes to cluster config
   ```

### Option 2: Rebuild Cluster (Downtime)

1. **Backup workloads:**

   ```bash
   kubectl get all -A -o yaml > cluster-backup.yaml
   ```

2. **Destroy Ansible-managed cluster:**

   ```bash
   cd ../../ansible/talos
   make reset  # DESTRUCTIVE!
   ```

3. **Deploy Terraform-managed cluster:**

   ```bash
   cd ../../terraform/talos-vms
   make apply
   ```

4. **Restore workloads:**

   ```bash
   kubectl apply -f cluster-backup.yaml
   ```

**Recommendation**: Use Option 2 for test/dev clusters. Option 1 requires
careful state manipulation.

## Troubleshooting

### VMs Not Starting

**Check Proxmox console:**

```bash
# From Proxmox node
qm monitor <vmid>
```

**Verify ISO exists:**

```bash
ls -lh /var/lib/vz/template/iso/talos-amd64.iso
```

### Terraform Init Fails

**Backend authentication issue:**

```bash
# Check GitLab token
grep gitlab_api_token terraform.tfvars.secret

# Manually set token
export TF_HTTP_PASSWORD="your-gitlab-token"
terraform init
```

### State Lock Issues

```bash
# Force unlock (use with caution)
terraform force-unlock <lock-id>
```

## Migration from K3s

If migrating from K3s to Talos:

1. **Backup K3s cluster:**

   ```bash
   cd ../../ansible/k3s
   # Export all resources
   kubectl get all --all-namespaces -o yaml > k3s-backup.yaml
   # Shutdown K3s nodes gracefully
   ansible-playbook playbooks/k3s-shutdown.yml
   ```

2. **Deploy Talos cluster (this module):**

   ```bash
   cd ../../terraform/talos-vms
   make apply  # Creates VMs + configures cluster
   make post-apply  # Exports credentials
   ```

3. **Verify Talos cluster:**

   ```bash
   export KUBECONFIG=../../ansible/talos/configs/kubeconfig
   kubectl get nodes
   make cluster-health
   ```

4. **Migrate workloads:**
   - Update manifests for Talos compatibility (if needed)
   - Use kubectl apply or GitOps (ArgoCD/FluxCD)

   ```bash
   kubectl apply -f k3s-backup.yaml
   ```

5. **Destroy K3s VMs (after verification):**

   ```bash
   cd ../../terraform/lxc  # or linux-vms if K3s on VMs
   make destroy-target TARGET='module.lxc["k3s-master-1"]'
   ```

**Key Differences K3s → Talos:**

- **No SSH**: All management via Talos API
- **No local storage**: Use Longhorn/Rook for persistent volumes
- **No kube-vip**: Talos uses Layer 2 VIP natively
- **No embedded LB**: Use MetalLB or external LB
- **Immutable OS**: Updates via `talosctl upgrade`, not apt/yum

## Security Notes

- **Credentials**: Never commit `terraform.tfvars.secret` to git
- **State**: GitLab backend encrypts state at rest
- **API Tokens**: Use minimal permissions (VM management only)
- **Talos API**: Certificate-based authentication (stored in `talosconfig`)

## References

- [Talos Documentation](https://www.talos.dev/)
- [Talos Terraform Provider][talos-terraform]
- [Proxmox Provider Docs][proxmox-provider]
- [GitLab Terraform Backend][gitlab-backend]
- [Talos Machine Configuration][talos-config]
- [Talos API](https://www.talos.dev/latest/reference/api/)

[talos-terraform]: https://registry.terraform.io/providers/siderolabs/talos/latest/docs
[proxmox-provider]: https://registry.terraform.io/providers/Telmate/proxmox/latest/docs
[gitlab-backend]: https://docs.gitlab.com/ee/user/infrastructure/iac/terraform_state.html
[talos-config]: https://www.talos.dev/latest/reference/configuration/

## Support

For issues:

1. Check Proxmox logs: `/var/log/pve/tasks/`
2. Verify Terraform state: `make state-list`
3. Review Ansible inventory: `make inventory`
4. Consult Talos docs: <https://www.talos.dev/>
