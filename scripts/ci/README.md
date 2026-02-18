# Proxmox Infrastructure CI/CD Scripts

Professional Docker Compose deployment automation with Python-based CI
orchestration and bash infrastructure scripts.

## Overview

This directory contains scripts for managing the complete Docker Compose
deployment lifecycle:

```text
scripts/ci/
├── lib/
│   ├── common.sh              # Shared utilities, logging, metadata loading
│   ├── ssh.sh                 # SSH setup and connection management
│   └── docker.sh              # Docker/Compose helpers, health checks
│
├── Python CI/CD Orchestration (New)
│   ├── detect_services.py     # Auto-discovery of changed services
│   ├── generate_pipeline.py   # Dynamic child pipeline generation
│   ├── build_image.py         # Docker image builder with version extraction
│   ├── publish_github.py      # Sanitize and publish to GitHub portfolio
│   ├── lint_yaml.py           # YAML linting with GitLab Code Quality
│   ├── lint_markdown.py       # Markdown linting
│   └── lint_shell.py          # Shell script linting
│
├── Infrastructure Scripts (Bash)
│   ├── validate-service.sh    # Compose validation and syntax checking
│   ├── preflight-check.sh     # Pre-deployment checks (SSH, Docker, disk)
│   ├── backup-service.sh      # Automated backup before deployment
│   ├── deploy_service.sh      # Main deployment script
│   └── health-check.sh        # Post-deployment health verification
```

## Key Features

- ✅ **100% Python CI/CD Orchestration** - Type-safe, testable scripts
- ✅ **Auto-Discovery** - Git-based service detection with change tracking
- ✅ **Dynamic Child Pipelines** - Generated based on changed services
- ✅ **Idempotent Deployments** - Checksum-based change detection
- ✅ **Pre-flight Checks** - SSH, Docker daemon, disk space validation
- ✅ **Automated Backups** - State saved before every deployment
- ✅ **Health Verification** - Proper Docker healthcheck waiting
- ✅ **GitLab Code Quality** - Inline MR feedback for YAML/Shell issues
- ✅ **Modular Design** - Separation of concerns across focused scripts
- ✅ **Structured Logging** - Timestamps and log levels
- ✅ **Error Handling** - Strict mode with cleanup traps

## Usage

### Python CI/CD Scripts

```bash
# Detect changed services
python3 scripts/ci/detect_services.py --verbose

# Generate child pipeline
python3 scripts/ci/generate_pipeline.py

# Build Docker image
python3 scripts/ci/build_image.py \
  --image registry.example.com/ci \
  --context docker/ci \
  --version-regex "YAMLLINT_VERSION=" \
  --verbose

# Lint YAML files (with GitLab Code Quality support)
python3 scripts/ci/lint_yaml.py --format gitlab

# Lint Markdown files
python3 scripts/ci/lint_markdown.py --verbose

# Lint Shell scripts
python3 scripts/ci/lint_shell.py --verbose

# Publish to GitHub portfolio
python3 scripts/ci/publish_github.py \
  --source . \
  --output /tmp/proxmox-infra-public \
  --verbose
```

### Infrastructure Scripts (Bash)

```bash
# Validate a service
./scripts/ci/validate-service.sh pihole-1

# Pre-flight checks
./scripts/ci/preflight-check.sh pihole-1

# Backup service
./scripts/ci/backup-service.sh pihole-1

# Deploy a service
./scripts/ci/deploy_service.sh pihole-1

# Health check
./scripts/ci/health-check.sh pihole-1
```

### Environment Variables

```bash
SSH_USER="maintainer"                    # SSH username
DOCKER_COMPOSE_DIR="/srv/docker"     # Remote docker-compose directory
SERVICES_DIR="services"              # Local services directory
MAX_HEALTH_WAIT="120"                # Health check timeout (seconds)
```

### Required Secrets (GitLab CI/CD Variables)

For each service, the following secrets must be configured:

```bash
# SSH keys (per target host)
SSH_KEY_<TARGET_HOST>    # e.g., SSH_KEY_PIHOLE_1

# Target IPs (per target host)
HOST_<TARGET_HOST>       # e.g., HOST_PIHOLE_1=10.10.0.20

# Environment variables (per service)
ENV_<SERVICE_NAME>       # e.g., ENV_PIHOLE_1
```

## GitLab CI Pipeline

The pipeline runs through 8 stages:

```text
build-tools → lint → build-images → generate → trigger → security → publish → renovate
```

### Stage Descriptions

1. **build-tools** - Build CI image with linting tools (Python-based)
2. **lint** - Lint YAML, Markdown, Shell scripts (GitLab Code Quality
   integration)
3. **build-images** - Build custom Docker images (Pi-hole, Unbound)
4. **generate** - Generate dynamic child pipeline based on changed services
5. **trigger** - Trigger child pipeline for service deployments
6. **security** - Secret scanning with Gitleaks (SARIF reports)
7. **publish** - Sanitize and publish to GitHub portfolio (Python-based)
8. **renovate** - Automated dependency updates (scheduled)

### Child Pipeline (Triggered Dynamically)

The child pipeline handles service deployments with 5 stages:

```text
validate → preflight → backup → deploy → verify
```

Per-service jobs:

- **validate** - Validate docker-compose.yml and metadata
- **preflight** - Check SSH, Docker daemon, disk space
- **backup** - Create backup before deployment
- **deploy** - Apply changes (**manual approval on main, auto on tags**)
- **verify** - Health checks and post-deployment verification

### Pipeline Behavior

- **Merge Requests**: Validates services (no deployment)
- **Main Branch**: Requires **manual approval** to deploy
- **Tags**: Auto-deploys all changed services
- **Manual Jobs**: Legacy deploy jobs still available

## ShellCheck Configuration

### Important: SC1091 Warnings

All scripts use dynamic sourcing of library files with proper error handling:

```bash
# shellcheck source=scripts/ci/lib/common.sh
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    source "$SCRIPT_DIR/lib/common.sh"
else
    echo "Error: common.sh not found" >&2
    exit 1
fi
```

**IDE Warning (Expected):**

```text
SC1091 (info): Not following: scripts/ci/lib/common.sh was not specified as
input (see shellcheck -x).
```

This is an **informational message only** - it's telling you to run shellcheck
with the `-x` flag to follow sources.

### Solution

The GitLab CI pipeline runs shellcheck with the `-x` flag:

```text
lint-scripts:
  script:
    - shellcheck -x scripts/ci/*.sh scripts/ci/lib/*.sh
```

This makes shellcheck follow the sourced files and validate them properly.

### Local Development

To lint locally with the same configuration as CI:

```bash
# Lint all scripts (following sources)
shellcheck -x scripts/ci/*.sh scripts/ci/lib/*.sh

# Lint individual script
shellcheck -x scripts/ci/deploy_service.sh
```

**Note:** The `-x` flag requires ShellCheck to find the sourced files, so run
from the repository root.

## Script Details

### Python CI/CD Scripts

#### detect_services.py

Auto-discovers changed services via git diff:

- Tag detection: Deploys ALL services on git tags
- Branch detection: Main vs feature branch comparison
- DEPLOY_ALL support: Environment variable override
- Outputs one service name per line for batch processing
- Comprehensive logging with emoji indicators
- Timeout handling for git operations

#### generate_pipeline.py

Generates dynamic child pipeline YAML:

- Calls detect_services.py for service discovery
- Creates per-service jobs (validate, preflight, backup, deploy, verify)
- Declarative rules blocks (tag → main → never)
- Optional dependencies for resilience
- No-changes fallback job when no services changed
- Proper YAML formatting with workflow rules

#### build_image.py

Docker image builder with version extraction:

- Regex-based version extraction from Dockerfile
- Support for build args (GITLEAKS_VERSION, SHELLCHECK_VERSION, etc.)
- Buildx with layer caching
- Multi-architecture support (linux/amd64)
- Dry-run mode for testing
- Comprehensive error handling

#### publish_github.py

Sanitize and publish to GitHub portfolio:

- Runs sanitize_repo.py to remove sensitive data
- Verifies sanitization completeness
- Initializes git repository
- Force pushes to GitHub (overwrites history)
- Dry-run mode available
- Detailed logging

#### lint_yaml.py

YAML linting with GitLab Code Quality integration:

- Uses yamllint for validation
- Converts output to GitLab Code Quality JSON format
- Supports standard, parsable, and gitlab output formats
- Generates gl-code-quality-report.json for MR widgets
- Strict mode enabled
- Version checking

#### lint_Markdown.py

Markdown linting for documentation quality:

- Uses markdownlint-cli2 v0.20.0
- Optional tool (graceful fallback if not installed)
- Lints all .md files recursively
- Verbose output mode
- Fail-on-error flag

#### lint_shell.py

Shell script linting with ShellCheck:

- Auto-discovers .sh files (skips common directories)
- Comprehensive error reporting
- Respects .shellcheckrc configuration
- External sources support
- Source path resolution

### Bash Infrastructure Scripts

#### lib/common.sh

Shared library providing:

- Logging functions: `log_info`, `log_success`, `log_warn`, `log_error`
- Metadata loading: `load_service_metadata`
- Idempotency checks: `needs_deployment`, `save_deployment_checksum`
- Error handling: EXIT trap, cleanup functions

### lib/ssh.sh

SSH management:

- `setup_ssh()` - Configure SSH agent and keys
- `test_ssh_connection()` - Verify connectivity
- `remote_exec()` - Execute commands with error handling
- `sync_files()` - Rsync with exclusions

### lib/docker.sh

Docker/Compose helpers:

- `wait_for_health()` - Wait for healthchecks with timeout
- `verify_containers_running()` - Check container states
- `validate_compose_file()` - Local syntax validation
- `pull_images()` - Pre-pull images before deploy
- `cleanup_old_images()` - Remove dangling images

### rollback-service.sh

Rollback to previous deployment:

- Restores from latest backup
- Stops current containers
- Restores docker-compose files
- Restarts from backup state

### validate-service.sh

Pre-deployment validation:

- docker-compose syntax validation
- Metadata file validation
- Health check presence check (warning only)
- Verifies secrets are available

### preflight-check.sh

Infrastructure checks:

- SSH connectivity test
- Docker daemon status
- Disk space verification (minimum 1GB)
- Docker Compose availability

### backup-service.sh

Automated backups:

- Creates timestamped backup
- Stores in `/srv/docker-backups`
- Keeps last 5 backups per service
- Safe if service doesn't exist yet

### deploy_service.sh

Main deployment:

- Idempotency check (skips if unchanged)
- Syncs files to remote host
- Updates environment variables
- Pulls latest images
- Runs `docker compose up -d`
- Saves deployment checksum

### health-check.sh

Post-deployment verification:

- Waits for containers to stabilize
- Verifies all containers are running
- Waits for Docker healthchecks
- Shows container status summary
- Fetches logs on failure

## Troubleshooting

### "common.sh not found"

Scripts use `$SCRIPT_DIR` to find libraries. Ensure you run from repository root
or scripts work correctly.

### "Service directory doesn't exist"

Add service to `services/` directory with required files:

- `docker-compose.yml`
- `.service.yml` (metadata)

### "Missing required secrets"

Configure in GitLab CI/CD settings:

- `SSH_KEY_<TARGET_HOST>`
- `HOST_<TARGET_HOST>`
- `ENV_<SERVICE>` (optional)

### "Chart version already exists"

This is expected idempotency behavior. No deployment needed if checksums match.

### Health check timeout

Increase `MAX_HEALTH_WAIT` environment variable or add/fix healthchecks in
docker-compose.yml.

## Migration to Python-Based CI/CD

As of January 2026, the CI/CD orchestration has been migrated from bash to
Python for better maintainability and type safety.

### Key Improvements

| Feature                 | Old (Bash)         | New (Python)           |
| ----------------------- | ------------------ | ---------------------- |
| **Service Detection**   | detect-services.sh | detect_services.py     |
| **Pipeline Generation** | Static YAML        | generate_pipeline.py   |
| **Image Building**      | Inline bash        | build_image.py         |
| **Linting**             | ShellCheck only    | YAML/MD/Shell + CI/CD  |
| **GitHub Publishing**   | Inline bash        | publish_github.py      |
| **Type Safety**         | ❌                 | ✅ Full type hints     |
| **Code Quality**        | ❌                 | ✅ GitLab integration  |
| **Error Handling**      | Basic              | ✅ Comprehensive       |
| **Testing**             | Manual             | ✅ Unit testable       |
| **Documentation**       | Comments           | ✅ Docstrings + README |

### What Stayed Bash

Infrastructure scripts remain in bash for simplicity and SSH/Docker
operations:

- `validate-service.sh`
- `preflight-check.sh`
- `backup-service.sh`
- `deploy_service.sh`
- `health-check.sh`
- `rollback-service.sh`
- Library files (`lib/*.sh`)

These scripts are tightly coupled to SSH operations and Docker Compose
commands, where bash excels.

## License

Part of the proxmox-infra repository. See repository root for license
information.
