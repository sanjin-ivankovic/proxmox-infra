# Ansible Role: monitoring_agent

Installs pinned [node_exporter](https://github.com/prometheus/node_exporter),
[cAdvisor](https://github.com/google/cadvisor) and
[Alloy](https://github.com/grafana/alloy) release binaries with systemd
units on a Docker host. Prometheus in the cluster
(argo-apps `apps/infra/kube-prometheus-stack`) scrapes node_exporter and
cAdvisor; Alloy pushes the journal and Docker container logs to Loki
(argo-apps `apps/infra/loki`).

## Requirements

- Debian 12+ LXC with Docker (`docker` Proxmox tag)
- Core-zone hosts: the `monitoring_exporters` port group in
  `terraform/unifi/groups.tf` lets the Talos nodes reach the ports

## Dependencies

- `common_docker` (cAdvisor reads the Docker socket and container cgroups)

## Role Variables

<!-- markdownlint-disable MD013 MD060 -->

| Variable | Description | Default |
| --- | --- | --- |
| `monitoring_agent_node_exporter_version` | node_exporter release (Renovate) | `1.12.1` |
| `monitoring_agent_cadvisor_version` | cAdvisor release (Renovate) | `0.60.6` |
| `monitoring_agent_install_dir` | One subdirectory or file per release | `/opt/monitoring-agent` |
| `monitoring_agent_node_exporter_port` | node_exporter port | `9100` |
| `monitoring_agent_cadvisor_port` | cAdvisor port (8080 is taken on several hosts) | `9338` |
| `monitoring_agent_textfile_dir` | Textfile collector directory | `/var/lib/node_exporter/textfile` |
| `monitoring_agent_etcd_backup_dir` | Talos etcd snapshot directory to report on; empty disables it | `""` |
| `monitoring_agent_alloy_version` | Alloy release (Renovate), same as the cluster DaemonSet | `1.21.1` |
| `monitoring_agent_alloy_port` | Alloy HTTP port | `12345` |
| `monitoring_agent_loki_push_url` | Loki push route | `https://loki.example.com/loki/api/v1/push` |
| `monitoring_agent_loki_push_user` | Push route basic-auth user | `alloy` |
| `monitoring_agent_loki_push_password` | Push route password | `vault_loki_push_password` |

<!-- markdownlint-enable MD013 MD060 -->

## What it installs

- `node_exporter` as the unprivileged `node_exporter` user, with the
  textfile collector and the systemd collector limited to the Docker,
  Periphery and agent units
- `cadvisor` as root, Docker containers only, 30s housekeeping and the
  costly metric groups disabled
- On semaphore only: an `etcd-backup-age` timer (every 5 minutes) that
  writes `talos_etcd_backup_newest_timestamp_seconds` and
  `talos_etcd_backup_files`. The snapshots are 0600 under a 0700 directory,
  so node_exporter cannot read them itself.

- `alloy` as the `alloy` user (groups `systemd-journal` and `docker`):
  the journal (`job=lxc-journal`, labels `unit`, `level`) and every
  container's logs through the Docker API (`job=lxc-docker`, labels
  `container`, `compose_project`, `compose_service`). Every stream carries
  `host` and `zone`. Read positions live in `/var/lib/alloy`.

Each release lands beside the previous one under the install directory and
`/usr/local/bin/<name>` links to it, so a version bump swaps the link and
restarts the service.

## Usage

```bash
make -C ansible monitoring-agent              # every Docker host
make -C ansible monitoring-agent HOST=gitlab  # one host
```
