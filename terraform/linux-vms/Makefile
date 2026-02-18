# ============================================================================
# Proxmox Infrastructure - Comprehensive Terraform Makefile
# ============================================================================
# Industry-standard Makefile with all possible Terraform operations
#
# Quick Start:
#   make help          - Show all available commands
#   make setup         - Complete initial setup
#   make deploy        - Deploy infrastructure
#
# Requirements:
#   - terraform >= 1.5.0
#   - jq (for JSON processing)
#   - Optional: tfsec, tflint, terraform-docs, infracost, checkov
# ============================================================================

# ============================================================================
# Configuration Variables
# ============================================================================

# Terraform settings
TF_VERSION := $(shell terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || echo "unknown")
TF_PARALLELISM ?= 10
TF_LOG ?=
TF_LOG_PATH ?=

# File paths
TFVARS_SECRET := terraform.tfvars.secret
TFVARS_EXAMPLE := terraform.tfvars.example
BACKEND_SECRETS := backend.secrets.tfvars
INSTANCES_DIR := instances
STATE_DIR := generated/state
BACKUP_DIR := generated/backups
ANSIBLE_INVENTORY := ../../ansible/inventory/linux-vms-hosts.yml

# ============================================================================
# GitLab Backend Authentication
# ============================================================================
# Extract GitLab API token from terraform.tfvars.secret and export as TF_HTTP_PASSWORD
# for GitLab HTTP backend authentication (state storage)
ifneq (,$(wildcard $(TFVARS_SECRET)))
    GITLAB_TOKEN := $(shell grep -E '^gitlab_api_token' $(TFVARS_SECRET) | cut -d'"' -f2)
    ifneq ($(GITLAB_TOKEN),)
        export TF_HTTP_PASSWORD := $(GITLAB_TOKEN)
    endif
endif

# ============================================================================
# Display Configuration
# ============================================================================
# Colors for output
COLOR_RESET := \033[0m
COLOR_BOLD := \033[1m
COLOR_RED := \033[31m
COLOR_GREEN := \033[32m
COLOR_YELLOW := \033[33m
COLOR_BLUE := \033[34m
COLOR_MAGENTA := \033[35m
COLOR_CYAN := \033[36m

# Symbols
SYMBOL_CHECK := ✅
SYMBOL_CROSS := ❌
SYMBOL_WARN := ⚠️
SYMBOL_INFO := ℹ️
SYMBOL_ROCKET := 🚀
SYMBOL_CLEAN := 🧹
SYMBOL_LOCK := 🔒
SYMBOL_BOOK := 📚
SYMBOL_CHART := 📊
SYMBOL_TOOL := 🔧
SYMBOL_FIRE := 🔥

# ============================================================================
# Default Target
# ============================================================================

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help message
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)╔══════════════════════════════════════════════════════════════════╗$(COLOR_RESET)"
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)║     Linux VMs - Terraform Management Makefile                     ║$(COLOR_RESET)"
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)╚══════════════════════════════════════════════════════════════════╝$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)$(SYMBOL_ROCKET) QUICK START:$(COLOR_RESET)"
	@echo "  make setup              - Complete initial setup (secrets + init)"
	@echo "  make deploy             - Deploy infrastructure (plan + apply + inventory)"
	@echo "  make status             - Show current infrastructure status"
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_CYAN)$(SYMBOL_TOOL) SETUP & INITIALIZATION:$(COLOR_RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; /^(secrets|init|upgrade|modules-update):/ {printf "  $(COLOR_CYAN)%-20s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)$(SYMBOL_ROCKET) DEPLOYMENT:$(COLOR_RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; /^(plan|apply|deploy|refresh|import|taint|untaint):/ {printf "  $(COLOR_GREEN)%-20s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_CYAN)$(SYMBOL_TOOL) IMPORT HELPERS:$(COLOR_RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; /^(import-from-proxmox|import-vm-linux|import-guide):/ {printf "  $(COLOR_CYAN)%-20s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_RED)$(SYMBOL_FIRE) DESTRUCTION:$(COLOR_RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; /^(destroy|destroy-target|destroy-auto):/ {printf "  $(COLOR_RED)%-20s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_YELLOW)$(SYMBOL_CHART) STATE MANAGEMENT:$(COLOR_RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; /^(state-|backup-|restore-):/ {printf "  $(COLOR_YELLOW)%-20s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_MAGENTA)$(SYMBOL_LOCK) WORKSPACE MANAGEMENT:$(COLOR_RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; /^workspace-/ {printf "  $(COLOR_MAGENTA)%-20s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_CYAN)$(SYMBOL_CHECK) VALIDATION & QUALITY:$(COLOR_RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; /^(validate|fmt|lint|security-|test):/ {printf "  $(COLOR_CYAN)%-20s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)$(SYMBOL_CHART) OUTPUTS & REPORTS:$(COLOR_RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; /^(output|inventory|graph|cost|docs|show):/ {printf "  $(COLOR_BLUE)%-20s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)$(SYMBOL_CLEAN) MAINTENANCE:$(COLOR_RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; /^(clean|lock|drift):/ {printf "  $(COLOR_GREEN)%-20s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_YELLOW)$(SYMBOL_INFO) WORKFLOWS:$(COLOR_RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; /^(quick|full-|ci-):/ {printf "  $(COLOR_YELLOW)%-20s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(COLOR_BOLD)Environment:$(COLOR_RESET)"
	@echo "  Terraform Version:    $(TF_VERSION)"
	@echo "  Parallelism:          $(TF_PARALLELISM)"
	@echo "  Current Workspace:    $(shell terraform workspace show 2>/dev/null || echo 'not initialized')"
	@echo ""
	@echo "$(COLOR_BOLD)Files:$(COLOR_RESET)"
	@echo "  Secrets:              $(TFVARS_SECRET) $(shell test -f $(TFVARS_SECRET) && echo '$(COLOR_GREEN)[exists]$(COLOR_RESET)' || echo '$(COLOR_RED)[missing]$(COLOR_RESET)')"
	@echo "  Instances:            $(INSTANCES_DIR)/*.auto.tfvars"
	@echo "  State:                $(STATE_DIR)/terraform.tfstate"
	@echo ""

# ============================================================================
# Setup & Initialization
# ============================================================================

.PHONY: secrets
secrets: ## Create terraform.tfvars.secret from example (if exists)
	@echo "$(COLOR_CYAN)$(SYMBOL_TOOL) Setting up secrets file...$(COLOR_RESET)"
	@if [ -f "$(TFVARS_SECRET)" ]; then \
		echo "$(COLOR_YELLOW)$(SYMBOL_WARN) $(TFVARS_SECRET) already exists. Skipping.$(COLOR_RESET)"; \
	elif [ -f "$(TFVARS_EXAMPLE)" ]; then \
		cp "$(TFVARS_EXAMPLE)" "$(TFVARS_SECRET)"; \
		echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Created $(TFVARS_SECRET) from example$(COLOR_RESET)"; \
		echo "$(COLOR_YELLOW)$(SYMBOL_WARN) Please edit $(TFVARS_SECRET) and add your credentials$(COLOR_RESET)"; \
	else \
		echo "$(COLOR_YELLOW)$(SYMBOL_WARN) $(TFVARS_EXAMPLE) not found. Creating empty $(TFVARS_SECRET)$(COLOR_RESET)"; \
		echo "# Proxmox Connection" > "$(TFVARS_SECRET)"; \
		echo "proxmox_api_url = \"\"" >> "$(TFVARS_SECRET)"; \
		echo "proxmox_api_token_id = \"\"" >> "$(TFVARS_SECRET)"; \
		echo "proxmox_api_token_secret = \"\"" >> "$(TFVARS_SECRET)"; \
		echo "" >> "$(TFVARS_SECRET)"; \
		echo "# GitLab API Token (for Terraform state backend)" >> "$(TFVARS_SECRET)"; \
		echo "gitlab_api_token = \"\"" >> "$(TFVARS_SECRET)"; \
		echo "" >> "$(TFVARS_SECRET)"; \
		echo "# Infrastructure Defaults" >> "$(TFVARS_SECRET)"; \
		echo "target_node = \"pve\"" >> "$(TFVARS_SECRET)"; \
		echo "default_storage = \"local-zfs\"" >> "$(TFVARS_SECRET)"; \
		echo "default_bridge = \"vmbr0\"" >> "$(TFVARS_SECRET)"; \
		echo "ssh_key_directory = \"~/.ssh\"" >> "$(TFVARS_SECRET)"; \
		echo "" >> "$(TFVARS_SECRET)"; \
		echo "# Linux VM-Specific Configuration" >> "$(TFVARS_SECRET)"; \
		echo "linux_vm_template = \"debian-12-cloudinit\"" >> "$(TFVARS_SECRET)"; \
		echo "$(COLOR_YELLOW)$(SYMBOL_WARN) Please edit $(TFVARS_SECRET) and add your credentials$(COLOR_RESET)"; \
	fi

.PHONY: init
init: ## Initialize Terraform (download providers, modules)
	@echo "$(COLOR_CYAN)$(SYMBOL_TOOL) Initializing Terraform...$(COLOR_RESET)"
	@if [ -f "$(BACKEND_SECRETS)" ]; then \
		echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Found $(BACKEND_SECRETS), using for backend auth$(COLOR_RESET)"; \
		terraform init -backend-config=$(BACKEND_SECRETS) -upgrade; \
	else \
		terraform init -upgrade; \
	fi
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Terraform initialized$(COLOR_RESET)"

.PHONY: init-backend
init-backend: ## Initialize Terraform with backend configuration
	@echo "$(COLOR_CYAN)$(SYMBOL_TOOL) Initializing Terraform with backend...$(COLOR_RESET)"
	@terraform init -backend-config=backend.hcl -upgrade
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Terraform initialized with backend$(COLOR_RESET)"

.PHONY: init-migrate
init-migrate: ## Initialize and migrate state to new backend
	@echo "$(COLOR_CYAN)$(SYMBOL_TOOL) Migrating Terraform state...$(COLOR_RESET)"
	@terraform init -migrate-state
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) State migration complete$(COLOR_RESET)"

.PHONY: init-reconfigure
init-reconfigure: ## Reconfigure backend (ignore existing state)
	@echo "$(COLOR_CYAN)$(SYMBOL_TOOL) Reconfiguring Terraform backend...$(COLOR_RESET)"
	@terraform init -reconfigure
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Backend reconfigured$(COLOR_RESET)"

.PHONY: upgrade
upgrade: ## Upgrade Terraform providers to latest versions
	@echo "$(COLOR_CYAN)$(SYMBOL_TOOL) Upgrading Terraform providers...$(COLOR_RESET)"
	@if [ -f "$(BACKEND_SECRETS)" ]; then \
		echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Found $(BACKEND_SECRETS), using for backend auth$(COLOR_RESET)"; \
		terraform init -backend-config=$(BACKEND_SECRETS) -upgrade; \
	else \
		terraform init -upgrade; \
	fi
	@terraform providers lock \
		-platform=darwin_amd64 \
		-platform=darwin_arm64 \
		-platform=linux_amd64 \
		-platform=linux_arm64 \
		-platform=windows_amd64
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Providers upgraded$(COLOR_RESET)"

.PHONY: modules-update
modules-update: ## Update all Terraform modules to latest versions
	@echo "$(COLOR_CYAN)$(SYMBOL_TOOL) Updating Terraform modules...$(COLOR_RESET)"
	@terraform get -update
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Modules updated$(COLOR_RESET)"

.PHONY: setup
setup: secrets init ## Complete initial setup (secrets + init)
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Setup complete!$(COLOR_RESET)"
	@echo "$(COLOR_YELLOW)$(SYMBOL_INFO) Next steps:$(COLOR_RESET)"
	@echo "  1. Edit $(TFVARS_SECRET) and add your credentials"
	@echo "  2. Copy and customize instance files in $(INSTANCES_DIR)/"
	@echo "  3. Run 'make plan' to preview changes"
	@echo "  4. Run 'make apply' to deploy infrastructure"

# ============================================================================
# Validation & Quality Assurance
# ============================================================================

.PHONY: fmt
fmt: ## Format all Terraform files
	@echo "$(COLOR_CYAN)$(SYMBOL_TOOL) Formatting Terraform files...$(COLOR_RESET)"
	@terraform fmt -recursive
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Formatting complete$(COLOR_RESET)"

.PHONY: fmt-check
fmt-check: ## Check if files are formatted (CI mode)
	@echo "$(COLOR_CYAN)$(SYMBOL_CHECK) Checking Terraform formatting...$(COLOR_RESET)"
	@if terraform fmt -check -recursive -diff; then \
		echo "$(COLOR_GREEN)$(SYMBOL_CHECK) All files are properly formatted$(COLOR_RESET)"; \
	else \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) Formatting issues found. Run 'make fmt' to fix.$(COLOR_RESET)"; \
		exit 1; \
	fi

.PHONY: validate
validate: ## Validate Terraform configuration
	@echo "$(COLOR_CYAN)$(SYMBOL_CHECK) Validating Terraform configuration...$(COLOR_RESET)"
	@terraform validate
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Configuration is valid$(COLOR_RESET)"

.PHONY: validate-json
validate-json: ## Validate and output as JSON
	@terraform validate -json

.PHONY: lint
lint: ## Run tflint on configuration (requires tflint)
	@echo "$(COLOR_CYAN)$(SYMBOL_CHECK) Running tflint...$(COLOR_RESET)"
	@if command -v tflint >/dev/null 2>&1; then \
		tflint --init && tflint; \
		echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Linting complete$(COLOR_RESET)"; \
	else \
		echo "$(COLOR_YELLOW)$(SYMBOL_WARN) tflint not installed. Skipping.$(COLOR_RESET)"; \
		echo "Install: https://github.com/terraform-linters/tflint"; \
	fi

.PHONY: security-scan
security-scan: ## Run all security scanners
	@$(MAKE) security-tfsec
	@$(MAKE) security-checkov
	@$(MAKE) security-terrascan

.PHONY: security-tfsec
security-tfsec: ## Run tfsec security scanner (requires tfsec)
	@echo "$(COLOR_CYAN)$(SYMBOL_LOCK) Running tfsec security scan...$(COLOR_RESET)"
	@if command -v tfsec >/dev/null 2>&1; then \
		tfsec . --format lovely --minimum-severity MEDIUM; \
		echo "$(COLOR_GREEN)$(SYMBOL_CHECK) tfsec scan complete$(COLOR_RESET)"; \
	else \
		echo "$(COLOR_YELLOW)$(SYMBOL_WARN) tfsec not installed. Skipping.$(COLOR_RESET)"; \
		echo "Install: https://github.com/aquasecurity/tfsec"; \
	fi

.PHONY: security-checkov
security-checkov: ## Run Checkov security scanner (requires checkov)
	@echo "$(COLOR_CYAN)$(SYMBOL_LOCK) Running Checkov security scan...$(COLOR_RESET)"
	@if command -v checkov >/dev/null 2>&1; then \
		checkov -d . --framework terraform --quiet --compact; \
		echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Checkov scan complete$(COLOR_RESET)"; \
	else \
		echo "$(COLOR_YELLOW)$(SYMBOL_WARN) checkov not installed. Skipping.$(COLOR_RESET)"; \
		echo "Install: pip install checkov"; \
	fi

.PHONY: security-terrascan
security-terrascan: ## Run Terrascan security scanner (requires terrascan)
	@echo "$(COLOR_CYAN)$(SYMBOL_LOCK) Running Terrascan security scan...$(COLOR_RESET)"
	@if command -v terrascan >/dev/null 2>&1; then \
		terrascan scan -t all; \
		echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Terrascan scan complete$(COLOR_RESET)"; \
	else \
		echo "$(COLOR_YELLOW)$(SYMBOL_WARN) terrascan not installed. Skipping.$(COLOR_RESET)"; \
		echo "Install: https://github.com/tenable/terrascan"; \
	fi

# ============================================================================
# Planning & Deployment
# ============================================================================

.PHONY: plan
plan: ## Create Terraform execution plan
	@echo "$(COLOR_CYAN)$(SYMBOL_CHART) Planning Terraform changes...$(COLOR_RESET)"
	@if [ -f "$(TFVARS_SECRET)" ]; then \
		VAR_FILES="-var-file=$(TFVARS_SECRET)"; \
		for file in $(INSTANCES_DIR)/*.auto.tfvars; do \
			if [ -f "$$file" ]; then \
				VAR_FILES="$$VAR_FILES -var-file=$$file"; \
			fi; \
		done; \
		terraform plan $$VAR_FILES -parallelism=$(TF_PARALLELISM); \
	else \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) $(TFVARS_SECRET) not found. Run 'make secrets' first.$(COLOR_RESET)"; \
		exit 1; \
	fi

.PHONY: plan-detailed
plan-detailed: ## Create detailed execution plan with all changes
	@echo "$(COLOR_CYAN)$(SYMBOL_CHART) Creating detailed plan...$(COLOR_RESET)"
	@if [ -f "$(TFVARS_SECRET)" ]; then \
		VAR_FILES="-var-file=$(TFVARS_SECRET)"; \
		for file in $(INSTANCES_DIR)/*.auto.tfvars; do \
			if [ -f "$$file" ]; then \
				VAR_FILES="$$VAR_FILES -var-file=$$file"; \
			fi; \
		done; \
		terraform plan $$VAR_FILES -parallelism=$(TF_PARALLELISM) -detailed-exitcode; \
	else \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) $(TFVARS_SECRET) not found.$(COLOR_RESET)"; \
		exit 1; \
	fi

.PHONY: plan-target
plan-target: ## Plan specific resource (usage: make plan-target TARGET=module.lxc)
	@if [ -z "$(TARGET)" ]; then \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) TARGET not specified. Usage: make plan-target TARGET=module.lxc$(COLOR_RESET)"; \
		exit 1; \
	fi
	@echo "$(COLOR_CYAN)$(SYMBOL_CHART) Planning changes for $(TARGET)...$(COLOR_RESET)"
	@if [ -f "$(TFVARS_SECRET)" ]; then \
		VAR_FILES="-var-file=$(TFVARS_SECRET)"; \
		for file in $(INSTANCES_DIR)/*.auto.tfvars; do \
			if [ -f "$$file" ]; then \
				VAR_FILES="$$VAR_FILES -var-file=$$file"; \
			fi; \
		done; \
		terraform plan $$VAR_FILES -target=$(TARGET); \
	else \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) $(TFVARS_SECRET) not found.$(COLOR_RESET)"; \
		exit 1; \
	fi

.PHONY: plan-destroy
plan-destroy: ## Create destruction plan
	@echo "$(COLOR_RED)$(SYMBOL_FIRE) Planning infrastructure destruction...$(COLOR_RESET)"
	@if [ -f "$(TFVARS_SECRET)" ]; then \
		VAR_FILES="-var-file=$(TFVARS_SECRET)"; \
		for file in $(INSTANCES_DIR)/*.auto.tfvars; do \
			if [ -f "$$file" ]; then \
				VAR_FILES="$$VAR_FILES -var-file=$$file"; \
			fi; \
		done; \
		terraform plan -destroy $$VAR_FILES; \
	else \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) $(TFVARS_SECRET) not found.$(COLOR_RESET)"; \
		exit 1; \
	fi

.PHONY: plan-out
plan-out: ## Create and save execution plan to file
	@echo "$(COLOR_CYAN)$(SYMBOL_CHART) Creating and saving plan...$(COLOR_RESET)"
	@mkdir -p generated/plans
	@PLAN_FILE="generated/plans/plan-$$(date +%Y%m%d-%H%M%S).tfplan"; \
	if [ -f "$(TFVARS_SECRET)" ]; then \
		VAR_FILES="-var-file=$(TFVARS_SECRET)"; \
		for file in $(INSTANCES_DIR)/*.auto.tfvars; do \
			if [ -f "$$file" ]; then \
				VAR_FILES="$$VAR_FILES -var-file=$$file"; \
			fi; \
		done; \
		terraform plan $$VAR_FILES -out=$$PLAN_FILE; \
		echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Plan saved to $$PLAN_FILE$(COLOR_RESET)"; \
	else \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) $(TFVARS_SECRET) not found.$(COLOR_RESET)"; \
		exit 1; \
	fi

.PHONY: apply
apply: ## Apply Terraform changes (deploy infrastructure)
	@echo "$(COLOR_GREEN)$(SYMBOL_ROCKET) Applying Terraform changes...$(COLOR_RESET)"
	@if [ -f "$(TFVARS_SECRET)" ]; then \
		VAR_FILES="-var-file=$(TFVARS_SECRET)"; \
		for file in $(INSTANCES_DIR)/*.auto.tfvars; do \
			if [ -f "$$file" ]; then \
				VAR_FILES="$$VAR_FILES -var-file=$$file"; \
			fi; \
		done; \
		terraform apply $$VAR_FILES -parallelism=$(TF_PARALLELISM); \
	else \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) $(TFVARS_SECRET) not found. Run 'make secrets' first.$(COLOR_RESET)"; \
		exit 1; \
	fi
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Infrastructure deployed successfully$(COLOR_RESET)"

.PHONY: apply-auto
apply-auto: ## Apply changes without confirmation (CI mode)
	@echo "$(COLOR_GREEN)$(SYMBOL_ROCKET) Auto-applying Terraform changes...$(COLOR_RESET)"
	@if [ -f "$(TFVARS_SECRET)" ]; then \
		terraform apply -var-file=$(TFVARS_SECRET) -auto-approve -parallelism=$(TF_PARALLELISM); \
	else \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) $(TFVARS_SECRET) not found.$(COLOR_RESET)"; \
		exit 1; \
	fi

.PHONY: apply-target
apply-target: ## Apply specific resource (usage: make apply-target TARGET=module.lxc)
	@if [ -z "$(TARGET)" ]; then \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) TARGET not specified. Usage: make apply-target TARGET=module.lxc$(COLOR_RESET)"; \
		exit 1; \
	fi
	@echo "$(COLOR_GREEN)$(SYMBOL_ROCKET) Applying changes for $(TARGET)...$(COLOR_RESET)"
	@if [ -f "$(TFVARS_SECRET)" ]; then \
		terraform apply -var-file=$(TFVARS_SECRET) -target=$(TARGET); \
	else \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) $(TFVARS_SECRET) not found.$(COLOR_RESET)"; \
		exit 1; \
	fi

.PHONY: refresh
refresh: ## Refresh Terraform state (sync with real infrastructure)
	@echo "$(COLOR_CYAN)$(SYMBOL_TOOL) Refreshing Terraform state...$(COLOR_RESET)"
	@if [ -f "$(TFVARS_SECRET)" ]; then \
		terraform refresh -var-file=$(TFVARS_SECRET); \
	else \
		terraform refresh; \
	fi
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) State refreshed$(COLOR_RESET)"

.PHONY: import
import: ## Import existing resource (usage: make import RESOURCE=module.lxc[\"dns-1\"] ID=pve/lxc/100)
	@if [ -z "$(RESOURCE)" ] || [ -z "$(ID)" ]; then \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) Usage: make import RESOURCE='module.lxc[\"dns-1\"]' ID=pve/lxc/100$(COLOR_RESET)"; \
		exit 1; \
	fi
	@echo "$(COLOR_CYAN)$(SYMBOL_TOOL) Importing $(RESOURCE) with ID $(ID)...$(COLOR_RESET)"
	@if [ -f "$(TFVARS_SECRET)" ]; then \
		VAR_FILES="-var-file=$(TFVARS_SECRET)"; \
		for file in $(INSTANCES_DIR)/*.auto.tfvars; do \
			if [ -f "$$file" ]; then \
				VAR_FILES="$$VAR_FILES -var-file=$$file"; \
			fi; \
		done; \
		terraform import $$VAR_FILES '$(RESOURCE)' '$(ID)'; \
	else \
		terraform import '$(RESOURCE)' '$(ID)'; \
	fi
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Resource imported$(COLOR_RESET)"

.PHONY: import-from-proxmox
import-from-proxmox: ## Auto-import Linux VM from Proxmox (usage: make import-from-proxmox VMID=200 [NODE=pve])
	@if [ -z "$(VMID)" ]; then \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) Usage: make import-from-proxmox VMID=200 [NODE=pve]$(COLOR_RESET)"; \
		exit 1; \
	fi
	@NODE=$${NODE:-pve}; \
	if [ ! -f "$(TFVARS_SECRET)" ]; then \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) $(TFVARS_SECRET) not found. Run 'make secrets' first.$(COLOR_RESET)"; \
		exit 1; \
	fi; \
	API_URL=$$(grep proxmox_api_url $(TFVARS_SECRET) | cut -d'"' -f2); \
	API_TOKEN_ID=$$(grep proxmox_api_token_id $(TFVARS_SECRET) | cut -d'"' -f2); \
	API_TOKEN_SECRET=$$(grep proxmox_api_token_secret $(TFVARS_SECRET) | cut -d'"' -f2); \
	echo "$(COLOR_CYAN)$(SYMBOL_TOOL) Fetching config for VMID $(VMID) from Proxmox...$(COLOR_RESET)"; \
	python3 ../scripts/import_proxmox.py \
		--vmid $(VMID) \
		--type vm \
		--node $$NODE \
		--api-url "$$API_URL" \
		--api-token-id "$$API_TOKEN_ID" \
		--api-token-secret "$$API_TOKEN_SECRET"; \
	if [ $$? -eq 0 ]; then \
		echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Configuration generated successfully$(COLOR_RESET)"; \
		echo "$(COLOR_YELLOW)$(SYMBOL_INFO) Review the changes in $(INSTANCES_DIR)/linux-vms.auto.tfvars$(COLOR_RESET)"; \
		echo "$(COLOR_YELLOW)$(SYMBOL_INFO) Then run the terraform import command shown above$(COLOR_RESET)"; \
	else \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) Import script failed$(COLOR_RESET)"; \
		exit 1; \
	fi

.PHONY: import-vm-linux
import-vm-linux: ## Import existing Linux VM (usage: make import-vm-linux HOSTNAME=web-01 NODE=pve VMID=200)
	@if [ -z "$(HOSTNAME)" ] || [ -z "$(VMID)" ]; then \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) Usage: make import-vm-linux HOSTNAME=vm-name VMID=200 [NODE=pve]$(COLOR_RESET)"; \
		exit 1; \
	fi
	@NODE=$${NODE:-pve}; \
	SSH_KEY_DIR=$${SSH_KEY_DIR:-$$HOME/.ssh}; \
	PRIVATE_KEY="$$SSH_KEY_DIR/$(HOSTNAME)_id_ed25519"; \
	PUBLIC_KEY="$$SSH_KEY_DIR/$(HOSTNAME)_id_ed25519.pub"; \
	echo "$(COLOR_CYAN)$(SYMBOL_TOOL) Importing Linux VM $(HOSTNAME) (VMID $(VMID)) from node $$NODE...$(COLOR_RESET)"; \
	if [ ! -f "$$PRIVATE_KEY" ] || [ ! -f "$$PUBLIC_KEY" ]; then \
		echo "$(COLOR_YELLOW)$(SYMBOL_WARN) SSH keys not found at $$PRIVATE_KEY$(COLOR_RESET)"; \
		echo "$(COLOR_YELLOW)$(SYMBOL_INFO) Terraform will generate new keys (you can replace them later)$(COLOR_RESET)"; \
	else \
		echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Found existing SSH keys at $$PRIVATE_KEY$(COLOR_RESET)"; \
	fi; \
	if [ -f "$(TFVARS_SECRET)" ]; then \
		VAR_FILES="-var-file=$(TFVARS_SECRET)"; \
		for file in $(INSTANCES_DIR)/*.auto.tfvars; do \
			if [ -f "$$file" ]; then \
				VAR_FILES="$$VAR_FILES -var-file=$$file"; \
			fi; \
		done; \
		echo "$(COLOR_CYAN)$(SYMBOL_INFO) Importing Linux VM resource...$(COLOR_RESET)"; \
		terraform import $$VAR_FILES 'module.linux_vms[0].proxmox_vm_qemu.vm["$(HOSTNAME)"]' "$$NODE/qemu/$(VMID)"; \
		if [ -f "$$PRIVATE_KEY" ] && [ -f "$$PUBLIC_KEY" ]; then \
			echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Existing SSH keys will be preserved by lifecycle rules$(COLOR_RESET)"; \
		fi; \
	else \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) $(TFVARS_SECRET) not found. Run 'make secrets' first.$(COLOR_RESET)"; \
		exit 1; \
	fi
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Linux VM $(HOSTNAME) imported$(COLOR_RESET)"
	@echo "$(COLOR_YELLOW)$(SYMBOL_WARN) Run 'make plan' to verify the import$(COLOR_RESET)"

.PHONY: import-guide
import-guide: ## Show guide for importing existing Linux VMs
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)╔══════════════════════════════════════════════════════════════════╗$(COLOR_RESET)"
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)║         Importing Existing Linux VMs Guide                       ║$(COLOR_RESET)"
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)╚══════════════════════════════════════════════════════════════════╝$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)OPTION 1: Automated Import (Recommended)$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_CYAN)Step 1: Run automated import$(COLOR_RESET)"
	@echo "  • $(COLOR_GREEN)make import-from-proxmox VMID=200 [NODE=pve]$(COLOR_RESET)"
	@echo "  This fetches the VM config from Proxmox API and generates the Terraform definition"
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_CYAN)Step 2: Review and run import command$(COLOR_RESET)"
	@echo "  The script will show you the terraform import command to run"
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_CYAN)Step 3: Verify import$(COLOR_RESET)"
	@echo "  Run: $(COLOR_GREEN)make plan$(COLOR_RESET) to verify the import and check for any drift"
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)OPTION 2: Manual Import$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_CYAN)Step 1: Define the VM in instance file$(COLOR_RESET)"
	@echo "  Add the VM definition to:"
	@echo "  • $(INSTANCES_DIR)/linux-vms.auto.tfvars"
	@echo "  Set preserve_ssh_key = true for VMs with existing SSH keys"
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_CYAN)Step 2: Import the VM$(COLOR_RESET)"
	@echo "  Use the import command:"
	@echo "  • $(COLOR_GREEN)make import-vm-linux HOSTNAME=vm-name VMID=200$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_CYAN)Step 3: Verify import$(COLOR_RESET)"
	@echo "  Run: $(COLOR_GREEN)make plan$(COLOR_RESET) to verify the import and check for any drift"
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_YELLOW)$(SYMBOL_WARN) Important Notes:$(COLOR_RESET)"
	@echo "  • The VM MUST be defined in the .auto.tfvars file BEFORE importing"
	@echo "  • Use the exact hostname as it appears in Proxmox"
	@echo "  • SSH keys: Ensure keys exist at ~/.ssh/<hostname>_id_ed25519 before import"
	@echo "  • Add hostname to imported.auto.tfvars to preserve existing SSH keys"
	@echo "  • After import, run 'make plan' to see what Terraform wants to change"
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_CYAN)Finding VMIDs:$(COLOR_RESET)"
	@echo "  • Proxmox Web UI: Check the VMID column in the resource tree"
	@echo "  • CLI: $(COLOR_GREEN)pvesh get /nodes/\$$NODE/qemu$(COLOR_RESET)"
	@echo ""

.PHONY: taint
taint: ## Mark resource for recreation (usage: make taint RESOURCE=module.lxc[\"dns-1\"])
	@if [ -z "$(RESOURCE)" ]; then \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) Usage: make taint RESOURCE='module.lxc[\"dns-1\"]'$(COLOR_RESET)"; \
		exit 1; \
	fi
	@echo "$(COLOR_YELLOW)$(SYMBOL_WARN) Tainting $(RESOURCE) for recreation...$(COLOR_RESET)"
	@terraform taint '$(RESOURCE)'
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Resource tainted$(COLOR_RESET)"

.PHONY: untaint
untaint: ## Remove taint from resource (usage: make untaint RESOURCE=module.lxc[\"dns-1\"])
	@if [ -z "$(RESOURCE)" ]; then \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) Usage: make untaint RESOURCE='module.lxc[\"dns-1\"]'$(COLOR_RESET)"; \
		exit 1; \
	fi
	@echo "$(COLOR_CYAN)$(SYMBOL_TOOL) Removing taint from $(RESOURCE)...$(COLOR_RESET)"
	@terraform untaint '$(RESOURCE)'
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Taint removed$(COLOR_RESET)"

# ============================================================================
# Destruction
# ============================================================================

.PHONY: destroy
destroy: ## Destroy all infrastructure (with confirmation)
	@echo "$(COLOR_RED)$(SYMBOL_FIRE) DESTROYING all infrastructure...$(COLOR_RESET)"
	@echo "$(COLOR_YELLOW)$(SYMBOL_WARN) This will DELETE all Linux VMs and related resources!$(COLOR_RESET)"
	@read -p "Type 'yes' to confirm destruction: " confirm && [ "$$confirm" = "yes" ] || exit 1
	@if [ -f "$(TFVARS_SECRET)" ]; then \
		terraform destroy -var-file=$(TFVARS_SECRET) -parallelism=$(TF_PARALLELISM); \
	else \
		terraform destroy -parallelism=$(TF_PARALLELISM); \
	fi
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Infrastructure destroyed$(COLOR_RESET)"

.PHONY: destroy-auto
destroy-auto: ## Destroy without confirmation (DANGEROUS - CI mode)
	@echo "$(COLOR_RED)$(SYMBOL_FIRE) Auto-destroying infrastructure...$(COLOR_RESET)"
	@if [ -f "$(TFVARS_SECRET)" ]; then \
		terraform destroy -var-file=$(TFVARS_SECRET) -auto-approve -parallelism=$(TF_PARALLELISM); \
	else \
		terraform destroy -auto-approve -parallelism=$(TF_PARALLELISM); \
	fi

.PHONY: destroy-target
destroy-target: ## Destroy specific resource (usage: make destroy-target TARGET=module.lxc[\"dns-1\"])
	@if [ -z "$(TARGET)" ]; then \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) Usage: make destroy-target TARGET='module.lxc[\"dns-1\"]'$(COLOR_RESET)"; \
		exit 1; \
	fi
	@echo "$(COLOR_RED)$(SYMBOL_FIRE) Destroying $(TARGET)...$(COLOR_RESET)"
	@read -p "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || exit 1
	@if [ -f "$(TFVARS_SECRET)" ]; then \
		terraform destroy -var-file=$(TFVARS_SECRET) -target=$(TARGET); \
	else \
		terraform destroy -target=$(TARGET); \
	fi

# ============================================================================
# State Management
# ============================================================================

.PHONY: state-list
state-list: ## List all resources in state
	@echo "$(COLOR_CYAN)$(SYMBOL_CHART) Listing Terraform state resources...$(COLOR_RESET)"
	@terraform state list

.PHONY: state-show
state-show: ## Show resource details (usage: make state-show RESOURCE=module.linux_vms[0].proxmox_vm_qemu.vm[\"vm-name\"])
	@if [ -z "$(RESOURCE)" ]; then \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) Usage: make state-show RESOURCE='module.linux_vms[0].proxmox_vm_qemu.vm[\"vm-name\"]'$(COLOR_RESET)"; \
		exit 1; \
	fi
	@terraform state show '$(RESOURCE)'

.PHONY: state-rm
state-rm: ## Remove resource from state (usage: make state-rm RESOURCE=k3s-worker-3 removes ALL resources for hostname, or RESOURCE='module.linux_vms[0].proxmox_vm_qemu.vm["vm-name"]' for specific resource)
	@if [ -z "$(RESOURCE)" ]; then \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) Usage: make state-rm RESOURCE=k3s-worker-3$(COLOR_RESET)"; \
		echo "$(COLOR_YELLOW)   (Removes ALL resources for that hostname)$(COLOR_RESET)"; \
		echo "$(COLOR_YELLOW)   Or: make state-rm RESOURCE='module.linux_vms[0].proxmox_vm_qemu.vm[\"vm-name\"]'$(COLOR_RESET)"; \
		exit 1; \
	fi
	@# Auto-detect if RESOURCE is just a hostname (contains no dots/brackets) or full resource address
	@if echo "$(RESOURCE)" | grep -qE '^[a-zA-Z0-9_-]+$$'; then \
		echo "$(COLOR_CYAN)$(SYMBOL_TOOL) Auto-detected hostname: $(RESOURCE)$(COLOR_RESET)"; \
		echo "$(COLOR_YELLOW)$(SYMBOL_WARN) This will remove ALL resources for $(RESOURCE) from state:$(COLOR_RESET)"; \
		RESOURCES=$$(terraform state list | grep -F "\"$(RESOURCE)\"" || true); \
		if [ -z "$$RESOURCES" ]; then \
			echo "$(COLOR_RED)No resources found for $(RESOURCE)$(COLOR_RESET)"; \
			exit 1; \
		fi; \
		echo "$$RESOURCES" | while read -r resource; do \
			echo "  - $$resource"; \
		done; \
		read -p "Type 'yes' to confirm removal of all resources: " confirm && [ "$$confirm" = "yes" ] || exit 1; \
		echo "$$RESOURCES" | while read -r resource; do \
			echo "$(COLOR_CYAN)Removing: $$resource$(COLOR_RESET)"; \
			terraform state rm $$resource || true; \
		done; \
		echo "$(COLOR_GREEN)$(SYMBOL_CHECK) All resources for $(RESOURCE) removed from state$(COLOR_RESET)"; \
	else \
		RESOURCE_ADDR="$(RESOURCE)"; \
		echo "$(COLOR_YELLOW)$(SYMBOL_WARN) Removing $$RESOURCE_ADDR from state...$(COLOR_RESET)"; \
		read -p "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || exit 1; \
		terraform state rm $$RESOURCE_ADDR; \
		echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Resource removed from state$(COLOR_RESET)"; \
	fi

.PHONY: state-mv
state-mv: ## Move/rename resource in state (usage: make state-mv FROM=old TO=new)
	@if [ -z "$(FROM)" ] || [ -z "$(TO)" ]; then \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) Usage: make state-mv FROM='module.old' TO='module.new'$(COLOR_RESET)"; \
		exit 1; \
	fi
	@echo "$(COLOR_CYAN)$(SYMBOL_TOOL) Moving $(FROM) to $(TO)...$(COLOR_RESET)"
	@terraform state mv '$(FROM)' '$(TO)'
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Resource moved$(COLOR_RESET)"

.PHONY: state-pull
state-pull: ## Pull remote state to stdout
	@terraform state pull

.PHONY: state-push
state-push: ## Push local state to remote (DANGEROUS)
	@echo "$(COLOR_RED)$(SYMBOL_WARN) Pushing local state to remote...$(COLOR_RESET)"
	@read -p "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || exit 1
	@if [ -z "$(FILE)" ]; then \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) Usage: make state-push FILE=path/to/state.tfstate$(COLOR_RESET)"; \
		exit 1; \
	fi
	@terraform state push $(FILE)

.PHONY: state-replace-provider
state-replace-provider: ## Replace provider in state (usage: make state-replace-provider FROM=old TO=new)
	@if [ -z "$(FROM)" ] || [ -z "$(TO)" ]; then \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) Usage: make state-replace-provider FROM='registry.terraform.io/old' TO='registry.terraform.io/new'$(COLOR_RESET)"; \
		exit 1; \
	fi
	@terraform state replace-provider '$(FROM)' '$(TO)'

# ============================================================================
# Backup & Restore
# ============================================================================

.PHONY: backup-state
backup-state: ## Backup current Terraform state
	@echo "$(COLOR_CYAN)$(SYMBOL_TOOL) Backing up Terraform state...$(COLOR_RESET)"
	@mkdir -p $(BACKUP_DIR)
	@BACKUP_FILE="$(BACKUP_DIR)/terraform.tfstate.$$(date +%Y%m%d-%H%M%S).backup"; \
	terraform state pull > $$BACKUP_FILE; \
	echo "$(COLOR_GREEN)$(SYMBOL_CHECK) State backed up to $$BACKUP_FILE$(COLOR_RESET)"

.PHONY: restore-state
restore-state: ## Restore Terraform state from backup (usage: make restore-state FILE=backup.tfstate)
	@if [ -z "$(FILE)" ]; then \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) Usage: make restore-state FILE=$(BACKUP_DIR)/terraform.tfstate.YYYYMMDD-HHMMSS.backup$(COLOR_RESET)"; \
		exit 1; \
	fi
	@echo "$(COLOR_YELLOW)$(SYMBOL_WARN) Restoring state from $(FILE)...$(COLOR_RESET)"
	@read -p "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || exit 1
	@terraform state push $(FILE)
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) State restored$(COLOR_RESET)"

.PHONY: backup-all
backup-all: backup-state ## Backup state and configuration
	@echo "$(COLOR_CYAN)$(SYMBOL_TOOL) Backing up configuration files...$(COLOR_RESET)"
	@mkdir -p $(BACKUP_DIR)
	@BACKUP_DIR_NAME="$(BACKUP_DIR)/config-$$(date +%Y%m%d-%H%M%S)"; \
	mkdir -p $$BACKUP_DIR_NAME; \
	cp -r $(INSTANCES_DIR) $$BACKUP_DIR_NAME/ 2>/dev/null || true; \
	cp $(TFVARS_SECRET) $$BACKUP_DIR_NAME/ 2>/dev/null || true; \
	echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Configuration backed up to $$BACKUP_DIR_NAME$(COLOR_RESET)"

# ============================================================================
# Workspace Management
# ============================================================================

.PHONY: workspace-list
workspace-list: ## List all workspaces
	@terraform workspace list

.PHONY: workspace-show
workspace-show: ## Show current workspace
	@terraform workspace show

.PHONY: workspace-new
workspace-new: ## Create new workspace (usage: make workspace-new NAME=dev)
	@if [ -z "$(NAME)" ]; then \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) Usage: make workspace-new NAME=dev$(COLOR_RESET)"; \
		exit 1; \
	fi
	@terraform workspace new $(NAME)

.PHONY: workspace-select
workspace-select: ## Switch to workspace (usage: make workspace-select NAME=dev)
	@if [ -z "$(NAME)" ]; then \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) Usage: make workspace-select NAME=dev$(COLOR_RESET)"; \
		exit 1; \
	fi
	@terraform workspace select $(NAME)

.PHONY: workspace-delete
workspace-delete: ## Delete workspace (usage: make workspace-delete NAME=dev)
	@if [ -z "$(NAME)" ]; then \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) Usage: make workspace-delete NAME=dev$(COLOR_RESET)"; \
		exit 1; \
	fi
	@terraform workspace delete $(NAME)

# ============================================================================
# Outputs & Reporting
# ============================================================================

.PHONY: output
output: ## Show all Terraform outputs
	@terraform output

.PHONY: output-json
output-json: ## Show outputs as JSON
	@terraform output -json

.PHONY: output-raw
output-raw: ## Show specific output raw (usage: make output-raw NAME=ssh_commands)
	@if [ -z "$(NAME)" ]; then \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) Usage: make output-raw NAME=ssh_commands$(COLOR_RESET)"; \
		exit 1; \
	fi
	@terraform output -raw $(NAME)

.PHONY: show
show: ## Show current state or saved plan
	@if [ ! -z "$(FILE)" ]; then \
		terraform show $(FILE); \
	else \
		terraform show; \
	fi

.PHONY: show-json
show-json: ## Show state or plan as JSON
	@if [ ! -z "$(FILE)" ]; then \
		terraform show -json $(FILE); \
	else \
		terraform show -json; \
	fi

.PHONY: inventory
inventory: ## Generate Ansible inventory from Terraform state
	@echo "$(COLOR_CYAN)$(SYMBOL_BOOK) Generating Ansible inventory...$(COLOR_RESET)"
	@mkdir -p $(dir $(ANSIBLE_INVENTORY))
	@terraform output -raw ansible_inventory_yaml > $(ANSIBLE_INVENTORY)
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Inventory written to $(ANSIBLE_INVENTORY)$(COLOR_RESET)"

.PHONY: inventory-ini
inventory-ini: ## Generate Ansible inventory in INI format
	@echo "$(COLOR_CYAN)$(SYMBOL_BOOK) Generating Ansible inventory (INI format)...$(COLOR_RESET)"
	@mkdir -p $(dir $(ANSIBLE_INVENTORY))
	@terraform output -raw ansible_inventory_ini > $(ANSIBLE_INVENTORY:.yml=.ini)
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Inventory written to $(ANSIBLE_INVENTORY:.yml=.ini)$(COLOR_RESET)"

.PHONY: ssh-commands
ssh-commands: ## Show SSH commands for all hosts
	@echo "$(COLOR_CYAN)$(SYMBOL_INFO) SSH Connection Commands:$(COLOR_RESET)"
	@terraform output -json ssh_commands 2>/dev/null | jq -r '.[]' || echo "No SSH commands available"

.PHONY: status
status: ## Show current infrastructure status
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)╔══════════════════════════════════════════════════════════════════╗$(COLOR_RESET)"
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)║            Linux VMs Status Report                               ║$(COLOR_RESET)"
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)╚══════════════════════════════════════════════════════════════════╝$(COLOR_RESET)"
	@echo ""
	@terraform output deployment_summary 2>/dev/null || echo "$(COLOR_YELLOW)No deployment summary available$(COLOR_RESET)"

.PHONY: graph
graph: ## Generate dependency graph (requires graphviz)
	@echo "$(COLOR_CYAN)$(SYMBOL_CHART) Generating Terraform dependency graph...$(COLOR_RESET)"
	@mkdir -p generated/graphs
	@terraform graph | dot -Tpng > generated/graphs/graph-$$(date +%Y%m%d-%H%M%S).png
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Graph saved to generated/graphs/$(COLOR_RESET)"

.PHONY: graph-plan
graph-plan: ## Generate graph of planned changes
	@echo "$(COLOR_CYAN)$(SYMBOL_CHART) Generating plan graph...$(COLOR_RESET)"
	@mkdir -p generated/graphs
	@if [ -f "$(TFVARS_SECRET)" ]; then \
		terraform graph -type=plan -var-file=$(TFVARS_SECRET) | dot -Tpng > generated/graphs/plan-graph-$$(date +%Y%m%d-%H%M%S).png; \
	else \
		terraform graph -type=plan | dot -Tpng > generated/graphs/plan-graph-$$(date +%Y%m%d-%H%M%S).png; \
	fi
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Plan graph saved to generated/graphs/$(COLOR_RESET)"

.PHONY: cost
cost: ## Estimate infrastructure cost (requires infracost)
	@echo "$(COLOR_CYAN)$(SYMBOL_CHART) Estimating infrastructure cost...$(COLOR_RESET)"
	@if command -v infracost >/dev/null 2>&1; then \
		infracost breakdown --path .; \
	else \
		echo "$(COLOR_YELLOW)$(SYMBOL_WARN) infracost not installed. Skipping.$(COLOR_RESET)"; \
		echo "Install: https://www.infracost.io/docs/#quick-start"; \
	fi

.PHONY: cost-diff
cost-diff: ## Show cost difference for planned changes (requires infracost)
	@echo "$(COLOR_CYAN)$(SYMBOL_CHART) Calculating cost difference...$(COLOR_RESET)"
	@if command -v infracost >/dev/null 2>&1; then \
		infracost diff --path .; \
	else \
		echo "$(COLOR_YELLOW)$(SYMBOL_WARN) infracost not installed.$(COLOR_RESET)"; \
	fi

.PHONY: docs
docs: ## Generate documentation (requires terraform-docs)
	@echo "$(COLOR_CYAN)$(SYMBOL_BOOK) Generating documentation...$(COLOR_RESET)"
	@if command -v terraform-docs >/dev/null 2>&1; then \
		terraform-docs markdown table --output-file README.md .; \
		for module in modules/*; do \
			if [ -d "$$module" ]; then \
				terraform-docs markdown table --output-file README.md "$$module"; \
			fi; \
		done; \
		echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Documentation generated$(COLOR_RESET)"; \
	else \
		echo "$(COLOR_YELLOW)$(SYMBOL_WARN) terraform-docs not installed. Skipping.$(COLOR_RESET)"; \
		echo "Install: https://terraform-docs.io/user-guide/installation/"; \
	fi

# ============================================================================
# Testing & Drift Detection
# ============================================================================

.PHONY: test
test: ## Run Terraform tests (requires Terraform >= 1.6)
	@echo "$(COLOR_CYAN)$(SYMBOL_CHECK) Running Terraform tests...$(COLOR_RESET)"
	@if terraform version | grep -q "v1\.[6-9]\|v1\.[1-9][0-9]"; then \
		terraform test; \
		echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Tests passed$(COLOR_RESET)"; \
	else \
		echo "$(COLOR_YELLOW)$(SYMBOL_WARN) Terraform >= 1.6 required for native tests$(COLOR_RESET)"; \
	fi

.PHONY: drift-detect
drift-detect: ## Detect configuration drift
	@echo "$(COLOR_CYAN)$(SYMBOL_CHART) Detecting configuration drift...$(COLOR_RESET)"
	@if [ -f "$(TFVARS_SECRET)" ]; then \
		if terraform plan -var-file=$(TFVARS_SECRET) -detailed-exitcode; then \
			echo "$(COLOR_GREEN)$(SYMBOL_CHECK) No drift detected$(COLOR_RESET)"; \
		else \
			EXIT_CODE=$$?; \
			if [ $$EXIT_CODE -eq 2 ]; then \
				echo "$(COLOR_YELLOW)$(SYMBOL_WARN) Configuration drift detected!$(COLOR_RESET)"; \
				exit 2; \
			fi; \
		fi; \
	else \
		echo "$(COLOR_RED)$(SYMBOL_CROSS) $(TFVARS_SECRET) not found.$(COLOR_RESET)"; \
		exit 1; \
	fi

# ============================================================================
# Maintenance & Cleanup
# ============================================================================

.PHONY: lock
lock: ## Update provider lock file for multiple platforms
	@echo "$(COLOR_CYAN)$(SYMBOL_LOCK) Updating provider lock file...$(COLOR_RESET)"
	@terraform providers lock \
		-platform=darwin_amd64 \
		-platform=darwin_arm64 \
		-platform=linux_amd64 \
		-platform=linux_arm64 \
		-platform=windows_amd64
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Lock file updated$(COLOR_RESET)"

.PHONY: clean
clean: ## Clean temporary files and caches
	@echo "$(COLOR_CYAN)$(SYMBOL_CLEAN) Cleaning temporary files...$(COLOR_RESET)"
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.tfstate.backup" -delete 2>/dev/null || true
	@find . -type f -name ".terraform.lock.hcl.bak" -delete 2>/dev/null || true
	@find . -type f -name "errored.tfstate" -delete 2>/dev/null || true
	@rm -rf generated/plans/*.tfplan 2>/dev/null || true
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Cleanup complete$(COLOR_RESET)"

.PHONY: clean-all
clean-all: clean ## Clean everything including state backups (DANGEROUS)
	@echo "$(COLOR_RED)$(SYMBOL_WARN) This will delete ALL backups and generated files!$(COLOR_RESET)"
	@read -p "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || exit 1
	@rm -rf $(BACKUP_DIR) generated/ 2>/dev/null || true
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Deep cleanup complete$(COLOR_RESET)"

.PHONY: providers
providers: ## Show required providers and versions
	@terraform providers

.PHONY: providers-schema
providers-schema: ## Show provider schemas as JSON
	@terraform providers schema -json

.PHONY: console
console: ## Open Terraform console for debugging
	@if [ -f "$(TFVARS_SECRET)" ]; then \
		terraform console -var-file=$(TFVARS_SECRET); \
	else \
		terraform console; \
	fi

# ============================================================================
# Workflows (Combined Commands)
# ============================================================================

.PHONY: quick
quick: fmt validate plan ## Quick workflow: format + validate + plan
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Quick validation complete$(COLOR_RESET)"

.PHONY: full-check
full-check: fmt-check validate lint security-scan ## Full quality check (CI mode)
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Full quality check passed$(COLOR_RESET)"

.PHONY: deploy
deploy: init plan ## Deploy workflow: init + plan (then prompts for apply)
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)$(SYMBOL_INFO) Deployment plan ready!$(COLOR_RESET)"
	@echo "$(COLOR_YELLOW)Review the plan above, then run:$(COLOR_RESET)"
	@echo "  $(COLOR_CYAN)make apply$(COLOR_RESET)         - Apply changes"
	@echo "  $(COLOR_CYAN)make apply-auto$(COLOR_RESET)    - Apply without confirmation"
	@echo ""
	@echo "$(COLOR_YELLOW)After deployment:$(COLOR_RESET)"
	@echo "  $(COLOR_CYAN)make inventory$(COLOR_RESET)     - Generate Ansible inventory"
	@echo "  $(COLOR_CYAN)make status$(COLOR_RESET)        - View deployment summary"

.PHONY: full-deploy
full-deploy: init plan apply inventory ## Full deployment: init + plan + apply + inventory
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) Full deployment complete!$(COLOR_RESET)"
	@$(MAKE) status

.PHONY: ci-plan
ci-plan: init fmt-check validate plan ## CI workflow: init + format check + validate + plan
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) CI plan check complete$(COLOR_RESET)"

.PHONY: ci-apply
ci-apply: init apply-auto inventory ## CI workflow: init + auto-apply + inventory
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) CI deployment complete$(COLOR_RESET)"

.PHONY: ci-destroy
ci-destroy: init destroy-auto ## CI workflow: init + auto-destroy
	@echo "$(COLOR_GREEN)$(SYMBOL_CHECK) CI destruction complete$(COLOR_RESET)"

# ============================================================================
# Version & Info
# ============================================================================

.PHONY: version
version: ## Show Terraform and provider versions
	@echo "$(COLOR_BOLD)Terraform Version:$(COLOR_RESET)"
	@terraform version
	@echo ""
	@echo "$(COLOR_BOLD)Required Providers:$(COLOR_RESET)"
	@terraform providers

.PHONY: info
info: ## Show environment information
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)╔══════════════════════════════════════════════════════════════════╗$(COLOR_RESET)"
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)║              Terraform Environment Information                    ║$(COLOR_RESET)"
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)╚══════════════════════════════════════════════════════════════════╝$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)Terraform:$(COLOR_RESET)       $(TF_VERSION)"
	@echo "$(COLOR_BOLD)Workspace:$(COLOR_RESET)       $(shell terraform workspace show 2>/dev/null || echo 'not initialized')"
	@echo "$(COLOR_BOLD)Parallelism:$(COLOR_RESET)     $(TF_PARALLELISM)"
	@echo "$(COLOR_BOLD)Log Level:$(COLOR_RESET)       $(if $(TF_LOG),$(TF_LOG),none)"
	@echo ""
	@echo "$(COLOR_BOLD)Files:$(COLOR_RESET)"
	@echo "  Secrets:           $(TFVARS_SECRET) $(shell test -f $(TFVARS_SECRET) && echo '[$(COLOR_GREEN)exists$(COLOR_RESET)]' || echo '[$(COLOR_RED)missing$(COLOR_RESET)]')"
	@echo "  State:             $(shell test -f $(STATE_DIR)/terraform.tfstate && echo '[$(COLOR_GREEN)exists$(COLOR_RESET)]' || echo '[$(COLOR_YELLOW)not initialized$(COLOR_RESET)]')"
	@echo "  Lock file:         $(shell test -f .terraform.lock.hcl && echo '[$(COLOR_GREEN)exists$(COLOR_RESET)]' || echo '[$(COLOR_YELLOW)missing$(COLOR_RESET)]')"
	@echo ""
	@echo "$(COLOR_BOLD)Tool Availability:$(COLOR_RESET)"
	@echo "  jq:                $(shell command -v jq >/dev/null 2>&1 && echo '[$(COLOR_GREEN)installed$(COLOR_RESET)]' || echo '[$(COLOR_RED)missing$(COLOR_RESET)]')"
	@echo "  tflint:            $(shell command -v tflint >/dev/null 2>&1 && echo '[$(COLOR_GREEN)installed$(COLOR_RESET)]' || echo '[$(COLOR_YELLOW)not installed$(COLOR_RESET)]')"
	@echo "  tfsec:             $(shell command -v tfsec >/dev/null 2>&1 && echo '[$(COLOR_GREEN)installed$(COLOR_RESET)]' || echo '[$(COLOR_YELLOW)not installed$(COLOR_RESET)]')"
	@echo "  checkov:           $(shell command -v checkov >/dev/null 2>&1 && echo '[$(COLOR_GREEN)installed$(COLOR_RESET)]' || echo '[$(COLOR_YELLOW)not installed$(COLOR_RESET)]')"
	@echo "  terrascan:         $(shell command -v terrascan >/dev/null 2>&1 && echo '[$(COLOR_GREEN)installed$(COLOR_RESET)]' || echo '[$(COLOR_YELLOW)not installed$(COLOR_RESET)]')"
	@echo "  terraform-docs:    $(shell command -v terraform-docs >/dev/null 2>&1 && echo '[$(COLOR_GREEN)installed$(COLOR_RESET)]' || echo '[$(COLOR_YELLOW)not installed$(COLOR_RESET)]')"
	@echo "  infracost:         $(shell command -v infracost >/dev/null 2>&1 && echo '[$(COLOR_GREEN)installed$(COLOR_RESET)]' || echo '[$(COLOR_YELLOW)not installed$(COLOR_RESET)]')"
	@echo "  graphviz (dot):    $(shell command -v dot >/dev/null 2>&1 && echo '[$(COLOR_GREEN)installed$(COLOR_RESET)]' || echo '[$(COLOR_YELLOW)not installed$(COLOR_RESET)]')"
	@echo ""

# ============================================================================
# End of Makefile
# ============================================================================
