# HashiCorp Vault

<!-- markdownlint-disable MD013 MD060 -->

The homelab's secret store: one Vault server on the `vault` LXC
(VMID 416, `10.140.0.16`), reached at `https://vault.example.com:8200`.

## Design rules

- **Vault never depends on what depends on it.** It runs outside the
  cluster, terminates its own TLS (no Traefik), and its A record points
  straight at the LXC.
- **Manual unseal, Shamir keys.** 3 shares, threshold 2. Every start of the
  container leaves Vault sealed. The shares and the initial root token are
  kept in Bitwarden plus a paper copy, never in Git, a file on a host, or a
  chat or agent session.
- **Nothing restarts it unattended.**
  - The Komodo stack is tagged `manual-deploy`: no wave tag and
    `deploy = false`, so GitOps Apply never redeploys or restarts it
    (`scripts/komodo_lint.py` enforces both).
  - The host is in `os_patch_excluded_hosts`.
  - Renovate opens a `hashicorp/vault` MR only after approval on the
    Dependency Dashboard.
- **The bootstrap tier stays in the Ansible vault.** It is what reaches
  Vault, or must work while Vault is sealed:
  - `vault_cloudflare_dns_token` (the certificate)
  - the AppRole SecretIDs: `vault_hashicorp_vault_snapshot_secret_id`,
    `vault_semaphore_vault_secret_id`
  - `vault_semaphore_ansible_vault_password` and `.vault_pass`
  - the `r2-terraform` profile

## Components

| Piece | Where |
| --- | --- |
| LXC | `terraform/lxc/instances/lxc.auto.tfvars` (`vault`) |
| DNS A + PTR | `ansible/configs/technitium.yml` (`hosts:`) |
| Compose + server config | `services/vault/docker-compose.yml`, `services/vault/vault.hcl` |
| Komodo | `komodo/servers.toml`, `komodo/stacks.toml` (`vault`, `manual-deploy`) |
| TLS | role `hashicorp_vault`: lego, Cloudflare DNS-01, timer `lego-vault.timer` at 03:40, deploy hook sends SIGHUP |
| Storage | integrated Raft in `/srv/docker/appdata/vault/file` |
| Monitoring | `vault-probe.timer` (same role) writes seal state and certificate expiry to node_exporter's textfile collector; alerts `VaultSealed`, `VaultDown`, `VaultCertExpiring` in argo-apps `prometheusrule-hosts.yaml` |
| Backup | `vault-raft-snapshot.timer` at 02:00 (role `hashicorp_vault`, AppRole `raft-snapshot`) into `/var/backups/vault`, newest 7 kept; the 02:30 PBS backup of `ct/416` takes them, and the `offsite-lxc` sync carries them to Google Drive |

## First deployment

1. Terraform: `make -C terraform/lxc plan`, then `apply`. Then the
   host-lifecycle steps for a Docker host:
   - `bootstrap-host`, `configure-host`, `install-periphery` and
     `monitoring-agent` (`HOST=vault`)
   - `make -C terraform/backup plan apply`
2. DNS: `make -C ansible technitium-bootstrap`.
3. TLS: add `vault_cloudflare_dns_token` to the Ansible vault. The token
   needs Zone:Read and DNS:Edit on `example.com` only. Then run
   `make -C ansible hashicorp-vault`, and on the host,
   `sudo systemctl start lego-vault.service`. Check that
   `/srv/docker/appdata/vault/tls/fullchain.pem` exists.
4. Deploy: push, let the ResourceSync create the stack, then
   `make komodo-deploy STACK=vault`.
5. **Initialise. The operator does this, never automation:**

   ```bash
   export VAULT_ADDR=https://vault.example.com:8200
   vault operator init -key-shares=3 -key-threshold=2
   ```

   Store the 3 unseal keys and the root token in Bitwarden, and keep a paper
   copy of the keys. Then unseal (below).

## Configuration as code

`terraform/vault` holds the structure: the `kv/` mount (KV v2), the file
audit device, the `admin` and `raft-snapshot` policies, and the `userpass`
and `approle` auth methods. It never holds secret values
([terraform/vault/README.md](../terraform/vault/README.md)).

KV layout: `kv/<repo or area>/<consumer>`, for example
`kv/proxmox-infra/bitwarden`.

## Kubernetes

The External Secrets Operator (argo-apps `apps/infra/external-secrets`)
reads `kv/k8s/<namespace>/<secret>` through the `kubernetes` auth method,
role `eso`, policy `k8s-read`. It logs in with a token of its own service
account; Vault checks it with the cluster's TokenReview API at
`https://10.140.0.40:6443`, using that same token, so the service account is
bound to `system:auth-delegator`. The token's audience is the API server's
own, `https://10.140.0.40:6443`: the API server accepts no other for
TokenReview, and Vault rejects a token with more than one audience. The cluster CA is
inline in `terraform/vault/main.tf`.

## GitLab CI

Jobs log in with an `id_tokens` JWT (audience `https://vault.example.com`) at
`auth/jwt`; GitLab CE has no `secrets:` keyword, so the job runs
`vault write auth/jwt/login role=ci-<name> jwt=$VAULT_ID_TOKEN` and reads
`kv/ci/<name>`. Each role `ci-<name>` reads only its own path (`ci-cosign`
reads nothing: it signs with the Transit key `transit/keys/cosign`, which
cosign uses as `--key hashivault://cosign`; the private key is not
exportable) and accepts only
the projects listed in `terraform/vault/main.tf` (`local.ci_roles`), on a
protected branch: a merge-request job is refused at login. Vault fetches
GitLab's signing keys from `https://source.example.com`.

| Path | Fields | Read by |
| --- | --- | --- |
| `transit/keys/cosign` | ECDSA P-256 signing key, public half in helm-charts `cosign.pub` | image and chart signing, SBOM attestations |
| `kv/ci/github` | `publish_token` | the GitHub mirrors |
| `kv/ci/ntfy` | `token` | `notify-ntfy` |
| `kv/ci/ci-components` | `release_token` | ci-components `auto-tag` |
| `kv/ci/komodo` | `webhook_secret` | proxmox-infra `komodo:redeploy-images`, and Ansible's `komodo_core` role |
| `kv/ci/renovate` | `token`, `github_com_token`, `docker_hub_username`, `docker_hub_token` | the Renovate runner |
| `kv/ci/cloudflare` | `api_token`, `account_id` | the portfolio-site deploy |

## Ansible

Playbooks read secrets through `kv_<service>` lookups in
`ansible/inventory/group_vars/all/secrets.yml` (and `kv_talos` in the Talos
inventory's own `secrets.yml`); `ansible.cfg` (`[hashi_vault_collection]`)
sets the address. A lookup runs only when a play uses its variable.

| Where | Login |
| --- | --- |
| Laptop | token in `~/.vault-token`, from `vault login -method=userpass` |
| Semaphore | AppRole `semaphore` (policy `proxmox-infra-read`): the SecretID arrives as a Periphery secret and is forwarded to each run (`SEMAPHORE_FORWARDED_ENV_VARS`); the RoleID and auth method are in the environments of `ansible/configs/semaphore.yml` |

The lookups need the `hvac` library in the Python that runs Ansible.
Homebrew's Ansible venv has no `pip`, so install it with `uv`, once per
install or `brew upgrade ansible`:

```bash
uv pip install --python "$(dirname "$(readlink -f "$(command -v ansible-playbook)")")/python" hvac
```

The Semaphore image installs it at build time.

On macOS a forked Ansible worker dies in `hvac`'s proxy lookup ("A worker
was found in a dead state") unless `OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES`
is set. The Ansible Makefiles export it; set it yourself when you run
`ansible-playbook` directly.

## Admin user and root token

After the first `terraform/vault` apply, still logged in with the root
token:

```bash
vault token lookup                                        # note the "accessor" row
read -rs VAULT_PW                                         # password from Bitwarden
printf '%s' "$VAULT_PW" | vault write auth/userpass/users/maintainer \
  token_policies=admin password=-
unset VAULT_PW
vault login -method=userpass username=maintainer
vault token revoke -accessor <root accessor>
```

`printf` is a shell builtin, so the password never appears in a process
list. From then on, log in with userpass. When a root token is needed
again, generate one from the unseal keys (`vault operator generate-root`)
and revoke it afterwards.

## Unseal (after every restart)

```bash
export VAULT_ADDR=https://vault.example.com:8200
vault operator unseal    # key 1
vault operator unseal    # key 2
vault status             # Sealed: false
```

`docker ps` shows the container `unhealthy` while sealed: the healthcheck
is `vault status`, which exits 2 then.

## Planned restart or upgrade

1. Merge the change (an approved Renovate MR, or a `vault.hcl` edit).
2. `make komodo-deploy STACK=vault`.
3. A `vault.hcl`-only change also needs `docker restart vault` on the host.
   The deploy leaves an unchanged compose project running, and the file is
   bind-mounted on its own: the container keeps the copy it started with
   until it restarts. Check with
   `docker exec vault grep <new setting> /vault/config/vault.hcl`.
4. Unseal.

A `vault.hcl` change does nothing before step 3 (`requires = "None"`).

## Restore from a snapshot

The snapshots are encrypted by Vault's barrier: restoring one needs the
unseal keys of the Vault that took it.

1. Copy the snapshot out of `/var/backups/vault` (or from a PBS restore of
   `ct/416`).
2. On an unsealed Vault, logged in as an admin:
   `vault operator raft snapshot restore -force <file>`. On a fresh Vault,
   `vault operator init` it first and log in with that root token.
3. Vault seals itself. Unseal with the keys from Bitwarden, the keys of the
   snapshot's Vault, not the fresh init's.

`vault operator raft snapshot inspect <file>` reads a snapshot without
restoring it.

## Certificate

- `lego-vault.timer` runs `lego run` daily. lego renews when the
  certificate is due, and the deploy hook installs the new files and sends
  SIGHUP.
- Logs: `journalctl -u lego-vault.service`.
- Force a renewal: `sudo systemctl start lego-vault.service` with
  `--renew-force` added by hand, or delete the certificate under
  `/etc/lego/certificates` and start the service.
