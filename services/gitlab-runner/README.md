# GitLab Runner

CI runner for `source.example.com`. Runs on its own `gitlab-runner` LXC
(`10.40.0.19`), isolated from the GitLab server (`gitlab` LXC, `10.40.0.18`).
Deployed by Komodo (`komodo/stacks.toml`, stack `gitlab-runner`) on merge to
main.

Executor: **Docker, binding this host's Docker socket** (not privileged DinD,
not Kubernetes). CI jobs build images with plain `docker build` against the
host daemon. Safe because the runner has its own LXC — jobs cannot reach the
GitLab server or its data.

## Registration (one-time)

The runner authentication token (`glrt-…`) comes from GitLab (Admin → CI/CD →
Runners → New instance runner), stored as `vault_gitlab_runner_token` and
delivered to the stack via the periphery secret env (see
[`../gitlab/README.md`](../gitlab/README.md) "First run"). Register once:

```bash
docker exec gitlab-runner gitlab-runner register --non-interactive \
  --url "$CI_SERVER_URL" --token "$CI_SERVER_TOKEN" \
  --executor docker --docker-image docker:28-cli
```

## config.toml (REQUIRED post-register tuning)

`register` writes `config.toml` to `${APPDATA_DIR}/gitlab-runner/config/`
(host path `/srv/docker/appdata/gitlab-runner/config/config.toml`). It is **not
in git** and is **hot-reloaded** (no restart). The register defaults are NOT
sufficient — edit `[runners.docker]` to:

```ini
concurrent = 2                          # socket-bind ceiling: one shared host
                                        # daemon, so keep concurrency low

[[runners]]
  executor = "docker"
  [runners.docker]
    # CRITICAL: mount the host Docker socket INTO job containers. The
    # docker-compose.yml mounts it into the RUNNER container, but job
    # containers get their volumes from here. Without it, docker:cli falls
    # back to tcp://docker:2375 (the DinD convention) and every `docker build`
    # fails with:
    #   error during connect: Head "http://docker:2375/_ping":
    #   dial tcp: lookup docker ... no such host
    volumes = ["/var/run/docker.sock:/var/run/docker.sock", "/cache"]
```

Verify the socket reaches a job-style sibling container:

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  docker:28-cli docker info --format 'Server: {{.ServerVersion}}'
```

`privileged` stays `false` — socket binding does not need it. Do not add a
`docker:dind` service to `.gitlab-ci.yml`; jobs talk to the host daemon
directly.

## Job tags

This is an **instance** runner tagged `docker, shared`. Pipelines target it
with `tags: [docker]` (set once per repo via a `default:` block in
`.gitlab-ci.yml`).

## Backups

Runner state is just the registration token + `config.toml` in
`${APPDATA_DIR}/gitlab-runner/config`, covered by the Proxmox Backup Server
container backup. Losing it only means re-registering a new runner token.
