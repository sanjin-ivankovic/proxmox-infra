# Terraform projects — proxmox-infra

<!-- markdownlint-disable MD013 MD060 -->

Three independent Terraform / OpenTofu projects, each driven by
`terragrunt` against a shared Cloudflare R2 state backend (see
[`root.hcl`](root.hcl)):

| Project | What it provisions |
| --- | --- |
| [`lxc/`](lxc/) | LXC containers (service hosts running Docker; the `komodo` LXC) |
| [`talos/`](talos/) | Talos Linux VMs for the homelab Kubernetes cluster |

The retired Windows-VMs project is archived under
[`.archive/terraform/windows-vms/`](../.archive/terraform/windows-vms/).

> See [`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) for the full
> three-phase IaC picture (Terraform → Ansible → Komodo). The shared
> Makefile reference for all three projects is
> [`docs/MAKEFILE.md`](docs/MAKEFILE.md).

## Layout

Each project is fully self-contained:

- `main.tf` / `variables.tf` / `outputs.tf` / `versions.tf` / `provider.tf`
- `terragrunt.hcl` — inherits the backend from `terraform/root.hcl`
- `Makefile` — the per-project target wrapper
- `terraform.tfvars.secret` — per-project secret file (gitignored)
- `instances/*.auto.tfvars` — host definitions
- `modules/` — per-project + shared helper modules
- `templates/` — static Ansible inventory templates emitted by `outputs.tf`;
  the live inventory is dynamic (see below)
- `generated/state/` — local state cache (real state lives in R2)

## Quick start

```bash
cd terraform/<project>     # lxc | talos
make setup                 # secrets + terragrunt init
make plan                  # preview
make apply                 # deploy
```

After apply, hand off to Ansible:

```bash
make -C ansible inventory-graph                  # the live (dynamic) inventory
make -C ansible/<project> bootstrap-host HOST=<h>
```

The Ansible inventory is **dynamic** — it reads live Terraform state via
`terragrunt state pull` on every run, so there is nothing to "generate"
post-apply and no static `inventory/*-hosts.yml` files to maintain.
See [`../docs/ANSIBLE.md#inventory`](../docs/ANSIBLE.md#inventory).

## Why separate projects?

- **Isolation** — each project owns its own state; a destroy in one
  can't touch the others.
- **Independence** — deploy, update, or destroy each project on its own
  schedule.
- **Clarity** — the LXC project doesn't carry any VM concepts and vice
  versa.

The cost is a tiny bit of duplication in `versions.tf` / `provider.tf`
across projects, which is fine.

## Shared bits

- **SSH keys** — every project drops per-host keys at
  `~/.ssh/<hostname>_id_ed25519`. The dynamic Ansible inventory finds
  them by hostname.
- **Backend** — R2 via Terragrunt, configured once in
  [`root.hcl`](root.hcl).
- **Templates** — `terraform/templates/` holds the static Ansible
  inventory templates referenced by per-project `outputs.tf`. They are
  still emitted, but the live inventory is the dynamic state-backed script.

## See also

- [`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) — three-phase IaC
  overview
- [`docs/MAKEFILE.md`](docs/MAKEFILE.md) — consolidated Makefile
  reference for the Terraform projects
- [`lxc/README.md`](lxc/README.md),
  [`talos/README.md`](talos/README.md) — per-project details
- [`.archive/README.md`](../.archive/README.md) — what was retired
  (Linux VMs, Windows VMs, K3s, pre-Komodo deploy framework, …)
