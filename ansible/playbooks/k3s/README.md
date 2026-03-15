# K3s Ansible Playbooks

This directory contains Ansible playbooks for managing the K3s cluster. These playbooks handle the full lifecycle of the cluster, from initial bootstrap to maintenance, updates, and recovery.

## Playbook Order

| Playbook | Description |
|----------|-------------|
| `01-bootstrap.yml` | Initial cluster setup. Deploys masters and workers, applies taints and labels. |
| `02-configure-labels.yml` | Applies the standard label schema (`workload.homelab/*`) to all nodes. |
| `03-verify.yml` | Key health checks. Verifies nodes, pods, labels, and tier configuration. |
| `04-update.yml` | Updates K3s version (rolling update). |
| `05-system-update.yml` | Updates OS packages on all nodes. |
| `06-diagnostics.yml` | Collects comprehensive cluster status, events, and resource usage. |
| `07-health-check.yml` | Fast pre-flight check for node readiness and critical component health. |
| `08-restart.yml` | Restarts K3s services without rebooting nodes. |
| `09-reboot.yml` | Rolling reboot. Drains and reboots nodes safely one by one. |
| `10-shutdown.yml` | Graceful shutdown. Drains all nodes and shuts down the cluster. |
| `11-startup.yml` | Cluster recovery. Starts services and recovers the cluster after a shutdown. |
| `12-drain-node.yml` | Emergency tool to cordon and drain a specific node. |
| `13-maintenance-mode.yml` | Toggles maintenance mode (cordon/drain) for a node. |
| `main.yml` | Orchestrator. Imports all playbooks with tag groups for selective execution. |

## Tag Groups (main.yml)

| Tag Group | Playbooks | Description |
|-----------|-----------|-------------|
| `deployment` | 01-03 | Initial cluster setup |
| `operations` | 04-07 | Day-2 operations (updates, diagnostics) |
| `lifecycle` | 08-11 | Service/node lifecycle management |
| `node-ops` | 12-13 | Per-node operations |

Destructive operations require explicit `--tags` to run (tagged with `never`).

## Host Groups & Tier Architecture

The cluster uses a three-tier architecture defined in `inventory/workload-tiers.yml`.

### Label Schema

| Tier | Label (`workload.homelab/tier`) | Description |
|------|--------------------------------|-------------|
| **Infrastructure** | `infrastructure` | Control plane nodes (Masters). Tainted to prevent general workloads. |
| **Stateful** | `stateful` | Nodes capable of persistent storage (Longhorn/local-path). |
| **Stateless** | `stateless` | Nodes for ephemeral workloads. |

Additional labels: `workload.homelab/role`, `workload.homelab/storage-capable`.

## Usage

**ALWAYS use the Makefile** in `ansible/k3s/` to run these playbooks.

```bash
cd ansible/k3s

# Health
make health-check
make verify
make diagnostics

# Maintenance
make reboot
make shutdown
make startup

# Node Management
make drain-node HOST=k3s-worker-1
make maintenance-mode HOST=k3s-worker-1 STATE=enable
make maintenance-mode HOST=k3s-worker-1 STATE=disable
```
