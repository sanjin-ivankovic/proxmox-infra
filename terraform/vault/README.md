# vault — HashiCorp Vault configuration

Manages the structure of the Vault at `https://vault.example.com:8200`
([docs/VAULT.md](../../docs/VAULT.md)): mounts, the audit device, policies
and auth methods. **No secret values live here.** Secrets are written with
`vault kv put`, passwords and AppRole SecretIDs with the CLI, so none of
them reach state.

## Resources

<!-- markdownlint-disable MD013 -->
| Resource | Vault path | Purpose |
| --- | --- | --- |
| `vault_mount.kv` | `kv/` | KV v2 for every secret |
| `vault_audit.file` | `sys/audit/file` | Audit log at `/vault/logs/audit.log`, rotated by the `hashicorp_vault` role |
| `vault_policy.admin` | `admin` | Operators: everything, including `sudo` paths |
| `vault_policy.raft_snapshot` | `raft-snapshot` | Read `sys/storage/raft/snapshot` only |
| `vault_auth_backend.userpass` | `auth/userpass` | Operator login, tokens 8 h (max 24 h) |
| `vault_auth_backend.approle` | `auth/approle` | Machine login |
| `vault_approle_auth_backend_role.raft_snapshot` | `auth/approle/role/raft-snapshot` | The nightly Raft snapshot timer |
| `vault_policy.proxmox_infra_read` | `proxmox-infra-read` | Read `kv/proxmox-infra/*` and `kv/ci/komodo` |
| `vault_approle_auth_backend_role.semaphore` | `auth/approle/role/semaphore` | Semaphore's playbook runs, tokens 1 h |
| `vault_policy.mcp_reader` | `mcp-reader` | List and read `kv/metadata/*`: secret paths and versions, never values |
| `vault_approle_auth_backend_role.mcp_reader` | `auth/approle/role/mcp-reader` | The homelab MCP plugin's drift scope `vault`, tokens 1 h |
| `vault_policy.k8s_read` | `k8s-read` | Read `kv/k8s/*` |
| `vault_auth_backend.kubernetes` + `vault_kubernetes_auth_backend_config.talos` | `auth/kubernetes` | Talos cluster service accounts; TokenReview with the login JWT, CA inline in `main.tf` |
| `vault_kubernetes_auth_backend_role.eso` | `auth/kubernetes/role/eso` | The External Secrets Operator (`external-secrets/external-secrets`, audience `https://10.140.0.40:6443`) |
| `vault_jwt_auth_backend.gitlab` | `auth/jwt` | GitLab CI `id_tokens`, keys from `https://source.example.com` |
| `vault_jwt_auth_backend_role.ci` + `vault_policy.ci` | `auth/jwt/role/ci-<name>`, `ci-<name>` | One per `kv/ci/<name>`: the listed projects, protected branches only, tokens 5 min; `ci-cosign` may only sign with the Transit key |
| `vault_mount.transit` + `vault_transit_secret_backend_key.cosign` | `transit/keys/cosign` | Non-exportable ECDSA P-256 signing key for cosign (`hashivault://cosign`) |
<!-- markdownlint-enable MD013 -->

## Credentials

The provider reads `VAULT_ADDR` and the token from `VAULT_TOKEN` or
`~/.vault-token`, and works with a 20-minute child token, so the login
token never sits in state. There is no `terraform.tfvars.secret`.

```bash
export VAULT_ADDR=https://vault.example.com:8200
vault login -method=userpass username=<you>
make -C terraform/vault plan
```

Vault must be unsealed; a sealed Vault fails every plan.

## First apply (root token)

The first apply creates userpass and the admin policy, so it runs with the
initial root token, in the operator's own shell:

```bash
export VAULT_ADDR=https://vault.example.com:8200
vault login                        # paste the root token from Bitwarden
make -C terraform/vault apply
```

Then create the admin user, log in as it, and revoke the root token
([docs/VAULT.md](../../docs/VAULT.md), Admin user).

## Import

```bash
cd terraform/vault
terragrunt import vault_policy.<name> <policy-name>
terragrunt import vault_auth_backend.<name> <path>
make plan                          # must be a no-op
```

## MCP reader

The homelab MCP plugin's drift scope `vault` logs in with the `mcp-reader`
AppRole. After the first apply, write its SecretID straight into the
plugin's secret file, so it never reaches the terminal or state:

```bash
vault write -f -field=secret_id auth/approle/role/mcp-reader/secret-id \
  > ~/.config/homelab-mcp/secrets/vault-secret-id
chmod 600 ~/.config/homelab-mcp/secrets/vault-secret-id
terragrunt output -raw mcp_reader_role_id   # role_id for config.toml [vault]
```

To rotate, issue a new SecretID the same way and destroy the old one with
`vault write auth/approle/role/mcp-reader/secret-id-accessor/destroy`.
