# ============================================================================
# GitLab HTTP Backend Configuration
# ============================================================================
# This backend stores Terraform state in GitLab's Terraform state API.
# State is encrypted at rest and supports locking for safe concurrent operations.
#
# Prerequisites:
#   1. GitLab access token with api scope
#   2. Project ID (found in GitLab project settings)
#
# Usage:
#   export GITLAB_ACCESS_TOKEN=<your-token>
#   export TF_STATE_NAME=lxc  # Use different names for lxc/linux-vms/windows-vms
#   terraform init \
#     -backend-config="address=https://gitlab.example.com/api/v4/projects/1/terraform/state/$TF_STATE_NAME" \
#     -backend-config="lock_address=https://gitlab.example.com/api/v4/projects/1/terraform/state/$TF_STATE_NAME/lock" \
#     -backend-config="unlock_address=https://gitlab.example.com/api/v4/projects/1/terraform/state/$TF_STATE_NAME/lock" \
#     -backend-config="username=maintainer" \
#     -backend-config="password=$GITLAB_ACCESS_TOKEN" \
#     -backend-config="lock_method=POST" \
#     -backend-config="unlock_method=DELETE" \
#     -backend-config="retry_wait_min=5"
# ============================================================================

terraform {
  backend "http" {
    address        = "https://gitlab.example.com/api/v4/projects/1/terraform/state/lxc"
    lock_address   = "https://gitlab.example.com/api/v4/projects/1/terraform/state/lxc/lock"
    unlock_address = "https://gitlab.example.com/api/v4/projects/1/terraform/state/lxc/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
    username       = "maintainer"
    # Password must be provided via environment variable or -backend-config flag:
    # export TF_HTTP_PASSWORD=$GITLAB_ACCESS_TOKEN
    # OR: terraform init -backend-config="password=$GITLAB_ACCESS_TOKEN"
  }
}
