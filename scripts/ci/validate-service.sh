#!/bin/bash
# scripts/ci/validate-service.sh SERVICE_NAME
# Validates docker-compose configuration and metadata

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
source_lib "$SCRIPT_DIR" docker

# Check arguments
if [ $# -lt 1 ]; then
    log_error "Usage: $0 SERVICE_NAME"
    exit 1
fi

SERVICE=$1

log_section "Validating service: $SERVICE"

# Verify service directory exists
if [ ! -d "$SERVICES_DIR/$SERVICE" ]; then
    fail "Service directory not found: $SERVICES_DIR/$SERVICE"
fi

# Validate compose file exists
COMPOSE_FILE="$SERVICES_DIR/$SERVICE/docker-compose.yml"
if [ ! -f "$COMPOSE_FILE" ]; then
    fail "docker-compose.yml not found: $COMPOSE_FILE"
fi


# Validate metadata file
METADATA="$SERVICES_DIR/$SERVICE/.service.yml"
if [ ! -f "$METADATA" ]; then
    fail "Metadata file not found: $METADATA"
fi

# Load and validate metadata
load_service_metadata "$SERVICE"

# Generate .env file from secrets (similar to deploy script)
# This ensures docker compose config has access to variables
log_info "Generating temporary .env file..."
ENV_CONTENT="$SERVICE_ENV"
[ -n "${REGISTRY_IMAGE:-}" ] && ENV_CONTENT="${ENV_CONTENT:+$ENV_CONTENT$'\n'}REGISTRY_IMAGE=$REGISTRY_IMAGE"

if [ -n "$ENV_CONTENT" ]; then
    echo "$ENV_CONTENT" > "$SERVICES_DIR/$SERVICE/.env"
    chmod 600 "$SERVICES_DIR/$SERVICE/.env"
fi

# Cleanup .env on exit, preserving common.sh cleanup
custom_cleanup() {
    rm -f "$SERVICES_DIR/$SERVICE/.env"
    if declare -f cleanup > /dev/null; then
        cleanup
    fi
}
trap custom_cleanup EXIT

if [ -z "$TARGET_HOST" ]; then
    fail "target_host not defined in .service.yml"
fi

# Validate compose syntax
validate_compose_file "$COMPOSE_FILE" || exit 1

# Check for health checks (warning only)
check_healthchecks "$COMPOSE_FILE" || true

log_section "Validation passed: $SERVICE"
log_success "  Target host: $TARGET_HOST"
log_success "  Target IP:   $TARGET_IP"
