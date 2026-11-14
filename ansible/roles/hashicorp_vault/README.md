# hashicorp_vault

Host side of the HashiCorp Vault stack (`services/vault`): the appdata
directories it mounts and the Let's Encrypt certificate it serves.

## Why this role exists

Vault terminates its own TLS so that it never depends on the cluster's
Traefik: the cluster reads its secrets from Vault. lego obtains the
certificate for `vault.example.com` by Cloudflare DNS-01, a daily timer
renews it, and the deploy hook copies it into the stack's TLS directory and
sends SIGHUP. SIGHUP reloads the certificate; a restart would seal Vault.

The role never starts or restarts the container. Deploying the stack is
manual (`make komodo-deploy STACK=vault`), followed by an unseal
(`docs/VAULT.md`).

## Variables

<!-- markdownlint-disable MD013 -->
| Variable | Default | Description |
| --- | --- | --- |
| `hashicorp_vault_domain` | `vault.example.com` | Hostname on the certificate |
| `hashicorp_vault_acme_email` | `admin@example.com` | ACME account contact |
| `hashicorp_vault_appdata_dir` | `/srv/docker/appdata/vault` | The stack's bind-mount root |
| `hashicorp_vault_image` | from the compose file | Image used to look up the container's vault gid |
| `hashicorp_vault_lego_version` | `5.6.0` | lego release |
| `hashicorp_vault_cloudflare_dns_token` | `vault_cloudflare_dns_token` | Zone:Read + DNS:Edit on example.com |
| `hashicorp_vault_dns_propagation_wait` | `90s` | Fixed wait instead of lego's propagation checks |
| `hashicorp_vault_renew_on_calendar` | `*-*-* 03:40:00` | Renewal check schedule |
| `hashicorp_vault_audit_log_keep_days` | `14` | Rotated audit logs kept |
| `hashicorp_vault_textfile_dir` | `/var/lib/node_exporter/textfile` | Where `vault-probe` and the snapshot timer write their `.prom` files |
| `hashicorp_vault_snapshot_role_id` | the `raft-snapshot` RoleID | `make -C terraform/vault output` |
| `hashicorp_vault_snapshot_secret_id` | `vault_hashicorp_vault_snapshot_secret_id` | SecretID of the `raft-snapshot` AppRole |
| `hashicorp_vault_snapshot_dir` | `/var/backups/vault` | Snapshot directory |
| `hashicorp_vault_snapshot_keep` | `7` | Newest snapshots kept |
| `hashicorp_vault_snapshot_on_calendar` | `*-*-* 02:00:00 Europe/Berlin` | Snapshot schedule, before the 02:30 PBS backup |
<!-- markdownlint-enable MD013 -->

## Usage

```bash
make -C ansible hashicorp-vault          # all tasks
make -C ansible hashicorp-vault ARGS=--check
sudo systemctl start lego-vault.service  # on the host: first certificate now
```

## Notes

- `vault-raft-snapshot.timer` logs in with the `raft-snapshot` AppRole,
  saves a snapshot through the API, revokes its token and keeps the newest
  7. It writes `vault_raft_snapshot_newest_timestamp_seconds` for the
  `VaultSnapshotStale` alert. Credentials and token only reach curl through
  0600 files, never a command line.
- `vault-probe.timer` writes `vault_probe_up`, `vault_probe_sealed`,
  `vault_probe_initialized` and `vault_probe_tls_not_after_seconds` every
  minute for node_exporter. A sealed Vault answers `/v1/sys/metrics` with
  503, so the alerts in argo-apps read these instead.
- `/etc/logrotate.d/vault-audit` rotates the audit log daily with
  `nocreate` and SIGHUP. Vault blocks every request when its audit device
  cannot write, and the global `create` would leave a root-owned file.
- Technitium answers for `example.com` inside the network, so lego's
  propagation checks would look there and never find the Cloudflare TXT
  record. The role disables them and waits a fixed time instead.
- The first `lego run` registers the ACME account under `/etc/lego`.
- Not molecule-tested: it needs Docker and the real Vault image.
