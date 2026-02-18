#!/usr/bin/env bash
# ============================================================================
# Migrate Linux VMs Terraform State to GitLab
# ============================================================================
# This script migrates the local Terraform state to GitLab's HTTP backend.
#
# Prerequisites:
#   - GitLab access token with api scope
#   - Existing local state file at generated/state/terraform.tfstate
#
# Usage:
#   export GITLAB_ACCESS_TOKEN=<your-token>
#   ./migrate-state.sh
# ============================================================================

set -euo pipefail

# Configuration
GITLAB_URL="https://gitlab.example.com"
PROJECT_ID="3"
TF_STATE_NAME="linux-vms"
GITLAB_USERNAME="maintainer"
TFVARS_SECRET="../terraform.tfvars.secret"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Extract GitLab token from terraform.tfvars.secret if not provided
if [ -z "${GITLAB_ACCESS_TOKEN:-}" ]; then
    if [ -f "$TFVARS_SECRET" ]; then
        echo -e "${YELLOW}Extracting GitLab token from $TFVARS_SECRET...${NC}"
        GITLAB_ACCESS_TOKEN=$(grep -E '^gitlab_api_token' "$TFVARS_SECRET" | cut -d'"' -f2)
        if [ -z "$GITLAB_ACCESS_TOKEN" ]; then
            echo -e "${RED}ERROR: gitlab_api_token not found in $TFVARS_SECRET${NC}"
            echo "Please add: gitlab_api_token = \"your-token-here\""
            exit 1
        fi
        echo -e "${GREEN}Token extracted successfully${NC}"
    else
        echo -e "${RED}ERROR: $TFVARS_SECRET not found and GITLAB_ACCESS_TOKEN not set${NC}"
        exit 1
    fi
fi

# Check if GITLAB_ACCESS_TOKEN is set
if [[ -z "${GITLAB_ACCESS_TOKEN:-}" ]]; then
    echo -e "${RED}Error: GITLAB_ACCESS_TOKEN environment variable is not set${NC}"
    echo "Usage: export GITLAB_ACCESS_TOKEN=<your-token>"
    exit 1
fi

# Check if local state exists
if [[ ! -f "../generated/state/terraform.tfstate" ]]; then
    echo -e "${RED}Error: Local state file not found at ../generated/state/terraform.tfstate${NC}"
    exit 1
fi

echo -e "${GREEN}Starting migration of Linux VMs Terraform state to GitLab...${NC}"
echo ""
echo "Configuration:"
echo "  GitLab URL: ${GITLAB_URL}"
echo "  Project ID: ${PROJECT_ID}"
echo "  State Name: ${TF_STATE_NAME}"
echo "  Username:   ${GITLAB_USERNAME}"
echo ""

# Backup local state
echo -e "${YELLOW}Creating backup of local state...${NC}"
cp ../generated/state/terraform.tfstate "../generated/state/terraform.tfstate.backup-$(date +%Y%m%d-%H%M%S)"
echo -e "${GREEN}✓ Backup created${NC}"
echo ""

# Initialize with GitLab backend
echo -e "${YELLOW}Initializing GitLab backend...${NC}"
cd .. && terraform init \
    -migrate-state \
    -backend-config="address=${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/terraform/state/${TF_STATE_NAME}" \
    -backend-config="lock_address=${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/terraform/state/${TF_STATE_NAME}/lock" \
    -backend-config="unlock_address=${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/terraform/state/${TF_STATE_NAME}/lock" \
    -backend-config="username=${GITLAB_USERNAME}" \
    -backend-config="password=${GITLAB_ACCESS_TOKEN}" \
    -backend-config="lock_method=POST" \
    -backend-config="unlock_method=DELETE" \
    -backend-config="retry_wait_min=5"

echo ""
echo -e "${GREEN}✓ Migration complete!${NC}"
echo ""
echo "Verification:"
echo "  - Check GitLab: ${GITLAB_URL}/homelab/proxmox-infra/-/terraform"
echo "  - Local backup: generated/state/terraform.tfstate.backup-*"
echo ""
echo "Next steps:"
echo "  1. Verify state in GitLab UI"
echo "  2. Run 'terraform plan' to ensure everything works"
echo "  3. Delete local backup once verified"
