# Ansible Role: common_users

Creates non-root user with sudo privileges and SSH access for Debian 13+ and
Ubuntu 24+. Optimized for secure LXC container and VM deployments.

## Requirements

- Ansible 2.9+
- Debian 13+ or Ubuntu 24.04+
- Root or sudo access
- Root's SSH authorized_keys file must exist

## Dependencies

- `common_system` role (runs first)
- `community.general` collection (for sudoers module)

## Role Variables

### User Configuration

<!-- markdownlint-disable MD013 -->

| Variable                          | Description              | Default                              |
| --------------------------------- | ------------------------ | ------------------------------------ |
| `common_users_user`               | Username to create       | `{{ user \| default('maintainer') }}`    |
| `common_users_user_shell`         | User shell               | `/bin/bash`                          |
| `common_users_user_password_hash` | Password hash (optional) | `null`                               |
| `common_users_user_comment`       | User GECOS field         | `System Administrator`               |
| `common_users_groups`             | Additional groups        | `['sudo', 'adm', 'systemd-journal']` |

<!-- markdownlint-enable MD013 -->

### Sudo Configuration

| Variable                       | Description       | Default |
| ------------------------------ | ----------------- | ------- |
| `common_users_sudo_nopassword` | Passwordless sudo | `true`  |
| `common_users_sudo_commands`   | Allowed commands  | `ALL`   |

### SSH Configuration

<!-- markdownlint-disable MD013 -->

| Variable                          | Description                 | Default                      |
| --------------------------------- | --------------------------- | ---------------------------- |
| `common_users_root_ssh_keys_path` | Root's authorized_keys path | `/root/.ssh/authorized_keys` |

<!-- markdownlint-enable MD013 -->

| `common_users_ssh_key_type` | SSH key type | `ed25519` |
| `common_users_ssh_key_bits` | SSH key bits | `4096` |

### Bash Configuration

| Variable                           | Description             | Default |
| ---------------------------------- | ----------------------- | ------- |
| `common_users_deploy_bash_aliases` | Deploy bash aliases     | `true`  |
| `common_users_bashrc_additions`    | Additional bashrc lines | `[]`    |

### Security

| Variable                            | Description              | Default |
| ----------------------------------- | ------------------------ | ------- |
| `common_users_lock_root_account`    | Lock root password       | `true`  |
| `common_users_test_sudo_access`     | Test sudo after creation | `false` |
| `common_users_expire_root_password` | Expire root password     | `true`  |

## Example Playbook

```text
- hosts: all
  become: true
  roles:
    - role: common_users
      vars:
        common_users_user: "maintainer"
        common_users_groups:
          - sudo
          - docker
        common_users_lock_root_account: true
```

## Tags

- `users` - User management tasks
- `create` - User creation
- `sudo` - Sudo configuration
- `ssh` - SSH setup
- `security` - Security tasks
- `config` - Configuration files
- `harden` - Security hardening

## Features

1. **User Creation** - Creates user with home directory and shell
2. **Group Management** - Adds user to sudo, adm, systemd-journal groups
3. **Passwordless Sudo** - Configures sudo without password requirement
4. **SSH Access** - Copies authorized_keys from root to user
5. **Bash Aliases** - Deploys custom bash aliases
6. **Root Hardening** - Locks and expires root password

## Optimizations

- Reduced from 150 to 72 lines (52% reduction)
- Removed redundant validations and stat checks
- Eliminated verbose rescue blocks
- Removed unnecessary shell validation (user module handles this)
- Removed username regex validation (Linux handles this)
- Added user to additional system groups automatically
- Simplified SSH key copying (no pre-validation needed)
- Disabled sudo testing by default (reduces execution time)

## Performance

- ~52% reduction in task count (150 lines → 72 lines)
- Eliminated 7 validation tasks
- Removed 3 rescue blocks
- Single user creation task (no pre-checks)
- Faster execution with fewer stat operations

## Security Features

- ✅ User added to sudo group for administrative access
- ✅ User added to adm group for log access
- ✅ User added to systemd-journal group for journal access
- ✅ Passwordless sudo (configurable)
- ✅ SSH key-based authentication
- ✅ Root password locked
- ✅ Root password expired
- ✅ Home directory created with proper permissions
- ✅ .ssh directory mode 0700
- ✅ authorized_keys mode 0600

## Notes

- Designed for Debian 13+ (Trixie) and Ubuntu 24+ (Noble)
- User module handles validation automatically
- Root's authorized_keys must exist before running
- Sudo validation optional (disabled by default for performance)
- Password hash can be generated: `mkpasswd -m sha-512`
- All operations are idempotent

## Troubleshooting

### User creation fails

Check that the username is valid for Linux

### SSH keys not copied

Ensure root's authorized_keys exists:

```bash
ls -la /root/.ssh/authorized_keys
```

### Sudo not working

Verify user is in sudo group:

```bash
groups username
```

## License

MIT
