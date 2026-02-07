# K3s Ansible Playbooks

This directory contains Ansible playbooks for managing the K3s cluster. These playbooks handle the full lifecycle of the cluster, from initial bootstrap to maintenance, updates, and recovery.

## Directory Structure

| Playbook               | Description                                                                                       |
| ---------------------- | ------------------------------------------------------------------------------------------------- |
| `bootstrap.yml`        | Initial cluster setup. Deploys masters and workers, applies taints and labels.                    |
| `deploy.yml`           | Main orchestrator playbook. Can run other playbooks via tags.                                     |
| `reboot.yml`           | **Rolling Reboot**. drains and reboots nodes safely one by one.                                   |
| `shutdown.yml`         | **Graceful Shutdown**. Drains all nodes and shuts down the cluster (e.g., for power maintenance). |
| `startup.yml`          | **Cluster Recovery**. Starts services and recovers the cluster after a shutdown.                  |
| `verify.yml`           | Key health checks. Verifies nodes, pods, labels, and tier configuration.                          |
| `diagnostics.yml`      | Collects comprehensive cluster status, events, and resource usage.                                |
| `health-check.yml`     | **Pre-flight Check**. Fast check for node readiness and critical component health.                |
| `configure-labels.yml` | Applies the standard label schema (`workload.homelab/*`) to all nodes.                            |
| `drain-node.yml`       | Emergency tool to cordon and drain a specific node.                                               |
| `maintenance-mode.yml` | Toggles maintenance mode (cordon/drain) for a node.                                               |
| `update.yml`           | Updates K3s version (rolling update).                                                             |
| `system-update.yml`    | Updates OS packages on all nodes.                                                                 |
| `restart.yml`          | Restarts K3s services without rebooting nodes.                                                    |

## Host Groups & Tier Architecture

The cluster uses a three-tier architecture defined in `inventory/workload-tiers.yml`.

### Label Schema

We support a dual label schema for backward compatibility. The new schema is preferred.

| Tier               | Old Label (`workload-tier`) | New Label (`workload.homelab/tier`) | Description                                                          |
| ------------------ | --------------------------- | ----------------------------------- | -------------------------------------------------------------------- |
| **Infrastructure** | `infrastructure`            | `infrastructure`                    | Control plane nodes (Masters). Tainted to prevent general workloads. |
| **Stateful**       | `stateful`                  | `stateful`                          | Nodes capable of persistent storage (Longhorn/local-path).           |
| **Stateless**      | `stateless`                 | `stateless`                         | Nodes for ephemeral workloads.                                       |

**Additional New Labels:**

- `workload.homelab/role`: `control-plane` or `worker`
- `workload.homelab/storage-capable`: `"true"` or `"false"`

## Usage

**ALWAYS use the Makefile** in `ansible/k3s/` to run these playbooks. It handles inventory paths and variables automatically.

```bash
cd ansible/k3s
```

### Common Commands

**Check Health:**

```bash
make health-check   # Fast pre-flight check
make verify         # Deep verification
make diagnostics    # Export debug logs
```

**Maintenance:**

```bash
make reboot         # Rolling reboot of entire cluster
make shutdown       # Shutdown entire cluster
make startup        # Start up cluster after shutdown
```

**Node Management:**

```bash
make drain-node HOST=k3s-worker-1           # Drain a specific node
make maintenance-mode HOST=k3s-worker-1 STATE=enable   # Enter maintenance
make maintenance-mode HOST=k3s-worker-1 STATE=disable  # Exit maintenance
```
