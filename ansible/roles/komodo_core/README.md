# Ansible Role: komodo_core

<!-- markdownlint-disable MD013 MD060 -->

Deploys [Komodo](https://komo.do) **Core** (UI/API, port 9120) + **FerretDB v2**
(Postgres-backed) as a docker-compose stack on the `komodo` LXC. Core is the
control plane that drives every host's Periphery agent to deploy stacks.

## Requirements

- Debian 13+ / Ubuntu 24.04+, root or sudo
- `community.docker` collection (in `requirements.yml`)
- Vault secrets set (see below)

## Dependencies

- `common_docker`

## Role Variables

| Variable                       | Description                              | Default                      |
| ------------------------------ | ---------------------------------------- | ---------------------------- |
| `komodo_core_image_tag`        | Komodo Core image tag                    | `2`                          |
| `komodo_core_ferretdb_image`   | FerretDB image                           | `ghcr.io/ferretdb/ferretdb:2`|
| `komodo_core_postgres_image`   | FerretDB Postgres/DocumentDB image       | `.../postgres-documentdb:17` |
| `komodo_core_dir`              | Compose + config dir                     | `/srv/komodo`                |
| `komodo_core_data_dir`        | Bind-mounted data (DB + keys)            | `/srv/komodo/data`           |
| `komodo_core_host`            | Browser URL (matches Traefik ingress)    | `https://komodo.example.com`  |
| `komodo_core_git_username`    | GitLab account Komodo clones repos as    | `komodo`                     |

## Required Vault keys

`vault_komodo_webhook_secret`, `vault_komodo_jwt_secret`,
`vault_komodo_db_password`, `vault_komodo_gitlab_token`
(and optionally `vault_komodo_db_username`).

## One-time handshake

After the first deploy, capture Core's generated public key and feed it to the
periphery role:

```bash
ssh komodo 'sudo docker exec komodo-core-1 cat /config/keys/core.pub'  # -> vault_komodo_core_public_key
ansible-playbook playbooks/lxc/10-komodo-periphery.yml --limit <host>
```

## Usage

```bash
ansible-playbook playbooks/lxc/09-komodo-core.yml --limit komodo
```
