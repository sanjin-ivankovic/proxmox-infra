# Terraform

Operational reference for the Terraform layer of proxmox-infra. This section was
previously `terraform/docs/MAKEFILE.md`.

## Terraform Makefile Reference

<!-- markdownlint-disable MD013 MD060 -->

How the Terraform units (`lxc`, `talos`, `unifi`) are driven. All three
share one target surface; the Proxmox units add import helpers. See
[Per-unit differences](#per-unit-differences).

> The Makefiles are thin wrappers around `terragrunt`. The repo-wide
> backend (Cloudflare R2 via Terragrunt) is configured in
> [`terraform/root.hcl`](../terraform/root.hcl) — each project's `terragrunt.hcl`
> inherits from there.
>
> See also: [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) for
> the three-phase IaC picture (Terraform → Ansible → Komodo).

### Quick start

```bash
cd terraform/<unit>/       # lxc | talos | unifi

make setup                 # once per machine: secret file + init
make plan                  # preview
make apply                 # apply (asks for confirmation)
make help                  # every target with its usage
```

The Ansible inventory reads live Terraform state on the laptop, so no step
is needed for local runs. After an apply that adds, removes or re-IPs a
host, run `make -C ansible semaphore-files` and commit the snapshot for
Semaphore. See [Ansible inventory](ANSIBLE.md#inventory).

### Requirements

- `tofu` ≥ 1.10 (the backend uses `use_lockfile`; Terraform is not used)
- `terragrunt` ≥ 0.50
- `jq` (for `ssh-commands`)

### How the Makefiles are built

All three units include [`terraform/Makefile.common`](../terraform/Makefile.common):
init, plan, apply, targeted apply and destroy, validate and fmt, state
operations with automatic backups, and `drift-detect`. The Proxmox units
(`lxc`, `talos`) also include
[`terraform/Makefile.hosts`](../terraform/Makefile.hosts) for imports and
`ssh-commands`. Each unit's `terragrunt.hcl` loads
`terraform.tfvars.secret` and the unit's `instances/*.auto.tfvars`, so a
bare `terragrunt plan` in the unit directory matches `make plan`.

`make help` is the target reference; this page does not repeat it.

### Per-unit differences

| Aspect | `lxc` | `talos` | `unifi` |
| --- | --- | --- | --- |
| Manages | LXC service hosts | Talos KVM VMs | UniFi networks, Wi-Fi, firewall |
| Host list | `instances/lxc.auto.tfvars` | `instances/talos.auto.tfvars` | (resources in `*.tf`) |
| Import | `make import-lxc HOSTNAME=<h> VMID=<v>` | `make import-vm HOSTNAME=<h> VMID=<v>` | none |
| Re-key a drifted VMID | `make reimport-lxc HOSTNAME=<h> VMID=<live>` | `make reimport-vm HOSTNAME=<h> VMID=<live>` | none |
| State address | `module.lxc[0].proxmox_virtual_environment_container.container["<h>"]` | `module.talos[0].proxmox_virtual_environment_vm.vm["<h>"]` | per resource |
| After apply | `make -C ansible bootstrap-host HOST=<h>` | `make -C ansible/talos deploy-full` | `make plan` shows no changes |

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

# Talos (generic)
make -C terraform/talos import-from-proxmox VMID=<v>
```

The wrapper preserves an SSH key at `~/.ssh/<hostname>_id_ed25519` if
one already exists; otherwise the next apply generates a fresh one.

#### Surgical destroy

```bash
# Drop one host without touching the rest
make destroy-target TARGET='module.lxc[0].proxmox_virtual_environment_container.container["<host>"]'
```

### Troubleshooting

#### `terraform.tfvars.secret not found`

```bash
make secrets               # copies from terraform.tfvars.secret.example
$EDITOR terraform.tfvars.secret
```

#### State lock stuck

A run killed mid-plan leaves `<key>.tflock` in the R2 bucket. The error
prints the lock ID; remove it only when no other run is active:

```bash
tofu force-unlock <LOCK_ID>
```

#### "Backend configuration changed" after a `root.hcl` edit

A changed backend block (bucket, key, `use_lockfile`) needs one re-init
per project directory. With bucket and key unchanged, state is untouched:

```bash
terragrunt init -reconfigure
```

#### Import says "resource not found"

- Confirm the VMID exists: `pvesh get /nodes/<node>/lxc` (or `qemu`).
- Confirm the hostname in your `*.auto.tfvars` matches what Proxmox
  knows.
- For LXC, the resource path is `module.lxc[0].proxmox_virtual_environment_container.container["<hostname>"]`.

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
