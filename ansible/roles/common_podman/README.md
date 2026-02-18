# Ansible Role: common_podman

Installs and configures rootless Podman for Debian 13+ and Ubuntu 24+.
Optimized for LXC containers with proper user lingering and socket management.

## Requirements

- Ansible 2.9+
- Debian 13+ or Ubuntu 24.04+
- Root or sudo access
- User account already created (via common_users role)

## Dependencies

- `common_system` role (runs first)

## Role Variables

### User Configuration

<!-- markdownlint-disable MD013 -->

| Variable             | Description              | Default                           |
| -------------------- | ------------------------ | --------------------------------- |
| `common_podman_user` | User for rootless Podman | `{{ user \| default('maintainer') }}` |

<!-- markdownlint-enable MD013 -->

### Directory Structure

<!-- markdownlint-disable MD013 -->

| Variable                      | Description                   | Default           |
| ----------------------------- | ----------------------------- | ----------------- |
| `common_podman_dir`           | Base directory for containers | `/srv/podman`     |
| `common_podman_config_dir`    | System config directory       | `/etc/containers` |
| `common_podman_create_readme` | Create README in podman_dir   | `true`            |

<!-- markdownlint-enable MD013 -->

### Package Configuration

<!-- markdownlint-disable MD013 -->

| Variable                 | Description         | Default                                             |
| ------------------------ | ------------------- | --------------------------------------------------- |
| `common_podman_packages` | Packages to install | `['podman', 'podman-compose', 'buildah', 'skopeo']` |

<!-- markdownlint-enable MD013 -->

### Podman Configuration

| Variable                        | Description         | Default    |
| ------------------------------- | ------------------- | ---------- |
| `common_podman_cgroup_manager`  | Cgroup manager type | `cgroupfs` |
| `common_podman_network_backend` | Network backend     | `netavark` |
| `common_podman_events_logger`   | Events logger type  | `file`     |

### Registry Configuration

<!-- markdownlint-disable MD013 -->

| Variable                   | Description          | Default                               |
| -------------------------- | -------------------- | ------------------------------------- |
| `common_podman_registries` | Container registries | `['docker.io', 'quay.io', 'ghcr.io']` |

<!-- markdownlint-enable MD013 -->

| `common_podman_default_registry` | Default registry | `docker.io` |

### Rootless Configuration

| Variable                              | Description               | Default |
| ------------------------------------- | ------------------------- | ------- |
| `common_podman_enable_user_lingering` | Enable loginctl lingering | `true`  |
| `common_podman_enable_socket`         | Enable Podman socket      | `true`  |
| `common_podman_export_runtime_dir`    | Export XDG_RUNTIME_DIR    | `true`  |
| `common_podman_export_dbus_address`   | Export DBUS address       | `true`  |

### Utilities

| Variable                            | Description           | Default |
| ----------------------------------- | --------------------- | ------- |
| `common_podman_deploy_aliases`      | Deploy Podman aliases | `true`  |
| `common_podman_test_run`            | Test with hello-world | `false` |
| `common_podman_verify_installation` | Verify installation   | `true`  |

## Example Playbook

```text
- hosts: all
  become: true
  roles:
    - role: common_podman
      vars:
        common_podman_user: "maintainer"
        common_podman_registries:
          - "docker.io"
          - "ghcr.io"
        common_podman_verify_installation: true
```

## Tags

- `podman` - All Podman tasks
- `install` - Package installation
- `packages` - Package management
- `config` - Configuration tasks
- `directories` - Directory creation
- `rootless` - Rootless setup
- `socket` - Socket management
- `environment` - Environment variables
- `aliases` - Alias deployment
- `verify` - Verification tasks

## Features

1. **Rootless Podman** - User-level container management
2. **Multiple Registries** - Docker Hub, Quay.io, GitHub Container Registry
3. **User Lingering** - Containers survive logout
4. **Podman Socket** - API compatibility
5. **Template-Based Config** - Clean, maintainable configurations
6. **Additional Tools** - Buildah, Skopeo included

## Optimizations

- Reduced from 209 to 166 lines (21% reduction)
- Removed redundant user validation
- Template-based config files (cleaner than inline)
- Added buildah and skopeo packages
- Retry logic for package installation
- Simplified fact setting (single task)
- Removed unnecessary assertions
- Better variable organization

## Performance

- ~21% reduction in task count (209 lines → 166 lines)
- Template-based configs (faster than inline content)
- Single getent call instead of multiple
- Retry logic prevents manual reruns
- Failed_when: false for optional tasks

## Rootless Podman Setup

This role configures:

- ✅ User lingering enabled (containers survive logout)
- ✅ Podman socket enabled (API access)
- ✅ XDG_RUNTIME_DIR exported
- ✅ DBUS_SESSION_BUS_ADDRESS exported
- ✅ Cgroupfs manager (LXC compatible)
- ✅ Netavark network backend
- ✅ Multi-registry support
- ✅ Podman aliases

## Configuration Files

### containers.conf

Located at: `~/.config/containers/containers.conf`

```text
[engine]
cgroup_manager = "cgroupfs"
events_logger = "file"

[network]
network_backend = "netavark"
```

### registries.conf

Located at: `~/.config/containers/registries.conf`

Configures unqualified image search order and registry settings.

## Notes

- Designed for Debian 13+ (Trixie) and Ubuntu 24+ (Noble)
- Uses cgroupfs for LXC compatibility
- User must exist before running (create with common_users role)
- Socket may fail in some LXC configurations (failed_when: false)
- All operations are idempotent

## Troubleshooting

### Package installation fails

Check network and apt cache:

```bash
apt update
apt install podman
```

### User lingering fails

Verify systemd is running:

```bash
systemctl status
```

### Socket fails to start

This is expected in some LXC setups. The role continues with failed_when:
false.

### Containers don't persist after logout

Verify lingering is enabled:

```bash
loginctl show-user username | grep Linger
```

## License

MIT
