# Retention is decided on PBS, never here: every job and storage keeps all
# backups from the PVE side, so the backup@pbs!pve token needs no prune or
# delete privilege (PBS's ransomware guidance). PBS prune jobs, scoped per
# datastore and namespace, remove old snapshots.

# Nightly vzdump of the LXC containers to the PBS storage "pbs"
# (datastore01, root namespace).
resource "proxmox_backup_job" "guests" {
  id             = "backup-9b2da867-dbd5"
  schedule       = "02:30"
  storage        = "pbs"
  mode           = "snapshot"
  enabled        = true
  notes_template = "{{guestname}}"
  vmid           = var.lxc_vmids

  notification_mode = "notification-system"

  prune_backups = {
    "keep-all" = "1"
  }

  fleecing = {
    enabled = false
  }
}

# The Talos VMs (500 GB disks, rebuildable from Terraform and the Talos
# configs) back up into their own namespace, so a PBS prune job can keep far
# fewer of them than of the containers. The namespace must exist on PBS before
# the first run: vzdump fails with "namespace not found" otherwise.
resource "proxmox_storage_pbs" "talos" {
  id        = "pbs-talos"
  server    = "pbs.example.com"
  datastore = "datastore01"
  namespace = "talos"
  username  = "backup@pbs!pve"
  password  = var.pbs_storage_password
  content   = ["backup"]

  backups {
    keep_all = true
  }
}

# Starts after the container job; vzdump serialises the two on its global lock
# if the container run is still going.
resource "proxmox_backup_job" "talos" {
  id             = "talos-vms"
  schedule       = "03:00"
  storage        = proxmox_storage_pbs.talos.id
  mode           = "snapshot"
  enabled        = true
  notes_template = "{{guestname}}"
  vmid           = var.talos_vmids

  notification_mode = "notification-system"

  prune_backups = {
    "keep-all" = "1"
  }

  fleecing = {
    enabled = false
  }
}
