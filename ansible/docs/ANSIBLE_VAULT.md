# Ansible Vault Guide

Complete guide to managing encrypted secrets with Ansible Vault in this
infrastructure project.

## Table of Contents

- [Overview](#overview)
- [Vault Files in This Project](#vault-files-in-this-project)
- [Common Operations](#common-operations)
- [Makefile Commands](#makefile-commands)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

Ansible Vault encrypts sensitive data (passwords, API tokens, SSH keys) so
they can be safely stored in version control. All vault files in this project
use AES256 encryption and require a password to access.

### Why Use Ansible Vault?

- ✅ **Version Control Safety** - Commit encrypted secrets to Git without
  exposing sensitive data
- ✅ **Shared Secrets** - Team members can decrypt with shared vault password
- ✅ **Audit Trail** - Track changes to secrets in Git history
- ✅ **GitOps Compatible** - Encrypted secrets work seamlessly with automated
  deployments

---

## Vault Files in This Project

### Encrypted Vault Files

<!-- markdownlint-disable MD013 -->

| File                                           | Purpose                                    | Encryption Status |
| ---------------------------------------------- | ------------------------------------------ | ----------------- |
| `group_vars/all/vault.yml`                     | Global secrets (API tokens, SSH passwords) | ✅ Encrypted      |
| `lxc/inventory/group_vars/all/vault.yml`       | LXC-specific secrets                       | ✅ Encrypted      |
| `linux-vms/inventory/group_vars/all/vault.yml` | Linux VM-specific secrets                  | ✅ Encrypted      |

<!-- markdownlint-enable MD013 -->

### Plain Text Variable Files

<!-- markdownlint-disable MD013 -->

| File                       | Purpose                          | Encryption Status |
| -------------------------- | -------------------------------- | ----------------- |
| `group_vars/all/users.yml` | Non-sensitive user configuration | ❌ Plain text     |

<!-- markdownlint-enable MD013 -->

**Security Check**: All vault files start with `$ANSIBLE_VAULT;1.1;AES256` when
properly encrypted.

---

## Common Operations

### View Encrypted Secrets

**Read-only** access to vault contents without modifying:

```bash
cd ansible
make vault-view
# Enter vault password when prompted
```

**Alternative** (direct command):

```bash
ansible-vault view group_vars/all/vault.yml
```

### Edit Encrypted Secrets

**Edit** vault file in your default editor (`$EDITOR`):

```bash
cd ansible
make vault-edit
# Enter vault password when prompted
# Make changes in editor
# Save and exit - file will be re-encrypted automatically
```

**Alternative** (direct command):

```bash
ansible-vault edit group_vars/all/vault.yml
```

**What Happens**:

1. Prompts for vault password
2. Decrypts file to temporary location
3. Opens in editor (`vim`, `nano`, etc.)
4. Re-encrypts file on save
5. Deletes temporary decrypted file

### Encrypt a New File

Create a new encrypted file from scratch:

```bash
cd ansible
# Interactive creation
ansible-vault create group_vars/all/new-vault.yml
# Enter vault password (twice)
# File opens in editor - add content
# Save and exit - file is encrypted
```

### Manually Encrypt Existing File

Convert existing plain text file to encrypted vault:

```bash
cd ansible
make vault-encrypt
# Encrypts group_vars/all/vault.yml
```

**Alternative** (specific file):

```bash
ansible-vault encrypt path/to/file.yml
```

**Warning**: This **replaces** the original file with encrypted version. Make
a backup first if unsure.

### Manually Decrypt File

**⚠️ DANGEROUS**: Decrypt vault file to plain text (temporarily):

```bash
cd ansible
make vault-decrypt
# WARNING prompt displayed
# Enter 'yes' to confirm
# File decrypted to plain text
```

**When to use**:

- Debugging vault corruption issues
- Converting secrets to GitLab CI/CD variables
- **NEVER** commit decrypted files to Git

**After use**:

```bash
make vault-encrypt  # Re-encrypt immediately
```

### Change Vault Password

Rotate the vault password:

```bash
cd ansible
make vault-rekey
# Enter current password
# Enter new password (twice)
```

**Alternative** (direct command):

```bash
ansible-vault rekey group_vars/all/vault.yml
```

---

## Makefile Commands

The project provides convenient Make targets for vault operations:

<!-- markdownlint-disable MD013 -->

| Command              | Purpose                         | Confirmation Required |
| -------------------- | ------------------------------- | --------------------- |
| `make vault-view`    | View vault contents (read-only) | No                    |
| `make vault-edit`    | Edit vault in editor            | No                    |
| `make vault-encrypt` | Encrypt vault file              | No                    |
| `make vault-decrypt` | **Decrypt vault to plain text** | ✅ Yes (dangerous)    |
| `make vault-rekey`   | Change vault password           | No                    |
| `make vault-check`   | Verify vault is encrypted       | No                    |

<!-- markdownlint-enable MD013 -->

### vault-check: Pre-Commit Verification

**Critical for security** - run before committing Ansible changes:

```bash
cd ansible
make vault-check
```

**What it checks**:

- ✅ Vault file exists
- ✅ Vault starts with `$ANSIBLE_VAULT;1.1;AES256` header
- ✅ File is not plain text

**Output**:

```text
✓ Vault is properly encrypted
```

**Failure**:

```text
✗ ERROR: vault.yml is NOT encrypted!
  Run 'make vault-encrypt' before committing.
```

**Add to Git pre-commit hook** (recommended):

```bash
#!/bin/bash
# .git/hooks/pre-commit
cd ansible && make vault-check || exit 1
```

---

## Security Best Practices

### ✅ DO - Vault Security

- **Use strong vault passwords** - Minimum 16 characters, mixed case,
  numbers, symbols
- **Store vault password securely** - Use password manager (1Password,
  LastPass, Bitwarden)
- **Run `vault-check` before commits** - Prevent accidental plain text
  commits
- **Rotate vault password periodically** - Use `vault-rekey` every 90 days
- **Use different passwords per environment** - Separate vault passwords for
  dev/staging/prod
- **Limit vault access** - Only grant access to team members who need it
- **Document vault password location** - Team should know where to find
  password (but not in Git!)

### ❌ DON'T - Vault Security

- **Don't commit vault password to Git** - NEVER store password in
  repository
- **Don't share passwords via email/Slack** - Use secure channels (encrypted
  messaging)
- **Don't disable `host_key_checking`** - Keep SSH verification enabled in
  production
- **Don't store vault password in shell history** - Avoid `echo $VAULT_PASSWORD`
- **Don't run `vault-decrypt` without re-encrypting** - Always re-encrypt
  immediately
- **Don't use weak passwords** - "password123" is NOT acceptable

### Vault Password Storage Options

**Recommended**:

1. **Password Manager** - 1Password, Bitwarden, LastPass
2. **Environment Variable** -
   `export ANSIBLE_VAULT_PASSWORD_FILE=~/.vault_pass.txt`
3. **Vault Password File** - Store in `~/.vault_pass.txt` (chmod 600)

**Not Recommended**:

- Plain text file in repository
- Shared via email or chat
- Sticky note on monitor

---

## Troubleshooting

### "Decryption failed" Error

**Symptoms**:

```text
ERROR! Decryption failed (no vault secrets were found that could decrypt)
```

**Causes**:

1. Wrong vault password
2. Corrupted vault file
3. File not actually encrypted

**Solution**:

```bash
# 1. Verify file is encrypted
make vault-check

# 2. Try viewing with correct password
make vault-view
# If successful, password is correct

# 3. If file is corrupted, restore from Git
git checkout group_vars/all/vault.yml
```

### Accidentally Committed Decrypted Vault

#### ⚠️ CRITICAL SECURITY ISSUE

**Immediate Actions**:

```bash
# 1. Remove from Git history
git filter-branch --force --index-filter \
  'git rm --cached --ignore-unmatch group_vars/all/vault.yml' \
  --prune-empty --tag-name-filter cat -- --all

# 2. Force push (requires team coordination)
git push origin --force --all

# 3. Rotate ALL secrets in vault
make vault-edit
# Change every password, token, key

# 4. Update vault password
make vault-rekey
```

**Prevention**:

- Set up pre-commit hook with `vault-check`
- Add `.git/hooks/pre-commit` script
- Use Git pre-commit framework

### Vault File Corrupted

**Symptoms**:

- Decryption fails with valid password
- File doesn't start with `$ANSIBLE_VAULT;1.1;AES256`

**Solution**:

```bash
# Restore from Git history
git log -- group_vars/all/vault.yml  # Find last good commit
git show <commit-hash>:group_vars/all/vault.yml > vault.yml.backup
mv vault.yml.backup group_vars/all/vault.yml
```

### Forgot Vault Password

**Solution**:

Unfortunately, **there is no password recovery** for Ansible Vault. You must:

1. Recreate all secrets from original sources
2. Create new vault file with new password
3. Update vault password in team documentation

**Prevention**:

- Store vault password in team password manager
- Document password location in team wiki
- Multiple team members should have access

---

## Example Vault Structure

### group_vars/all/vault.yml

```text
---
# Proxmox API Credentials
vault_proxmox_api_token_id: "terraform@pam!terraform-token"
vault_proxmox_api_token_secret: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Ansible User Password (for sudo)
vault_ansible_user_password: "$6$rounds=656000$..." # hashed password

# GitLab CI/CD
vault_gitlab_runner_token: "xxxxxxxxxxxxxxxxxxxx"

# Service Secrets
vault_pihole_password: "strong-password-here"
vault_semaphore_admin_password: "another-strong-password"
```

### Using Vault Variables in Playbooks

```text
---
- name: Configure Pi-hole
  hosts: pihole_servers
  vars:
    pihole_admin_password: "{{ vault_pihole_password }}" # Reference vault variable
  tasks:
    - name: Set Pi-hole password
      command: pihole -a -p "{{ pihole_admin_password }}"
```

---

## Related Documentation

<!-- markdownlint-disable MD013 -->

- [Ansible Vault Documentation](https://docs.ansible.com/ansible/latest/user_guide/vault.html)
<!-- markdownlint-enable MD013 -->
- [Ansible README](../README.md) - Main Ansible documentation
- [Main README](../../README.md) - Full project documentation

---

**⚠️ Remember**: Always run `make vault-check` before committing Ansible
changes!
