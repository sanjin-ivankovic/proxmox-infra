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
`root.hcl` configures the backend, providers, and common locals. State is
locked with OpenTofu's S3-native lockfile (`<key>.tflock` in the bucket),
so a laptop apply and a Semaphore state read cannot overlap.

**Outputs downstream uses:** per-host SSH keys at `~/.ssh/<hostname>_id_ed25519`
(written by a `terraform_data` local-exec in the module). Ansible's dynamic
inventory reads container IPs + tags directly from the Terraform state.

## Phase 2: Ansible

### Inventory (dynamic)

[`ansible/inventory/terraform_state_inventory.py`](../ansible/inventory/terraform_state_inventory.py)
is a Python script inventory that runs `terragrunt state pull` against the
3 TF projects and emits hosts **named by real hostname** (e.g. `komodo`,
`pihole-2`), grouped by Proxmox tags. Laptop runs read live state.
Semaphore reads the committed `inventory/hosts.snapshot.json` the same
script renders (`make -C ansible semaphore-files`), so it holds no R2
credentials.

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
common_system  (base: APT cache, packages, timezone)
   └── common_users  (creates maintainer, copies SSH key)
   └── common_ssh    (hardens SSH, disables root)
   └── common_docker (Docker CE + compose plugin + /srv/docker layout)
         ├── komodo_core      (deploys Komodo Core + FerretDB on the komodo LXC)
         └── komodo_periphery (deploys the agent + [secrets] on every service host)
talos_cluster  (talosctl-driven; local-connection plays)
```

Roles in [`ansible/roles/`](../ansible/roles/), called by bare name:
[`common_{system,users,ssh,docker}`](../ansible/roles/),
[`komodo_{core,periphery}`](../ansible/roles/),
[`talos_cluster`](../ansible/roles/talos_cluster/). (Podman and Landscape were
removed; K3s is archived.) The host lifecycle runs from
[`playbooks/site.yml`](../ansible/playbooks/site.yml) over a single uniform set
under [`playbooks/hosts/`](../ansible/playbooks/hosts/).

### Secrets

Real secrets live in HashiCorp Vault ([VAULT.md](VAULT.md)), under
`kv/proxmox-infra/<service>`, read by the `kv_<service>` lookups in
[`group_vars/all/secrets.yml`](../ansible/inventory/group_vars/all/secrets.yml).
The Ansible vault next to it keeps only the bootstrap tier.
`host_vars/<svc>.yml` maps those fields into each host's Komodo periphery
`[secrets]` block — see the
[Secrets model](#secrets-model) below and
[`ANSIBLE.md#secrets`](ANSIBLE.md#secrets) for the full
key index.

## Phase 3: Komodo

[Komodo](https://komo.do) deploys the docker-compose services. Two
components:

- **Core** (UI + API + FerretDB v2) on the dedicated `komodo` LXC
  (vmid 414, `10.140.0.14`). UI on `:9120`, fronted by the Traefik `lan`
  entrypoint at
  [`https://komodo.example.com`](https://komodo.example.com) (LAN only)
  with no edge auth middleware — Komodo authenticates callers with its own
  built-in login.
  Persisted Noise keypair in named volume `komodo_keys` mounted at
  `/config/keys`.
- **Periphery** agent on each service host (`:8120`). Receives
  Core-signed work over the Noise transport; runs `docker compose` locally.
- **Alerts**: the `ntfy` alerter sends failed procedures, stack state
  changes, unreachable servers, disk alerts and pending sync updates to
  ntfy in the Talos cluster
  ([`komodo/README.md`](../komodo/README.md#alerts)).

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
  referencing `[[VARIABLE]]` and `[[SECRET]]`, the `iac` tag plus one wave
  tag, `deploy = true`, and `config_files` for every repo file it mounts.
- **`procedures.toml`** — `GitOps Apply`, the only deploy path (below).

### Deploy flow on push

One webhook per push, to the `GitOps Apply` Procedure. Its stages run in
order and stop at the first failure:

```text
git push to example-org/proxmox-infra (main)
        │
        ▼
GitLab webhook  POST .../listener/gitlab/procedure/<GitOps Apply id>/main
        │
        ▼
Stage 1  RunSync proxmox-infra
         - applies komodo/*.toml (match_tags = iac, delete = true)
         - deploy = true: deploys new stacks and stacks whose Komodo
           config changed, HA secondaries `after` their primary
         - deletes iac-tagged resources removed from the files
        │
        ▼
Stage 2  BatchDeployStackIfChanged  tags iac + wave-1
         (primaries, single-node stacks)
        │
        ▼
Stage 3  BatchDeployStackIfChanged  tags iac + wave-2
         (HA secondaries)
         - per stack: refresh, then redeploy if the compose file changed,
           restart the mounting service if a config_files entry changed
```

(The whole `komodo.example.com` host is one ungated catch-all route, so the
webhook reaches `/listener` without any bypass rule. The webhook is
authenticated by its own shared secret, which lives in
`kv/ci/komodo` `webhook_secret`; see the [secrets model](#secrets-model).)

The sync runs inside the Procedure rather than on its own webhook, so the
deploy stages always see the definitions of the same push. Komodo filters
webhooks by branch, never by path; the IfChanged checks and an unchanged
`docker compose up -d` keep an unrelated push from touching anything. The
behaviour this relies on was verified on Komodo 2.3.4
([`komodo/README.md`](../komodo/README.md), Behaviour verified).

### CI: lint, build, sign

The repo's GitLab CI pipeline ([`.gitlab-ci.yml`](../.gitlab-ci.yml)) runs
on the homelab `gitlab-runner` LXC. It lints (native per-tool jobs), tests
(playbook syntax checks and molecule role tests), and builds, scans and
cosign-signs the custom Docker images (pihole, unbound, unbound-recursive,
dnscrypt-proxy, semaphore). Deployment is
Komodo's job and runs independently of CI: a push triggers Komodo's own
webhook (above), which neither gates nor blocks the pipeline.

## Service exposure

Every service has one name, `<svc>.example.com`. What is public is decided by
which Traefik entrypoint carries a route for it, not by the name. Routes,
middlewares and the tunnel live in the **argo-apps** repo; this repo only runs
the backends.

| Entrypoint | Reached from | Routes | Gate |
| --- | --- | --- | --- |
| `lan` — Service `traefik-lan`, MetalLB `10.140.0.60` | LAN clients (Technitium points every name here) | every service | none; apps keep their own login |
| `public` — Service `traefik`, ClusterIP only, no LAN address | the in-cluster Cloudflare tunnel | public services only: `auth`, `docuseal`, `gist`, `privatebin`, `translate`, `pdf`, `secret`, `plex`, `seerr` | Cloudflare Access and/or Authentik; `plex` + `seerr` restricted to Serbia by a Cloudflare rule |

- **DNS:** the Technitium `example.com` zone has an A record → `10.140.0.60` for
  each service; a new service needs its own record. Public DNS (Cloudflare)
  holds only the tunnel hostnames, `wg` (DDNS) and ACME TXT records.
- **GitLab SSH:** `git@source.example.com:22` is the cluster Service
  `gitlab-ssh-lan` on `10.140.0.60`, forwarding to the `gitlab` LXC's `:2222`.
- **Other names on the domain:** `auth.example.com` (Authentik issuer
  `https://auth.example.com/application/o/<slug>/`), the Talos node names
  (`talos-*.example.com`), and Technitium's own `ns1`/`ns2` and
  `dns.example.com` zone.
- **Network:** VLANs, firewall zones, DNS/DHCP and the switch and Wi-Fi
  layout are in [NETWORK.md](NETWORK.md).

## Secrets model

Two tiers, both surfaced to a stack via `[[NAME]]` interpolation:

| Tier | Where it lives | Who renders it | Examples |
| --- | --- | --- | --- |
| **Variable** (non-secret) | [`komodo/variables.toml`](../komodo/variables.toml), committed to git | Komodo Core (DB-stored) | `TZ`, `APPDATA_DIR`, `REGISTRY_IMAGE` |
| **Secret** (host-local) | Each periphery's `[secrets]` block in `/etc/komodo/periphery.config.toml` | Ansible (`komodo_periphery` role) from Vault → `host_vars/<svc>.yml` → periphery config. **Never in Komodo Core's DB.** | DB passwords, OIDC client secrets, API tokens |

The full per-service vault key index lives in
[`ANSIBLE.md#secrets`](ANSIBLE.md#secrets).

## See also

- [`NETWORK.md`](NETWORK.md) — address plan, firewall zones, DNS/DHCP,
  switch ports, Wi-Fi, and the network diagrams.
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
