#!/bin/bash
# scripts/ci/lib/common.sh
# Shared utilities for deployment scripts

set -euo pipefail

# Source required library files
source_lib() {
    local script_dir=$1
    shift
    for lib in "$@"; do
        local lib_path="$script_dir/lib/$lib.sh"
        if [ -f "$lib_path" ]; then
            # shellcheck source=/dev/null
            source "$lib_path"
        else
            echo "Error: $lib.sh not found at $lib_path" >&2
            exit 1
        fi
    done
}

# Colors for structured logging
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

# Configuration
DOCKER_COMPOSE_DIR="${DOCKER_COMPOSE_DIR:-/srv/docker}"
SSH_USER="${SSH_USER:-maintainer}"
# shellcheck disable=SC2034 # Used in backup-service.sh and other scripts
export BACKUP_DIR="/srv/docker-backups"
MAX_HEALTH_WAIT="${MAX_HEALTH_WAIT:-120}"  # seconds
SERVICES_DIR="${SERVICES_DIR:-services}"

# Logging with timestamps and levels
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

log_info() {
    log "${BLUE}INFO${NC}  $*"
}

log_success() {
    log "${GREEN}OK${NC}    $*"
}

log_warn() {
    log "${YELLOW}WARN${NC}  $*"
}

log_error() {
    log "${RED}ERROR${NC} $*" >&2
}

# Draw a box around a message
log_section() {
    local msg="$1"
    local length=${#msg}
    local width=$((length + 4))
    local border
    border=$(printf '═%.0s' $(seq 1 "$width"))
    
    log_info "╔${border}╗"
    log_info "║  $msg  ║"
    log_info "╚${border}╝"
}

fail() {
    log_error "$1"
    exit 1
}

# Cleanup trap
cleanup() {
    local exit_code=$?
    # Cleanup SSH agent, temp files, etc.
    if [ -n "${SSH_AGENT_PID:-}" ]; then
        kill "$SSH_AGENT_PID" 2>/dev/null || true
    fi
    exit "$exit_code"
}
trap cleanup EXIT

# Load service metadata
load_service_metadata() {
    local service=$1
    local metadata="$SERVICES_DIR/$service/.service.yml"

    if [ ! -f "$metadata" ]; then
        fail "Metadata file not found: $metadata"
    fi

    local target_host
    target_host=$(yq eval '.target_host' "$metadata")
    export TARGET_HOST="$target_host"

    # Transform names for secret variables (e.g. pihole-1 -> PIHOLE_1)
    local target_host_secret
    target_host_secret=$(echo "$TARGET_HOST" | tr 'a-z-' 'A-Z_')
    local service_secret
    service_secret=$(echo "$service" | tr 'a-z-' 'A-Z_')

    # Construct variable names
    local ssh_key_var="SSH_KEY_${target_host_secret}"
    local target_ip_var="HOST_${target_host_secret}"
    local service_env_var="ENV_${service_secret}"

    # Fetch values from environment (use :- to avoid unbound variable errors with set -u)
    export SSH_KEY="${!ssh_key_var:-}"
    export TARGET_IP="${!target_ip_var:-}"
    export SERVICE_ENV="${!service_env_var:-}"

    if [ -z "$SSH_KEY" ] || [ -z "$TARGET_IP" ]; then
        fail "Missing required secrets: $ssh_key_var or $target_ip_var"
    fi

    log_info "Loaded metadata: service=$service, host=$TARGET_HOST, ip=$TARGET_IP"
}

# Check if deployment needed (compare checksums)
needs_deployment() {
    local service=$1
    local local_checksum remote_checksum

    log_info "Checking if deployment is needed..."

    # Calculate local checksum (exclude .service.yml and .env)
    local_checksum=$(find "$SERVICES_DIR/$service" -type f \
        ! -name '.service.yml' \
        ! -name '.env' \
        -exec md5sum {} \; 2>/dev/null | sort | md5sum | cut -d' ' -f1)

    # Get remote checksum if exists
    escaped_checksum_path=$(printf '%q' "$DOCKER_COMPOSE_DIR/$service/.checksum")
    # shellcheck disable=SC2029 # Variables are escaped with printf %q for safe server-side expansion
    remote_checksum=$(ssh -n "$SSH_USER@$TARGET_IP" \
        "[ -f $escaped_checksum_path ] && cat $escaped_checksum_path || echo 'none'" 2>/dev/null || echo "none")

    if [ "$local_checksum" != "$remote_checksum" ]; then
        log_info "Changes detected"
        log_info "  Local:  $local_checksum"
        log_info "  Remote: $remote_checksum"
        export DEPLOYMENT_CHECKSUM="$local_checksum"
        return 0
    else
        log_info "No changes detected - deployment not needed"
        return 1
    fi
}

# Save deployment checksum
save_deployment_checksum() {
    local service=$1

    if [ -n "${DEPLOYMENT_CHECKSUM:-}" ]; then
        log_info "Saving deployment checksum..."
        escaped_checksum_path=$(printf '%q' "$DOCKER_COMPOSE_DIR/$service/.checksum")
        # shellcheck disable=SC2029 # Variables are escaped with printf %q for safe server-side expansion
        # Note: Do NOT use -n flag here as we're piping data into SSH
        echo "$DEPLOYMENT_CHECKSUM" | ssh "$SSH_USER@$TARGET_IP" \
            "cat > $escaped_checksum_path"
    fi
}

# Verify required commands are available
verify_requirements() {
    local missing_commands=()

    for cmd in docker yq ssh rsync; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_commands+=("$cmd")
        fi
    done

    if [ ${#missing_commands[@]} -gt 0 ]; then
        fail "Missing required commands: ${missing_commands[*]}"
    fi
}
