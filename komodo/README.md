# Komodo Resource Sync

<!-- markdownlint-disable MD013 MD060 -->

Declarative [Komodo](https://komo.do) resources for deploying the
`services/<svc>/` docker-compose stacks. Komodo Core reconciles the runtime to
match these TOML files; Git is the source of truth.

## Files

| File                | Declares                                                       |
| ------------------- | ------------------------------------------------------------- |
| `repos.toml`        | The shared `[[repo]]` git source; stacks link it via `linked_repo` |
| `servers.toml`      | One Periphery server per LXC host (`address` = `:8120`)        |
| `variables.toml`    | Shared **non-secret** pins (`TZ`, `APPDATA_DIR`, …) as `[[VAR]]`|
| `stacks.toml`       | One stack per service: server pin, `linked_repo`, compose path, env |
| `procedures.toml`   | `GitOps Apply`, the only deploy path (one webhook)             |
| `alerters.toml`     | The ntfy alerter (Komodo alerts to the `komodo-alerts` topic)  |
| `resource-sync.toml`| The ResourceSync resource Core polls + reconciles             |

## Git source

All stacks (and this is the only place the git coordinates live once) reference
the `proxmox-infra` `[[repo]]` in `repos.toml` via `linked_repo`, instead of
repeating `git_provider` / `git_account` / `repo` / `branch` inline. One edit
there re-points every stack (branch rename, git-account rotation, org move).

> `linked_repo` shares **config, not checkouts** — each stack still clones on
> its own host. With ~one stack per host there's no clone-sharing benefit; the
> win is purely DRY. The ResourceSync keeps its git config **inline** (it must
> clone before any Repo resource exists, so it can't bootstrap from one).

## Env / secrets model

- **Non-secret** (image tags, TZ, paths, public URLs): committed here, in the
  stack `environment` block or `variables.toml`, referenced as `[[NAME]]`.
- **Secret** (DB passwords, API keys, OIDC secrets): live **host-local** in each
  periphery's `[secrets]` table — delivered by Ansible from Vault
  (`ansible/roles/komodo_periphery`, `host_vars/<svc>.yml`), **never** in
  Komodo Core's DB. Also referenced as `[[NAME]]`.
- **Core secret** (only what Core sends itself, today the ntfy alerter's
  `[[NTFY_KOMODO_AUTH]]`): Core's own `[secrets]` table in `core.config.toml`,
  rendered by `ansible/roles/komodo_core` from Vault. Not settable in the UI or
  through env vars.

## Deploy flow

Every push to `main` fires **one** GitLab webhook, to the `GitOps Apply`
Procedure (`/listener/gitlab/procedure/<id>/main`). Its stages run in order,
and the first failure stops the run and raises a `ProcedureFailed` alert:

1. **Sync** (`RunSync proxmox-infra`): applies `komodo/*.toml`.
   - Every stack sets `deploy = true`, so the sync deploys a **new** stack
     and any stack whose **Komodo config** changed (`environment`,
     `file_paths`, `server`, ...). Within an HA pair, `after` makes the
     secondary wait until the primary's deploy has returned, which with
     `--wait` means healthy. A failed primary deploy does not stop it.
   - With `delete = true` and `match_tags = ["iac"]`, a resource tagged
     `iac` that was removed from the files is deleted; for a stack that
     stops its containers. Untagged resources are never touched.
2. **Wave 1**, then **Wave 2** (`BatchDeployStackIfChanged`, tags
   `iac` + `wave-1` / `wave-2`): each stack's cache is refreshed and the
   stack is acted on only if its compose file or a `config_files` entry
   changed since its last deploy. A changed compose file redeploys; a changed
   `config_files` entry (`requires = "Restart"`) restarts the service that
   mounts it. Wave 1 holds primaries and single-node stacks, wave 2 the HA
   secondaries, so a shared change never takes a whole pair down at once.

Stacks the sync already deployed are skipped by the waves, and an unrelated
push changes nothing: Komodo filters webhooks by branch, never by path, and
`docker compose up -d` leaves an unchanged definition alone.

### Behaviour verified on Komodo 2.3.4

Checked on a canary stack (2026-10-30) and in the 2.3.4 source:

- The sync deploys a new stack on creation and redeploys on an
  `environment` change.
- `requires = "Redeploy"` for a bind-mounted file runs `compose up -d`, which
  keeps the container and the old file. `requires = "Restart"` applies it.
- `auto_pull` defaults to true, so every deploy pulls the pinned tag.
- `match_tags` filters both the files and the existing resources before
  deletions are computed. An untagged resource in the files is silently
  ignored: `scripts/komodo_lint.py --strict` requires `iac` on every
  resource and one wave tag on every stack.
- Deleting a stack stops its containers but leaves the Periphery clone of
  the linked repo, `/etc/komodo/repos/proxmox-infra/` (with the stack's
  `.env` of interpolated secrets at its root), and its images on the host.
- A failed deploy marks the Procedure failed and leaves the old containers
  running.

## Rebuilt images

CI rebuilds a self-built image (`docker/<image>/`) under its existing tag, and
no compose change follows. Once `sign:pihole`, `sign:unbound` or
`sign:semaphore` has signed the rebuilt image, the CI job
`komodo:redeploy-images` runs the
`Redeploy Images` Procedure through `scripts/komodo_trigger.py` (secret:
Vault `kv/ci/komodo` `webhook_secret`, read as role `ci-komodo`). It deploys pihole-1 and
semaphore, waits 30 s, then deploys pihole-2; each deploy pulls first, so a
stack whose digest did not change stays as it is.

## HA pairs

`technitium-1`/`technitium-2` and `pihole-1`/`pihole-2` are ordered twice:
by `after` for deploys the sync starts, and by the wave tags (with a 30 s
settle stage between the waves, since `compose up -d` returns before a
recreated service answers) for file changes. Nothing needs a manual
rollout.

Both members of a pair deploy one compose (`services/pihole/`,
`services/technitium/`); the stacks differ only in `NODE` and the other
per-node values in their `environment`. Both set `project_name` to the pair
name and `extra_args = ["--wait", "--wait-timeout=180"]`, so a deploy only
returns once its services are healthy.

`after` does not stop on a failed deploy: DeployStack records the failure
but the sync still runs the next round. A change that could fail on both
nodes the same way (a service rename, a new mount) moves the secondary in
one MR and the primary in the next, once the first is verified.

Changing a stack's `project_name` makes its next deploy run `compose down`
on the previously deployed project before `up`. That is the way to rename a
compose service: with the same project name the old container is an orphan
holding the `container_name`, and `--remove-orphans` loses the race against
the new container.

## Alerts

The `ntfy` alerter (`alerters.toml`) posts to
`https://ntfy.example.com/komodo-alerts` (argo-apps `apps/user/ntfy`) for
`ProcedureFailed`, `StackStateChange`, `ServerUnreachable`, `ServerDisk` and
`ResourceSyncPendingUpdates`. It authenticates with the `?auth=` query
parameter, `[[NTFY_KOMODO_AUTH]]` (Core secret above): the `komodo` ntfy user
may only write that topic.

- Test it: `scripts/km-run.sh test-alerter ntfy`.
- A rotated token (re-seal of the argo-apps `ntfy-secret`): update
  `ntfy_token` in `kv/proxmox-infra/komodo-core`, then `make -C ansible upgrade-komodo`, which
  re-renders `core.config.toml` and recreates the Core container.
- ntfy runs in the Talos cluster, so alerts about a cluster outage are not
  delivered.

## What stays manual

- The ResourceSync's own config (`resource-sync.toml`): a sync cannot update
  itself, so edit it in the UI to match the file.
- A change to the `GitOps Apply` Procedure itself: its sync stage cannot
  update the Procedure that is running it, so that run fails with the change
  still pending. Once it has finished, run the sync once (UI Execute, or
  `.../listener/gitlab/sync/<sync id>/sync`).
- The GitLab webhook (`docs/ANSIBLE.md`, GitLab webhook).
- Removing a stack's leftovers on its host after the sync deleted it:
  `sudo rm -rf /etc/komodo/repos/proxmox-infra` and unused images.
- Komodo Core and Periphery upgrades (`make -C ansible upgrade-komodo`, then
  `upgrade-periphery`).
- A changed secret value behind an unchanged `[[NAME]]`:
  `make -C ansible periphery-secrets HOST=<h>`, then
  `make komodo-deploy STACK=<stack>` (`docs/ANSIBLE.md`, Secrets).
