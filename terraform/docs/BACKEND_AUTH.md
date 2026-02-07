# GitLab Backend Authentication

This document explains how to configure GitLab HTTP backend authentication
for Terraform state storage, so you don't have to enter your password every
time.

## Quick Setup (Recommended)

```bash
# Run the setup script with your GitLab token
cd terraform/
./setup-backend-auth.sh GITLAB_TOKEN_HERE

# Or run interactively (will prompt for token)
./setup-backend-auth.sh
```

That's it! Now `make init`, `make plan`, `make apply` will work without
prompting for credentials.

---

## Manual Setup

### Step 1: Get Your GitLab Personal Access Token

1. Go to: <https://gitlab.example.com/-/user_settings/personal_access_tokens>
2. Create a new token with these scopes:
   - ✅ `api`
   - ✅ `read_api`
   - ✅ `write_repository`
3. Copy the token (starts with `gitlab-token-`)

### Step 2: Create backend.secrets.tfvars

In each Terraform directory (`lxc/`, `linux-vms/`, `windows-vms/`):

```bash
cd lxc/  # or linux-vms/ or windows-vms/

# Create the secrets file
cat > backend.secrets.tfvars <<EOF
password = "GITLAB_TOKEN_HERE"
EOF

# Secure the file
chmod 600 backend.secrets.tfvars
```

### Step 3: Verify It Works

```bash
# Initialize Terraform (will use backend.secrets.tfvars automatically)
make init

# Should not prompt for password!
terraform plan
```

---

## How It Works

The Makefile automatically detects `backend.secrets.tfvars` and passes it to
Terraform:

```bash
.PHONY: init
init:
 @if [ -f "$(BACKEND_SECRETS)" ]; then \
  terraform init -backend-config=$(BACKEND_SECRETS) -upgrade; \
 else \
  terraform init -upgrade; \
 fi
```

This is equivalent to running:

```bash
terraform init -backend-config=backend.secrets.tfvars
```

---

## Security

✅ **Safe:**

- `backend.secrets.tfvars` is in `.gitignore` (won't be committed)
- File permissions set to `600` (only you can read it)
- Token is stored locally on your machine

⚠️ **Important:**

- Never commit `backend.secrets.tfvars` to git
- Don't share your token with others
- Rotate tokens periodically (recommended: yearly)

---

## Troubleshooting

### Still Being Prompted for Password?

Check if the file exists:

```bash
ls -la backend.secrets.tfvars
# Should show: -rw------- ... backend.secrets.tfvars
```

Check the file contents:

```bash
cat backend.secrets.tfvars
# Should show: password = "gitlab-token-..."
```

Re-run setup if needed:

```bash
cd .. && ./setup-backend-auth.sh GITLAB_TOKEN_HERE
```

### Token Invalid or Expired?

1. Create a new token at:
   <https://gitlab.example.com/-/user_settings/personal_access_tokens>
2. Update all `backend.secrets.tfvars` files with the new token
3. Or re-run: `./setup-backend-auth.sh NEW_TOKEN`

### Want to Use Environment Variables Instead?

Alternative approach (add to `~/.zshrc` or `~/.bashrc`):

```bash
export TF_HTTP_PASSWORD="GITLAB_TOKEN_HERE"
```

Then reload: `source ~/.zshrc`

This works alongside `backend.secrets.tfvars` (environment variable takes
precedence).

---

## Files Created

- `lxc/backend.secrets.tfvars` - LXC containers auth
- `linux-vms/backend.secrets.tfvars` - Linux VMs auth
- `windows-vms/backend.secrets.tfvars` - Windows VMs auth

All three files contain the same token but are kept separate per directory
for modularity.

---

## Related

- [terraform/lxc/backend.tf](lxc/backend.tf) - Backend configuration
- [terraform/linux-vms/backend.tf](linux-vms/backend.tf) - Backend configuration
- [terraform/windows-vms/backend.tf](windows-vms/backend.tf) - Backend
  configuration
