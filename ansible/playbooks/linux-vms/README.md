# Linux VMs Ansible Playbooks

Playbooks for managing Proxmox Linux virtual machines.

## Playbook Order

| Playbook | Description |
|----------|-------------|
| `01-bootstrap.yml` | Initial VM setup (user creation, SSH hardening). Run as root. |
| `02-configure.yml` | Regular configuration (packages, Podman). Run as non-root user. |
| `03-verify.yml` | Health checks (connectivity, services, disk space). |
| `04-system-update.yml` | APT package updates with reboot check. |
| `05-diagnostics.yml` | Collect system diagnostics (CPU, memory, disk, Podman). |
| `06-restart-services.yml` | Restart Podman and related services. |
| `07-reboot.yml` | Rolling reboot of VMs. |
| `08-shutdown.yml` | Graceful shutdown of VMs. |
| `main.yml` | Orchestrator. Imports all playbooks with tag groups. |

## Tag Groups (main.yml)

| Tag Group | Playbooks | Description |
|-----------|-----------|-------------|
| `deployment` | 01-03 | Initial setup and verification |
| `operations` | 04-05 | Day-2 operations |
| `lifecycle` | 06-08 | Service and VM lifecycle |

## Usage

```bash
cd ansible/linux-vms

make bootstrap-host HOST=pihole-1    # Initial setup (as root)
make configure-host HOST=pihole-1    # Configure (as non-root)
make verify-host HOST=pihole-1       # Health check
make system-update-host HOST=pihole-1
make reboot-host HOST=pihole-1
```
