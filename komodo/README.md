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
| `procedures.toml`   | Deploy drivers: `Deploy On Push` (webhook) + `Rollout DNS HA` (manual) |
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

## Deploy flow

Every push to `main` fires **two** webhooks on the GitLab repo. They
cover disjoint concerns:

1. **ResourceSync `/sync`** — Core re-reads `komodo/*.toml`, reconciles
   any drift in Server / Stack / Variable / Procedure resource
   definitions. It does **not** deploy stacks; it only updates
   definitions.
2. **Procedure `/main`** (`Deploy On Push`) — runs a single
   `BatchDeployStackIfChanged` (pattern `"*"`). For each matched Stack,
   Periphery pulls the repo on the target host and redeploys **only** if
   the compose file (or any tracked `config_files`) differs from the last
   deployed snapshot. Unchanged stacks no-op.

> **Why a Procedure and not per-stack `/deploy` webhooks?** An earlier
> design gave each Stack its own `/deploy` webhook (~10 of them),
> justified by the belief that "ResourceSync diffs TOML, not compose
> files, so the per-Stack webhook fills the gap." That rationale was
> wrong on two counts:
>
> - A ResourceSync with `deploy = true` on a `[[stack]]` **does** deploy
>   on compose changes — it compares the deployed git commit, so a new
>   commit to a compose file triggers redeploy. (We still don't use
>   sync-driven deploy — see below — but the premise was false.)
> - A git webhook fires on **every** push to the branch; Komodo filters
>   by **branch, never by path**. So one push to `services/bitwarden/`
>   hit *all 10* per-stack listeners anyway. The only thing keeping the
>   untouched stacks quiet was `DeployStackIfChanged`'s content check —
>   the exact check `BatchDeployStackIfChanged` runs from one webhook.
>
> So per-stack webhooks bought nothing over a single batch except 10×
> the webhook bookkeeping. The Procedure is the maintainer-endorsed
> monorepo pattern (komodo issue #1433).
>
> **Why not sync-driven deploy (`deploy = true` on every stack)?** Komodo
> tracks a Stack's deployed state against **repo HEAD, not the stack's
> path** (komodo issue #1433). With `deploy = true`, *any* push would mark
> *every* stack out-of-date and fan a deploy across all 9 hosts. Routing
> through `BatchDeployStackIfChanged` instead means the per-stack content
> check still gates each redeploy, so only genuinely-changed stacks roll.

## HA pairs

`adguard-1`/`adguard-2` and `technitium-1`/`technitium-2` are normally
deployed by the single `Deploy On Push` Procedure, which runs all changed
stacks in one parallel stage. In practice each push edits one compose
file, so only one member of a pair rolls per push.

When you genuinely need a **coordinated** primary-then-secondary rollout
(e.g. a shared base-image bump that touched both members), run the
`Rollout DNS HA` Procedure from the Komodo UI. Its sequential stages roll
the primaries (`technitium-1`, `adguard-1`), wait for health, then roll
the secondaries (`technitium-2`, `adguard-2`) — each `IfChanged`, so
unchanged members no-op.

The per-`[[stack]]` `after = [...]` field is **not** used: it is only
honored by ResourceSync-driven deploys (`deploy = true`), which we don't
use. Procedure stages give the same ordering explicitly.
