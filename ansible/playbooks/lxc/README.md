# LXC Ansible Playbooks

Playbooks for managing Proxmox LXC containers.

## Playbook Order

| Playbook | Description |
|----------|-------------|
| `01-bootstrap.yml` | Initial container setup (user creation, SSH hardening). Run as root. |
| `02-configure.yml` | Regular configuration (packages, Docker). Run as non-root user. |
| `03-verify.yml` | Health checks (connectivity, services, disk space). |
| `04-system-update.yml` | APT package updates with reboot check. |
| `05-diagnostics.yml` | Collect system diagnostics (CPU, memory, disk, Docker). |
| `06-restart-services.yml` | Restart Docker and related services. |
| `07-reboot.yml` | Rolling reboot of containers. |
| `08-shutdown.yml` | Graceful shutdown of containers. |
| `main.yml` | Orchestrator. Imports all playbooks with tag groups. |

## Tag Groups (main.yml)

| Tag Group | Playbooks | Description |
|-----------|-----------|-------------|
| `deployment` | 01-03 | Initial setup and verification |
| `operations` | 04-05 | Day-2 operations |
| `lifecycle` | 06-08 | Service and container lifecycle |

## Usage

```bash
cd ansible/lxc

make bootstrap-host HOST=dns-1    # Initial setup (as root)
make configure-host HOST=dns-1    # Configure (as non-root)
make verify-host HOST=dns-1       # Health check
make system-update-host HOST=dns-1
make reboot-host HOST=dns-1
```
