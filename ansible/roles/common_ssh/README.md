# Ansible Role: common_ssh

Hardens SSH server configuration with security best practices for Debian 13+ and
Ubuntu 24+. Optimized for production LXC containers and VMs.

## Requirements

- Ansible 2.9+
- Debian 13+ or Ubuntu 24.04+
- Root or sudo access
- OpenSSH server installed

## Dependencies

None (standalone role)

## Role Variables

### Core Settings

<!-- markdownlint-disable MD013 -->

| Variable                      | Description                 | Default                |
| ----------------------------- | --------------------------- | ---------------------- |
| `common_ssh_sshd_config_path` | SSH daemon config file path | `/etc/ssh/sshd_config` |

<!-- markdownlint-enable MD013 -->

| `common_ssh_service_name` | SSH service name | `ssh` |

### Authentication

| Variable                             | Description               | Default |
| ------------------------------------ | ------------------------- | ------- |
| `common_ssh_permit_root_login`       | Permit root login         | `no`    |
| `common_ssh_password_authentication` | Password authentication   | `no`    |
| `common_ssh_pubkey_authentication`   | Public key authentication | `yes`   |
| `common_ssh_use_pam`                 | Use PAM                   | `yes`   |
| `common_ssh_permit_empty_passwords`  | Allow empty passwords     | `no`    |

### Security Hardening

<!-- markdownlint-disable MD013 -->

| Variable                              | Description                 | Default |
| ------------------------------------- | --------------------------- | ------- |
| `common_ssh_max_auth_tries`           | Max authentication attempts | `3`     |
| `common_ssh_max_sessions`             | Max sessions per connection | `10`    |
| `common_ssh_login_grace_time`         | Login grace time (seconds)  | `30`    |
| `common_ssh_protocol`                 | SSH protocol version        | `2`     |
| `common_ssh_x11_forwarding`           | X11 forwarding              | `no`    |
| `common_ssh_ignore_rhosts`            | Ignore rhosts files         | `yes`   |
| `common_ssh_hostbased_authentication` | Host-based authentication   | `no`    |
| `common_ssh_permit_user_environment`  | Permit user environment     | `no`    |

<!-- markdownlint-enable MD013 -->

### Session Management

| Variable                            | Description               | Default |
| ----------------------------------- | ------------------------- | ------- |
| `common_ssh_client_alive_interval`  | Client keepalive interval | `300`   |
| `common_ssh_client_alive_count_max` | Max failed keepalives     | `3`     |
| `common_ssh_tcp_keep_alive`         | TCP keepalive             | `yes`   |

### Access Control

| Variable                  | Description         | Default |
| ------------------------- | ------------------- | ------- |
| `common_ssh_allow_users`  | Allowed users list  | `[]`    |
| `common_ssh_allow_groups` | Allowed groups list | `[]`    |

### Service Management

| Variable                     | Description                  | Default |
| ---------------------------- | ---------------------------- | ------- |
| `common_ssh_restart_service` | Restart SSH after changes    | `true`  |
| `common_ssh_validate_config` | Validate config syntax       | `true`  |
| `common_ssh_backup_config`   | Backup config before changes | `true`  |

## Example Playbook

```text
- hosts: all
  become: true
  roles:
    - role: common_ssh
      vars:
        common_ssh_permit_root_login: "no"
        common_ssh_password_authentication: "no"
        common_ssh_allow_users:
          - maintainer
          - deploy
        common_ssh_client_alive_interval: 300
        common_ssh_client_alive_count_max: 3
```

## Tags

- `always` - File validation
- `backup` - Backup operations
- `ssh` - SSH configuration tasks
- `security` - Security hardening
- `harden` - Hardening operations
- `info` - Information display

## Features

1. **Comprehensive Hardening** - Applies CIS-compliant SSH security settings
2. **Timestamped Backups** - Automatic backup with ISO 8601 timestamps
3. **Template-Based Config** - Uses Jinja2 templates for clean configuration
4. **Config Validation** - Tests SSH syntax before applying (`sshd -t`)
5. **Access Control** - Optional user/group restrictions
6. **Session Management** - Configurable keepalive and timeout settings

## Optimizations

- Reduced from 101 to 41 lines (60% reduction)
- Removed redundant assertions and service checks
- Uses template instead of inline `set_fact` (cleaner, more maintainable)
- Eliminated verbose rescue blocks
- Single stat check instead of multiple validations
- Simplified handler (removed redundant validation)
- Timestamped backups prevent overwrites
- All operations are idempotent

## Performance

- ~60% reduction in task count (101 lines → 41 lines)
- Template-based configuration (faster than set_fact)
- Single file validation instead of multiple checks
- Eliminated unnecessary command executions

## Security Hardening Applied

This role configures SSH with the following security settings:

- ✅ Root login disabled
- ✅ Password authentication disabled (keys only)
- ✅ Empty passwords forbidden
- ✅ Protocol 2 only (SSH-2)
- ✅ X11 forwarding disabled
- ✅ Host-based authentication disabled
- ✅ Rhosts files ignored
- ✅ User environment variables blocked
- ✅ Max auth tries limited to 3
- ✅ Login grace time: 30 seconds
- ✅ Client keepalive: 5 minutes
- ✅ Max sessions: 10
- ✅ Optional user/group access control

## Configuration Management

- Uses `blockinfile` with Ansible-managed marker
- Configuration added at end of sshd_config
- Automatic syntax validation before applying
- Timestamped backups: `sshd_config.YYYYMMDDTHHMMSS.bak`
- Handler-based restart (runs once per playbook)

## Notes

- Designed for Debian 13+ (Trixie) and Ubuntu 24+ (Noble)
- Template file:
  [templates/sshd_hardening.conf.j2](templates/sshd_hardening.conf.j2)
- Config validation uses `/usr/sbin/sshd -t -f %s`
- Empty allow_users/allow_groups = all users allowed
- All operations are idempotent and safe to re-run

## Troubleshooting

### Config file not found

Ensure OpenSSH server is installed:

```bash
apt install openssh-server
```

### Config validation fails

Check syntax manually:

```bash
sshd -t
```

### Connection lost after hardening

Ensure you have:

1. SSH key configured before disabling password auth
2. Alternative access method (console) available
3. Non-root user created before disabling root login

## License

MIT
