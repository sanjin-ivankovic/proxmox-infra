# ============================================================================
# Local Backend Configuration (Temporary - GitLab Unreachable)
# ============================================================================
# Use this when GitLab HTTP backend is unreachable
# To switch back to GitLab:
#   1. Rename this file to backend-local.tf.disabled
#   2. Uncomment backend.tf
#   3. Run: terraform init -migrate-state
# ============================================================================

terraform {
  backend "local" {
    path = "generated/state/terraform.tfstate"
  }
}
