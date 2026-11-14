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

> TL;DR: the laptop resolves the host list from live Terraform state,
> naming hosts by their real hostname and grouping them by Proxmox tags.
> Semaphore reads a committed snapshot of the same hosts.

### The dynamic inventory script

Semaphore reads the same hosts from the committed
[`inventory/hosts.snapshot.json`](../ansible/inventory/hosts.snapshot.json)
(`INVENTORY_SOURCE=snapshot`), so it needs no R2 credentials or terragrunt.
Re-render it with `make -C ansible semaphore-files` after a host is added,
removed, re-IP'd or re-tagged; `make -C ansible inventory-doctor` fails while
it is stale. Wave groups are built from `group_vars/all/patching.yml` in both
modes.

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
unwraps that nesting and emits real names (`komodo`, `pihole-1`, …) so
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
hosts: filtering          # Pi-hole hosts (tag: filtering)
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
  stack's `[[SECRET]]` placeholders to `kv_<service>` fields from Vault, which the
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
| **Secret** (host-local) | Each periphery's `[secrets]` block, rendered by [`komodo_periphery`](../ansible/roles/komodo_periphery) from Ansible Vault → `host_vars/<svc>.yml`. Never stored in Komodo Core. | `[[BW_DB_PASSWORD]]`, `[[GITLAB_RUNNER_TOKEN]]` | Vaultwarden DB password, runner token |

Both look the same in the stack's `environment = """ … """` block —
`MY_THING = [[MY_THING]]`. Komodo Core resolves `[[NAME]]` first against
its own Variables, then asks the destination periphery agent to fill in
anything still unresolved from its local `[secrets]`.

### The flow for a real secret

```text
   1. HashiCorp Vault                2. host_vars/<svc>.yml
   kv/proxmox-infra/bitwarden        inventory/host_vars/bitwarden.yml
   ─ db_password ───────────────►   komodo_periphery_secrets:
     (read by kv_bitwarden in          BW_DB_PASSWORD:
      group_vars/all/secrets.yml)       "{{ kv_bitwarden.db_password }}"
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

The value exists at rest in Vault and, rendered, in
`/etc/komodo/periphery.config.toml` on the destination host (mode 0600,
root-owned). The container gets it as an env var at runtime. Komodo stacks
never call Vault: a sealed Vault blocks re-rendering a config, not the
running services.

### Where secrets come from

[`group_vars/all/secrets.yml`](../ansible/inventory/group_vars/all/secrets.yml)
defines one dict per KV path, `kv_<service>` for
`kv/proxmox-infra/<service>`; the Talos inventory has its own
[`secrets.yml`](../ansible/inventory/talos/group_vars/all/secrets.yml) with
`kv_talos`. Each is a `community.hashi_vault` lookup that runs only when a
play uses it. The `kv_` prefix keeps them apart from role parameters such as
`komodo_core_secrets`. Logins, the `hvac` requirement and the macOS
fork-safety setting are in [VAULT.md](VAULT.md#ansible).

```bash
vault login -method=userpass username=<you>      # once per 8 h
vault kv get -mount=kv proxmox-infra/bitwarden    # prints the values; -field=<f> for one
```

The Ansible vault, `ansible/inventory/group_vars/all/vault.yml`, holds only
the bootstrap tier: what is needed to reach Vault, or while it is sealed.

| Key | Why it stays |
| --- | --- |
| `vault_cloudflare_dns_token` | the Vault certificate must renew while Vault is sealed |
| `vault_hashicorp_vault_snapshot_secret_id` | the snapshot timer's login to Vault |
| `vault_semaphore_vault_secret_id` | Semaphore's login to Vault (AppRole `semaphore`) |
| `vault_semaphore_ansible_vault_password` | Semaphore decrypts this file |

```bash
make -C ansible vault-edit     # decrypts, opens $EDITOR, re-encrypts on save
make -C ansible vault-view
make -C ansible vault-check    # CI guard: still encrypted
```

### Adding a new secret — the 4-step recipe

Use this any time a service needs a new `[[SECRET]]`:

```bash
# 1. Store it in Vault. patch adds a field to an existing path; put creates
#    a new path. "-" reads the value from stdin, so it stays off the command
#    line and out of the shell history.
vault kv patch -mount=kv proxmox-infra/myapp db_password=-
#    A new path also gets its dict in group_vars/all/secrets.yml:
#      kv_myapp: "{{ lookup('community.hashi_vault.vault_kv2_get', 'proxmox-infra/myapp').secret }}"

# 2. Map it into the host's komodo_periphery_secrets in
#    ansible/inventory/host_vars/<svc>.yml:
#      komodo_periphery_secrets:
#        DB_PASSWORD: "{{ kv_myapp.db_password }}"

# 3. Re-render the host's periphery config (/etc/komodo/periphery.config.toml)
#    and restart Periphery if it changed. Only the Periphery config tasks run:
#    no Docker or system roles, no dist-upgrade.
make -C ansible periphery-secrets HOST=<svc>

# 4. Reference it from the stack's environment block in komodo/stacks.toml:
#      environment = """
#      DB_PASSWORD = [[DB_PASSWORD]]
#      """
```

Push the `host_vars/<svc>.yml` + `stacks.toml` changes. GitOps Apply's
sync sees the changed stack `environment` and redeploys the stack with the
new secret.

**Changing an existing secret's value** is steps 1 and 3 only. The stack
still says `[[NAME]]`, so the sync sees no change and redeploys nothing.
Deploy it explicitly:

```bash
make -C ansible periphery-secrets HOST=<svc>
make komodo-deploy STACK=<stack>     # fails if the deploy fails
```

### Secret index by KV path

Every path under `kv/proxmox-infra/` and where each field is consumed. Use
it to audit what Vault holds and to spot fields that became dead when a
service was retired.

#### Service stacks

##### bitwarden ([`host_vars/bitwarden.yml`](../ansible/inventory/host_vars/bitwarden.yml))

| Field | Stack env (`[[NAME]]`) | Notes |
| --- | --- | --- |
| `db_password` | `BW_DB_PASSWORD` | Postgres password |
| `installation_id` | `BW_INSTALLATION_ID` | Bitwarden install ID |
| `installation_key` | `BW_INSTALLATION_KEY` | Bitwarden install key |
| `r2_access_key_id` | `BACKUP_R2_ACCESS_KEY` | Offsite backup creds (R2) |
| `r2_secret_access_key` | `BACKUP_R2_SECRET_KEY` | Offsite backup creds (R2) |

##### gitlab ([`host_vars/gitlab.yml`](../ansible/inventory/host_vars/gitlab.yml))

| Field | Stack env (`[[NAME]]`) | Notes |
| --- | --- | --- |
| `root_password` | `GITLAB_ROOT_PASSWORD` | First-boot root password seed |

(Instance config — `external_url`, SSH port, memory tuning — is non-secret and
lives in `services/gitlab/omnibus_config.rb`, loaded via `GITLAB_OMNIBUS_CONFIG
= from_file('/omnibus_config.rb')`.)

##### gitlab-runner ([`host_vars/gitlab-runner.yml`](../ansible/inventory/host_vars/gitlab-runner.yml))

| Field | Stack env (`[[NAME]]`) | Notes |
| --- | --- | --- |
| `runner_token` | `GITLAB_RUNNER_TOKEN` | Runner authentication token (glrt-…) from the GitLab UI |

(`CI_SERVER_URL` is non-secret → `komodo/stacks.toml`.)

##### paperless ([`host_vars/paperless-ngx.yml`](../ansible/inventory/host_vars/paperless-ngx.yml))

| Field | Stack env | Notes |
| --- | --- | --- |
| `postgres_password` | `POSTGRES_PASSWORD` | DB password |
| `secret_key` | `PAPERLESS_SECRET_KEY` | Django session signing |
| `admin_password` | `PAPERLESS_ADMIN_PASSWORD` | Web UI admin |

##### semaphore ([`host_vars/semaphore.yml`](../ansible/inventory/host_vars/semaphore.yml))

| Field | Stack env | Notes |
| --- | --- | --- |
| `admin_password` | `SEMAPHORE_ADMIN_PASSWORD` | Web UI admin |
| `api_token` | — | the `maintainer` API token for `semaphore-bootstrap` and `semaphore-doctor` |
| `pve_api_token_id` | `SEMAPHORE_PVE_API_TOKEN_ID` | `user@realm!name` |
| `pve_api_token_secret` | `SEMAPHORE_PVE_API_TOKEN_SECRET` | Snapshot auth |
| `oidc_client_secret` | `SEMAPHORE_OIDC_CLIENT_SECRET` | Authentik OIDC; copy of `SEMAPHORE_CLIENT_SECRET` |

Two more Periphery secrets come from the bootstrap tier above:
`SEMAPHORE_ANSIBLE_VAULT_PASSWORD` and `SEMAPHORE_VAULT_SECRET_ID`. The
compose file passes the SecretID as `ANSIBLE_HASHI_VAULT_SECRET_ID` and lists
it in `SEMAPHORE_FORWARDED_ENV_VARS`: Semaphore hands a run only the
variables named there. The RoleID and `ANSIBLE_HASHI_VAULT_AUTH_METHOD`
are in the environments of
[`configs/semaphore.yml`](../ansible/configs/semaphore.yml).
`SEMAPHORE_PVE_API_URL` and the admin username, name and email are
non-secret → `komodo/stacks.toml`.

Semaphore runs this repo's playbooks from a committed host snapshot, so it
carries no R2 credentials. The PVE trio is meant for pre-patch snapshots.
Its templates ([`configs/semaphore.yml`](../ansible/configs/semaphore.yml),
applied by `make -C ansible semaphore-bootstrap`), named `<scope>: <action>`:
Hosts: Verify, Hosts: Patch (one wave), Hosts: Authorized Keys, Hosts:
Configure (one wave), Pi-hole: Reset and Talos: etcd Backup (scheduled nightly
at 02:00 Europe/Berlin). The backup authenticates with a restricted
talosconfig, `kv/proxmox-infra/talos` `etcd_backup_talosconfig`
(os:etcd:backup). Terraform, Talos upgrades and config
changes, bootstrap of a new host and the Komodo installs stay on the laptop:
they need credentials and tools the runner deliberately does not carry.

##### technitium ([`host_vars/technitium-1.yml`](../ansible/inventory/host_vars/technitium-1.yml), [`host_vars/technitium-2.yml`](../ansible/inventory/host_vars/technitium-2.yml))

| Field | Stack env | Notes |
| --- | --- | --- |
| `admin_password` | `DNS_SERVER_ADMIN_PASSWORD` | Shared across the HA pair |
| `api_token` | — | `technitium-bootstrap` and `technitium-doctor` |

#### komodo-core

Komodo Core (deployed by [`roles/komodo_core`](../ansible/roles/komodo_core) on
the `komodo` LXC) reads these, rendered into `/srv/komodo/compose.env` and
`core.config.toml` (git provider, `[secrets]`) on that host:

| Field | Used for |
| --- | --- |
| `webhook_secret` | GitLab `/listener` webhook HMAC |
| `jwt_secret` | Komodo Core JWT signing |
| `db_username`, `db_password` | FerretDB v2 credentials |
| `admin_password` | First-boot admin seed (see [`KOMODO.md`](#komodo--operator-runbook) on rotation) |
| `gitlab_token` | GitLab homelab-group access token (komodo, read_repository) — ResourceSync clones `example-org/proxmox-infra` |
| `ntfy_token` | ntfy `komodo` token (argo-apps `ntfy-secret`, key `komodo_token`); the role derives the alerter's `NTFY_KOMODO_AUTH` Core secret from it |

Core's PKI public key is not a secret: `komodo_core_public_key` in
[`group_vars/all/vars.yml`](../ansible/inventory/group_vars/all/vars.yml),
copied verbatim into each periphery's `core_public_keys`.

#### pihole

`pihole-1` and `pihole-2` share `web_password`, the web admin password,
passed as `WEB_PASSWORD` through `komodo_periphery_secrets`. The app
password for `pihole-doctor` and the MCP tools is set per node in the web UI
and kept as `app_passwords` (node -> password).

#### pbs

`api_token_id` (`infra@pbs!config`) and `api_token_secret` authenticate
[`scripts/pbs_bootstrap.py`](../ansible/scripts/pbs_bootstrap.py), which
converges the PBS datastores, namespaces and prune, verify and sync jobs on
[`configs/pbs.yml`](../ansible/configs/pbs.yml). The token and its user have
`DatastoreAdmin` on `/datastore` and `Audit` on `/`. PBS sits on the storage
VLAN, so run it from the admin network:
`make -C ansible pbs-bootstrap ARGS=--dry-run`, then `pbs-bootstrap`, and
`pbs-doctor` to check for drift.

#### monitoring

`loki_push_password`: the `monitoring_agent` role's Alloy pushes logs to
`loki.example.com` with it (Traefik basic auth in argo-apps).

#### talos

The Talos inventory's `kv_talos`:

| Field | Used for |
| --- | --- |
| `proxmox_api_user`, `proxmox_api_token_id`, `proxmox_api_token_secret` | starting the Talos VMs through the Proxmox API (`02-apply-configs`, `11-startup`) |
| `dockerhub_username`, `dockerhub_password` | containerd registry auth on every node (`talos/patches/common.yaml.j2`) |
| `etcd_backup_talosconfig` | the os:etcd:backup talosconfig of `etcd-backup.yml`; renew with `make -C ansible/talos restricted-configs` |

#### HashiCorp Vault host

`vault_cloudflare_dns_token` (Ansible vault): Cloudflare API token,
Zone:Read and DNS:Edit on `example.com` only. The `hashicorp_vault` role
writes it to `/etc/lego/cloudflare.env` on the `vault` LXC for the Let's
Encrypt DNS-01 challenge (`make -C ansible hashicorp-vault`). See
[VAULT.md](VAULT.md).

`vault_hashicorp_vault_snapshot_secret_id` (Ansible vault): SecretID of the
`raft-snapshot` AppRole, written to `/etc/vault-snapshot/approle.json` for
the nightly Raft snapshot. Issue a new one with
`vault write -f -field=secret_id auth/approle/role/raft-snapshot/secret-id`.

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

> Web UI: <https://komodo.example.com> (no edge auth middleware — Komodo has
> its own built-in login). The GitLab webhook posts straight to `/listener`.

### Deploy Komodo Core on a fresh komodo host

Assumes the LXC has been provisioned by Terraform and bootstrapped
(`make -C ansible bootstrap-host HOST=komodo` →
`configure-host HOST=komodo`).

```bash
# 1. Confirm the Komodo Core secrets exist (field names only)
vault kv get -format=json -mount=kv proxmox-infra/komodo-core | jq -r '.data.data | keys[]'
# expected: admin_password db_password db_username gitlab_token jwt_secret ntfy_token webhook_secret

# 2. Deploy Core (renders /srv/komodo/{docker-compose.yml,.env}, brings the stack up)
make -C ansible deploy-komodo-core

# 3. One-time: capture Core's PKI public key; set it as komodo_core_public_key
#    in ansible/inventory/group_vars/all/vars.yml and commit it (not a secret)
ssh komodo 'sudo docker exec komodo-core-1 cat /config/keys/core.pub'
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
   - `core_public_keys = ["<komodo_core_public_key>"]` — the PKI
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
# 1. Recapture it and update komodo_core_public_key in group_vars/all/vars.yml
ssh komodo 'sudo docker exec komodo-core-1 cat /config/keys/core.pub'

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
`kv/proxmox-infra/komodo-core` `gitlab_token`), and the server appears in the UI as
"healthy" once the Periphery agent responds.

### GitLab webhook (exactly one)

The `example-org/proxmox-infra` repo has **one** webhook: content-type
`application/json`, the `gitlab` listener (Komodo compares GitLab's
`X-Gitlab-Token` header with its webhook secret), Secret token =
`kv/ci/komodo` `webhook_secret`, trigger = **push events**, branch filter
`main`.

| Purpose | Payload URL |
| --- | --- |
| Sync, then deploy changed stacks | `https://komodo.example.com/listener/gitlab/procedure/<ID>/main` |

It targets the **GitOps Apply** Procedure
([`komodo/procedures.toml`](../komodo/procedures.toml)), whose first stage
runs the ResourceSync. There is no separate sync webhook: a second hook
would race the Procedure. The trailing path segment is the **branch**
(`main`), since Procedure listeners filter by branch. A new stack needs
**no** new webhook.

> **Use the Procedure ID, not its name, in the URL.** Copy it from the
> resource's Config → Webhooks panel in the UI. A rename in the sync is
> delete+create, which gives the Procedure a new ID, so update the webhook
> after renaming it. Names work too, URL-encoded (`GitOps%20Apply`).

### Rotate the Komodo admin password

> **Caveat**: `KOMODO_INIT_ADMIN_USERNAME` / `KOMODO_INIT_ADMIN_PASSWORD`
> are **first-boot only**. They create the initial admin user when the
> Mongo/Ferret store is empty; on subsequent boots they're ignored.

To actually rotate the live admin password:

1. Change it in the UI: <https://komodo.example.com> → top-right user
   menu → Settings → Change password.
2. Update Vault to match, so a future from-scratch redeploy uses the new
   value (it reads the password from stdin):

   ```bash
   vault kv patch -mount=kv proxmox-infra/komodo-core admin_password=-
   ```

3. Re-render `/srv/komodo/compose.env` on the host so the on-disk env matches
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
ssh <host> 'sudo systemctl restart periphery'
ssh <host> 'sudo journalctl -u periphery -f'  # follow logs
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
disconnected; `ssh <host> 'systemctl status periphery'` shows the
service running.

**Causes (in order of frequency):**

1. **Wrong `core_public_keys` form.** Komodo Periphery expects the
   bare base64 (one line, no PEM wrapper). If `komodo_core_public_key`
   was pasted with `-----BEGIN PUBLIC KEY-----` headers, the handshake
   rejects every Core request.

   **Fix:** re-capture with `ssh komodo 'sudo docker exec komodo-core-1 cat /config/keys/core.pub'`,
   replace `komodo_core_public_key` in `group_vars/all/vars.yml`, then re-render the
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
# 1. Is the field populated in Vault? (field names only)
vault kv get -format=json -mount=kv proxmox-infra/<service> | jq -r '.data.data | keys[]'

# 2. Is host_vars/<svc>.yml mapping it under komodo_periphery_secrets?
grep -A2 komodo_periphery_secrets ansible/inventory/host_vars/<svc>.yml

# 3. Is the rendered config on the host complete?
ssh <svc> 'sudo grep <key-uppercase> /etc/komodo/periphery.config.toml'

# 4. Is the stack env referencing it correctly?
grep "<KEY>" komodo/stacks.toml
```

The 4-step recipe to add a new secret is in [`SECRETS.md`](#secrets).

#### `KOMODO_INIT_ADMIN_*` changes don't update the admin password

**Symptom:** rotated `admin_password` in `kv/proxmox-infra/komodo-core`, re-deployed Core,
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

1. **The stack lacks the `iac` tag** — with `match_tags = ["iac"]` the
   sync ignores an untagged resource without an error.
   `python3 scripts/komodo_lint.py --strict` catches it before the push.
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

Removing an `iac`-tagged `[[stack]]` from `komodo/stacks.toml` makes the
GitOps Apply sync delete the stack, and that runs `docker compose down` on
its host (verified on 2.3.4). If the service still runs afterwards:

**Causes:**

1. **The stack lacked the `iac` tag** — the sync ignores untagged
   resources, so it was never deleted. Check the stack in the UI.
2. **The sync stage failed** — the latest GitOps Apply run in
   `komodo_updates` shows the error; nothing after it ran.
3. **The stack was deleted outside the sync** (UI), which only removes the
   definition and leaves the compose project running.

**Fix:** tear it down on the host by **project name**:

```bash
ssh <host>
docker compose -p <stack-name> down --remove-orphans
# fallback if compose can't resolve it:
docker stop <container> && docker rm <container>
```

Either way, Komodo leaves the Periphery clone of the linked repo behind,
including the stack's `.env` with the interpolated secrets, plus its
images:

```bash
ssh <host> 'sudo rm -rf /etc/komodo/repos/proxmox-infra && docker image prune -f'
```

Add `-v` to the `down` only when the named volumes should go too (that
destroys data).

#### GitLab `/listener` returns 401

**Symptom:** GitLab webhook delivery log shows a 401 on
`https://komodo.example.com/listener/...`.

**First, localize the failure** — the 401 has two unrelated causes, and
the response body tells them apart. A quick unauthenticated probe from
any host:

```bash
curl -sS -o /dev/null -w "%{http_code}\n" \
  https://komodo.example.com/listener/gitlab/procedure/<procedure-id>/main
```

- **`405` (Method Not Allowed)** → the request reached **Komodo** (it
  only accepts POST). The auth-proxy bypass is working; the 401 is a
  **secret mismatch** (see cause 1).
- **`401` / a login redirect / HTML body** → the request was stopped by
  the **auth proxy** before reaching Komodo. The `/listener` bypass is
  broken (see cause 2).

**Cause 1 — webhook secret mismatch (most common).** Komodo rejects the
`X-Gitlab-Token` header. The GitLab webhook's **Secret token** must equal
`webhook_secret` in `kv/proxmox-infra/komodo-core`. Verify with a probe that
sends the stored value (read from stdin, so it never appears in the process
list):

```bash
URL=https://komodo.example.com/listener/gitlab/procedure/<procedure-id>/main
vault kv get -mount=kv -field=webhook_secret proxmox-infra/komodo-core \
  | sed 's/^/X-Gitlab-Token: /' \
  | curl -sS -X POST "$URL" -H @- -H 'Content-Type: application/json' \
      -H 'X-Gitlab-Event: Push Hook' -d '{"ref":"refs/heads/main"}' \
      -w '\n%{http_code}\n'
```

A `200` here proves the canonical secret is correct — so fix the value
in GitLab (repo → Settings → Webhooks → Secret) to match.

> **NOTE — a successful POST runs a real GitOps Apply.** It only acts on
> changed stacks, so it is safe as a probe, but it shows up in the run
> history.

**Cause 2 — edge routing not reaching Komodo.** `komodo.example.com` carries
**no auth middleware at all**: the whole host is a single catch-all route, so
`/listener` needs no special-case rule. If webhook POSTs fail before Komodo
sees them, the problem is the route itself, not an auth gate. The Traefik
IngressRoute lives in **argo-apps**, not this repo — confirm the
`komodo.example.com` IngressRoute exists on the `lan` entrypoint
(`10.140.0.60`), has no `middlewares:` block, and points at the Core service.
The name is LAN-only, so the caller (GitLab) must reach `10.140.0.60` directly;
it is never routed through the Cloudflare tunnel.

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

**Fix:** LXC hosts pull from Docker Hub anonymously: the `common_docker`
role's `/etc/docker/daemon.json` sets no credential helper and no registry
mirror, so the limit is per source IP. Wait for the window to reset, or
`docker login` on the host for a one-off. The Talos nodes authenticate
through containerd (`talos/patches/common.yaml.j2`, credentials in
`kv/proxmox-infra/talos`).

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
| [`ansible/Makefile`](../ansible/Makefile) | Single entry point: host lifecycle, Komodo, Molecule, inventory, vault, lint (`+ Makefile.d/` includes) |
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

### Role tests

| Target | What it does |
| --- | --- |
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
| `make -C ansible diagnostics [HOST=<h>]` | Dump diagnostic info |
| `make -C ansible restart-docker [HOST=<h>]` | Restart the Docker daemon |
| `make -C ansible monitoring-agent [HOST=<h>]` | Install node_exporter (9100), cAdvisor (9338) and Alloy (12345, logs to Loki) on every Docker host, or one host |
| `make -C ansible site TAGS=<group> [HOST=<h>]` | Run `site.yml` by tag group (`deployment`/`operations`/`lifecycle`) |

### Komodo

| Target | What it does |
| --- | --- |
| `make -C ansible deploy-komodo-core` | Provision/redeploy Komodo Core on the `komodo` host |
| `make -C ansible install-periphery [HOST=<h>]` | Provision the Komodo Periphery agent (all `docker:!komodo`, or one host) |
| `make -C ansible upgrade-komodo` | Upgrade Komodo Core only — skips the Docker/system dependency roles |
| `make -C ansible upgrade-periphery [HOST=<h>]` | Upgrade the Periphery agents only — skips the Docker/system dependency roles |
| `make -C ansible periphery-secrets HOST=<h>` | Re-render one host's Periphery config and `[secrets]`, restart Periphery if it changed — refuses without `HOST=` |
| `make komodo-deploy STACK=<s>` / `komodo-sync` / `komodo-run PROC="<p>"` | Run a Komodo deploy, the ResourceSync or a Procedure through `km` from the repo root; exits non-zero when Komodo reports a failure (`km` itself always exits 0) |

Use the `upgrade-*` targets for a Renovate version bump. Both Komodo roles
depend on `common_docker` (which pulls in `common_system`), so the provisioning
targets also reinstall Docker and run an apt `dist-upgrade` on every target
host — right for a new host, unwanted when only an image tag or binary release
moved. Renovate's `komodo` group bumps Core and Periphery in one MR; upgrade
Core first, since the agents connect to it.

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
