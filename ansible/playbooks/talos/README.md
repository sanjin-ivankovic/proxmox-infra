# Talos Cluster Playbooks

API-driven playbooks for managing Talos Linux Kubernetes clusters.

## Overview

These playbooks manage Talos clusters using the `talosctl` CLI and API,
**not SSH**. All operations are performed via the Talos API using
certificate-based authentication.

## Prerequisites

- `talosctl` installed: `brew install siderolabs/tap/talosctl`
- `ansible` installed
- Proxmox VMs created (via Terraform) with Talos ISO
- Inventory file generated from Terraform

## Playbook Execution Order

1. **01-generate-configs.yml** - Generate machine configs with patches and VIP
   - Generates cluster secrets separately (`talosctl gen secrets`)
   - Applies machine config patches (common, controlplane, worker)
   - Configures Layer 2 VIP for HA control planes
2. **02-apply-configs.yml** - Push configs to nodes via Talos API
   - Auto-detects first boot (insecure mode) vs updates (authenticated mode)
3. **03-bootstrap.yml** - Initialize etcd and Kubernetes cluster
4. **04-apply-rbac.yml** - Apply RBAC patches to cluster
   - Applies system:node-reader permissions
5. **05-verify.yml** - Verify cluster health and readiness
6. **06-diagnostics.yml** - Collect comprehensive diagnostics to
   timestamped reports
   - Includes dmesg, etcd status, members, service status
   - Saves to `talos/diagnostics/<timestamp>/`
7. **07-upgrade.yml** - Upgrade Talos OS version (rolling)
   - Drains workloads before upgrading
   - Uncordons after successful upgrade
8. **08-reboot.yml** - Rolling reboot via Talos API
   - Drains workloads before rebooting
   - Uncordons after successful reboot
9. **09-shutdown.yml** - Graceful cluster shutdown
   - Workers shut down first, then control planes
10. **10-startup.yml** - Start VMs via Proxmox API and verify cluster
    - Control planes start first (establish quorum), then workers
11. **11-health-check.yml** - Comprehensive health validation
    - Dynamically iterates over inventory (no hardcoded IPs)
12. **12-reset.yml** - **DESTRUCTIVE** Reset cluster to maintenance mode
    - Requires confirmation
    - Wipes all Kubernetes and etcd data
    - Requires re-apply and re-bootstrap

## Quick Start

```bash
cd /home/user/projects/proxmox-infra/ansible/talos

# 1. Generate machine configurations
make generate-configs

# 2. Apply configs to nodes (pushes via API)
make apply-configs

# 3. Bootstrap Kubernetes cluster
make bootstrap

# 4. Verify cluster health
make verify
```

## Key Differences from K3s Playbooks

- **Access**
  - K3s: SSH (user/key vars)
  - Talos: Talos API (`talosctl` with certs)
- **Config Application**
  - K3s: `copy`, `template`, `lineinfile`
  - Talos: `talosctl apply`
- **Service Management**
  - K3s: `systemd`, `service` modules
  - Talos: Immutable OS
- **Logs**
  - K3s: `journalctl` via SSH
  - Talos: `talosctl logs` via API
- **Reboots**
  - K3s: `reboot` module via SSH
  - Talos: `talosctl reboot` via API
- **Package Management**
  - K3s: `apt`, `yum` modules
  - Talos: None - OS is immutable

## Configuration Files

Generated in `talos/configs/` (gitignored):

- **secrets.yaml** - Cluster PKI and identity (keep secure!)
  - Generated once with `talosctl gen secrets`
  - Allows config regeneration without losing cluster identity
- **talosconfig** - Talos API credentials (like ~/.kube/config for talosctl)
- **controlplane.yaml** - Control plane node configuration (with VIP + patches)
- **worker.yaml** - Worker node configuration (with patches)
- **kubeconfig** - Kubernetes config (generated after bootstrap)

## Machine Config Patches

Located in `talos/patches/` (version controlled):

- **common.yaml** - Applied to all nodes
  - Install disk configuration
  - Kernel modules (iSCSI for Longhorn)
  - Sysctls (inotify limits)
  - Time servers
  - KubePrism for reliable localhost K8s API
- **controlplane.yaml** - Applied to control planes only
  - **Layer 2 VIP** configuration (`10.40.0.59`)
  - etcd metrics
  - API server audit logging
  - Additional certificate SANs
- **worker.yaml** - Applied to workers only
  - Kubelet eviction thresholds
  - Max pods per node
  - Node labels

## High Availability Setup

- **Control Plane VIP**: `10.40.0.59` (Layer 2)
  - Automatically announces from one CP at a time via gratuitous ARP
  - Endpoint: `https://10.40.0.59:6443`
  - Configured via machine patches
- **3 Control Planes**: etcd quorum and API HA
- **3 Workers**: Distributed workload execution

## Common Commands

```bash
# Generate configs
make generate-configs

# Apply to nodes
make apply-configs

# Bootstrap cluster
make bootstrap

# Get kubeconfig
make kubeconfig
export KUBECONFIG=$(pwd)/configs/kubeconfig

# Verify cluster
make verify

# Collect diagnostics
make diagnostics

# Upgrade Talos
make upgrade  # Will prompt for version

# Reboot cluster
make reboot

# Shutdown cluster
make shutdown

# Start cluster after shutdown
make startup

# Reset cluster (DESTRUCTIVE - requires confirmation)
make reset

# View Talos dashboard (TUI)
make dashboard
```

## Operational Improvements

- **Graceful upgrades/reboots**: Automatically drains workloads with
  `kubectl drain` before disruptive operations, then uncordons after
  health checks
- **Ordered shutdown/startup**: Workers shut down before control planes;
  control planes start before workers (ensures proper quorum)
- **Enhanced diagnostics**: Collects dmesg, etcd status, members,
  service status, and saves to timestamped reports in
  `talos/diagnostics/`
- **Authenticated re-application**: Detects if nodes are already
  configured and uses authenticated mode instead of insecure mode for
  config updates
- **Shared role tasks**: Centralized talosctl checks, config
  validation, health checks, and API waits in the `talos_cluster` role
- **Proxmox API integration**: Startup playbook uses Proxmox REST API
  instead of relying on `pvesh` CLI (works from any machine)

## Accessing Talos Nodes

**No SSH!** All access via `talosctl`:

```bash
# Set talosconfig
export TALOSCONFIG=/path/to/ansible/talos/configs/talosconfig

# View logs
talosctl logs -f --nodes 10.40.0.60

# Get system info
talosctl health --nodes 10.40.0.60
talosctl version --nodes 10.40.0.60

# Read files
talosctl read /proc/meminfo --nodes 10.40.0.60

# Interactive dashboard
talosctl dashboard --nodes 10.40.0.60

# List containers
talosctl containers --nodes 10.40.0.60
```

## Inventory Structure

```text
all:
  children:
    talos_cluster:
      children:
        control_planes:
          hosts:
            talos-cp-1:
              ansible_host: 10.40.0.60
              # No ansible_user or SSH key!
        workers:
          hosts:
            talos-worker-1:
              ansible_host: 10.40.0.70
```

## Troubleshooting

### Issue: talosctl not found

```bash
brew install siderolabs/tap/talosctl
```

### Issue: Connection refused

- Verify VMs are running in Proxmox
- Check network connectivity: `ping 10.40.0.60`
- Verify Talos API port 50000 is accessible

### Issue: Invalid credentials

- Regenerate configs: `make generate-configs`
- Reapply to nodes: `make apply-configs`

### Issue: Bootstrap fails

- Ensure only ONE control plane node is bootstrapped
- Check etcd port 2379 is accessible between control planes
- Verify no firewalls blocking cluster communication

## Resource Savings vs K3s

| Component                | K3s   | Talos   | Savings |
| ------------------------ | ----- | ------- | ------- |
| Control Plane (per node) | 6 GB  | 2-3 GB  | 50%     |
| Worker (per node)        | 8 GB  | 4-6 GB  | 25-50%  |
| OS Overhead              | ~1 GB | ~300 MB | 70%     |

## Further Reading

- [Talos Documentation](https://www.talos.dev/latest/)
- [talosctl Reference](https://www.talos.dev/latest/reference/cli/)
- [Talos API](https://www.talos.dev/latest/reference/api/)
