# Services

<!-- markdownlint-disable MD013 MD060 -->

This directory holds the `docker-compose.yml` for each service that runs
on a Proxmox LXC. Deployment is handled by [Komodo](https://komo.do) — the
**stack** that ties each compose file to its host + env lives in
[`komodo/stacks.toml`](../komodo/stacks.toml).

See [`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) for the full
deploy flow and the secrets model.

## Layout

```text
services/
├── adguard-1/           # AdGuard Home — filtering DNS (HA pair)
├── adguard-2/
├── technitium-1/        # Technitium — authoritative DNS (HA pair)
├── technitium-2/
├── bitwarden/           # Vaultwarden / Bitwarden self-host
├── hermes/              # Hermes agent (NousResearch) — Telegram gateway
├── paperless-ngx/       # Document management
├── patchmon/            # Patch management
├── semaphore/           # Semaphore (Ansible UI)
├── omni/                # Sidero Omni (Talos management plane)
├── gitlab/              # GitLab CE — Git forge (serves source.example.com)
├── gitlab-runner/       # GitLab CI runner (dedicated host)
└── _templates/
    ├── docker-compose.yml.example   # starter compose
    └── komodo-stack.toml.example    # starter [[stack]] entry
```

## Per-service convention

Only `docker-compose.yml` is **required** in each service directory. A
service's host placement and HA grouping live in
[`komodo/stacks.toml`](../komodo/stacks.toml) as the stack's `server`,
`file_paths`, and `after = [...]` fields.

`.env` files are not committed (gitignored). Real values come from one of
two places, depending on whether they're secret — see below.

## Env: `[[VARIABLE]]` vs `[[SECRET]]`

Both are referenced from the stack's `environment` block as `[[NAME]]`
interpolation, but they live in very different places:

| Tier | Where it lives | Example |
| --- | --- | --- |
| **Variable** (non-secret) | [`komodo/variables.toml`](../komodo/variables.toml) — committed to git | `[[TZ]]`, `[[APPDATA_DIR]]`, `[[REGISTRY_IMAGE]]` |
| **Secret** (host-local) | Each periphery's `[secrets]` block, rendered by [`ansible/roles/komodo_periphery`](../ansible/roles/komodo_periphery/) from Ansible Vault → `host_vars/<svc>.yml`. **Never** stored in Komodo Core. | `[[BW_DB_PASSWORD]]`, `[[OMNI_OIDC_CLIENT_SECRET]]` |

Full vault-key index + the "how to add a secret" recipe lives in
[`../docs/ANSIBLE.md#secrets`](../docs/ANSIBLE.md#secrets).

## Adding a new service

1. **Compose file** — `services/<name>/docker-compose.yml` (copy
   `_templates/docker-compose.yml.example`).
2. **Komodo Variables** (optional, only if you need new shared pins) —
   add `[[variable]]` entries to [`komodo/variables.toml`](../komodo/variables.toml).
3. **Secrets** (if the service has any) — add `vault_<name>_*` keys via
   `make -C ansible vault-edit`, then create
   [`ansible/inventory/host_vars/<name>.yml`](../ansible/inventory/host_vars/)
   mapping them into `komodo_periphery_secrets`.
4. **Komodo stack** — copy `_templates/komodo-stack.toml.example` into
   [`komodo/stacks.toml`](../komodo/stacks.toml), set `name`, `server`,
   `file_paths`, and the `environment` block. If the host is new, also
   add a `[[server]]` to [`komodo/servers.toml`](../komodo/servers.toml).
5. **Push.** The GitLab webhook triggers Komodo Core to re-read the
   TOML; if the host has a periphery installed, it deploys.

The full per-host setup sequence (provision LXC, install agent, etc.) is
in the top-level [`README.md`](../README.md) Quick Start.

## HA pairs

`adguard-1`/`adguard-2` and `technitium-1`/`technitium-2` use the Komodo
stack's `after = [...]` field for sequential rollout — when a deploy
ripples across both members, the second waits for the first to settle.
See the relevant `[[stack]]` entries in
[`komodo/stacks.toml`](../komodo/stacks.toml).
