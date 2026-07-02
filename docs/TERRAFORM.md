# Terraform

Operational reference for the Terraform layer of proxmox-infra. This section was
previously `terraform/docs/MAKEFILE.md`.

## Terraform Makefile Reference

<!-- markdownlint-disable MD013 MD060 -->

Consolidated reference for the per-project Terraform Makefiles
(`terraform/lxc/Makefile`, `terraform/talos/Makefile`). Both share the
same target surface; only the **import helpers** differ per project (LXC vs
Talos VM). Project-specific differences are called out in the
[Per-project differences](#per-project-differences) table.

> The Makefiles are thin wrappers around `terragrunt`. The repo-wide
> backend (Cloudflare R2 via Terragrunt) is configured in
> [`terraform/root.hcl`](../terraform/root.hcl) — each project's `terragrunt.hcl`
> inherits from there.
>
> See also: [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) for
> the three-phase IaC picture (Terraform → Ansible → Komodo).

### Quick start

```bash
cd terraform/<project>/    # lxc | talos

# One-time per machine: download providers, init backend
make setup

# Day to day
make plan                  # preview
make apply                 # deploy
make status                # what's running
```

The Ansible inventory is **dynamic** — it reads live Terraform state via
`terragrunt state pull` every run, so there is no `make inventory`
post-step anymore. See
[Ansible inventory](ANSIBLE.md#inventory).

### Requirements

- `tofu` (or `terraform`) ≥ 1.5
- `terragrunt` ≥ 0.50
- `jq`
- Optional: `tfsec`, `tflint`, `terraform-docs`, `infracost`, `checkov`,
  `terrascan`, `graphviz`

### Target reference

#### Setup & init

| Target | What it does |
| --- | --- |
| `make setup` | `secrets` + `init` — the one-time bootstrap |
| `make secrets` | Create `terraform.tfvars.secret` from the example |
| `make init` | Download providers + modules |
| `make init-backend` | Init with explicit backend config |
| `make init-migrate` | Init and migrate state to a new backend |
| `make init-reconfigure` | Reconfigure backend without touching state |
| `make upgrade` | Bump provider versions to their latest acceptable |
| `make modules-update` | Update child modules to their latest |

#### Validate & lint

| Target | What it does |
| --- | --- |
| `make fmt` | `tofu fmt -recursive` |
| `make fmt-check` | Same but exits non-zero in CI mode |
| `make validate` | `tofu validate` |
| `make validate-json` | Validate, emit JSON |
| `make lint` | Run `tflint` (if installed) |
| `make security-scan` | Run all available security scanners |
| `make security-tfsec` / `make security-checkov` / `make security-terrascan` | Run a specific scanner |

#### Plan & apply

| Target | What it does |
| --- | --- |
| `make plan` | Standard execution plan |
| `make plan-detailed` | Plan with full per-resource diff |
| `make plan-target TARGET=<addr>` | Plan a single resource |
| `make plan-destroy` | Plan a destroy |
| `make plan-out` | Save the plan to `generated/plans/` |
| `make apply` | Apply (interactive confirmation) |
| `make apply-auto` | Apply with `-auto-approve` (CI mode) |
| `make apply-target TARGET=<addr>` | Apply a single resource |
| `make refresh` | `tofu refresh` |

#### Import

The generic helper is the same in every project:

| Target | What it does |
| --- | --- |
| `make import RESOURCE=<addr> ID=<proxmox-id>` | Generic import |
| `make import-from-proxmox VMID=<id> [NODE=<node>]` | Auto-import by looking up the Proxmox resource |
| `make import-guide` | Print the per-project import guide |

The **project-specific** import wrappers are listed in the next section.

#### Destroy

| Target | What it does |
| --- | --- |
| `make destroy` | Destroy with confirmation |
| `make destroy-auto` | Destroy with `-auto-approve` (**dangerous**) |
| `make destroy-target TARGET=<addr>` | Destroy a single resource |
| `make taint RESOURCE=<addr>` / `make untaint RESOURCE=<addr>` | Force recreation on next apply |

#### State management

| Target | What it does |
| --- | --- |
| `make state-list` | List resources in state |
| `make state-show RESOURCE=<addr>` | Pretty-print one resource |
| `make state-rm RESOURCE=<addr>` | Remove from state |
| `make state-mv FROM=<addr> TO=<addr>` | Rename / move |
| `make state-pull` | Dump remote state to stdout |
| `make state-push FILE=<path>` | Push local state (**dangerous**) |
| `make state-replace-provider FROM=<addr> TO=<addr>` | Swap provider on a resource |
| `make backup-state` | Snapshot current state to `generated/backups/` |
| `make backup-all` | Backup state + config |
| `make restore-state FILE=<backup>` | Restore from backup |

#### Outputs & inspection

| Target | What it does |
| --- | --- |
| `make output` / `make output-json` | Show all outputs |
| `make output-raw NAME=<name>` | Show one output (raw) |
| `make show` / `make show-json` | Show state or a saved plan |
| `make status` | Resource count + summary |
| `make ssh-commands` | Print SSH commands for every host |
| `make graph` / `make graph-plan` | Render the dependency graph (needs graphviz) |
| `make cost` / `make cost-diff` | Estimate cost (needs infracost) |
| `make docs` | Regenerate `terraform-docs` README block |

#### Workspaces

| Target | What it does |
| --- | --- |
| `make workspace-list` / `workspace-show` | Inspect workspaces |
| `make workspace-new NAME=<n>` / `workspace-select NAME=<n>` / `workspace-delete NAME=<n>` | Lifecycle |

#### Testing & drift

| Target | What it does |
| --- | --- |
| `make test` | Run `tofu test` (≥ 1.6) |
| `make drift-detect` | Detect drift between state and real infra |

#### Maintenance

| Target | What it does |
| --- | --- |
| `make lock` | Regenerate `.terraform.lock.hcl` for all platforms |
| `make clean` | Remove temp files + plan caches |
| `make clean-all` | Also wipe state backups (**dangerous**) |
| `make providers` | List required providers and versions |
| `make providers-schema` | Dump provider schemas as JSON |
| `make console` | `tofu console` |

#### Composite workflows

| Target | What it does |
| --- | --- |
| `make quick` | `fmt + validate + plan` |
| `make full-check` | `fmt-check + validate + lint + security-scan` (CI mode) |
| `make deploy` | `init + plan` (then prompts to apply) |
| `make full-deploy` | `init + plan + apply` |
| `make ci-plan` | `init + fmt-check + validate + plan` |
| `make ci-apply` | `init + apply-auto` |
| `make ci-destroy` | `init + destroy-auto` |

#### Info

| Target | What it does |
| --- | --- |
| `make version` | Tofu + provider versions |
| `make info` | Environment + paths |
| `make help` | Print the inline help block |

### Per-project differences

| Aspect | `lxc` | `talos` |
| --- | --- | --- | --- |
| Proxmox kind | LXC container | KVM VM (Talos image) |
| Module under `modules/` | `lxc-instance` | `vm-talos` |
| Instances file | `instances/lxc.auto.tfvars` | `instances/talos.auto.tfvars` |
| Import wrapper | `make import-lxc HOSTNAME=<h> VMID=<v> [NODE=<n>]` | (uses generic `make import` / `import-from-proxmox`) |
| State resource path | `module.lxc[0].proxmox_lxc.container["<host>"]` | `module.talos[0].proxmox_virtual_environment_vm.vm["<host>"]` |
| Typical post-apply | `make -C ansible bootstrap-host HOST=<h>` | `make -C ansible bootstrap-host HOST=<h>` | `make -C ansible/talos deploy-full` |

### Common workflows

#### Add a new host

1. Append an entry to `instances/<project>.auto.tfvars`.
2. `make plan` → review.
3. `make apply`.
4. Hand off to Ansible — see [Ansible inventory](ANSIBLE.md#inventory); host
   setup runs from `make -C ansible bootstrap-host HOST=<h>` (Talos uses
   `make -C ansible/talos`).

#### Import an existing host

```bash
# LXC
make -C terraform/lxc import-lxc HOSTNAME=<h> VMID=<v>

# Linux VM

# Talos (generic)
make -C terraform/talos import-from-proxmox VMID=<v>
```

The wrapper preserves an SSH key at `~/.ssh/<hostname>_id_ed25519` if
one already exists; otherwise the next apply generates a fresh one.

#### Surgical destroy

```bash
# Drop one host without touching the rest
make destroy-target TARGET='module.lxc[0].proxmox_lxc.container["<host>"]'
```

### Troubleshooting

#### `terraform.tfvars.secret not found`

```bash
make secrets               # copies from terraform.tfvars.secret.example
$EDITOR terraform.tfvars.secret
```

#### State lock stuck

```bash
tofu force-unlock <LOCK_ID>
```

#### Import says "resource not found"

- Confirm the VMID exists: `pvesh get /nodes/<node>/lxc` (or `qemu`).
- Confirm the hostname in your `*.auto.tfvars` matches what Proxmox
  knows.
- For LXC, the resource path is `module.lxc[0].proxmox_lxc.container["<hostname>"]`.

#### Drift on every plan

- Run `make refresh` first; if drift persists, inspect with
  `make state-show RESOURCE=<addr>` and reconcile by editing the tfvars
  or by `state mv` / `state rm` + re-import.

### File locations

| Path | Purpose |
| --- | --- |
| `terraform.tfvars.secret` | Per-project secret (Proxmox API token) — gitignored |
| `terraform.tfvars.secret.example` | Template |
| `instances/*.auto.tfvars` | Host definitions |
| `generated/state/` | Local state cache (real state is in R2 via Terragrunt) |
| `generated/backups/` | `make backup-state` snapshots |
| `generated/plans/` | Saved `tfplan` files |

### See also

- [`terraform/README.md`](../terraform/README.md) — projects index
- [`terraform/lxc/README.md`](../terraform/lxc/README.md),
  [`terraform/talos/README.md`](../terraform/talos/README.md)
- [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) — full IaC flow
- [Ansible inventory](ANSIBLE.md#inventory) — how
  the dynamic Ansible inventory consumes Terraform state
