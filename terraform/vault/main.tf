# KV v2 for every secret: kv/<consumer>/... (docs/VAULT.md, KV layout).
resource "vault_mount" "kv" {
  path        = "kv"
  type        = "kv"
  options     = { version = "2" }
  description = "Homelab secrets (KV v2)"
}

# Vault blocks every request when no enabled audit device can write, so
# logrotate on the host (role hashicorp_vault) keeps /vault/logs from filling
# the disk.
resource "vault_audit" "file" {
  type        = "file"
  description = "Audit log, rotated by logrotate on the host"

  options = {
    file_path = "/vault/logs/audit.log"
  }
}

resource "vault_policy" "admin" {
  name   = "admin"
  policy = file("${path.module}/policies/admin.hcl")
}

resource "vault_policy" "raft_snapshot" {
  name   = "raft-snapshot"
  policy = file("${path.module}/policies/raft-snapshot.hcl")
}

# Human login. Users are created with the CLI so passwords never reach state
# (README, Admin user).
resource "vault_auth_backend" "userpass" {
  type        = "userpass"
  description = "Operators"

  tune {
    default_lease_ttl = "8h"
    max_lease_ttl     = "24h"
  }
}

# Machine login: one role per consumer. Secret IDs are issued with the CLI
# and kept in the Ansible vault (bootstrap tier), never in state.
resource "vault_auth_backend" "approle" {
  type        = "approle"
  description = "Machines"
}

# The 02:00 Raft snapshot timer on the vault host (role hashicorp_vault).
resource "vault_approle_auth_backend_role" "raft_snapshot" {
  backend        = vault_auth_backend.approle.path
  role_name      = "raft-snapshot"
  token_policies = [vault_policy.raft_snapshot.name]
  token_ttl      = 300
  token_max_ttl  = 600
}

resource "vault_policy" "proxmox_infra_read" {
  name   = "proxmox-infra-read"
  policy = file("${path.module}/policies/proxmox-infra-read.hcl")
}

# Semaphore's playbook runs. The SecretID reaches the container as a Komodo
# Periphery secret (Ansible vault, bootstrap tier) and Semaphore forwards it
# to each run; one run takes well under an hour.
resource "vault_approle_auth_backend_role" "semaphore" {
  backend        = vault_auth_backend.approle.path
  role_name      = "semaphore"
  token_policies = [vault_policy.proxmox_infra_read.name]
  token_ttl      = 3600
  token_max_ttl  = 7200
}

resource "vault_policy" "mcp_reader" {
  name   = "mcp-reader"
  policy = file("${path.module}/policies/mcp-reader.hcl")
}

# The homelab MCP plugin on the operator's laptop. The SecretID is issued
# with the CLI straight into ~/.config/homelab-mcp/secrets/vault-secret-id
# (README, MCP reader), never into state or the Ansible vault.
resource "vault_approle_auth_backend_role" "mcp_reader" {
  backend        = vault_auth_backend.approle.path
  role_name      = "mcp-reader"
  token_policies = [vault_policy.mcp_reader.name]
  token_ttl      = 3600
  token_max_ttl  = 7200
}

resource "vault_policy" "k8s_read" {
  name   = "k8s-read"
  policy = file("${path.module}/policies/k8s-read.hcl")
}

# The Talos cluster logs in with service-account tokens. No reviewer token is
# stored: Vault calls TokenReview with the login JWT itself, so the service
# account needs system:auth-delegator (argo-apps apps/infra/external-secrets).
# The cluster CA certificate (public; "*.pem" files are gitignored, hence
# inline). Refresh it from the kubeconfig's certificate-authority-data if the
# cluster is rebuilt.
locals {
  talos_cluster_ca = <<-EOT
    -----BEGIN CERTIFICATE-----
    MIIBizCCATCgAwIBAgIRAPlYRK01PjDi1UCIFY58IuAwCgYIKoZIzj0EAwIwFTET
    MBEGA1UEChMKa3ViZXJuZXRlczAeFw0yNjAyMTkxOTU3NTFaFw0zNjAyMTcxOTU3
    NTFaMBUxEzARBgNVBAoTCmt1YmVybmV0ZXMwWTATBgcqhkjOPQIBBggqhkjOPQMB
    BwNCAAQ3wQ0GFmu2P1mK8BDaOwDdfqR+aNsJ5MRCK8wrFvwjNXlplXvnDGa+889g
    EwcxSBMdn1Bf+0Z5xydaN22+mAhyo2EwXzAOBgNVHQ8BAf8EBAMCAoQwHQYDVR0l
    BBYwFAYIKwYBBQUHAwEGCCsGAQUFBwMCMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0O
    BBYEFBn5d2e7OLY+U5SVzrPk/t0UmDnUMAoGCCqGSM49BAMCA0kAMEYCIQCAKG9+
    1NYb+CG+5UgKAQoNNHiVsTV7MkDDj8s1SQjE9QIhAIUu2pAdUwza75cgK2N67p+I
    lrgOOl6FpZ1M2WZbkpT/
    -----END CERTIFICATE-----
  EOT
}

resource "vault_auth_backend" "kubernetes" {
  type        = "kubernetes"
  description = "Talos cluster service accounts"
}

resource "vault_kubernetes_auth_backend_config" "talos" {
  backend              = vault_auth_backend.kubernetes.path
  kubernetes_host      = "https://10.140.0.40:6443"
  kubernetes_ca_cert   = local.talos_cluster_ca
  disable_local_ca_jwt = true
}

# Vault 1.21+ refuses roles without an audience. It is the API server's own
# (the cluster's service-account issuer): Vault calls TokenReview with the login
# token itself, and the API server only accepts a token for its own audience,
# while Vault rejects a token that carries more than one. ESO requests this
# audience in the ClusterSecretStore's serviceAccountRef.audiences.
resource "vault_kubernetes_auth_backend_role" "eso" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "eso"
  bound_service_account_names      = ["external-secrets"]
  bound_service_account_namespaces = ["external-secrets"]
  audience                         = "https://10.140.0.40:6443"
  token_policies                   = [vault_policy.k8s_read.name]
  token_ttl                        = 3600
}

# GitLab CI jobs log in with an `id_tokens` JWT (GitLab CE has no `secrets:`
# keyword). Vault fetches GitLab's signing keys from source.example.com, which is
# served through the cluster's Traefik: with the cluster down CI cannot log in,
# but it cannot clone either, and Vault itself keeps running.
resource "vault_jwt_auth_backend" "gitlab" {
  path               = "jwt"
  description        = "GitLab CI id_tokens"
  oidc_discovery_url = "https://source.example.com"
  bound_issuer       = "https://source.example.com"
}

# One role per secret, readable only by the projects that use it and only from
# protected branches: a merge-request or feature-branch job is refused at login.
# bound_claims takes comma-separated alternatives.
locals {
  ci_roles = {
    cosign        = ["argo-apps", "helm-charts", "proxmox-infra", "ci-components"]
    github        = ["argo-apps", "helm-charts", "proxmox-infra", "ci-components", "renovate", "mcp-plugins"]
    ntfy          = ["argo-apps", "helm-charts", "proxmox-infra", "ci-components", "renovate", "mcp-plugins", "portfolio-site"]
    ci-components = ["ci-components"]
    komodo        = ["proxmox-infra"]
    renovate      = ["renovate"]
    cloudflare    = ["portfolio-site"]
  }
}

# Every role reads its own kv/ci/<name>, except cosign: it signs with the
# Transit key below and reads no secret at all.
resource "vault_policy" "ci" {
  for_each = local.ci_roles
  name     = "ci-${each.key}"
  policy   = each.key == "cosign" ? file("${path.module}/policies/ci-cosign.hcl") : <<-EOT
    # GitLab CI: read kv/ci/${each.key}.
    path "kv/data/ci/${each.key}" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_mount" "transit" {
  path        = "transit"
  type        = "transit"
  description = "Signing keys that never leave Vault"
}

# The image, chart and SBOM signing key. cosign uses it as
# `--key hashivault://cosign` and Vault signs: the private key is not
# exportable and has no plaintext backup, so it exists only inside Vault (and
# its encrypted Raft snapshots). Its public half is helm-charts/cosign.pub.
resource "vault_transit_secret_backend_key" "cosign" {
  backend                = vault_mount.transit.path
  name                   = "cosign"
  type                   = "ecdsa-p256"
  exportable             = false
  allow_plaintext_backup = false
  deletion_allowed       = false
}

resource "vault_jwt_auth_backend_role" "ci" {
  for_each        = local.ci_roles
  backend         = vault_jwt_auth_backend.gitlab.path
  role_name       = "ci-${each.key}"
  role_type       = "jwt"
  user_claim      = "project_path"
  bound_audiences = ["https://vault.example.com"]
  bound_claims = {
    project_path  = join(",", [for p in each.value : "homelab/${p}"])
    ref_protected = "true"
    ref_type      = "branch"
  }
  token_policies         = [vault_policy.ci[each.key].name]
  token_ttl              = 300
  token_explicit_max_ttl = 900
}
