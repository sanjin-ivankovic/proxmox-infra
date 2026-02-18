#!/bin/bash
# scripts/ci/lib/ssh.sh
# SSH setup and connection management

# shellcheck disable=SC2029 # Client-side expansion is intended

# Setup SSH for CI/CD deployment
setup_ssh() {
    log_info "Setting up SSH connection..."

    mkdir -p ~/.ssh
    chmod 700 ~/.ssh

    # Add key to agent
    eval "$(ssh-agent -s)" > /dev/null

    # Write key to temp file to ensure proper formatting (newlines)
    local key_file
    key_file=$(mktemp)

    # Handle both file path (GitLab File variable) or content variable
    if [ -f "$SSH_KEY" ]; then
        cat "$SSH_KEY" > "$key_file"
    else
        echo "$SSH_KEY" > "$key_file"
    fi

    # Ensure newline at end of key (critical for some SSH versions)
    if [ -n "$(tail -c1 "$key_file" 2>/dev/null)" ]; then
        echo >> "$key_file"
    fi

    chmod 600 "$key_file"
    if ! output=$(ssh-add "$key_file" 2>&1); then
        rm -f "$key_file"
        fail "Failed to add SSH key: $output"
    fi
    rm -f "$key_file"

    # Configure SSH options for CI/CD automation
    cat > ~/.ssh/config <<EOF
Host *
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ~/.ssh/known_hosts
    ConnectTimeout 10
    BatchMode yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF
    chmod 600 ~/.ssh/config

    # Pre-populate known host to avoid interactive prompts
    log_info "Adding $TARGET_IP to known hosts..."
    ssh-keyscan -H "$TARGET_IP" >> ~/.ssh/known_hosts 2>/dev/null || true

    log_success "SSH setup complete"
}

# Test SSH connectivity
test_ssh_connection() {
    log_info "Testing SSH connectivity..."

    if ssh -n -o ConnectTimeout=5 "$SSH_USER@$TARGET_IP" "echo 'SSH connection successful'" > /dev/null 2>&1; then
        log_success "SSH connection verified"
        return 0
    else
        log_error "Failed to connect via SSH to $TARGET_IP"
        return 1
    fi
}

# Execute remote command with error handling
remote_exec() {
    local cmd=$1
    local description=${2:-"remote command"}

    log_info "Executing: $description"

    if ! ssh -n "$SSH_USER@$TARGET_IP" "$cmd"; then
        log_error "Failed to execute: $description"
        return 1
    fi

    return 0
}

# Sync files to remote host
sync_files() {
    local source=$1
    local dest=$2
    local exclude_args=()

    # Add exclusions
    for exclude in "${@:3}"; do
        exclude_args+=(--exclude "$exclude")
    done

    log_info "Syncing files: $source -> $dest"

    if ! rsync -az --delete "${exclude_args[@]}" "$source" "$SSH_USER@$TARGET_IP:$dest"; then
        log_error "Failed to sync files"
        return 1
    fi

    log_success "Files synced successfully"
    return 0
}
