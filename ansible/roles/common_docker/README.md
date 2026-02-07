# Ansible Role: common_docker

Installs and configures Docker Engine with Docker Compose plugin for Debian
13+ and Ubuntu 24+. Optimized for production LXC containers and VMs.

## Requirements

- Ansible 2.9+
- Debian 13+ or Ubuntu 24.04+
- Root or sudo access
- Network connectivity (for Docker repository access)
- User variable must be set (for group membership)

## Dependencies

- `common_system` role (runs first)

## Role Variables

### Core Configuration

<!-- markdownlint-disable MD013 -->

| Variable                      | Description                          | Default       |
| ----------------------------- | ------------------------------------ | ------------- |
| `common_docker_dir`           | Base directory for Docker containers | `/srv/docker` |
| `common_docker_create_readme` | Create README in Docker directory    | `true`        |
| `common_docker_test_run`      | Run hello-world test after install   | `false`       |

<!-- markdownlint-enable MD013 -->

### Docker Repository

<!-- markdownlint-disable MD013 -->

| Variable                      | Description           | Default                                       |
| ----------------------------- | --------------------- | --------------------------------------------- |
| `docker_repo_url`             | Docker repository URL | Auto-detected from OS                         |
| `docker_distribution_release` | Distribution release  | `{{ ansible_facts['distribution_release'] }}` |

<!-- markdownlint-enable MD013 -->

### Docker Daemon Configuration

| Variable             | Description                  | Default |
| -------------------- | ---------------------------- | ------- |
| `docker_tls_enabled` | Enable TLS for Docker daemon | `false` |

### User Configuration

| Variable | Description                     | Default                  |
| -------- | ------------------------------- | ------------------------ |
| `user`   | Username to add to docker group | Required (from playbook) |

## Example Playbook

```text
- hosts: all
  become: true
  roles:
    - role: common_docker
      vars:
        user: "maintainer"
        common_docker_dir: "/srv/docker"
        common_docker_test_run: true
```

## Tags

- `docker` - All Docker-related tasks
- `install` - Package installation
- `packages` - Package management
- `config` - Configuration tasks
- `users` - User group management
- `directories` - Directory structure setup
- `setup` - Initial setup tasks
- `aliases` - Bash alias deployment
- `verify` - Verification tasks
- `check` - Check operations

## Features

1. **Docker Engine Installation** - Installs Docker CE from official repository
2. **Docker Compose Plugin** - Includes Docker Compose v2 plugin
3. **Buildx Support** - Includes Docker Buildx for advanced builds
4. **Daemon Configuration** - Configures log rotation and storage driver
5. **User Group Management** - Adds user to docker group for non-root access
6. **Directory Structure** - Creates organized Docker directory structure
7. **Bash Aliases** - Deploys comprehensive Docker command aliases
8. **Service Override** - Configures systemd service override for containerd
9. **PUID/PGID Facts** - Sets user UID/GID as facts for container use

## Daemon Settings

The role configures Docker with the following settings:

- ✅ JSON log driver with rotation (10MB max, 3 files)
- ✅ Overlay2 storage driver
- ✅ Live restore enabled (containers survive daemon restart)
- ✅ BuildKit enabled for faster builds
- ✅ Builder garbage collection (10GB default keep storage)

## Directory Structure

Creates the following structure:

```text
/srv/docker/
├── README.md (optional, documents structure)
└── {service-name}/
    └── docker-compose.yml
```

## Bash Aliases

Deploys comprehensive Docker aliases including:

- **Container Management**: `dps`, `dstop`, `drm`, `dexec`
- **Logs**: `dlogs`, `dlogsize`, `dips`
- **System Info**: `ddf`, `dinfo`
- **Cleanup**: `dprune`, `dprunevol`, `dprunesys`
- **Docker Compose**: `dcup`, `dcdown`, `dcrestart`, `dclogs`, `dcps`
- **Navigation**: `cds`, `cdservice`

## Notes

- Designed for Debian 13+ (Trixie) and Ubuntu 24+ (Noble)
- Uses official Docker repository with GPG key verification
- User must be set in playbook vars or group_vars
- Docker daemon configuration uses template:
  [templates/daemon.json.j2](templates/daemon.json.j2)
- Systemd override configured for containerd socket path
- All operations are idempotent
- Docker service enabled and started automatically

## Troubleshooting

### Docker installation fails

Check repository access and GPG key:

```bash
curl -fsSL https://download.docker.com/linux/debian/gpg
apt update
```

### User cannot run Docker commands

Verify user is in docker group:

```bash
groups $USER
```

If not, log out and back in, or run:

```bash
newgrp docker
```

### Docker daemon not starting

Check systemd status:

```bash
systemctl status docker
journalctl -u docker -n 50
```

### Permission denied errors

Ensure user is in docker group and has logged out/in:

```bash
usermod -aG docker $USER
```

### Docker Compose not found

Verify plugin installation:

```bash
docker compose version
```

If missing, reinstall:

```bash
apt install docker-compose-plugin
```

## License

MIT
