# GitLab CE

Self-hosted Git forge (GitLab CE omnibus); **serves `source.example.com`**.
Runs on the `gitlab` LXC (`10.140.0.10`); CI runs on the separate
`gitlab-runner` LXC (`10.140.0.11`). Deployed by Komodo (`komodo/stacks.toml`)
on merge to main.

- Web: `https://source.example.com`
- Git SSH: `git@source.example.com:22`

Both are LAN-only. The web UI is served by the cluster Traefik `lan`
entrypoint (MetalLB `10.140.0.60`); Git SSH is the cluster Service
`gitlab-ssh-lan`, also on `10.140.0.60`, forwarding `:22` to this LXC's
`:2222`. Neither is published through the Cloudflare tunnel. Both resources
live in the **argo-apps** repo under `apps/infra/external-services/`.

## Instance config

Non-secret instance config (reverse proxy, SSH port, memory tuning) lives in
[`omnibus_config.rb`](omnibus_config.rb) (gitlab.rb syntax). The container
loads it via `GITLAB_OMNIBUS_CONFIG = from_file('/omnibus_config.rb')`; it is
mounted read-only outside `/etc/gitlab` so reconfigure does not try to chmod
it. Edit that file to change the external URL, SSH port, or memory tuning.

## First run

1. After the stack deploys, sign in at the web URL as `root` (password =
   `root_password` in `kv/proxmox-infra/gitlab`).
2. Create a **runner authentication token**: Admin → CI/CD → Runners → New
   instance runner. Store it in Vault:
   `vault kv put -mount=kv proxmox-infra/gitlab-runner runner_token=-`, then
   `make -C ansible install-periphery HOST=gitlab-runner` and redeploy.
3. Register the runner once (token comes from the periphery secret env):

   ```bash
   docker exec gitlab-runner gitlab-runner register --non-interactive \
     --url "$CI_SERVER_URL" --token "$CI_SERVER_TOKEN" \
     --executor docker --docker-image alpine:latest
   ```

   `config.toml` then persists in `${APPDATA_DIR}/gitlab-runner/config` and is
   hot-reloaded; no restart needed.

## Backups

Handled by the existing **Proxmox Backup Server** container backup — all
GitLab state is in the LXC-rootfs bind-mounts
(`${APPDATA_DIR}/gitlab/{config,logs,data}`), including repos, the bundled
Postgres, uploads, and `/etc/gitlab` (`gitlab-secrets.json`). Use PBS
**stop-mode** for this LXC if you want a guaranteed application-consistent
snapshot, and ensure the PBS datastore is replicated offsite.

Optional portable artifact (for an upgrade rollback / host migration):

```bash
docker exec gitlab gitlab-backup create   # tar in ${APPDATA_DIR}/gitlab/data
# also copy ${APPDATA_DIR}/gitlab/config (gitlab.rb + gitlab-secrets.json)
```
