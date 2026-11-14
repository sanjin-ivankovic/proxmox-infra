# Terraform

Operational reference for the Terraform layer of proxmox-infra. This section was
previously `terraform/docs/MAKEFILE.md`.

## Terraform Makefile Reference

<!-- markdownlint-disable MD013 MD060 -->

How the Terraform units (`lxc`, `talos`, `unifi`, `backup`, `vault`) are driven. All
four share one target surface; the Proxmox host units add import helpers. See
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
cd terraform/<unit>/       # lxc | talos | unifi | backup | vault

vault login -method=userpass username=<you>   # secrets come from Vault
make init                  # once per machine
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
`ssh-commands`. Each unit's `terragrunt.hcl` loads the unit's
`instances/*.auto.tfvars` and reads its secrets from Vault, so a bare
`terragrunt plan` in the unit directory matches `make plan`.

### Secrets

The units read their secrets from HashiCorp Vault ([VAULT.md](VAULT.md)) with
`run_cmd("--terragrunt-quiet", ..., "vault", "kv", "get", ...)` in their
`terragrunt.hcl`, and pass them as `inputs`, which Terragrunt hands to OpenTofu
as `TF_VAR_*`. Nothing secret is written to disk. There are no
`terraform.tfvars.secret` files.

| Vault path | Fields | Units |
| --- | --- | --- |
| `kv/terraform/proxmox` | `api_token_id`, `api_token_secret` (`terraform-prov@pve`) | lxc, talos, backup |
| `kv/terraform/lxc` | `lxc_password` | lxc |
| `kv/terraform/backup` | `pbs_storage_password` (the `backup@pbs!pve` secret) | backup |
| `kv/terraform/unifi` | `api_key`, `wlan_passphrases` (SSID -> passphrase) | unifi |

`terraform/vault` has none: its provider uses the login token itself.

Every command needs a valid `vault login` and an unsealed Vault. A rotated
value is a `vault kv patch -mount=kv terraform/<path> <field>=-`, then
`make plan`. While Vault is sealed or down, no Terraform command runs (the
`run_cmd` lookups fail as Terragrunt parses the unit): unseal it first
([runbook](VAULT.md)). Running infrastructure is unaffected.

`make help` is the target reference; this page does not repeat it.

### Per-unit differences

| Aspect | `lxc` | `talos` | `unifi` | `backup` | `vault` |
| --- | --- | --- | --- | --- | --- |
| Manages | LXC service hosts | Talos KVM VMs | UniFi networks, Wi-Fi, firewall | PVE vzdump backup jobs | Vault mounts, audit, policies, auth methods |
| Host list | `instances/lxc.auto.tfvars` | `instances/talos.auto.tfvars` | (resources in `*.tf`) | read from the `lxc` and `talos` state | (resources in `*.tf`) |
| Import | `make import-lxc HOSTNAME=<h> VMID=<v>` | `make import-vm HOSTNAME=<h> VMID=<v>` | none | `terragrunt import proxmox_backup_job.<name> <job-id>` | `terragrunt import <addr> <path>` |
| Re-key a drifted VMID | `make reimport-lxc HOSTNAME=<h> VMID=<live>` | `make reimport-vm HOSTNAME=<h> VMID=<live>` | none | none | none |
| State address | `module.lxc[0].proxmox_virtual_environment_container.container["<h>"]` | `module.talos[0].proxmox_virtual_environment_vm.vm["<h>"]` | per resource | `proxmox_backup_job.<name>` | per resource |
| After apply | `make -C ansible bootstrap-host HOST=<h>` | `make -C ansible/talos deploy-full` | `make plan` shows no changes | `make plan` shows no changes | `make plan` shows no changes |

### Common workflows

#### Add a new host

1. Append an entry to `instances/<project>.auto.tfvars`.
2. `make plan` → review.
3. `make apply`.
4. `make -C terraform/backup plan apply` adds the new VMID to its backup job.
5. Hand off to Ansible — see [Ansible inventory](ANSIBLE.md#inventory); host
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

#### `run_cmd` fails with `permission denied` or a connection error

The `vault login` token expired (8 h) or Vault is sealed:

```bash
vault login -method=userpass username=<you>
vault status                # Sealed: false
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
