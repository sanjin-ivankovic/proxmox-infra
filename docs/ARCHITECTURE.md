# Architecture

<!-- markdownlint-disable MD013 MD060 MD024 -->

This is the canonical "how the homelab actually works today" doc. The
per-component READMEs ([`komodo/`](../komodo/README.md),
[`services/`](../services/README.md),
[`ansible/`](../ansible/README.md),
[`terraform/`](../terraform/README.md)) describe their own internals;
this doc is the **hub** that explains how they fit together.

## Three-phase workflow

```text
Terraform  ──▶  Ansible  ──▶  Komodo
provisions     configures      deploys
LXCs + VMs     hosts           services
```

| Phase | What it does | Trigger |
| --- | --- | --- |
| [**1. Terraform**](#phase-1-terraform) | Provisions Proxmox LXCs + VMs; generates per-host SSH keys | Operator: `terragrunt apply` |
| [**2. Ansible**](#phase-2-ansible) | Bootstraps users + SSH, installs Docker, sets up Komodo agents | Operator: `make -C ansible bootstrap-host …`, `configure-host`, `install-periphery` |
| [**3. Komodo**](#phase-3-komodo) | Reconciles `komodo/*.toml` from git to running stacks | GitLab push → webhook → Komodo Core |

## Phase 1: Terraform

Three independent Terraform projects under [`terraform/`](../terraform/):

| Project | What it provisions | State |
| --- | --- | --- |
| [`lxc/`](../terraform/lxc/) | LXC containers (service hosts + the `komodo` control plane) | R2 (S3-compat) via Terragrunt |
| [`talos/`](../terraform/talos/) | The Talos Kubernetes cluster nodes | R2 (S3-compat) via Terragrunt |

Provider: [`bpg/proxmox`](https://registry.opentofu.org/providers/bpg/proxmox)
(OpenTofu via Terragrunt). Each project owns its own state file; a shared
`root.hcl` configures the backend, providers, and common locals.

**Outputs downstream uses:** per-host SSH keys at `~/.ssh/<hostname>_id_ed25519`
(written by a `terraform_data` local-exec in the module). Ansible's dynamic
inventory reads container IPs + tags directly from the Terraform state.

## Phase 2: Ansible

### Inventory (dynamic)

[`ansible/inventory/terraform_state_inventory.py`](../ansible/inventory/terraform_state_inventory.py)
is a Python script inventory that runs `terragrunt state pull` against the
3 TF projects and emits hosts **named by real hostname** (e.g. `komodo`,
`adguard-2`), grouped by Proxmox tags. **No generated YAML inventory
files**, no `make inventory-all` step — every Ansible command reads live
state.

```bash
make -C ansible inventory-graph    # human-readable group/host tree
make -C ansible inventory-list     # JSON dump (every host with vars)
```

### User model (maintainer / root)

The inventory sets `ansible_user: maintainer` (the steady-state user, post-
bootstrap). `ansible.cfg` defaults to `remote_user = maintainer`. **Bootstrap
is the one exception** — `playbooks/hosts/bootstrap.yml` sets
`ansible_user: root` as a play var (highest precedence, overrides the
inventory hostvar). After bootstrap, root SSH is disabled and every
subsequent play connects as `maintainer`.

### Role tree

```text
common_system  (base: APT updates, packages, timezone)
   └── common_users  (creates maintainer, copies SSH key)
   └── common_ssh    (hardens SSH, disables root)
   └── common_docker (Docker CE + compose plugin + /srv/docker layout)
         ├── komodo_core      (deploys Komodo Core + FerretDB on the komodo LXC)
         └── komodo_periphery (deploys the agent + [secrets] on every service host)
talos_cluster  (talosctl-driven; local-connection plays)
```

Roles, packaged as the [`homelab.proxmox`](../ansible/galaxy.yml) collection:
[`common_{system,users,ssh,docker}`](../ansible/roles/),
[`komodo_{core,periphery}`](../ansible/roles/),
[`talos_cluster`](../ansible/roles/talos_cluster/). (Podman and Landscape were
removed; K3s is archived.) The host lifecycle runs from
[`playbooks/site.yml`](../ansible/playbooks/site.yml) over a single uniform set
under [`playbooks/hosts/`](../ansible/playbooks/hosts/).

### Ansible Vault

Real secrets live in
[`ansible/inventory/group_vars/all/vault.yml`](../ansible/inventory/group_vars/all/)
(Ansible-Vault encrypted). `host_vars/<svc>.yml` references vault keys
into each host's Komodo periphery `[secrets]` block — see the
[Secrets model](#secrets-model) below and
[`ANSIBLE.md#secrets`](ANSIBLE.md#secrets) for the full
key index.

## Phase 3: Komodo

[Komodo](https://komo.do) deploys the docker-compose services. Two
components:

- **Core** (UI + API + FerretDB v2) on the dedicated `komodo` LXC
  (vmid 417, `10.40.0.17`). UI on `:9120`, fronted by Traefik at
  [`https://komodo.example.com`](https://komodo.example.com) behind the
  `pocket-id-auth` ForwardAuth middleware (Pocket ID via oauth2-proxy).
  Persisted Noise keypair in named volume `komodo_keys` mounted at
  `/config/keys`.
- **Periphery** agent on each service host (`:8120`). Receives
  Core-signed work over the Noise transport; runs `docker compose` locally.

### What deploys what

Source of truth lives in [`komodo/`](../komodo/) — see its
[README](../komodo/README.md) for the file model. The TOML files:

- **`repos.toml`** — the shared `[[repo]]` git source; every stack links
  it via `linked_repo` instead of repeating git fields inline.
- **`servers.toml`** — one `[[server]]` per Periphery (the agent address).
- **`variables.toml`** — shared non-secret pins (`TZ`, `APPDATA_DIR`,
  `REGISTRY_IMAGE`).
- **`stacks.toml`** — one `[[stack]]` per service: target server,
  `linked_repo = "proxmox-infra"`, compose path in
  [`services/<svc>/docker-compose.yml`](../services/), env block
  referencing `[[VARIABLE]]` and `[[SECRET]]`. No per-stack
  `deploy`/`webhook` — deploys run through the `Deploy On Push` Procedure
  (below).
- **`procedures.toml`** — deploy drivers: `Deploy On Push` (the
  single webhook-triggered `BatchDeployStackIfChanged`) and
  `Rollout DNS HA` (manual coordinated HA rollout).

### Deploy flow on push

Two independent webhooks fire per push — one reconciles resource
definitions, one deploys the stacks whose compose content changed. They
handle different things and must not race (see "Why two webhooks" below).

```text
git push to example-org/proxmox-infra
        │
        ├─────────────────────────────┐
        ▼                             ▼
GitLab webhook A              GitLab webhook B (ONE, repo-wide)
POST .../listener/github/     POST .../listener/github/procedure/
     sync/<sync-id>/sync           <procedure-id>/main
        │                             │
        ▼                             ▼
ResourceSync reconcile        Procedure: BatchDeployStackIfChanged "*"
- pulls repo on Core          - for each matched Stack, Periphery
- re-reads komodo/*.toml        pulls the repo on its host and
- updates Server / Stack /      diffs compose + config_files
  Variable / Procedure defs    - skips if unchanged; otherwise
- does NOT deploy stacks         `docker compose up -d`
```

(The `/listener` PathPrefix has its own higher-priority IngressRoute
that skips `pocket-id-auth` so the webhook hits Komodo unauthenticated.
The GitLab webhook secret lives in
[`vault_komodo_webhook_secret`](#secrets-model).)

### Why two webhooks

Komodo's ResourceSync diffs **resource definitions** in `komodo/*.toml`
— it does not deploy stacks (we don't set `deploy = true`; see the
trade-off note). The **deploy Procedure** handles the compose files: a
single `BatchDeployStackIfChanged` matches every Stack and, per stack,
clones/pulls the repo on the target host and diffs the compose file plus
any `config_files` against the last deploy — redeploying only what
changed. Adding a new service needs no new webhook; the `"*"` pattern
picks it up automatically.

> **Historical note.** An earlier design used one `/deploy` webhook
> **per stack** (~10 webhooks), on the belief that the per-stack webhook
> was "forced" because the sync can't see compose changes. That was a
> misconception: a git webhook fires on **every** push to the branch
> (Komodo filters by branch, never by path), so every per-stack listener
> fired on every push anyway — only `DeployStackIfChanged`'s content
> check kept the untouched stacks quiet. `BatchDeployStackIfChanged` runs
> that same check from a single webhook, so the per-stack fan-out bought
> nothing but bookkeeping. This is the maintainer-endorsed monorepo
> pattern (komodo issue #1433).

Trade-off: we deliberately don't use sync-driven deploy (`deploy = true`
on each stack). Komodo tracks a Stack against **repo HEAD, not its path**
(issue #1433), so `deploy = true` would mark *every* stack out-of-date on
*any* push and fan a deploy across all 9 hosts. The Procedure's per-stack
content check avoids that. The `after = [...]` HA-ordering field is only
honored by sync deploys, so it's unused; the `Rollout DNS HA` Procedure's
sequential stages provide coordinated HA rollout when you need it.

### CI: lint, build, sign

The repo's GitLab CI pipeline ([`.gitlab-ci.yml`](../.gitlab-ci.yml)) runs
on the homelab `gitlab-runner` LXC. It lints (native per-tool jobs), tests
(`pytest` for `.ci/scripts`), and builds + cosign-signs the custom Docker
images (pihole, unbound, unbound-recursive, dnscrypt-proxy). Deployment is
Komodo's job and runs independently of CI: a push triggers Komodo's own
webhooks (above), which neither gate nor block the pipeline.

## Secrets model

Two tiers, both surfaced to a stack via `[[NAME]]` interpolation:

| Tier | Where it lives | Who renders it | Examples |
| --- | --- | --- | --- |
| **Variable** (non-secret) | [`komodo/variables.toml`](../komodo/variables.toml), committed to git | Komodo Core (DB-stored) | `TZ`, `APPDATA_DIR`, `REGISTRY_IMAGE` |
| **Secret** (host-local) | Each periphery's `[secrets]` block in `/etc/komodo/periphery.config.toml` | Ansible (`komodo_periphery` role) from Vault → `host_vars/<svc>.yml` → periphery config. **Never in Komodo Core's DB.** | DB passwords, OIDC client secrets, API tokens |

The full per-service vault key index lives in
[`ANSIBLE.md#secrets`](ANSIBLE.md#secrets).

## See also

- [`komodo/README.md`](../komodo/README.md) — the Komodo resource model
  (servers, variables, stacks, resource-sync).
- [`services/README.md`](../services/README.md) — what lives in `services/`
  and how to add a new one.
- [`ANSIBLE.md#inventory`](ANSIBLE.md#inventory) — inventory
  script + groups + user model in depth.
- [`ANSIBLE.md#secrets`](ANSIBLE.md#secrets) — Vault →
  host_vars → periphery `[secrets]` flow + the full key index.
- [`ANSIBLE.md#komodo--operator-runbook`](ANSIBLE.md#komodo--operator-runbook) — task-oriented
  runbook (deploy Core, install periphery, key handshake, rotate admin).
- [`ANSIBLE.md#troubleshooting`](ANSIBLE.md#troubleshooting) —
  failure modes + fixes from real incidents.
- [`.archive/README.md`](../.archive/README.md) — index of everything retired.
