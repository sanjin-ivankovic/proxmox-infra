#!/bin/bash
# scripts/ci/rollback-service.sh SERVICE_NAME [BACKUP_NAME]
# Restores a service from a backup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
source_lib "$SCRIPT_DIR" ssh docker

# Check arguments
if [ $# -lt 1 ]; then
    log_error "Usage: $0 SERVICE_NAME [BACKUP_NAME]"
    exit 1
fi

SERVICE=$1
SPECIFIC_BACKUP=${2:-}

log_section "Rolling back service: $SERVICE"

# Load metadata
load_service_metadata "$SERVICE"
setup_ssh

# Identify backup to restore
if [ -n "$SPECIFIC_BACKUP" ]; then
    BACKUP_TO_RESTORE="$SPECIFIC_BACKUP"
elif [ -n "${BACKUP_NAME:-}" ]; then
    BACKUP_TO_RESTORE="$BACKUP_NAME"
else
    # Find latest backup
    log_info "No backup name provided, finding latest..."
    escaped_backup_dir=$(printf '%q' "$BACKUP_DIR")
    escaped_service=$(printf '%q' "${SERVICE}_*")
    
    # shellcheck disable=SC2029
    LATEST_BACKUP=$(ssh -n "$SSH_USER@$TARGET_IP" \
        "cd $escaped_backup_dir && ls -td $escaped_service | head -1")
    
    if [ -z "$LATEST_BACKUP" ]; then
        fail "No backups found for $SERVICE"
    fi
    BACKUP_TO_RESTORE="$LATEST_BACKUP"
fi

log_info "Restoring from: $BACKUP_TO_RESTORE"

# Restore files
remote_exec \
    "rm -rf $DOCKER_COMPOSE_DIR/$SERVICE && cp -a $BACKUP_DIR/$BACKUP_TO_RESTORE $DOCKER_COMPOSE_DIR/$SERVICE" \
    "restore backup files"

# Fix permissions
remote_exec \
    "chmod 755 $DOCKER_COMPOSE_DIR/$SERVICE && chmod 644 $DOCKER_COMPOSE_DIR/$SERVICE/*" \
    "fix permissions"

# Restart service
log_info "Restarting service..."
if remote_exec \
    "cd $DOCKER_COMPOSE_DIR/$SERVICE && docker compose up -d --remove-orphans" \
    "docker compose up"; then
    log_success "Rollback successful"
else
    fail "Rollback failed check logs"
fi
