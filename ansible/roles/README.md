# Ansible Roles

<!-- markdownlint-disable MD013 MD060 -->

Roles for the proxmox-infra playbooks. Every role (except `talos_cluster`,
which is read-only checks) ships a `meta/argument_specs.yml`, so inputs are
type-validated at the start of execution.

## Role Index

| Role | Description | Depends on |
| --- | --- | --- |
| `common_system` | System packages, APT, timezone | — |
| `common_users` | Non-root user creation, sudo setup | `common_system` |
| `common_ssh` | SSH hardening (disable root, key-only) | — |
| `common_docker` | Docker CE installation and configuration | `common_system` |
| `komodo_core` | Komodo Core + FerretDB on the `komodo` LXC | `common_docker` |
| `komodo_periphery` | Komodo Periphery agent + per-host `[secrets]` | `common_docker` |
| `monitoring_agent` | node_exporter (9100) + cAdvisor (9338) for Prometheus, Alloy (12345) shipping logs to Loki; etcd backup age on semaphore | `common_docker` |
| `talos_cluster` | Talos read-only checks via talosctl (action dispatcher) | — |

Dependencies are declared in each role's `meta/main.yml`, so calling
`komodo_core` automatically pulls in `common_docker` → `common_system`.

The retired `common_podman`, `landscape_server`, `k3s_cluster`, and
`k3s_system_prep` roles were removed (podman/landscape are deprecated; k3s is
archived under [`.archive/ansible/k3s-on-proxmox/`](../../.archive/ansible/k3s-on-proxmox/),
replaced by `talos_cluster`).

## Role Resolution

Playbooks reference roles by bare name, resolved from this directory by
`roles_path` in `ansible.cfg`:

```ini
roles_path = ./roles:~/.ansible/roles:/usr/share/ansible/roles:/etc/ansible/roles
```

## Argument validation

Each role's inputs are documented and validated in `meta/argument_specs.yml`.
Render a role's interface with:

```bash
ansible-doc -t role -r roles common_ssh   # from ansible/
```
