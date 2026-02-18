#!/bin/bash
# scripts/ci/backup-service.sh SERVICE_NAME
# Backs up current deployment state before changes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
source_lib "$SCRIPT_DIR" ssh

# Check arguments
if [ $# -lt 1 ]; then
    log_error "Usage: $0 SERVICE_NAME"
    exit 1
fi

SERVICE=$1

log_section "Backing up service: $SERVICE"

# Load service metadata
load_service_metadata "$SERVICE"

# Setup SSH
setup_ssh

# Create backup timestamp
BACKUP_TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
BACKUP_NAME="${SERVICE}_${BACKUP_TIMESTAMP}"

log_info "Backup name: $BACKUP_NAME"

# Create backup directory on remote host
log_info "Creating backup directory..."
remote_exec \
    "mkdir -p $BACKUP_DIR" \
    "create backup directory"

# Check if service exists on remote
escaped_dir=$(printf '%q' "$DOCKER_COMPOSE_DIR/$SERVICE")
# shellcheck disable=SC2029 # Variables are escaped with printf %q for safe server-side expansion
if ! ssh -n "$SSH_USER@$TARGET_IP" "[ -d $escaped_dir ]"; then
    log_warn "Service directory doesn't exist on remote - nothing to backup"
    exit 0
fi

# Backup current deployment
log_info "Backing up current deployment..."
if remote_exec \
    "cp -a $DOCKER_COMPOSE_DIR/$SERVICE $BACKUP_DIR/$BACKUP_NAME" \
    "backup service directory"; then
    log_success "Backup created: $BACKUP_DIR/$BACKUP_NAME"
else
    log_warn "Backup failed - continuing anyway"
    exit 0
fi

# Keep only last 5 backups
log_info "Cleaning up old backups (keeping last 5)..."
escaped_backup_dir=$(printf '%q' "$BACKUP_DIR")
escaped_service_pattern=$(printf '%q' "${SERVICE}_*")
# shellcheck disable=SC2029 # Variables are escaped with printf %q for safe server-side expansion
ssh -n "$SSH_USER@$TARGET_IP" \
    "cd $escaped_backup_dir && ls -t $escaped_service_pattern 2>/dev/null | tail -n +6 | xargs -r rm -rf" || true

log_section "Backup complete: $BACKUP_NAME"

# Export backup name for potential rollback (if env files exist)
if [ -n "${GITHUB_ENV:-}" ]; then
    echo "BACKUP_NAME=$BACKUP_NAME" >> "$GITHUB_ENV" || true
fi
if [ -n "${CI_ENV:-}" ]; then
    echo "BACKUP_NAME=$BACKUP_NAME" >> "$CI_ENV" || true
fi
