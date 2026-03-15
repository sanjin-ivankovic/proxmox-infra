# Ansible Roles

Shared roles used across all sub-projects (talos, k3s, lxc, linux-vms).

## Role Index

| Role | Description | Used By |
|------|-------------|---------|
| `common_system` | System packages, APT updates, timezone, capabilities | lxc, linux-vms, k3s |
| `common_users` | Non-root user creation and sudo configuration | lxc, linux-vms, k3s |
| `common_ssh` | SSH hardening (disable root login, key-only auth) | lxc, linux-vms, k3s |
| `common_docker` | Docker CE installation and configuration | lxc |
| `common_podman` | Podman installation and configuration | linux-vms |
| `k3s_cluster` | K3s cluster deployment and management | k3s |
| `k3s_system_prep` | System preparation for K3s nodes | k3s |
| `talos_cluster` | Talos Linux cluster management via talosctl API | talos |

## Role Resolution

Roles are resolved via `roles_path` in `ansible.cfg`:

```
roles_path = ./roles:~/.ansible/roles:/usr/share/ansible/roles:/etc/ansible/roles
```

All roles live in this directory. Playbooks reference them by name (e.g., `role: common_system`).
