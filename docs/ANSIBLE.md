# Ansible

Operational reference for the Ansible layer of proxmox-infra: host inventory,
secret management, the Komodo operator runbook, troubleshooting, and the Make
targets. Each section below was a standalone document under `ansible/docs/`;
they are consolidated here.

## Contents

- [Inventory](#inventory)
- [Secrets](#secrets)
- [Komodo — operator runbook](#komodo--operator-runbook)
- [Troubleshooting](#troubleshooting)
- [Makefile reference](#makefile-reference)

## Inventory

<!-- markdownlint-disable MD013 MD060 -->

How hosts come to exist in Ansible's view of this repo. Companion to
[`docs/ARCHITECTURE.md`](ARCHITECTURE.md) (Phase 2).

> TL;DR: there is **no committed inventory**. Every Ansible run resolves
> the host list dynamically by reading live Terraform state, naming hosts
> by their real hostname, and grouping them by Proxmox tags.

### The dynamic inventory script

`ansible/inventory/terraform_state_inventory.py` is wired as the
inventory in [`ansible.cfg`](../ansible/ansible.cfg):

```ini
[defaults]
inventory = ./inventory/terraform_state_inventory.py
```

What it does on every invocation:

1. **`terragrunt state pull`** for each Terraform project (`lxc`,
   `talos`) → JSON state from the Cloudflare R2 backend.
2. Walks the `bpg/proxmox` resources
   (`proxmox_virtual_environment_container`,
   `proxmox_virtual_environment_vm`) and emits one host per instance.
3. Sets per-host vars:
   - `ansible_host` — eth0 from the qemu-agent, falling back to the
     configured CIDR.
   - `ansible_user` — `maintainer` for Linux LXC/VM (steady-state).
     `ansible_connection: local` for Talos (talosctl-driven; no SSH).
   - `ansible_ssh_private_key_file: ~/.ssh/<hostname>_id_ed25519` — the
     per-host key Terraform generated.
   - `proxmox_tags` — list of Proxmox tags from state (renamed from
     `tags` because Ansible reserves that name).

This is a live script inventory, not a "generated inventory" pattern with a
custom generator and committed `all-hosts.yml` / `<project>-hosts.yml` files.
There is nothing to sync, nothing to commit, nothing to drift.

### Why a script, not `cloud.terraform.terraform_state`

`cloud.terraform.terraform_state` can only name hosts by a top-level
state attribute. For the `bpg/proxmox` provider, that means hostnames
come out as the bare `vm_id` (`110`, `417`, …) because the human-friendly
name lives in the nested `initialization.hostname` block. The script
unwraps that nesting and emits real names (`komodo`, `adguard-1`, …) so
`--limit komodo` and `make … HOST=komodo` work without translation.

### Groups

Groups are derived from Proxmox tags. Each tag becomes a group; hyphens
in tag names are converted to underscores because Ansible group names
can't contain hyphens (`dns-filtering` → group `dns_filtering`).

In addition to tag-derived groups, the script adds a per-project group:

| Project | Group |
| --- | --- |
| `terraform/lxc` | `lxc_containers` |
| `terraform/talos` | `talos_cluster` |

Inspect the current group graph:

```bash
make -C ansible inventory-graph     # human-readable tree
make -C ansible inventory-list      # full JSON dump with hostvars
```

Use groups in plays the usual way:

```yaml
hosts: docker:!komodo     # every host with the "docker" tag except komodo
hosts: dns_filtering      # AdGuard hosts (tag: dns-filtering)
hosts: lxc_containers     # every LXC, regardless of tag
```

### The maintainer/root connection-user model

There are two connection identities and we use **exactly one
playbook-time switch** to pick between them.

- **`maintainer`** — the steady-state user. Created by `common_users`,
  granted passwordless `sudo`, and used by every play except bootstrap.
  Set as `remote_user = maintainer` in `ansible.cfg`, and emitted as
  `ansible_user: maintainer` by the dynamic inventory for every Linux host.

- **`root`** — only for first-time bootstrap, before `maintainer` exists.
  [`playbooks/hosts/bootstrap.yml`](../ansible/playbooks/hosts/bootstrap.yml)
  sets `ansible_user: root` as a play var, which has higher precedence than
  the inventory hostvar, so it cleanly overrides the `maintainer` default just for
  the bootstrap play.

After bootstrap, `common_ssh` disables root SSH outright, so the only
plays that connect as root are the bootstrap ones, on a fresh host,
exactly once.

Talos hosts are different: `talos_cluster` is `ansible_connection: local`
because everything goes through `talosctl` / `kubectl` against the
cluster API — there is no SSH on a Talos node.

### Per-host vars (`host_vars/<host>.yml`)

`ansible/inventory/host_vars/<host>.yml` holds per-host overrides. Today
two patterns appear there:

- **Komodo periphery secrets** — `komodo_periphery_secrets:` maps the
  stack's `[[SECRET]]` placeholders to `vault_<svc>_*` keys, which the
  `komodo_periphery` role then renders into the host's
  `[secrets]` block. See [`SECRETS.md`](#secrets) for the full flow.

- **OS overrides** — e.g. semaphore is still on Debian 12, so its
  `host_vars/semaphore.yml` sets
  `common_system_debian_version_min: 12` to let `common_system` run.
  Drop the override once the host is upgraded.

Group_vars work the usual way too — `inventory/group_vars/all/vars.yml`
applies everywhere, `inventory/group_vars/all/vault.yml` is the
Ansible-Vault-encrypted secret store, and you can add
`group_vars/<group>.yml` for tag-derived groups.

### Inspecting the inventory

```bash
make -C ansible inventory-graph             # group → host tree
make -C ansible inventory-list              # JSON dump (every host + vars)
make -C ansible list-hosts                  # bare host list
ansible <host> -i ansible/inventory/terraform_state_inventory.py -m debug -a "var=hostvars[inventory_hostname]"
```

### What broke this, historically

| Symptom | Cause | Fix |
| --- | --- | --- |
| "Permission denied (publickey)" on bootstrap | Inventory says `ansible_user: maintainer` but maintainer doesn't exist yet | `bootstrap.yml` sets `ansible_user: root` as a play var, so `make bootstrap-host` connects as root automatically. |
| Hostnames show up as numbers (`110`, `417`) | You're running an older `cloud.terraform.terraform_state` config, not the script | Use `inventory/terraform_state_inventory.py` per current `ansible.cfg`. |
| `--limit <tag>` finds nothing | Tag has a hyphen; you used the hyphen form | Group names use underscores. `dns-filtering` → `dns_filtering`. |
| Inventory is empty for one project | `terragrunt state pull` failed (e.g. R2 creds, network) for that project | Check stderr from `ansible-inventory --list`; the script prints a `warn:` line per failed project and keeps going. |

### See also

- [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) — three-phase IaC overview
- [`ansible/README.md`](../ansible/README.md) — Ansible quick start
- [`SECRETS.md`](#secrets) — Vault + host_vars → periphery `[secrets]` flow
- [`MAKEFILES.md`](#makefile-reference) — every make target across the
  `ansible/Makefile` + per-project Makefiles

## Secrets

<!-- markdownlint-disable MD013 MD060 -->

How real secrets travel from your laptop to the docker containers on each
host. Single canonical doc — replaces the retired `ANSIBLE_VAULT.md` and
the per-service `VAULT_KEYS_KOMODO.md`.

> Nothing in this flow stores secrets in Komodo Core's database. Every
> secret is local to the periphery agent on the host that needs it.

### The two-tier model

| Tier | Where the value lives | Reference in stack | Example |
| --- | --- | --- | --- |
| **Variable** (non-secret) | [`komodo/variables.toml`](../komodo/variables.toml) — committed to git | `[[TZ]]`, `[[APPDATA_DIR]]` | Time zone, registry path, port |
| **Secret** (host-local) | Each periphery's `[secrets]` block, rendered by [`komodo_periphery`](../ansible/roles/komodo_periphery) from Ansible Vault → `host_vars/<svc>.yml`. Never stored in Komodo Core. | `[[BW_DB_PASSWORD]]`, `[[OMNI_OIDC_CLIENT_SECRET]]` | Vaultwarden DB password, OIDC client secret |

Both look the same in the stack's `environment = """ … """` block —
`MY_THING = [[MY_THING]]`. Komodo Core resolves `[[NAME]]` first against
its own Variables, then asks the destination periphery agent to fill in
anything still unresolved from its local `[secrets]`.

### The flow for a real secret

```text
   1. Ansible Vault                  2. host_vars/<svc>.yml
   inventory/group_vars/             inventory/host_vars/
     all/vault.yml                     bitwarden.yml
   ─ vault_bitwarden_db_password ─► komodo_periphery_secrets:
     "actual-secret-value"             BW_DB_PASSWORD:
                                        "{{ vault_bitwarden_db_password }}"
                                              │
                                              ▼
                          3. komodo_periphery role
                          renders /etc/komodo/periphery.config.toml
                                              │
                                              ▼
                                       [secrets]
                                       BW_DB_PASSWORD = "actual-secret-value"
                                              │
                                              ▼
                          4. komodo/stacks.toml on push
                          [[stack]] bitwarden
                          environment = """
                            BW_DB_PASSWORD = [[BW_DB_PASSWORD]]
                          """
                                              │
                                              ▼
                          5. docker compose up
                          container env: BW_DB_PASSWORD=actual-secret-value
```

The value only exists in three places at rest: encrypted in
`vault.yml` (committed), and rendered into
`/etc/komodo/periphery.config.toml` on the destination host (mode 0600,
root-owned). The compose container gets it as an env var at runtime.

### Vault operator workflow

The encrypted store is `ansible/inventory/group_vars/all/vault.yml`. The
vault password file path is in `ansible.cfg`
(`vault_password_file = ./.vault_pass`).

```bash
# Edit (decrypts, opens $EDITOR, re-encrypts on save)
make -C ansible vault-edit

# Read-only view
make -C ansible vault-view

# Verify it's actually encrypted (CI guard)
make -C ansible vault-check

# Rotate the vault password (every collaborator must pick up the new pass file)
make -C ansible vault-rekey
```

The full Make-target list is in [`MAKEFILES.md`](#makefile-reference).

### Adding a new secret — the 4-step recipe

Use this any time a service needs a new `[[SECRET]]`:

```bash
# 1. Add the value to the vault, keyed as vault_<svc>_<key>.
make -C ansible vault-edit
#   vault_myapp_db_password: "actual-secret-value"

# 2. Map it into the host's komodo_periphery_secrets in
#    ansible/inventory/host_vars/<svc>.yml:
#      komodo_periphery_secrets:
#        DB_PASSWORD: "{{ vault_myapp_db_password }}"

# 3. Re-render the host's periphery config (writes /etc/komodo/periphery.config.toml).
make -C ansible install-periphery HOST=<svc>

# 4. Reference it from the stack's environment block in komodo/stacks.toml:
#      environment = """
#      DB_PASSWORD = [[DB_PASSWORD]]
#      """
```

Push the `host_vars/<svc>.yml` + `stacks.toml` changes. Komodo Core
re-reads the TOML on push (via the GitLab `/listener` webhook); the next
deploy picks up the new secret.

### Per-service vault key index

The full set of `vault_*` keys in use today, and where each one is
consumed. Use this to audit "what's actually in the vault" and to spot
keys that became dead when a service was retired.

#### Service stacks

##### bitwarden ([`host_vars/bitwarden.yml`](../ansible/inventory/host_vars/bitwarden.yml))

| Vault key | Stack env (`[[NAME]]`) | Notes |
| --- | --- | --- |
| `vault_bitwarden_db_password` | `BW_DB_PASSWORD` | Postgres password |
| `vault_bitwarden_installation_id` | `BW_INSTALLATION_ID` | Bitwarden install ID |
| `vault_bitwarden_installation_key` | `BW_INSTALLATION_KEY` | Bitwarden install key |
| `vault_bitwarden_r2_access_key` | `BACKUP_R2_ACCESS_KEY` | Offsite backup creds (R2) |
| `vault_bitwarden_r2_secret_key` | `BACKUP_R2_SECRET_KEY` | Offsite backup creds (R2) |

##### gitlab ([`host_vars/gitlab.yml`](../ansible/inventory/host_vars/gitlab.yml))

| Vault key | Stack env (`[[NAME]]`) | Notes |
| --- | --- | --- |
| `vault_gitlab_root_password` | `GITLAB_ROOT_PASSWORD` | First-boot root password seed |

(Instance config — `external_url`, SSH port, memory tuning — is non-secret and
lives in `services/gitlab/omnibus_config.rb`, loaded via `GITLAB_OMNIBUS_CONFIG
= from_file('/omnibus_config.rb')`.)

##### gitlab-runner ([`host_vars/gitlab-runner.yml`](../ansible/inventory/host_vars/gitlab-runner.yml))

| Vault key | Stack env (`[[NAME]]`) | Notes |
| --- | --- | --- |
| `vault_gitlab_runner_token` | `GITLAB_RUNNER_TOKEN` | Runner authentication token (glrt-…) from the GitLab UI |

(`CI_SERVER_URL` is non-secret → `komodo/stacks.toml`.)

##### omni ([`host_vars/omni.yml`](../ansible/inventory/host_vars/omni.yml))

| Vault key | Stack env | Notes |
| --- | --- | --- |
| `vault_omni_oidc_client_secret` | `OMNI_OIDC_CLIENT_SECRET` | Pocket ID OIDC client secret (client `omni`) |

(Non-secret OIDC pins like `OMNI_OIDC_CLIENT_ID` live in
`komodo/variables.toml`, not here.)

##### paperless-ngx ([`host_vars/paperless-ngx.yml`](../ansible/inventory/host_vars/paperless-ngx.yml))

| Vault key | Stack env | Notes |
| --- | --- | --- |
| `vault_paperless_postgres_password` | `POSTGRES_PASSWORD` | DB password |
| `vault_paperless_secret_key` | `PAPERLESS_SECRET_KEY` | Django session signing |
| `vault_paperless_admin_password` | `PAPERLESS_ADMIN_PASSWORD` | Web UI admin |
| `vault_paperless_ai_api_token` | `PAPERLESS_AI_API_TOKEN` | paperless-ai shared token |
| `vault_paperless_custom_api_key` | `CUSTOM_API_KEY` | LiteLLM-proxy "custom" provider key |

##### patchmon ([`host_vars/patchmon.yml`](../ansible/inventory/host_vars/patchmon.yml))

| Vault key | Stack env | Notes |
| --- | --- | --- |
| `vault_patchmon_postgres_password` | `POSTGRES_PASSWORD` | DB password |
| `vault_patchmon_redis_password` | `REDIS_PASSWORD` | Redis password |
| `vault_patchmon_jwt_secret` | `JWT_SECRET` | JWT signing key |

##### semaphore ([`host_vars/semaphore.yml`](../ansible/inventory/host_vars/semaphore.yml))

| Vault key | Stack env | Notes |
| --- | --- | --- |
| `vault_semaphore_admin_password` | `SEMAPHORE_ADMIN_PASSWORD` | Web UI admin |

(Admin username / name / email are non-secret → `komodo/variables.toml`.)

##### technitium-1 / technitium-2 ([`host_vars/technitium-1.yml`](../ansible/inventory/host_vars/technitium-1.yml), [`host_vars/technitium-2.yml`](../ansible/inventory/host_vars/technitium-2.yml))

| Vault key | Stack env | Notes |
| --- | --- | --- |
| `vault_technitium_admin_password` | `DNS_SERVER_ADMIN_PASSWORD` | Shared across the HA pair |

#### Komodo Core's own vault keys

Komodo Core (deployed by [`roles/komodo_core`](../ansible/roles/komodo_core) on
the `komodo` LXC) has its own family of vault keys, rendered into
`/srv/komodo/.env` on that host:

| Vault key | Used for |
| --- | --- |
| `vault_komodo_webhook_secret` | GitLab `/listener` webhook HMAC |
| `vault_komodo_jwt_secret` | Komodo Core JWT signing |
| `vault_komodo_db_password` | FerretDB v2 password |
| `vault_komodo_admin_password` | First-boot admin seed (see [`KOMODO.md`](#komodo--operator-runbook) on rotation) |
| `vault_komodo_gitlab_token` | GitLab homelab-group access token (komodo, read_repository) — ResourceSync clones `example-org/proxmox-infra` |
| `vault_komodo_core_public_key` | Core's PKI public key — copied verbatim into each periphery's `core_public_keys` |

#### AdGuard (no secrets in the vault)

`adguard-1` and `adguard-2` carry their own per-instance admin password
inside the AdGuardHome.yaml stored on the host (mounted into the
container). Nothing goes through the vault for AdGuard.

### What's *not* in here, by design

- **Komodo Variables** (`komodo/variables.toml`) — non-secret pins like
  `TZ`, `APPDATA_DIR`, `REGISTRY_IMAGE`. Committed to git, fine.
- **Per-app `.env` files in `services/<svc>/`** — gitignored, never the
  source of truth. The render flow above is the source of truth.
- **The retired SealedSecrets** —
  `proxmox-infra-{deploy,hosts,env-<svc>}` are gone (the
  Argo-Workflows-driven deploy framework was retired). Archived under
  [`.archive/ci/argo-deploy-framework/`](../.archive/ci/argo-deploy-framework).

### See also

- [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) — §Secrets model
- [`KOMODO.md`](#komodo--operator-runbook) — operator runbook for Komodo Core +
  Periphery (incl. admin password rotation caveat)
- [`komodo/README.md`](../komodo/README.md) — the Komodo resource
  model (servers / variables / stacks)
- [`roles/komodo_periphery/README.md`](../ansible/roles/komodo_periphery) — the
  role that renders `[secrets]` into `periphery.config.toml`

## Komodo — operator runbook

<!-- markdownlint-disable MD013 MD060 -->

Task-oriented runbook for running Komodo (Core + Periphery) from
Ansible's side. Different audience from the two adjacent docs:

- [`komodo/README.md`](../komodo/README.md) — the **resource model**
  (`repos.toml`, `servers.toml`, `variables.toml`, `stacks.toml`, `procedures.toml`, `resource-sync.toml`).
- [`roles/komodo_core/README.md`](../ansible/roles/komodo_core), [`roles/komodo_periphery/README.md`](../ansible/roles/komodo_periphery) —
  the **roles**, in isolation.
- **This doc** — the things you do at 22:00 when something needs fixing.

> Web UI: <https://komodo.example.com> (behind Pocket ID via oauth2-proxy
> ForwardAuth). The GitLab webhook bypasses that gate at the `/listener` path.

### Deploy Komodo Core on a fresh komodo host

Assumes the LXC has been provisioned by Terraform and bootstrapped
(`make -C ansible bootstrap-host HOST=komodo` →
`configure-host HOST=komodo`).

```bash
# 1. Confirm the Komodo Core vault keys exist
make -C ansible vault-view | grep -E '^vault_komodo_(webhook_secret|jwt_secret|db_password|admin_password|gitlab_token):'
# expected lines: webhook_secret, jwt_secret, db_password, admin_password, gitlab_token

# 2. Deploy Core (renders /srv/komodo/{docker-compose.yml,.env}, brings the stack up)
make -C ansible deploy-komodo-core

# 3. One-time: capture Core's PKI public key, save into vault
ssh komodo 'sudo docker exec komodo-core-1 cat /config/keys/core.pub'
# → paste into vault as vault_komodo_core_public_key
make -C ansible vault-edit
```

The Noise keypair is persisted in the named docker volume `komodo_keys`
(mounted at `/config/keys`), so re-rendering the compose / restarting the
container does not regenerate it. That's important — the public key is
pinned in every periphery's `core_public_keys`.

### Install Periphery on a service host

```bash
make -C ansible install-periphery HOST=<service>
```

What this does:

1. Installs the Komodo Periphery binary + a systemd unit.
2. Renders `/etc/komodo/periphery.config.toml` from
   `host_vars/<service>.yml`, with:
   - `core_public_keys = ["<vault_komodo_core_public_key>"]` — the PKI
     trust anchor.
   - `allowed_ips = [...]` — only Komodo Core is allowed to dial in.
   - `[secrets]` — the host-local secret map (see
     [`SECRETS.md`](#secrets)).
3. Enables and starts the agent on `:8120`.

Bulk roll-out: `make -C ansible install-periphery` (no `HOST=`) runs against
`docker:!komodo` (every docker host except Komodo Core itself).

### The Core ↔ Periphery key handshake

Both directions are authenticated, but they're not symmetric.

| Direction | Who's the client | What's checked |
| --- | --- | --- |
| Core → Periphery | Core (dials in) | Periphery's `allowed_ips` includes Core's IP; Core signs requests with its private key in `/config/keys/core.key`. |
| Periphery → Core | Periphery (responds) | Periphery's `core_public_keys` includes the matching pubkey, so it accepts Core's signature. |

If you ever rotate Core's keypair, every Periphery needs the new pubkey
in its config. Two steps:

```bash
# 1. Recapture and re-vault
ssh komodo 'sudo docker exec komodo-core-1 cat /config/keys/core.pub'
make -C ansible vault-edit         # update vault_komodo_core_public_key

# 2. Re-render every periphery config
make -C ansible install-periphery
```

Common pitfall: the pubkey must be the **bare base64** form, not PEM.
The role accepts it verbatim — paste exactly what `cat /config/keys/core.pub`
emits.

### Add a new server to Komodo's worldview

After installing the periphery on a host, Komodo Core doesn't auto-find
it — it has to be declared in `komodo/servers.toml`. From the repo:

```ini
[[server]]
name = "myservice"
config = { address = "https://myservice.lan:8120", enabled = true }
```

Push. The GitLab webhook fires the `/listener`, Komodo Core re-reads
`komodo/*.toml` through its ResourceSync (clones with
`vault_komodo_gitlab_token`), and the server appears in the UI as
"healthy" once the Periphery agent responds.

### GitLab webhooks (exactly two)

The `example-org/proxmox-infra` repo needs **two** webhooks total — not one
per stack. Both point at Komodo Core's `/listener` (which bypasses the
oauth2-proxy/Pocket ID edge auth), use **content-type `application/json`**,
auth type **`github`** (GitLab sends a github-compatible webhook that
validates as GitHub-style), secret = `vault_komodo_webhook_secret`, trigger =
**push events**.

| # | Purpose | Payload URL |
| - | --- | --- |
| 1 | Reconcile resource defs | `https://komodo.example.com/listener/github/sync/proxmox-infra/sync` |
| 2 | Deploy changed stacks | `https://komodo.example.com/listener/github/procedure/<ID>/main` |

Webhook 2 targets the **Deploy On Push** Procedure
([`komodo/procedures.toml`](../komodo/procedures.toml)). Its trailing
path segment is the **branch** (`main`), since Procedure/Action listeners
filter by branch. It runs `BatchDeployStackIfChanged "*"`, so adding a
new stack needs **no** new webhook — the pattern picks it up.

> **Use the Procedure ID, not its name, in the URL.** Copy it from the
> resource's Config → Webhooks panel in the UI. Renaming a Procedure
> changes its name-based URL (and a sync rename is actually
> delete+create → new ID), so the ID-based URL is the stable choice. If
> you must use the name, URL-encode spaces (`Deploy%20On%20Push`).

### Rotate the Komodo admin password

> **Caveat**: `KOMODO_INIT_ADMIN_USERNAME` / `KOMODO_INIT_ADMIN_PASSWORD`
> are **first-boot only**. They create the initial admin user when the
> Mongo/Ferret store is empty; on subsequent boots they're ignored.

To actually rotate the live admin password:

1. Change it in the UI: <https://komodo.example.com> → top-right user
   menu → Settings → Change password.
2. Update the vault to match, so a future from-scratch redeploy uses
   the new value:

   ```bash
   make -C ansible vault-edit
   # vault_komodo_admin_password: "<new password>"
   ```

3. Re-render `/srv/komodo/.env` on the host so the on-disk env matches
   (idempotent if Core is up):

   ```bash
   make -C ansible deploy-komodo-core
   ```

### Make Komodo Core re-read the TOML right now

Komodo Core re-reads `komodo/*.toml` on GitLab `push` events through
`/listener`. To force a re-read without pushing:

- UI → Resource Syncs → `proxmox-infra` → **Refresh** (re-clones and
  re-evaluates).
- Or push an empty commit:
  `git commit --allow-empty -m "chore(komodo): force sync" && git push`.

### Restart the Periphery on a host

```bash
ssh <host> 'sudo systemctl restart komodo-periphery'
sudo journalctl -u komodo-periphery -f      # follow logs
```

Or re-render and bounce in one step (idempotent):

```bash
make -C ansible install-periphery HOST=<host>
```

### Inspect what the agent thinks its config is

```bash
ssh <host> 'sudo cat /etc/komodo/periphery.config.toml'
```

`[secrets]` is the section to check when a `[[NAME]]` in a stack is
arriving empty. The most common cause is a missing
`host_vars/<host>.yml` entry — see the recipe in
[`SECRETS.md`](#secrets).

### See also

- [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) — §Phase 3
- [`komodo/README.md`](../komodo/README.md) — TOML resource model
- [`SECRETS.md`](#secrets) — Vault → host_vars → periphery flow
- [`TROUBLESHOOTING.md`](#troubleshooting) — Komodo-related incidents
  - their fixes

## Troubleshooting

<!-- markdownlint-disable MD013 MD060 -->

Incident-derived failure → fix index. Each entry is a symptom (what you
actually see), a cause, and the fix that worked. Append new entries as
incidents surface — keep them specific.

### Ansible playbook failures

#### Permission denied (publickey) on bootstrap

**Symptom:**

```text
fatal: [<host>]: UNREACHABLE! => {"changed": false,
  "msg": "Failed to connect to the host via ssh:
  Permission denied (publickey)."}
```

**Cause:** the inventory says `ansible_user: maintainer`, but on a freshly
provisioned host `maintainer` doesn't exist yet — only `root` does.

**Fix:** the bootstrap playbook sets `ansible_user: root` as a play var, so
`make bootstrap-host HOST=<host>` connects as root automatically. If you invoke
`ansible-playbook` directly:

```bash
ansible-playbook -i ansible/inventory/terraform_state_inventory.py \
  ansible/playbooks/hosts/bootstrap.yml --limit <host>
```

The bootstrap play's `ansible_user: root` var has higher precedence than the
inventory hostvar.

#### "Debian 12 is below the minimum supported version"

**Symptom:** `common_system` fails on a single host with a version
guard like:

```text
"Debian 12 is below the minimum supported version (13)."
```

**Cause:** the host is still on a previous Debian major. The role's
default `common_system_debian_version_min: 13` rejects it.

**Fix:** drop a per-host override into `host_vars/<host>.yml`:

```yaml
common_system_debian_version_min: 12
```

Remove the override after upgrading the LXC OS to 13 (`do-release-upgrade`
inside the container, or rebuild). This pattern is already in place for
`semaphore` — see [`inventory/host_vars/semaphore.yml`](../ansible/inventory/host_vars/semaphore.yml).

#### `make -C ansible inventory-graph` returns an empty graph (or one project missing)

**Symptom:** the group tree is missing one of `lxc_containers`,
`talos_cluster`, or stderr shows
`warn: state pull failed for ../../terraform/<project>: …`.

**Cause:** `terragrunt state pull` failed for that project — typically
missing R2 credentials, an expired session, or a network blip.

**Fix:**

```bash
cd terraform/<project>
terragrunt init           # re-init the backend
terragrunt state pull >/dev/null   # confirm state pull works in isolation
```

Then re-run `make -C ansible inventory-graph`.

### Komodo

#### Periphery shows "Disconnected" / Core can't reach the agent

**Symptom:** `https://komodo.example.com` lists the server as
disconnected; `ssh <host> 'systemctl status komodo-periphery'` shows the
service running.

**Causes (in order of frequency):**

1. **Wrong `core_public_keys` form.** Komodo Periphery expects the
   bare base64 (one line, no PEM wrapper). If `vault_komodo_core_public_key`
   was pasted with `-----BEGIN PUBLIC KEY-----` headers, the handshake
   rejects every Core request.

   **Fix:** re-capture with `ssh komodo 'sudo docker exec komodo-core-1 cat /config/keys/core.pub'`,
   replace the value via `make -C ansible vault-edit`, then re-render the
   config: `make -C ansible install-periphery HOST=<host>`.

2. **`allowed_ips` doesn't include Core's address.** The role uses
   Komodo Core's host IP from inventory. If you've changed Core's IP
   (re-provisioned the `komodo` LXC), re-render every Periphery.

3. **Firewall on the host blocks `:8120`.** `ufw status` / `nft list ruleset`
   on the host.

#### `[[NAME]]` interpolation arrives empty in the container env

**Symptom:** a service comes up but a value that should be set is
empty (e.g. `BW_DB_PASSWORD=`).

**Cause:** `[[NAME]]` resolution fell through Komodo Variables AND the
destination periphery's `[secrets]`.

**Fix:** verify the chain:

```bash
# 1. Is the vault key actually populated?
make -C ansible vault-view | grep vault_<svc>_<key>

# 2. Is host_vars/<svc>.yml mapping it under komodo_periphery_secrets?
grep -A2 komodo_periphery_secrets ansible/inventory/host_vars/<svc>.yml

# 3. Is the rendered config on the host complete?
ssh <svc> 'sudo grep <key-uppercase> /etc/komodo/periphery.config.toml'

# 4. Is the stack env referencing it correctly?
grep "<KEY>" komodo/stacks.toml
```

The 4-step recipe to add a new secret is in [`SECRETS.md`](#secrets).

#### `KOMODO_INIT_ADMIN_*` changes don't update the admin password

**Symptom:** rotated `vault_komodo_admin_password`, re-deployed Core,
and the UI still rejects the new password.

**Cause:** `KOMODO_INIT_ADMIN_USERNAME` / `KOMODO_INIT_ADMIN_PASSWORD`
seed the admin user on **first boot only** — once the FerretDB has
records, they're ignored.

**Fix:** rotate in the UI (top-right user menu → Settings → Change
password), then update the vault to match so a from-scratch redeploy
still works. Full procedure in [`KOMODO.md`](#komodo--operator-runbook).

#### Komodo sync runs but creates nothing / "no changes" on push

**Symptom:** GitLab webhook fires, Komodo Core logs "ResourceSync
executed", but no stacks change state — even though
`komodo/stacks.toml` clearly changed.

**Causes:**

1. **`deploy = true` with zero peripheries reachable** — Komodo silently
   "deploys" against nothing. Confirm at least one server in
   `komodo/servers.toml` is healthy.
2. **TOML parse error in one of the three files** — the sync stops at
   the first parse error. UI → Resource Syncs → `proxmox-infra` shows
   the parse error on the most recent run; fix the offending TOML and
   re-push (or hit Refresh).

#### New resource file (e.g. `procedures.toml`) never appears

**Symptom:** you add a new TOML file (e.g. `komodo/procedures.toml`),
push, the sync runs green — but the new resources never show up and
there are **no pending changes** on Refresh.

**Cause:** the live sync's `resource_path` is stored in **Komodo's DB**
(set when the sync was created in the UI), not read from
`komodo/resource-sync.toml`. A ResourceSync **cannot manage its own
definition** — `resource-sync.toml` is deliberately excluded from its own
`resource_path` — so editing that file in git has **no effect** on which
files the running sync reads. It keeps reading only the paths it already
knows.

**Fix:** add the new file to the path list **in the UI**: Resource Syncs
→ `proxmox-infra` → Config → Source → **Resource Path** → add
`komodo/procedures.toml` → Save → Refresh. The new resources then show as
pending → Execute. (Symptom of the same root cause: a stale `synced:`
commit hash that won't advance — the sync isn't reading the file that
changed.)

#### Deleted a stack but the container keeps running

**Symptom:** you remove a `[[stack]]` from `komodo/stacks.toml` (and the
sync reconciles the deletion), but the service is **still running** on
its host — e.g. a retired exporter still answering on its old port long
after its stack was deleted.

**Cause:** deleting a Komodo Stack removes only the **resource
definition**. Komodo does **not** run `docker compose down` on delete —
the already-running compose project is simply no longer watched. Under
`restart: unless-stopped` it survives reboots, orphaned. Komodo even
cleans the cloned compose file from `/etc/komodo/stacks/<stack>/...`, so
the project lingers with no file backing it (`docker compose ls` still
lists it as `running`).

**Fix:** tear it down on the host by **project name** (works even with
the compose file gone):

```bash
ssh <host>
docker compose -p <stack-name> down --remove-orphans
# fallback if compose can't resolve it:
docker stop <container> && docker rm <container>
```

Verify: `docker ps -a | grep <name>` empty, `docker compose ls -a` no
longer lists it, and the service port no longer listens. If the stack
declared **named volumes** you want gone too, add `-v` to the `down`
(destroys data — only when truly retiring). **Retirement checklist:**
remove the `[[stack]]` → push/reconcile → then `compose down` on the
host. The git change alone never stops the container.

#### GitLab `/listener` returns 401

**Symptom:** GitLab webhook delivery log shows a 401 on
`https://komodo.example.com/listener/...`.

**First, localize the failure** — the 401 has two unrelated causes, and
the response body tells them apart. A quick unauthenticated probe from
any host:

```bash
curl -sS -o /dev/null -w "%{http_code}\n" \
  https://komodo.example.com/listener/github/procedure/<procedure-id>/main
```

- **`405` (Method Not Allowed)** → the request reached **Komodo** (it
  only accepts POST). The auth-proxy bypass is working; the 401 is a
  **secret mismatch** (see cause 1).
- **`401` / a login redirect / HTML body** → the request was stopped by
  the **auth proxy** before reaching Komodo. The `/listener` bypass is
  broken (see cause 2).

**Cause 1 — webhook secret mismatch (most common).** Komodo rejects the
HMAC signature. The GitLab webhook's **Secret** must equal
`vault_komodo_webhook_secret`. Verify with a signed probe:

```bash
SECRET=$(make -C ansible vault-view | sed -nE "s/^vault_komodo_webhook_secret: '(.+)'/\1/p")
URL=https://komodo.example.com/listener/github/procedure/<procedure-id>/main
BODY='{"ref":"refs/heads/main","repository":{"full_name":"example-org/proxmox-infra"}}'
SIG="sha256=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | sed 's/^.*= //')"
curl -sS -X POST "$URL" -H 'Content-Type: application/json' \
  -H 'X-GitHub-Event: push' -H "X-Hub-Signature-256: $SIG" \
  -d "$BODY" -w '\n%{http_code}\n'
```

A `200` here proves the canonical secret is correct — so fix the value
in GitLab (repo → Settings → Webhooks → Secret) to match. Do this for
**both** the `sync` and `Deploy On Push` webhooks.

> **NOTE — a successful POST to `Deploy On Push` triggers a real
> `BatchDeployStackIfChanged "*"`.** It only redeploys stacks whose
> compose content changed since the last deploy, so it's safe to run as
> a probe, but don't be surprised to see a deploy in the run history.

**Cause 2 — auth proxy eating `/listener`.** The edge proxy on
`komodo.example.com` is **oauth2-proxy backed by Pocket ID**. Its ForwardAuth
middleware must **skip** the `/listener` path so unauthenticated webhook
POSTs reach Komodo. The Traefik IngressRoute lives in **argo-apps**, not
this repo. Confirm the `komodo.example.com` IngressRoute attaches the
oauth2-proxy ForwardAuth middleware only to the UI routes, with a
higher-priority `/listener` route that has **no** auth middleware.

### Terraform / Terragrunt

#### State lock stuck

**Symptom:** `tofu plan` errors with `Error acquiring the state lock`.

**Fix:**

```bash
cd terraform/<project>
tofu force-unlock <LOCK_ID>
```

(Or wait it out if you know another operator is mid-apply.)

#### `tofu` "lockfile maintenance does nothing" — Renovate ignores it

**Symptom:** Renovate PRs never include a `.terraform.lock.hcl` bump,
even though new provider versions are out.

**Cause:** Renovate's `allowedPostUpgradeCommands` allowlist (set on the
Renovate runner, not in `renovate.json`) doesn't include the script that
regenerates the lock file.

**Fix:** see the [renovate-allowed-commands memory note][renovate-cmds]
for the env-var and the manual regen recipe:

```bash
cd terraform/<project>
make lock
```

[renovate-cmds]: ../../README.md

#### Plan shows drift on every run

**Symptom:** `tofu plan` reports the same diff over and over even
though nothing changes.

**Fix sequence:**

1. `make refresh` (or `tofu refresh`) and re-plan.
2. If still drifting, `make state-show RESOURCE=<addr>` to see the live
   attributes Terraform thinks it owns; reconcile by editing
   `instances/*.auto.tfvars` to match reality.
3. If the resource was created out-of-band, `state mv` / `state rm`
   then re-import (`make import-lxc HOSTNAME=<h> VMID=<v>` for LXC,
   the talos import helper for Talos nodes).

### Docker / common_docker

#### `/srv/docker` permissions break a new stack

**Symptom:** a freshly deployed stack fails on
`Permission denied: '/srv/docker/<service>/data'`.

**Cause:** the `common_docker` role creates `/srv/docker` owned by
`maintainer:maintainer`, but the container runs as a different UID/GID and
mounts a subdir directly.

**Fix:** add the per-service directory to your compose's pre-step or
use named docker volumes for state. Don't `chown -R` `/srv/docker`
wholesale — see [`roles/common_docker/README.md`](../ansible/roles/common_docker)
for the directory model.

#### Pulls hit Docker Hub rate limits

**Symptom:** stack deploy fails with
`toomanyrequests: You have reached your pull rate limit.`

**Fix:** the homelab uses authenticated Docker Hub pulls via the
`dockerhub-auth` Reflector pattern **in the cluster**. For LXC
periphery hosts, the analogous pattern is configured in
`/srv/docker/.daemon.json` by the `common_docker` role — confirm the
host has the credential helper set and that `~/.docker/config.json` has
the right auth entry. Rotate creds via the kryptos tool in **argo-apps**;
the registry-mirror entry in `daemon.json` is the failsafe.

### SSH housekeeping

#### "Host key verification failed" on a re-provisioned host

**Symptom:** Ansible UNREACHABLE with `Host key verification failed`.

**Fix:**

```bash
# Remove the stale key and trust the new one (per host IP):
ssh-keygen -R <ip>; ssh-keyscan -H <ip> >> ~/.ssh/known_hosts
```

### See also

- [`INVENTORY.md`](#inventory) — inventory + connection user model
- [`SECRETS.md`](#secrets) — secrets flow (the source of most
  "empty value" mysteries)
- [`KOMODO.md`](#komodo--operator-runbook) — Komodo operator runbook
- [`MAKEFILES.md`](#makefile-reference) — every Make target
- [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) — the canonical
  three-phase doc

## Makefile reference

<!-- markdownlint-disable MD013 MD060 -->

Every Make target across the Ansible side of this repo, grouped by what
you're trying to do. There are two Makefiles:

| Path | Scope |
| --- | --- |
| [`ansible/Makefile`](../ansible/Makefile) | Single entry point: collection, host lifecycle, Komodo, inventory, vault, lint (`+ Makefile.d/` includes) |
| [`ansible/talos/Makefile`](../ansible/talos/Makefile) | Talos cluster lifecycle (talosctl-driven) |

Invoke with `make -C ansible <target>` (don't `cd` first; the relative paths
inside the Makefiles assume the repo root is two levels up). Run
`make -C ansible help` for the full target list, or
`make -C ansible talos T=<target>` to reach a Talos sub-target.

### Inventory & connectivity

| Target | What it does |
| --- | --- |
| `make -C ansible inventory-graph` | Print the dynamic inventory as a group → host tree |
| `make -C ansible inventory-list` | JSON dump (every host with hostvars) |
| `make -C ansible list-hosts` | Bare host list |
| `make -C ansible ping` | `ansible all -m ping` across the live inventory |
| `make -C ansible gather-facts` | Run `setup` on every host |

See [`INVENTORY.md`](#inventory) for how the dynamic script works.

### Vault

| Target | What it does |
| --- | --- |
| `make -C ansible vault-edit` | Decrypt → open in `$EDITOR` → re-encrypt on save |
| `make -C ansible vault-view` | Read-only view of the decrypted vault |
| `make -C ansible vault-encrypt` / `vault-decrypt` | Manual encrypt/decrypt (rarely needed) |
| `make -C ansible vault-rekey` | Change the vault password |
| `make -C ansible vault-check` | CI guard — fails if `vault.yml` is plaintext |

Full secret flow is in [`SECRETS.md`](#secrets).

### Collection

| Target | What it does |
| --- | --- |
| `make -C ansible collection` | Build + install the `homelab.proxmox` collection into `./collections` |
| `make -C ansible collection-doc ROLE=<r>` | Render a role's `argument_specs` via `ansible-doc` |
| `make -C ansible molecule` | Run all Molecule scenarios (needs molecule + docker) |
| `make -C ansible molecule-scenario S=<s>` | Run one Molecule scenario |

### Host lifecycle (LXC)

> Steady-state user is `maintainer`. Bootstrap is the one play that connects as
> root (via the play's `ansible_user: root` var). All hosts are uniform Debian
> LXCs (and future VMs run Docker the same way). See [the inventory section](#inventory).

| Target | What it does |
| --- | --- |
| `make -C ansible bootstrap-host HOST=<h>` | Create maintainer + harden SSH on one host (connects as root) |
| `make -C ansible configure-host HOST=<h>` | Install Docker (if `docker`-tagged) + base config |
| `make -C ansible verify-host HOST=<h>` | Run the verify playbook on one host |
| `make -C ansible update-hosts [HOST=<h>]` | apt update + dist-upgrade |
| `make -C ansible diagnostics [HOST=<h>]` | Dump diagnostic info |
| `make -C ansible restart-docker [HOST=<h>]` | Restart the Docker daemon |
| `make -C ansible site TAGS=<group> [HOST=<h>]` | Run `site.yml` by tag group (`deployment`/`operations`/`lifecycle`) |

### Komodo

| Target | What it does |
| --- | --- |
| `make -C ansible deploy-komodo-core` | Deploy/redeploy Komodo Core on the `komodo` host |
| `make -C ansible install-periphery [HOST=<h>]` | Install the Komodo Periphery agent (all `docker:!komodo`, or one host) |

Operator playbook for these targets — [`KOMODO.md`](#komodo--operator-runbook).

### Talos

Talos is talosctl-driven (no SSH), so the targets look different — they
manage the Talos cluster lifecycle rather than per-host config.

| Target | What it does |
| --- | --- |
| `make -C ansible/talos deploy` / `deploy-full` | Generate configs → apply → bootstrap the cluster |
| `make -C ansible/talos generate-configs` | Render Talos machine configs |
| `make -C ansible/talos apply-configs` | Apply configs to nodes via the Talos API |
| `make -C ansible/talos bootstrap` / `bootstrap-only` | `talosctl bootstrap` the etcd cluster |
| `make -C ansible/talos configure-tiers` | Apply production workload scheduling labels + PriorityClasses |
| `make -C ansible/talos verify` / `health-check` | Talos cluster health |
| `make -C ansible/talos upgrade` | Rolling Talos OS upgrade |
| `make -C ansible/talos upgrade-k8s` | Kubernetes version upgrade (control plane + kubelets) |
| `make -C ansible/talos reboot` / `shutdown` / `startup` | Cluster-wide lifecycle |
| `make -C ansible/talos reset` | **Destructive** — reset nodes to maintenance mode |
| `make -C ansible/talos diagnostics` | Collect cluster diagnostics |
| `make -C ansible/talos ping-host HOST=<h>` / `test-talosctl` | Connectivity checks |
| `make -C ansible/talos run-tags PB=<deploy\|operate\|lifecycle> TAGS=<a,b,…>` | Run an orchestrator with custom tags |
| `make -C ansible/talos list-tags` | List tags across the deploy/operate/lifecycle orchestrators |

### Development & CI

| Target | What it does |
| --- | --- |
| `make -C ansible setup` | Install `pre-commit` hooks for the repo |
| `make -C ansible lint` | `ansible-lint playbooks/ roles/` (production profile) |
| `make -C ansible lint-strict` | Strict ansible-lint (no skips) |
| `make -C ansible yamllint` | Yamllint over the tree |
| `make -C ansible syntax-check` | `ansible-playbook --syntax-check` for every playbook |
| `make -C ansible clean` | Clear `.ansible_facts` + any stale generated inventory leftovers |
| `make -C ansible update-roles` | `ansible-galaxy install -r requirements.yml --force` (if requirements.yml exists) |

### See also

- [`INVENTORY.md`](#inventory) — what the inventory actually looks like
- [`SECRETS.md`](#secrets) — vault & periphery `[secrets]` flow
- [`KOMODO.md`](#komodo--operator-runbook) — Komodo Core + Periphery operator runbook
- [`TROUBLESHOOTING.md`](#troubleshooting) — common failures
- [Terraform Makefile reference](TERRAFORM.md) — the
  Terraform-side Makefile reference
