# Ansible Tags Guide

Complete reference for using Ansible tags to run specific tasks or roles in
this infrastructure project.

## Table of Contents

- [Overview](#overview)
- [Bootstrap Tags](#bootstrap-tags)
- [Configure Tags](#configure-tags)
- [K3s Cluster Tags](#k3s-cluster-tags)
- [Usage Examples](#usage-examples)
- [Best Practices](#best-practices)

---

## Overview

Ansible tags enable targeted execution of specific tasks without running
entire playbooks. This is useful for:

- ✅ **Selective Updates** - Run only security-related tasks
- ✅ **Faster Execution** - Skip unnecessary tasks
- ✅ **Troubleshooting** - Re-run specific failed tasks
- ✅ **Development** - Test individual roles

### Tag Syntax

```bash
# Run specific tags
ansible-playbook playbook.yml --tags "tag1,tag2"

# Skip specific tags
ansible-playbook playbook.yml --skip-tags "tag1,tag2"

# List available tags
ansible-playbook playbook.yml --list-tags
```

---

## Bootstrap Tags

Bootstrap playbooks create users and harden SSH - **run once per host**.

### LXC Bootstrap (`playbooks/lxc/bootstrap.yml`)

<!-- markdownlint-disable MD013 -->

| Tag         | Scope                         | Purpose                                     |
| ----------- | ----------------------------- | ------------------------------------------- |
| `bootstrap` | Entire playbook               | Run complete bootstrap process              |
| `system`    | `common_system` role          | System updates and packages                 |
| `packages`  | `common_system` role          | Install base packages (vim, curl, git)      |
| `users`     | `common_users` role           | Create non-root user, SSH keys              |
| `security`  | `common_users` + `common_ssh` | User creation + SSH hardening               |
| `ssh`       | `common_ssh` role             | SSH hardening (disable root, key-only auth) |

<!-- markdownlint-enable MD013 -->

### Linux VM Bootstrap (`playbooks/linux-vms/bootstrap.yml`)

Same tags as LXC bootstrap.

### Tag Dependencies (Bootstrap)

```text
bootstrap (entire playbook)
├── system, packages → common_system role
├── users, security   → common_users role
└── ssh, security     → common_ssh role
```

**Order matters**: `users` must run before `ssh` (SSH hardening requires user
to exist).

### Bootstrap Usage Examples

**Complete bootstrap**:

```bash
cd ansible
ansible-playbook playbooks/lxc/bootstrap.yml -i inventory/lxc-hosts.yml \
  --limit pihole-1 --tags bootstrap
```

**System updates only**:

```bash
ansible-playbook playbooks/lxc/bootstrap.yml -i inventory/lxc-hosts.yml \
  --limit pihole-1 --tags system
```

**User creation only** (skip SSH hardening):

```bash
ansible-playbook playbooks/lxc/bootstrap.yml -i inventory/lxc-hosts.yml \
  --limit pihole-1 --tags users
```

**Security tasks only** (users + SSH):

```bash
ansible-playbook playbooks/lxc/bootstrap.yml -i inventory/lxc-hosts.yml \
  --limit pihole-1 --tags security
```

**Skip SSH hardening** (for debugging):

```bash
ansible-playbook playbooks/lxc/bootstrap.yml -i inventory/lxc-hosts.yml \
  --limit pihole-1 --skip-tags ssh
```

---

## Configure Tags

Configure playbooks install container runtimes (Docker/Podman) - **run once
per host** after bootstrap.

### LXC Configure (`playbooks/lxc/configure.yml`)

| Tag           | Scope                | Purpose                           |
| ------------- | -------------------- | --------------------------------- |
| `configure`   | Entire playbook      | Run complete configuration        |
| `system`      | `common_system` role | System updates and packages       |
| `packages`    | `common_system` role | Install base packages             |
| `update`      | `common_system` role | System package updates            |
| `docker`      | `common_docker` role | Full Docker installation + config |
| `containers`  | `common_docker` role | Same as `docker`                  |
| `install`     | `common_docker` role | Install Docker packages only      |
| `config`      | `common_docker` role | Docker daemon config only         |
| `users`       | `common_docker` role | Add user to docker group          |
| `directories` | `common_docker` role | Create `/srv/docker/` structure   |
| `setup`       | `common_docker` role | daemon.json + directories + users |
| `aliases`     | `common_docker` role | Create `~/.bash_aliases`          |
| `verify`      | `common_docker` role | Verify Docker installation        |
| `check`       | `common_docker` role | Same as `verify`                  |

### Linux VM Configure (`playbooks/linux-vms/configure.yml`)

| Tag         | Scope                | Purpose                           |
| ----------- | -------------------- | --------------------------------- |
| `configure` | Entire playbook      | Run complete configuration        |
| `system`    | `common_system` role | System updates and packages       |
| `packages`  | `common_system` role | Install base packages             |
| `update`    | `common_system` role | System package updates            |
| `podman`    | `common_podman` role | Full Podman installation + config |
| `install`   | `common_podman` role | Install Podman packages only      |
| `config`    | `common_podman` role | Podman config files               |

### Tag Dependencies (Configure - LXC)

```text
configure (entire playbook)
├── system, packages, update → common_system role
└── docker, containers       → common_docker role
    ├── install, packages
    ├── config
    ├── users
    ├── directories
    ├── setup → config + directories + users
    ├── aliases
    └── verify, check
```

### Configure Usage Examples

**Complete configuration**:

```bash
cd ansible
ansible-playbook playbooks/lxc/configure.yml -i inventory/lxc-hosts.yml \
  --limit pihole-1 --tags configure
```

**Docker installation only**:

```bash
ansible-playbook playbooks/lxc/configure.yml -i inventory/lxc-hosts.yml \
  --limit pihole-1 --tags docker
```

**Update Docker daemon config**:

```bash
ansible-playbook playbooks/lxc/configure.yml -i inventory/lxc-hosts.yml \
  --limit pihole-1 --tags config
```

**Recreate `/srv/docker/` structure**:

```bash
ansible-playbook playbooks/lxc/configure.yml -i inventory/lxc-hosts.yml \
  --limit pihole-1 --tags directories
```

**System updates only** (no Docker changes):

```bash
ansible-playbook playbooks/lxc/configure.yml -i inventory/lxc-hosts.yml \
  --limit pihole-1 --tags update
```

**Verify Docker installation**:

```bash
ansible-playbook playbooks/lxc/configure.yml -i inventory/lxc-hosts.yml \
  --limit pihole-1 --tags verify
```

---

## K3s Cluster Tags

K3s playbooks manage Kubernetes cluster lifecycle.

### Update Cluster (`playbooks/k3s/update-cluster.yml`)

| Tag      | Scope           | Purpose                |
| -------- | --------------- | ---------------------- |
| `update` | Entire playbook | Rolling cluster update |

**Note**: Most K3s playbooks don't use tags - they run completely.

### K3s Playbooks (No Tags)

| Playbook                | Purpose                          | Tags? |
| ----------------------- | -------------------------------- | ----- |
| `bootstrap-cluster.yml` | Initial cluster deployment       | ❌ No |
| `verify-cluster.yml`    | Health checks and diagnostics    | ❌ No |
| `diagnostics.yml`       | Detailed cluster diagnostics     | ❌ No |
| `restart-k3s.yml`       | Restart K3s service on all nodes | ❌ No |
| `reboot-cluster.yml`    | Reboot all cluster nodes         | ❌ No |
| `shutdown-cluster.yml`  | Gracefully shutdown cluster      | ❌ No |
| `system-update.yml`     | Update packages on cluster nodes | ❌ No |
| `deploy.yml`            | Deploy applications to cluster   | ❌ No |
| `update-dns.yml`        | Update cluster DNS configuration | ❌ No |

### K3s Usage Examples

**Update cluster** (rolling update with tags):

```bash
cd ansible
ansible-playbook playbooks/k3s/update-cluster.yml -i k3s/inventory/hosts.ini \
  --tags update
```

**Bootstrap cluster** (no tags):

```bash
cd ansible
ansible-playbook playbooks/k3s/bootstrap-cluster.yml -i k3s/inventory/hosts.ini
```

**Verify cluster health** (no tags):

```bash
cd ansible
ansible-playbook playbooks/k3s/verify-cluster.yml -i k3s/inventory/hosts.ini
```

---

## Usage Examples

### Via Makefile (Recommended)

The Makefile provides convenient targets that handle inventory and tags:

```bash
cd ansible

# Bootstrap (uses bootstrap.yml with bootstrap tag)
make bootstrap-host HOST=pihole-1

# Configure (uses configure.yml with configure tag)
make configure-host HOST=pihole-1

# K3s operations
make k3s-bootstrap
make k3s-verify
make k3s-update
```

### Via Ansible Playbook Directly

#### List Available Tags

```bash
cd ansible
ansible-playbook playbooks/lxc/configure.yml --list-tags
```

**Output**:

```text
playbook: playbooks/lxc/configure.yml

  play #1 (all): Configure LXC containers  TAGS: [configure]
      TASK TAGS: [aliases, check, config, configure, containers, directories,
                 docker, install, packages, setup, system, update, users, verify]
```

#### Run Multiple Tags

```bash
cd ansible
ansible-playbook playbooks/lxc/configure.yml -i inventory/lxc-hosts.yml \
  --limit pihole-1 --tags "docker,verify"
```

#### Skip Specific Tags

```bash
cd ansible
ansible-playbook playbooks/lxc/configure.yml -i inventory/lxc-hosts.yml \
  --limit pihole-1 --skip-tags verify
```

#### Check Mode with Tags

Run in dry-run mode (no changes):

```bash
cd ansible
ansible-playbook playbooks/lxc/configure.yml -i inventory/lxc-hosts.yml \
  --limit pihole-1 --tags docker --check
```

---

## Best Practices

### ✅ DO - Using Tags

- **List tags first** - Run `--list-tags` to see available options
- **Use Makefile targets** - Abstracts tag complexity
- **Test with `--check`** - Dry-run before applying changes
- **Combine related tags** - `--tags "config,verify"` for update + validation
- **Use `system` tag** - For regular system updates
- **Document tag usage** - Note which tags were used for specific changes

### ❌ DON'T - Using Tags

- **Don't skip dependencies** - Running `ssh` tag without `users` will fail
- **Don't use tags for bootstrap** - Run complete bootstrap once
- **Don't mix incompatible tags** - `docker` and `podman` are mutually exclusive
- **Don't assume tag order** - Tags run in playbook order, not command order
- **Don't use `--tags all`** - Just run without `--tags` instead

### Common Patterns

**System updates only** (all hosts):

```bash
cd ansible
ansible-playbook playbooks/lxc/configure.yml -i inventory/lxc-hosts.yml \
  --tags update
```

**Docker config refresh** (specific host):

```bash
cd ansible
ansible-playbook playbooks/lxc/configure.yml -i inventory/lxc-hosts.yml \
  --limit pihole-1 --tags config
```

**Verify all installations** (all hosts):

```bash
cd ansible
ansible-playbook playbooks/lxc/configure.yml -i inventory/lxc-hosts.yml \
  --tags verify
```

**Complete re-configuration** (specific host):

```bash
cd ansible
ansible-playbook playbooks/lxc/configure.yml -i inventory/lxc-hosts.yml \
  --limit pihole-1 --tags configure
```

---

## Tag Quick Reference

### Most Useful Tags

| Tag        | When to Use                                 |
| ---------- | ------------------------------------------- |
| `update`   | Regular system package updates              |
| `config`   | Update Docker/Podman daemon configuration   |
| `verify`   | Verify installations after changes          |
| `docker`   | Full Docker installation or re-installation |
| `system`   | System-level tasks (packages, updates)      |
| `security` | Security-related tasks (users, SSH)         |

### Role-Specific Tags

<!-- markdownlint-disable MD013 -->

| Role            | Tags                                                                                                       |
| --------------- | ---------------------------------------------------------------------------------------------------------- |
| `common_system` | `system`, `packages`, `update`                                                                             |
| `common_users`  | `users`, `security`                                                                                        |
| `common_ssh`    | `ssh`, `security`                                                                                          |
| `common_docker` | `docker`, `containers`, `install`, `config`, `users`, `directories`, `setup`, `aliases`, `verify`, `check` |
| `common_podman` | `podman`, `install`, `config`                                                                              |
| `k3s_cluster`   | `update`                                                                                                   |

<!-- markdownlint-enable MD013 -->

---

## Related Documentation

<!-- markdownlint-disable MD013 -->

- [Ansible Tags Documentation](https://docs.ansible.com/ansible/latest/user_guide/playbooks_tags.html)
<!-- markdownlint-enable MD013 -->
- [Ansible README](../README.md) - Main Ansible documentation
- [Docker Configuration](./DOCKER.md) - Docker role details
- [Main README](../../README.md) - Full project documentation

---

**💡 Tip**: Use `--list-tags` frequently to discover available tags in each
playbook!
