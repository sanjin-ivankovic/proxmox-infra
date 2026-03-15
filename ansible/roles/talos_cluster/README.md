# Talos Cluster Role

Ansible role for managing Talos Linux Kubernetes clusters via the Talos API.

## Description

This role provides minimal abstractions for Talos cluster operations.
Unlike traditional Ansible roles that use SSH-based modules, this role
wraps `talosctl` commands for API-driven cluster management.

## Requirements

- `talosctl` CLI installed on the control machine (Ansible host)
- Talos VMs booted with Talos ISO
- Network connectivity to Talos API port (50000)

## Role Variables

See `defaults/main.yml` for all available variables.

### Cluster Configuration

```text
talos_version: "v1.9.3"
kubernetes_version: "1.32.0"
cluster_name: "talos-homelab"
cluster_domain: "example.com"
```

### Network Configuration

```text
talos_control_plane_endpoint: "https://10.40.0.59:6443"  # VIP for HA
talos_api_port: 50000
talos_kubernetes_api_port: 6443
```

### Node Configuration

```text
talos_control_planes:
  - name: talos-cp-1
    ip: 10.40.0.60  # Individual CP IP (VIP is 10.40.0.59)
    hostname: talos-cp-1.example.com

talos_workers:
  - name: talos-worker-1
    ip: 10.40.0.70
    hostname: talos-worker-1.example.com
```

## Dependencies

None. This role is standalone and uses only Ansible core modules plus
`talosctl`.

## Example Playbook

```text
- name: Manage Talos cluster
  hosts: localhost
  gather_facts: false
  roles:
    - role: talos_cluster
      vars:
        talos_version: "v1.9.3"
        cluster_name: "my-talos-cluster"
```

## Role Tasks

The role provides tasks for:

- Validating `talosctl` installation
- Generating machine configurations
- Applying configurations via API
- Bootstrapping Kubernetes
- Health checks

## Key Differences from SSH-Based Roles

| Traditional Role                     | Talos Role                            |
| ------------------------------------ | ------------------------------------- |
| Uses `copy`, `template` modules      | Uses `command` module with `talosctl` |
| Requires `ansible_user` and SSH keys | No SSH - API only                     |
| Service management via `systemd`     | Immutable - no service management     |
| Package installation via `apt`/`yum` | No package management                 |
| File editing via `lineinfile`        | Declarative config push only          |

## License

MIT

## Author

Infrastructure Team
