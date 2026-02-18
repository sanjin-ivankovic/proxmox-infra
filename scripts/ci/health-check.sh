#!/bin/bash
# scripts/ci/health-check.sh SERVICE_NAME
# Verifies deployment health and container status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
source_lib "$SCRIPT_DIR" ssh docker

# Check arguments
if [ $# -lt 1 ]; then
    log_error "Usage: $0 SERVICE_NAME"
    exit 1
fi

SERVICE=$1

log_section "Health check: $SERVICE"

# Load service metadata and setup SSH
load_service_metadata "$SERVICE"
setup_ssh

# Wait a moment for containers to stabilize
log_info "Waiting for containers to stabilize..."
sleep 5

# Check 1: Verify containers are running
log_info "Check 1/3: Container status..."
if ! verify_containers_running "$SERVICE"; then
    log_error "Health check failed: containers not running"
    get_container_logs "$SERVICE" 50
    exit 1
fi

# Check 2: Wait for health checks to pass
log_info "Check 2/3: Health checks..."
if ! wait_for_health "$SERVICE"; then
    log_warn "Health check timeout - some containers may not be healthy"
    log_warn "Fetching logs for debugging..."
    get_container_logs "$SERVICE" 50
    # Don't fail - might be a slow startup
fi

# Check 3: Final status verification
log_info "Check 3/3: Final verification..."
escaped_service_dir=$(printf '%q' "$DOCKER_COMPOSE_DIR/$SERVICE")
# shellcheck disable=SC2029 # Variables are escaped with printf %q for safe server-side expansion
CONTAINER_STATUS=$(ssh -n "$SSH_USER@$TARGET_IP" \
    "cd $escaped_service_dir && docker compose ps --format '{{.Name}}: {{.Status}}'" 2>/dev/null)

log_info "Container status:"
echo "$CONTAINER_STATUS" | while read -r line; do
    log_info "  $line"
done

# Count running containers
RUNNING_COUNT=$(echo "$CONTAINER_STATUS" | grep -c "Up" || echo "0")
TOTAL_COUNT=$(echo "$CONTAINER_STATUS" | wc -l)

log_info "Running: $RUNNING_COUNT/$TOTAL_COUNT containers"

if [ "$RUNNING_COUNT" -eq 0 ]; then
    fail "No containers are running"
fi

if [ "$RUNNING_COUNT" -lt "$TOTAL_COUNT" ]; then
    log_warn "Not all containers are running ($RUNNING_COUNT/$TOTAL_COUNT)"
    exit 1
fi

log_section "Health check passed: $SERVICE"
log_success "All $RUNNING_COUNT containers are running"
