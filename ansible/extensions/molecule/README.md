# Molecule scenarios

<!-- markdownlint-disable MD013 MD060 -->

Role tests for the `homelab.proxmox` collection, run with
[Molecule](https://ansible.readthedocs.io/projects/molecule/) using the Docker
driver against a systemd-enabled Debian image (matching the LXC fleet).

## Coverage

| Scenario        | Role            | What it checks                                   |
| --------------- | --------------- | ------------------------------------------------ |
| `common_system` | `common_system` | OS validation, APT update, base packages, backup dir |
| `common_users`  | `common_users`  | admin user, passwordless sudo, authorized_keys copy  |
| `common_ssh`    | `common_ssh`    | sshd hardening block + `sshd -t` validity        |

Each scenario runs converge → idempotence → verify.

**Not molecule-tested** (integration-heavy, not unit-testable in a plain
container): `common_docker` (needs Docker-in-Docker), `komodo_core` /
`komodo_periphery` (need a Docker daemon + Komodo), `talos_cluster` (needs
talosctl + a live Talos cluster). These are exercised by their playbooks against
real hosts.

## Running

From the collection root (`ansible/`), build + install the collection so the
`homelab.proxmox.*` FQCNs resolve, then run a scenario:

```bash
ansible-galaxy collection build --force --output-path /tmp/coll
ansible-galaxy collection install /tmp/coll/homelab-proxmox-*.tar.gz -p ./collections --force
export ANSIBLE_COLLECTIONS_PATH="$PWD/collections"
molecule test -s common_ssh        # or common_system / common_users
```

CI runs these in the `test:molecule` job (see `.gitlab-ci.yml`), gated to
changes under `ansible/roles/` or `ansible/extensions/molecule/`. The CI image
([`.ci/docker/Dockerfile`](../../../.ci/docker/Dockerfile)) ships molecule + the
Docker driver and drives containers over the runner's host Docker socket.
