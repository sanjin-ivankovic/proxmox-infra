# ============================================================================
# Local Backend Configuration (fallback / disaster recovery)
# ============================================================================
# Use this when the S3 backend (Garage) is unreachable.
# To switch back to the remote backend:
#   1. Rename this file to backend-local.tf.disabled
#   2. Uncomment backend.tf (S3 backend)
#   3. Run: terraform init -migrate-state
# ============================================================================

terraform {
  backend "local" {
    path = "generated/state/terraform.tfstate"
  }
}
