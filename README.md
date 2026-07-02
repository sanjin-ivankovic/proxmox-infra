# 🚀 Proxmox Infrastructure as Code

<!-- markdownlint-disable MD013 MD060 -->

[![Terraform](https://img.shields.io/badge/Terraform-1.13+-623CE4.svg?style=for-the-badge&logo=terraform)](https://www.terraform.io/)
[![Ansible](https://img.shields.io/badge/Ansible-2.20+-EE0000.svg?style=for-the-badge&logo=ansible)](https://www.ansible.com/)
[![Proxmox](https://img.shields.io/badge/Proxmox-VE-E57000.svg?style=for-the-badge&logo=proxmox)](https://www.proxmox.com/)
[![Komodo](https://img.shields.io/badge/Komodo-Service%20Deployment-3ddc84.svg?style=for-the-badge)](https://komo.do)
[![GitOps](https://img.shields.io/badge/GitOps-Enabled-4CAF50.svg?style=for-the-badge)](https://www.gitops.tech/)
[![Renovate](https://img.shields.io/badge/Renovate-Enabled-1A1F6C.svg?style=for-the-badge&logo=renovate)](https://docs.renovatebot.com/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED.svg?style=for-the-badge&logo=docker)](https://docs.docker.com/compose/)

Infrastructure as Code for a homelab Proxmox cluster: LXC containers,
and a Talos Kubernetes cluster — provisioned with Terraform,
configured with Ansible, with services deployed via [Komodo](https://komo.do).

Three-phase workflow: **Terraform** provisions → **Ansible** configures →
**Komodo** deploys.

---

## 📋 Table of Contents

<!-- markdownlint-disable MD051 -->

- [Quick Start](#-quick-start)
- [Architecture](#-architecture)
- [Project Structure](#-project-structure)
- [Prerequisites](#-prerequisites)
- [Common Operations](#-common-operations)
- [Documentation](#-documentation)
- [Contributing](#-contributing)

<!-- markdownlint-enable MD051 -->

---

## ⚡ Quick Start

```bash
# 1️⃣ Provision infrastructure with Terraform
cd terraform/lxc                          # or terraform/talos
terragrunt apply                          # creates LXCs/VMs on Proxmox + generates per-host SSH keys

# 2️⃣ Inspect inventory (dynamic — reads live TF state)
cd ../../ansible
make inventory-graph                      # show hosts grouped by Proxmox tags
make -C lxc accept-host-keys              # accept SSH fingerprints

# 3️⃣ One-time host setup (bootstrap as root, configure as maintainer)
make -C lxc bootstrap-host HOST=<hostname>   # creates maintainer, hardens SSH (root login then disabled)
make -C lxc configure-host HOST=<hostname>   # installs Docker, prepares /srv/docker/

# 4️⃣ Install the Komodo Periphery agent so the host is deploy-ready
make -C lxc install-periphery HOST=<hostname>

# 5️⃣ Deploy services (automatic on git push)
git push                                  # GitLab webhook → Komodo Core → ResourceSync → docker compose up
```

The first four steps are **per-host one-time** setup. After that, every
`git push` to `example-org/proxmox-infra` triggers Komodo Core to re-read
[`komodo/stacks.toml`](komodo/) and redeploy affected stacks.
[Architecture overview →](docs/ARCHITECTURE.md)

---

## 🏗️ Architecture

```text
Terraform  ──▶  Ansible  ──▶  Komodo
provisions     configures      deploys
LXCs + VMs     hosts           services
```

| Phase | Tool | Source of truth |
| --- | --- | --- |
| **1. Provision** | Terraform (via Terragrunt + OpenTofu) | [`terraform/`](terraform/) — 2 projects: `lxc`, `talos` |
| **2. Configure** | Ansible (dynamic inventory) | [`ansible/`](ansible/) — playbooks + roles (`common_*`, `komodo_*`, `talos_cluster`) |
| **3. Deploy** | Komodo Core + Periphery agents | [`komodo/`](komodo/) — TOML resource sync ([`servers.toml`](komodo/servers.toml), [`variables.toml`](komodo/variables.toml), [`stacks.toml`](komodo/stacks.toml)) |

**See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the canonical
deep-dive** — flow diagrams, the secrets model
(`[[VARIABLE]]` vs host-local `[[SECRET]]`), the per-phase
responsibilities, and the [Decommission map](docs/ARCHITECTURE.md#decommission-map).

### What runs where

- **Komodo Core + FerretDB v2** — the `komodo` LXC (`10.40.0.17`),
  managed by [`ansible/roles/komodo_core`](ansible/roles/komodo_core/).
  UI at [`https://komodo.example.com`](https://komodo.example.com) behind
  Pocket ID via oauth2-proxy (the `/listener` path bypasses the gate for
  GitLab's webhook).
- **Komodo Periphery** — one agent per service LXC, port `:8120`,
  managed by [`ansible/roles/komodo_periphery`](ansible/roles/komodo_periphery/).
  Receives Core-signed work over the Noise transport.
- **Lint + custom Docker image build/sign** — GitLab CI
  ([`.gitlab-ci.yml`](.gitlab-ci.yml)). Builds + cosign-signs `pihole`,
  `unbound`, `unbound-recursive`, `dnscrypt-proxy` images on push.

---

## 📂 Project Structure

```text
proxmox-infra/
├── .archive/                        # retired components — see .archive/README.md
├── .ci/
│   └── scripts/                     # CI helpers (lint, security scans, publish)
├── ansible/
│   ├── ansible.cfg                  # remote_user=maintainer, inventory=terraform_state_inventory.py
│   ├── Makefile                     # vault-edit, inventory-graph, ping
│   ├── docs/                        # INVENTORY, SECRETS, KOMODO, MAKEFILES, TROUBLESHOOTING
│   ├── inventory/
│   │   ├── terraform_state_inventory.py   # dynamic inventory — reads live TF state
│   │   ├── group_vars/all/{vars,vault}.yml
│   │   └── host_vars/<host>.yml           # per-host overrides (komodo_periphery_secrets, OS overrides)
│   ├── lxc/                         # Makefile for LXC operations (bootstrap-host, configure-host, install-periphery)
│   ├── talos/                       # Makefile for Talos cluster operations (talosctl-driven)
│   ├── playbooks/{site,hosts,komodo,talos}/  # site.yml + uniform host/komodo/talos playbooks
│   └── roles/                       # common_{system,users,ssh,docker,podman}, komodo_{core,periphery}, talos_cluster
├── docs/
│   └── ARCHITECTURE.md              # canonical "how it works today"
├── komodo/                          # Komodo Resource Sync (servers, variables, stacks, resource-sync)
├── services/                        # docker-compose.yml per service; see services/README.md
│   ├── adguard-{1,2}/               # AdGuard Home HA pair (DNS filtering)
│   ├── technitium-{1,2}/            # Technitium HA pair (authoritative DNS)
│   ├── bitwarden/
│   ├── paperless-ngx/
│   ├── patchmon/
│   ├── semaphore/
│   ├── omni/                        # Sidero Omni (Talos management plane)
│   └── _templates/
├── terraform/                       # 2 independent projects (lxc, talos)
│   ├── docs/MAKEFILE.md             # consolidated Makefile reference (shared across projects)
│   ├── lxc/                         # LXC containers (service hosts + komodo)
│   └── talos/                   # Talos Kubernetes cluster VMs
└── docker/                          # Custom Docker images built in CI (pihole, unbound, dnscrypt-proxy)
```

---

## 📋 Prerequisites

### Control machine (your laptop)

- **Terraform / OpenTofu** 1.14+ (we use Terragrunt as a wrapper)
- **Terragrunt** — drives the multi-project Terraform setup
- **Ansible** 2.20+
- **jq** — JSON processor (inventory inspection)
- **SSH client** + **Git**

```bash
# macOS via Homebrew
brew install terragrunt opentofu ansible jq
```

### Proxmox VE

- **Proxmox VE** 9.0+ with an API token (Datacenter → Permissions → API Tokens)
- **Debian 13 LXC template** available locally (Local → CT Templates)
- Network connectivity from the cluster to Cloudflare R2 (Terraform state backend)

### Komodo Core (one time)

The `komodo` LXC is provisioned by
[`terraform/lxc/instances/lxc.auto.tfvars`](terraform/lxc/instances/lxc.auto.tfvars)
and brought up by
[`ansible/playbooks/lxc/09-komodo-core.yml`](ansible/playbooks/lxc/).
A GitLab service account named `komodo` with read access to
`example-org/proxmox-infra` is required (the token is stored as
`vault_komodo_gitlab_token`). See
[`docs/ANSIBLE.md#komodo--operator-runbook`](docs/ANSIBLE.md#komodo--operator-runbook) for the full
runbook.

---

## 🔧 Common Operations

### Add a new LXC service

1. Append the instance to
   [`terraform/lxc/instances/lxc.auto.tfvars`](terraform/lxc/instances/lxc.auto.tfvars)
   (include `"docker"` in `tags`).
2. `cd terraform/lxc && terragrunt apply`.
3. `make -C ansible/lxc bootstrap-host HOST=<name>`
   then `configure-host HOST=<name>`.
4. `make -C ansible/lxc install-periphery HOST=<name>`.
5. Create [`services/<name>/docker-compose.yml`](services/).
6. Add a `[[server]]` and `[[stack]]` to
   [`komodo/servers.toml`](komodo/servers.toml) and
   [`komodo/stacks.toml`](komodo/stacks.toml). For secrets, add the
   matching vault key + `host_vars/<name>.yml` — see
   [`docs/ANSIBLE.md#secrets`](docs/ANSIBLE.md#secrets).
7. Push. Komodo reconciles + deploys.

### Day-to-day

```bash
make -C ansible vault-edit                   # edit Ansible Vault
make -C ansible inventory-graph              # snapshot of all hosts/groups
make -C ansible/lxc bootstrap-host HOST=…    # one-time host bootstrap
make -C ansible/lxc configure-host HOST=…    # one-time host configure
make -C ansible/lxc install-periphery HOST=… # install Komodo periphery agent
make -C ansible/lxc deploy-komodo-core       # (re)deploy the komodo control plane
```

Full Makefile reference:
[`docs/ANSIBLE.md#makefile-reference`](docs/ANSIBLE.md#makefile-reference).

### Troubleshooting

See [`docs/ANSIBLE.md#troubleshooting`](docs/ANSIBLE.md#troubleshooting)
for the live failure-mode index (Debian-12 hosts, Komodo handshake,
periphery key rotation, Tofu lockfile maintenance, etc.).

---

## 📚 Documentation

### Core

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — canonical
  "how it works today" (3-phase flow, secrets model, decommission map).
- [`komodo/README.md`](komodo/README.md) — Komodo resource model
  (TOML files, env interpolation, HA pairs).
- [`services/README.md`](services/README.md) — what `services/` holds and
  how to add one.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — workflow, commit conventions.

### Ansible

- [`ansible/README.md`](ansible/README.md) — overview + role tree.
- [`docs/ANSIBLE.md#inventory`](docs/ANSIBLE.md#inventory) — dynamic
  inventory script + maintainer/root user model.
- [`docs/ANSIBLE.md#secrets`](docs/ANSIBLE.md#secrets) — Vault flow +
  full per-service vault key index.
- [`docs/ANSIBLE.md#komodo--operator-runbook`](docs/ANSIBLE.md#komodo--operator-runbook) — operator runbook
  for deploying Core, periphery, and the key handshake.
- [`docs/ANSIBLE.md#makefile-reference`](docs/ANSIBLE.md#makefile-reference) — every Make
  target across `ansible/` and `ansible/lxc/`.
- [`docs/ANSIBLE.md#troubleshooting`](docs/ANSIBLE.md#troubleshooting) —
  incident-derived failure → fix index.

### Terraform

- [`terraform/README.md`](terraform/README.md) — Terraform projects overview.
- [`docs/TERRAFORM.md`](docs/TERRAFORM.md) —
  consolidated Makefile reference across all projects.
- Per-project: [`terraform/lxc/README.md`](terraform/lxc/README.md),
  [`terraform/talos/README.md`](terraform/talos/README.md).

### Archive

- [`.archive/README.md`](.archive/README.md) — index of everything
  retired (CI eras, K3s, Windows VMs, pre-Komodo deploy framework,
  Pi-hole/Unbound).

### External

- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [bpg/proxmox Terraform provider](https://registry.opentofu.org/providers/bpg/proxmox)
- [Komodo Documentation](https://komo.do/docs)
- [Talos Linux Documentation](https://www.talos.dev/latest/)
- [Ansible Documentation](https://docs.ansible.com/)
- [GitOps Principles](https://www.gitops.tech/)

---

## 🤝 Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for workflow, branch conventions,
and commit-message format (Conventional Commits, signed commits, the
pre-commit hooks suite). Bug fixes and improvements welcome — open an
issue or PR on [source.example.com/example-org/proxmox-infra](https://source.example.com/example-org/proxmox-infra).

---

**⭐ Star the repo on GitLab if you find it useful.**
