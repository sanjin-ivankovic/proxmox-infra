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

## Required secrets

`kv/ci/komodo` (the `kv_komodo_webhook` lookup): `webhook_secret`, shared with
proxmox-infra's CI.

`kv/proxmox-infra/komodo-core` (the `kv_komodo_core` lookup): `jwt_secret`, `db_username`, `db_password`, `admin_password`, `gitlab_token`,
`ntfy_token`.

## One-time handshake

After the first deploy, capture Core's generated public key and feed it to the
periphery role:

```bash
ssh komodo 'sudo docker exec komodo-core-1 cat /config/keys/core.pub'  # -> komodo_core_public_key in group_vars/all/vars.yml
make -C ansible install-periphery HOST=<host>
```

## Usage

```bash
make -C ansible deploy-komodo-core
```
