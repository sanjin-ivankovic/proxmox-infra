# Ansible Role: komodo_periphery

<!-- markdownlint-disable MD013 MD060 -->

Installs the [Komodo](https://komo.do) **Periphery** agent (binary + systemd
unit) on a Docker host and renders `/etc/komodo/periphery.config.toml`. The
agent is what Komodo Core drives to deploy docker-compose stacks on this host.

## Requirements

- Debian 13+ / Ubuntu 24.04+, root or sudo
- Komodo Core reachable (its public key in `vault_komodo_core_public_key`)

## Dependencies

- `common_docker` (Docker Engine + compose plugin)

## Role Variables

| Variable                            | Description                                              | Default            |
| ----------------------------------- | ------------------------------------------------------- | ------------------ |
| `komodo_periphery_version`          | Release to install (pinned, e.g. `2.2.0`; or `latest`)  | `2.2.0`            |
| `komodo_periphery_root_dir`         | Agent root directory                                    | `/etc/komodo`      |
| `komodo_periphery_port`             | Inbound listener port                                   | `8120`             |
| `komodo_periphery_bind_ip`          | Listener bind address                                   | `[::]`             |
| `komodo_periphery_ssl_enabled`      | Serve over HTTPS                                         | `true`             |
| `komodo_periphery_allowed_ips`      | IPs allowed to connect (Core only)                      | `["10.40.0.14"]`   |
| `komodo_periphery_core_public_keys` | Core public key (v2 PKI) — from Vault                   | `vault_*`          |
| `komodo_periphery_secrets`          | Host-local `[secrets]` map exposed as `[[NAME]]`        | `{}`               |

## Secrets model

Real secrets live **only** on the host, in the `[secrets]` table — never sent to
Komodo Core. Set them per host from Vault:

```yaml
# host_vars/bitwarden.yml
komodo_periphery_secrets:
  BW_DB_PASSWORD: "{{ vault_bitwarden_db_password }}"
```

Reference them from a stack's env as `[[BW_DB_PASSWORD]]`. Non-secret pins
(image tags, `TZ`, paths) are Komodo Variables (`[[NAME]]`) declared in the
`komodo/` Resource-Sync TOML in the proxmox-infra repo.

## Usage

```bash
ansible-playbook playbooks/lxc/10-komodo-periphery.yml --limit adguard-2
```
