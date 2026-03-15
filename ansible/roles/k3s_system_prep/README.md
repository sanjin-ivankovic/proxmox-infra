# Ansible Role: k3s_system_prep

This role prepares all nodes in your Kubernetes/K3s cluster with essential
system configuration and packages.

## Purpose

- Installs required OS packages
- Installs Python/pip and Kubernetes Python client
- Disables swap (if configured)
- Loads and persists kernel modules
- Applies sysctl tuning for Kubernetes
- Configures networking and firewall

## Role Variables

<!-- markdownlint-disable MD013 MD052 MD060 -->

| Variable                                 | Description                             | Default/Example                                        |
| ---------------------------------------- | --------------------------------------- | ------------------------------------------------------ |
| system_prep_packages                     | List of required system packages        | [curl, iptables, iproute2, ca-certificates, conntrack] |
| system_prep_disable_swap                 | Whether to disable swap (boolean)       | true                                                   |
| system_prep_sysctl_settings              | List of sysctl settings (list of dicts) | See defaults/main.yml                                  |
| system_prep_configure_firewall           | Whether to configure firewall (boolean) | false                                                  |
| system_prep_firewall_allowed_tcp_ports   | List of allowed TCP ports for firewall  | [22, 6443, 10250, ...]                                 |
| system_prep_firewall_allowed_udp_ports   | List of allowed UDP ports for firewall  | [8472]                                                 |
| system_prep_python_pip_package           | Python pip package name                 | python3-pip                                            |
| system_prep_kubernetes_client_package    | Kubernetes Python client package        | kubernetes>=24.2.0                                     |
| system_prep_kubernetes_client_extra_args | Extra args for pip install              | --break-system-packages                                |

<!-- markdownlint-enable MD013 MD052 MD060 -->

## Example Playbook

```text
- hosts: all
  become: true
  roles:
    - role: k3s_system_prep
      vars:
        system_prep_disable_swap: true
        system_prep_configure_firewall: true
        system_prep_firewall_allowed_tcp_ports:
          - 22
          - 6443
          - 10250
```

## Notes

- See `defaults/main.yml` for all available variables and their descriptions.
- This role is intended to be used before installing K3s or Kubernetes.

## License

MIT
