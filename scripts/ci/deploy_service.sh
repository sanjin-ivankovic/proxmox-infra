#!/bin/bash
# scripts/ci/deploy-service-new.sh SERVICE_NAME
# Deploys a service using Docker Compose (modular version)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
source_lib "$SCRIPT_DIR" ssh docker

# Error handler for automatic rollback
on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code $exit_code"
    
    if [ -n "${SERVICE:-}" ]; then
        log_warn "Initiating rollback for service: $SERVICE"
        "$SCRIPT_DIR/rollback-service.sh" "$SERVICE" || log_error "Rollback failed!"
    fi
    exit $exit_code
}
trap 'on_error' ERR

# Check arguments
if [ $# -lt 1 ]; then
    log_error "Usage: $0 SERVICE_NAME"
    exit 1
fi

SERVICE=$1

log_section "Deploying: $SERVICE"

# Load service metadata and setup SSH
load_service_metadata "$SERVICE"
setup_ssh

# Check if deployment is needed (idempotency)
if ! needs_deployment "$SERVICE"; then
    log_success "Service is up-to-date - skipping deployment"
    exit 0
fi

# Prepare remote directory
log_info "Step 1/5: Preparing remote directory..."
remote_exec \
    "mkdir -p $DOCKER_COMPOSE_DIR/$SERVICE" \
    "create service directory"

# Sync files
log_info "Step 2/5: Syncing files..."
sync_files \
    "$SERVICES_DIR/$SERVICE/" \
    "$DOCKER_COMPOSE_DIR/$SERVICE/" \
    ".env" \
    ".service.yml"

# Fix directory permissions (755 for directory, 644 for files)
remote_exec \
    "chmod 755 $DOCKER_COMPOSE_DIR/$SERVICE && chmod 644 $DOCKER_COMPOSE_DIR/$SERVICE/*" \
    "fix permissions"

# Update environment variables
ENV_CONTENT="$SERVICE_ENV"
[ -n "${REGISTRY_IMAGE:-}" ] && ENV_CONTENT="${ENV_CONTENT:+$ENV_CONTENT$'\n'}REGISTRY_IMAGE=$REGISTRY_IMAGE"

if [ -n "$ENV_CONTENT" ]; then
    log_info "Step 3/5: Updating environment variables..."
    escaped_env_path=$(printf '%q' "$DOCKER_COMPOSE_DIR/$SERVICE/.env")
    # shellcheck disable=SC2029 # Variables are escaped with printf %q for safe server-side expansion
    # Note: Do NOT use -n flag here as we're piping data into SSH
    echo "$ENV_CONTENT" | ssh "$SSH_USER@$TARGET_IP" \
        "cat > $escaped_env_path && chmod 600 $escaped_env_path"
    log_success "Environment variables updated"
else
    log_info "Step 3/5: No environment variables to update"
fi

# Prepare service-specific volume directories
if [[ "$SERVICE" == adguard-* ]]; then
    log_info "Step 3.5/5: Preparing AdGuard Home volumes..."
    # Source the .env file to get APPDATA_DIR, then create volume dirs with correct permissions
    remote_exec \
        "source $DOCKER_COMPOSE_DIR/$SERVICE/.env && mkdir -p \$APPDATA_DIR/$SERVICE/work \$APPDATA_DIR/$SERVICE/conf && chmod 700 \$APPDATA_DIR/$SERVICE/work \$APPDATA_DIR/$SERVICE/conf" \
        "prepare AdGuard volumes"
fi

# Authenticate to container registry (if credentials are available)
log_info "Step 3.6/5: Authenticating to container registry..."
ensure_registry_login

# Pull latest images
log_info "Step 4/5: Pulling latest images..."
pull_images "$SERVICE" || log_warn "Image pull failed - continuing with cached images"

# Apply changes
log_info "Step 5/5: Applying changes with Docker Compose..."
if remote_exec \
    "cd $DOCKER_COMPOSE_DIR/$SERVICE && docker compose up -d --remove-orphans --pull missing" \
    "docker compose up"; then
    log_success "Docker Compose deployment successful"
else
    fail "Docker Compose deployment failed"
fi

# Save deployment checksum
save_deployment_checksum "$SERVICE"

# Cleanup old images
cleanup_old_images

log_section "Deployment complete: $SERVICE"
