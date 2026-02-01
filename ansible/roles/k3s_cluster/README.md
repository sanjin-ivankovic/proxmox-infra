# Ansible Role: k3s_cluster

This role installs and configures K3s (Lightweight Kubernetes) on your
cluster nodes.

## Requirements

- Ansible 2.9+
- Supported OS: Ubuntu/Debian (others may work with minor changes)

## Role Variables

<!-- markdownlint-disable MD013 MD034 MD052 -->

| Variable                  | Description                                            | Default/Example                                    |
| ------------------------- | ------------------------------------------------------ | -------------------------------------------------- |
| k3s_version               | Version of K3s to install                              | v1.32.4+k3s1                                       |
| k3s_channel               | K3s release channel                                    | stable                                             |
| k3s_install_script_url    | Installer script URL                                   | https://get.k3s.io                                 |
| k3s_token                 | Shared secret token for cluster (set in Ansible Vault) | ''                                                 |
| k3s_cluster_endpoint      | Endpoint for agents to join (control-plane IP)         | ''                                                 |
| k3s_datastore_endpoint    | External datastore endpoint (etcd/MySQL/Postgres)      | ''                                                 |
| k3s_datastore_cacert      | External datastore CA cert file (optional)             | ''                                                 |
| k3s_datastore_cert        | External datastore cert file (optional)                | ''                                                 |
| k3s_datastore_key         | External datastore key file (optional)                 | ''                                                 |
| k3s_enable_traefik        | Enable/disable Traefik                                 | false                                              |
| k3s_enable_servicelb      | Enable/disable servicelb                               | false                                              |
| k3s_enable_metrics_server | Enable/disable metrics-server                          | false                                              |
| k3s_server_extra_args     | Extra arguments for server                             | ''                                                 |
| k3s_agent_extra_args      | Extra arguments for agent                              | '--node-ip {{ ansible_host }}'                     |
| k3s_master_tls_san        | TLS SANs for master (comma-separated)                  | '{{ ansible_default_ipv4.address }},...'           |
| k3s_write_kubeconfig_mode | Kubeconfig file permissions                            | '0644'                                             |
| k3s_apiserver_host        | API server host (set from inventory)                   | '{{ hostvars[groups['master'][0]].ansible_host }}' |
| k3s_apiserver_port        | API server port                                        | 6443                                               |

<!-- markdownlint-enable MD013 MD034 MD052 -->

## Example Playbook

```text
- hosts: k3s_cluster
  become: true
  roles:
    - role: k3s_cluster
      vars:
        k3s_token: 'mysecrettoken123'
        k3s_cluster_endpoint: 'https://10.40.0.40:6443'
        k3s_enable_traefik: false
        k3s_enable_servicelb: false
        k3s_enable_metrics_server: false
        k3s_datastore_endpoint: 'etcd://10.0.0.1:2379,10.0.0.2:2379'
```

## Notes

- Set sensitive variables (like `k3s_token`) in Ansible Vault or group_vars.
- For external DB, set `k3s_datastore_endpoint` and related cert/key
  variables as needed.
- See `defaults/main.yml` for all available variables and their descriptions.

## License

MIT
