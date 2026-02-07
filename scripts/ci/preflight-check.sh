#!/bin/bash
# scripts/ci/preflight-check.sh SERVICE_NAME
# Pre-deployment checks: connectivity, disk space, Docker daemon

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

log_section "Pre-flight checks: $SERVICE"

# Load service metadata
load_service_metadata "$SERVICE"

# Setup SSH
setup_ssh

# Check 1: SSH Connectivity
log_info "Check 1/4: SSH connectivity to $TARGET_IP..."
if ! test_ssh_connection; then
    fail "SSH connectivity check failed"
fi

# Check 2: Docker daemon
log_info "Check 2/4: Docker daemon status..."
if ! remote_exec "docker info > /dev/null 2>&1" "docker daemon check"; then
    fail "Docker daemon is not running on $TARGET_IP"
fi
log_success "Docker daemon is running"

# Check 3: Disk space (require at least 1GB free)
log_info "Check 3/4: Disk space..."
escaped_docker_dir=$(printf '%q' "$DOCKER_COMPOSE_DIR")
# shellcheck disable=SC2029 # Variables are escaped with printf %q for safe server-side expansion
DISK_FREE=$(ssh -n "$SSH_USER@$TARGET_IP" \
    "df -BG $escaped_docker_dir 2>/dev/null | tail -1 | awk '{print \$4}' | sed 's/G//'" || echo "0")

if [ "$DISK_FREE" -lt 1 ]; then
    fail "Insufficient disk space: ${DISK_FREE}GB free (minimum 1GB required)"
fi
log_success "Disk space: ${DISK_FREE}GB available"

# Check 4: Docker Compose availability
log_info "Check 4/4: Docker Compose version..."
COMPOSE_VERSION=$(ssh -n "$SSH_USER@$TARGET_IP" \
    "docker compose version --short 2>/dev/null" || echo "unknown")
if [ "$COMPOSE_VERSION" == "unknown" ]; then
    fail "Docker Compose is not available on $TARGET_IP"
fi
log_success "Docker Compose version: $COMPOSE_VERSION"

log_section "All pre-flight checks passed"
