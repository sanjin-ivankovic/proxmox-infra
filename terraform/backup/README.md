# backup — Proxmox VE backup jobs

Manages the cluster vzdump jobs and the PVE storage entry `pbs-talos`. Both
jobs write to datastore `datastore01` on PBS. PBS-side retention, sync,
verify and GC are not here: every job keeps all backups from the PVE side, so
the `backup@pbs!pve` token never needs prune rights, and PBS prune jobs
decide retention.

## Guest lists

`terragrunt.hcl` reads the VMIDs from the `lxc` (`container_details`) and
`talos` (`ansible_info`) state. A guest added, renumbered or removed there
reaches its backup job on the next apply of this unit, so run it after any
apply in `lxc` or `talos`:

```bash
make -C terraform/backup plan    # only the expected VMID change
make -C terraform/backup apply
```

`validate` uses empty mock outputs, so it works without state access; `plan`
and `apply` always read the real state.

## Jobs

<!-- markdownlint-disable MD013 -->
| Resource | Job ID | Guests | Schedule | Retention |
| --- | --- | --- | --- | --- |
| `proxmox_backup_job.guests` | `backup-9b2da867-dbd5` | LXC containers → storage `pbs` (root namespace) | 02:30 | PBS prune job on the root namespace |
| `proxmox_backup_job.talos` | `talos-vms` | Talos VMs → storage `pbs-talos` (namespace `talos`) | 03:00 | PBS prune job on namespace `talos` |
<!-- markdownlint-enable MD013 -->

The namespace `talos` must exist on `datastore01` before the first Talos
run; vzdump fails with "namespace not found" otherwise.

## Import

There is no import target. Read the live job with the `pve_backup_jobs` MCP
tool, write the resource to match, then:

```bash
cd terraform/backup
terragrunt import proxmox_backup_job.<name> <job-id>
make plan                        # must be a no-op
```

## Credentials

`terragrunt.hcl` reads them from Vault: the `terraform-prov@pve` token from
`kv/terraform/proxmox`, shared with `lxc` and `talos`, which also needs
`PVEDatastoreAdmin` on `/storage`: editing a backup job checks the target
storage, and creating a storage entry checks `/storage` itself. It also needs
`pbs_storage_password` from `kv/terraform/backup`: the secret of the PBS
token `backup@pbs!pve`, the same as in `/etc/pve/priv/storage/pbs.pw` on the
PVE host.
