#!/bin/bash
# scripts/ci/lib/docker.sh
# Docker and Docker Compose helpers

# Wait for container health checks to pass
wait_for_health() {
    local service=$1
    local timeout=${2:-$MAX_HEALTH_WAIT}
    local elapsed=0
    local check_interval=5

    log_info "Waiting for health checks (timeout: ${timeout}s)..."

    while [ $elapsed -lt "$timeout" ]; do
        # Get container health status
        local unhealthy_count
        escaped_service_dir=$(printf '%q' "$DOCKER_COMPOSE_DIR/$service")
        # shellcheck disable=SC2029 # Variables are escaped with printf %q for safe server-side expansion
        unhealthy_count=$(ssh -n "$SSH_USER@$TARGET_IP" \
            "cd $escaped_service_dir && docker compose ps --format json" 2>/dev/null \
            | jq -r 'select(.Health != "" and .Health != "healthy") | .Name' 2>/dev/null \
            | wc -l)

        if [ "$unhealthy_count" -eq 0 ]; then
            log_success "All containers are healthy"
            return 0
        fi

        log_info "Waiting for containers to become healthy... (${elapsed}s/${timeout}s)"
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done

    log_error "Health check timeout after ${timeout}s"
    return 1
}

# Verify all containers are running
verify_containers_running() {
    local service=$1

    log_info "Verifying containers are running..."

    local not_running
    escaped_service_dir=$(printf '%q' "$DOCKER_COMPOSE_DIR/$service")
    # shellcheck disable=SC2029 # Variables are escaped with printf %q for safe server-side expansion
    not_running=$(ssh -n "$SSH_USER@$TARGET_IP" \
        "cd $escaped_service_dir && docker compose ps --format '{{.State}}' 2>/dev/null | grep -v 'running'" || true)

    if [ -n "$not_running" ]; then
        log_error "Some containers are not running:"
        # shellcheck disable=SC2029 # Variables are escaped with printf %q for safe server-side expansion
        ssh -n "$SSH_USER@$TARGET_IP" "cd $escaped_service_dir && docker compose ps"
        return 1
    fi

    log_success "All containers are running"
    return 0
}

# Get container logs for debugging
get_container_logs() {
    local service=$1
    local lines=${2:-50}

    log_info "Fetching container logs (last $lines lines)..."

    escaped_service_dir=$(printf '%q' "$DOCKER_COMPOSE_DIR/$service")
    escaped_lines=$(printf '%q' "$lines")
    # shellcheck disable=SC2029 # Variables are escaped with printf %q for safe server-side expansion
    ssh -n "$SSH_USER@$TARGET_IP" \
        "cd $escaped_service_dir && docker compose logs --tail=$escaped_lines"
}

# Cleanup old images safely
cleanup_old_images() {
    log_info "Cleaning up unused Docker images..."

    # Only remove dangling images (not tagged)
    ssh -n "$SSH_USER@$TARGET_IP" \
        "docker image prune -f" > /dev/null 2>&1 || true

    log_success "Cleanup complete"
}

# Validate docker-compose file locally
validate_compose_file() {
    local compose_file=$1

    log_info "Validating docker-compose syntax..."

    if ! docker compose -f "$compose_file" config --quiet 2>&1; then
        log_error "Invalid docker-compose.yml syntax"
        return 1
    fi

    log_success "Compose file validation passed"
    return 0
}

# Check if compose file has health checks
check_healthchecks() {
    local compose_file=$1

    if docker compose -f "$compose_file" config 2>/dev/null | grep -q "healthcheck:"; then
        log_info "Health checks defined in compose file"
        return 0
    else
        log_warn "No health checks defined - consider adding them for better reliability"
        return 1
    fi
}

# Authenticate to container registries (GitLab and DockerHub)
ensure_registry_login() {
    local login_attempted=false

    # Attempt GitLab Container Registry login
    local gitlab_registry="${CI_REGISTRY:-}"
    local gitlab_password="${CI_DEPLOY_TOKEN:-}"
    local gitlab_username="${CI_DEPLOY_TOKEN_USERNAME:-gitlab+deploy-token-1}"

    if [ -n "$gitlab_registry" ] && [ -n "$gitlab_password" ]; then
        log_info "Authenticating to GitLab Container Registry: $gitlab_registry"
        login_attempted=true

        # shellcheck disable=SC2029 # Client-side expansion is intentional for security
        if echo "$gitlab_password" | ssh "$SSH_USER@$TARGET_IP" \
            "docker login $gitlab_registry -u '$gitlab_username' --password-stdin" > /dev/null 2>&1; then
            log_success "GitLab registry authentication successful"
        else
            log_warn "GitLab registry authentication failed"
        fi
    fi

    # Attempt DockerHub login
    local dockerhub_username="${DOCKER_HUB_USERNAME:-}"
    local dockerhub_token="${DOCKER_HUB_TOKEN:-}"

    if [ -n "$dockerhub_username" ] && [ -n "$dockerhub_token" ]; then
        log_info "Authenticating to DockerHub"
        login_attempted=true

        # shellcheck disable=SC2029 # Client-side expansion is intentional for security
        if echo "$dockerhub_token" | ssh "$SSH_USER@$TARGET_IP" \
            "docker login -u '$dockerhub_username' --password-stdin" > /dev/null 2>&1; then
            log_success "DockerHub authentication successful"
        else
            log_warn "DockerHub authentication failed"
        fi
    fi

    if [ "$login_attempted" = false ]; then
        log_info "No registry credentials configured - skipping login"
    fi

    return 0
}

# Pull images before deploy
pull_images() {
    local service=$1

    log_info "Pulling latest images..."

    if remote_exec \
        "cd $DOCKER_COMPOSE_DIR/$service && docker compose pull" \
        "docker compose pull"; then
        log_success "Images pulled successfully"
        return 0
    else
        log_error "Failed to pull images"
        return 1
    fi
}
