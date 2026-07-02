# Ansible — proxmox-infra

<!-- markdownlint-disable MD013 MD060 -->

[![Ansible](https://img.shields.io/badge/Ansible-2.15%2B-red.svg)](https://www.ansible.com/)
[![Collection](https://img.shields.io/badge/Collection-homelab.proxmox-blue.svg)](galaxy.yml)
[![Komodo](https://img.shields.io/badge/Komodo-Service%20Deployment-3ddc84.svg)](https://komo.do)

The Ansible (Phase 2) half of the homelab's three-phase workflow —
**Terraform provisions → Ansible configures → Komodo deploys**. This directory
is packaged as the **`homelab.proxmox` Ansible collection** ([`galaxy.yml`](galaxy.yml)):
it bootstraps Debian LXC hosts, installs Docker, deploys
the Komodo control plane, and manages the Talos cluster lifecycle.

> Canonical architecture doc: [`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md).
> Ansible deep-dive (inventory, secrets, Komodo runbook, troubleshooting):
> [`docs/ANSIBLE.md`](../docs/ANSIBLE.md).

## Quick start

```bash
# Build + install the collection so homelab.proxmox.* FQCNs resolve locally
make collection

# Inspect / validate the dynamic inventory (reads live Terraform state)
make inventory-graph
make inventory-doctor

# Per-host setup (bootstrap forces root; everything else connects as maintainer)
make bootstrap-host HOST=<host>
make configure-host HOST=<host>
make install-periphery HOST=<host>     # Komodo Periphery agent

# Komodo Core itself
make deploy-komodo-core

# Vault
make vault-edit
```

`make help` lists every target. Deep Talos operations live in the Talos
sub-Makefile — `make -C talos help` (or `make talos T=<target>`).

## Collection model

Roles and playbooks are addressable by fully-qualified collection name once the
collection is built and installed into `./collections` (gitignored):

- Roles: `homelab.proxmox.common_system`, `homelab.proxmox.komodo_core`, …
- Master host playbook: `homelab.proxmox.site`

`make collection` runs `ansible-galaxy collection build` + `install -p
./collections`. Roles still resolve by bare name from `./roles` during in-repo
work; FQCN is the addressable form. Every role ships a
`meta/argument_specs.yml`, so role inputs are type-validated at the start of
execution instead of silently falling back to defaults.

## Inventory (dynamic)

The inventory is computed on every run by
[`inventory/terraform_state_inventory.py`](inventory/terraform_state_inventory.py),
which calls `terragrunt state pull` against each Terraform project (in parallel)
and emits hosts named by real hostname, grouped by Proxmox tags — no committed
static inventory files for the SSH fleet.

```bash
make inventory-graph    # human-readable group tree
make inventory-list     # JSON dump (every host with vars)
make inventory-doctor   # validate terragrunt, per-host IP + SSH key, name collisions
```

`INVENTORY_CACHE=1` enables an opt-in state cache for faster repeat runs. Talos
nodes use a static inventory
([`inventory/talos/hosts.yml`](inventory/talos/hosts.yml)) with
`ansible_connection: local`. See [`docs/ANSIBLE.md`](../docs/ANSIBLE.md) for the
state → groups → hostvars mapping and the maintainer/root connection-user model.

## Roles

| Role | Purpose |
| --- | --- |
| [`common_system`](roles/common_system/) | APT updates, base packages, timezone |
| [`common_users`](roles/common_users/) | Creates the `maintainer` user, copies SSH key from root |
| [`common_ssh`](roles/common_ssh/) | Hardens SSH, disables root login |
| [`common_docker`](roles/common_docker/) | Installs Docker CE + compose plugin, sets up `/srv/docker` |
| [`komodo_core`](roles/komodo_core/) | Deploys Komodo Core + FerretDB on the `komodo` LXC |
| [`komodo_periphery`](roles/komodo_periphery/) | Installs the Komodo Periphery agent + renders `[secrets]` from Vault |
| [`talos_cluster`](roles/talos_cluster/) | Talos read-only checks (talosctl), dispatched by `talos_cluster_action` |

Dependencies are enforced via each role's `meta/main.yml` (calling
`komodo_core` pulls in `common_docker` → `common_system`). See
[`roles/README.md`](roles/README.md).

## Playbooks

All hosts are Debian LXCs configured by **one uniform
set** under `playbooks/hosts/`, plus the Komodo playbooks. The master
[`playbooks/site.yml`](playbooks/site.yml) groups them by tag.

| Playbook | What it does | Connection user |
| --- | --- | --- |
| [`hosts/bootstrap.yml`](playbooks/hosts/bootstrap.yml) | Create maintainer, copy SSH key, harden SSH | **root** (play var) |
| [`hosts/configure.yml`](playbooks/hosts/configure.yml) | Install Docker on `docker`-tagged hosts | maintainer |
| [`hosts/verify.yml`](playbooks/hosts/verify.yml) | Health checks | maintainer |
| [`hosts/update.yml`](playbooks/hosts/update.yml) | APT upgrade pass | maintainer |
| [`hosts/diagnostics.yml`](playbooks/hosts/diagnostics.yml) | Diagnostic info dump | maintainer |
| [`hosts/restart-docker.yml`](playbooks/hosts/restart-docker.yml) | Restart the Docker daemon | maintainer |
| [`hosts/reboot.yml`](playbooks/hosts/reboot.yml) | Rolling reboot (one host at a time) | maintainer |
| [`hosts/shutdown.yml`](playbooks/hosts/shutdown.yml) | Graceful shutdown | maintainer |
| [`komodo/core.yml`](playbooks/komodo/core.yml) | Deploy Komodo Core (komodo host) | maintainer |
| [`komodo/periphery.yml`](playbooks/komodo/periphery.yml) | Install the Periphery agent (every other docker host) | maintainer |

`site.yml` tag groups: `deployment` (bootstrap, configure, verify),
`operations` (update, diagnostics), `lifecycle` (restart-docker, reboot,
shutdown — reboot/shutdown are `never`-gated). Talos has its own
talosctl-driven stages plus three orchestrators
([`talos/deploy.yml`](playbooks/talos/deploy.yml),
[`operate.yml`](playbooks/talos/operate.yml),
[`lifecycle.yml`](playbooks/talos/lifecycle.yml)).

## Layout

```text
ansible/
├── galaxy.yml                  # homelab.proxmox collection metadata
├── meta/runtime.yml            # requires_ansible
├── ansible.cfg                 # inventory + collections_path + vault
├── Makefile + Makefile.d/      # single entry point (host/komodo/collection targets) + includes
├── changelogs/changelog.yaml
├── inventory/
│   ├── terraform_state_inventory.py   # dynamic inventory (+ --doctor)
│   ├── group_vars/{all,talos_cluster}.yml # globals + talos group vars
│   ├── host_vars/<host>.yml           # per-host overrides (komodo_periphery_secrets)
│   └── talos/                         # static Talos inventory (local connection)
├── playbooks/
│   ├── site.yml                # master host orchestrator
│   ├── hosts/                  # uniform host lifecycle
│   ├── komodo/                 # core + periphery
│   └── talos/                  # stages + deploy/operate/lifecycle orchestrators
├── roles/                      # the 7 roles (see table above)
├── extensions/molecule/        # role tests (common_system/users/ssh)
└── talos/                      # talosctl working dirs + the Talos sub-Makefile
```

## Connection user model

- **Steady state**: `maintainer`. The inventory script emits `ansible_user: maintainer`
  for every SSH host; Talos hosts use `ansible_connection: local`.
- **Bootstrap**: `playbooks/hosts/bootstrap.yml` sets `ansible_user: root` as a
  play var (which outranks the inventory hostvar) to connect as root for the
  one-time setup. After bootstrap, root SSH is disabled by `common_ssh`.

## Vault

Secrets live in
[`inventory/group_vars/all/vault.yml`](inventory/group_vars/all/) (Ansible Vault
encrypted, committed). Edit via `make vault-edit`. The per-service key index and
the "add a secret" recipe are in [`docs/ANSIBLE.md`](../docs/ANSIBLE.md).

## See also

- [`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) — the canonical "how it works
  today" doc.
- [`docs/ANSIBLE.md`](../docs/ANSIBLE.md) — inventory, secrets, Komodo runbook,
  troubleshooting.
- [`extensions/molecule/README.md`](extensions/molecule/README.md) — role tests.
- [`komodo/README.md`](../komodo/README.md) — the Komodo resource model.
