# Molecule scenarios

<!-- markdownlint-disable MD013 MD060 -->

Role tests for the proxmox-infra roles, run with
[Molecule](https://ansible.readthedocs.io/projects/molecule/) using the Docker
driver against a systemd-enabled Debian image (matching the LXC fleet).

## Coverage

| Scenario        | Role            | What it checks                                   |
| --------------- | --------------- | ------------------------------------------------ |
| `common_system` | `common_system` | OS validation, APT update, base packages, backup dir |
| `common_users`  | `common_users`  | admin user, passwordless sudo, authorized_keys copy  |
| `common_ssh`    | `common_ssh`    | sshd hardening block + `sshd -t` validity        |
| `common_authorized_keys` | `common_authorized_keys` | add, remove and keep keys; exclusive mode; the empty-exclusive guard |
| `os_patch`      | `os_patch`      | preflight, apt upgrade and report in check-safe form |

Each scenario runs converge → idempotence → verify.

**Not molecule-tested** (integration-heavy, not unit-testable in a plain
container): `common_docker` (needs Docker-in-Docker), `komodo_core` /
`komodo_periphery` (need a Docker daemon + Komodo), `talos_cluster` (needs
talosctl + a live Talos cluster). These are exercised by their playbooks against
real hosts.

## Running

From `ansible/`; each scenario's `molecule.yml` points `ANSIBLE_ROLES_PATH`
at `roles/`:

```bash
make molecule-scenario S=common_ssh   # or: molecule test -s common_ssh
make molecule                         # every scenario
```

Scenarios live in `ansible/molecule/`, molecule's default location. The
`extensions/molecule/` layout only works for a Galaxy collection (it keys
on `galaxy.yml`).

CI runs these in the `test:molecule` job (see `.gitlab-ci.yml`), one
parallel job per scenario, gated to changes under `ansible/roles/` or
`ansible/molecule/`. A new scenario goes into the job's matrix and into
`MOLECULE_SCENARIOS` in `ansible/Makefile`. The CI image
([`.ci/docker/Dockerfile`](../../.ci/docker/Dockerfile)) ships molecule + the
Docker driver and drives containers over the runner's host Docker socket.
