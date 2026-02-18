.PHONY: help inventory generate-configs apply-configs bootstrap apply-rbac configure-tiers verify diagnostics upgrade reboot shutdown startup health-check reset ping-host check-talosctl accept-host-keys vault-encrypt vault-decrypt vault-edit vault-view vault-rekey vault-check

# Default target
.DEFAULT_GOAL := help

# Color output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Project root (relative to talos/ directory)
PROJECT_ROOT := $(shell cd ../.. && pwd)
TERRAFORM_TALOS_DIR := $(PROJECT_ROOT)/terraform/talos-vms
ANSIBLE_DIR := $(PROJECT_ROOT)/ansible

# Ansible configuration (point to parent ansible.cfg)
ANSIBLE_CONFIG := ../ansible.cfg
export ANSIBLE_CONFIG

# Inventory file paths (relative to talos/ directory)
INVENTORY_HOSTS := inventory/hosts.yml
INVENTORY_ARGS := -i $(INVENTORY_HOSTS)

# Config directory
CONFIGS_DIR := configs

# Playbook paths (relative to talos/ directory)
PLAYBOOK_MAIN := ../playbooks/talos/main.yml
PLAYBOOK_GENERATE_CONFIGS := ../playbooks/talos/01-generate-configs.yml
PLAYBOOK_APPLY_CONFIGS := ../playbooks/talos/02-apply-configs.yml
PLAYBOOK_BOOTSTRAP := ../playbooks/talos/03-bootstrap.yml
PLAYBOOK_APPLY_RBAC := ../playbooks/talos/04-apply-rbac.yml
PLAYBOOK_CONFIGURE_TIERS := ../playbooks/talos/05-configure-workload-tiers.yml
PLAYBOOK_VERIFY := ../playbooks/talos/06-verify.yml
PLAYBOOK_DIAGNOSTICS := ../playbooks/talos/07-diagnostics.yml
PLAYBOOK_UPGRADE := ../playbooks/talos/08-upgrade.yml
PLAYBOOK_REBOOT := ../playbooks/talos/09-reboot.yml
PLAYBOOK_SHUTDOWN := ../playbooks/talos/10-shutdown.yml
PLAYBOOK_STARTUP := ../playbooks/talos/11-startup.yml
PLAYBOOK_HEALTH_CHECK := ../playbooks/talos/12-health-check.yml
PLAYBOOK_RESET := ../playbooks/talos/13-reset.yml

# Vault configuration
VAULT_PASSWORD_FILE := ../.vault_pass
VAULT_FILE := inventory/group_vars/all/vault.yml

##@ General

help: ## Display this help message
	@echo "$(BLUE)Talos Cluster Makefile - Immutable Kubernetes Management$(NC)"
	@echo ""
	@echo "$(YELLOW)Usage:$(NC)"
	@echo "  cd talos && make <target>"
	@echo "  OR"
	@echo "  make -C talos <target>"
	@echo ""
	@echo "$(YELLOW)⚠️  Talos uses API-based management (no SSH)$(NC)"
	@echo "$(YELLOW)⚠️  Requires talosctl CLI: brew install siderolabs/tap/talosctl$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Targets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(GREEN)%-25s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(BLUE)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Prerequisites

check-talosctl: ## Verify talosctl is installed
	@command -v talosctl >/dev/null 2>&1 || \
		(echo "$(RED)✗ talosctl not found$(NC)" && \
		 echo "$(YELLOW)→ Install: brew install siderolabs/tap/talosctl$(NC)" && \
		 echo "$(YELLOW)→ Or: curl -sL https://talos.dev/install | sh$(NC)" && \
		 exit 1)
	@echo "$(GREEN)✓ talosctl found: $$(talosctl version --client --short)$(NC)"

check-terraform: ## Verify Terraform state exists
	@if [ -d "$(TERRAFORM_TALOS_DIR)" ] && ([ -f "$(TERRAFORM_TALOS_DIR)/generated/state/terraform.tfstate" ] || [ -f "$(TERRAFORM_TALOS_DIR)/terraform.tfstate" ]); then \
		echo "$(GREEN)✓ Terraform state found$(NC)"; \
	else \
		echo "$(YELLOW)⚠ Terraform state not found - VMs may not exist yet$(NC)"; \
	fi

##@ Inventory Management

inventory: ## Sync Talos cluster inventory from Terraform
	@make -C .. inventory-all

##@ Cluster Deployment

deploy-full: check-talosctl ## Full deployment using main.yml with deployment tag (offline, no inventory sync)
	@echo "$(BLUE)🚀 Full Talos cluster deployment (via main.yml)...$(NC)"
	@echo "$(YELLOW)⚠️  Runs: generate-configs → apply-configs → bootstrap → apply-rbac → configure-tiers → verify$(NC)"
	@read -p "Continue? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	@ansible-playbook $(PLAYBOOK_MAIN) $(INVENTORY_ARGS) --tags deployment $(ARGS)
	@echo "$(GREEN)✓ Deployment complete!$(NC)"

run-tags: check-talosctl inventory ## Run main.yml with custom tags (usage: make run-tags TAGS="generate-configs,verify")
	@if [ -z "$(TAGS)" ]; then \
		echo "$(RED)✗ Error: TAGS parameter required$(NC)"; \
		echo "$(YELLOW)Usage: make run-tags TAGS=\"generate-configs,apply-configs\"$(NC)"; \
		echo "$(YELLOW)Tag groups: deployment, operations, lifecycle$(NC)"; \
		echo "$(YELLOW)Individual: generate-configs, apply-configs, bootstrap, apply-rbac, configure-tiers, verify, diagnostics, upgrade, reboot, shutdown, startup, health-check, reset$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Running main.yml with tags: $(TAGS)$(NC)"
	@ansible-playbook $(PLAYBOOK_MAIN) $(INVENTORY_ARGS) --tags "$(TAGS)" $(ARGS)

list-tags: ## List all available tags in main.yml playbook
	@echo "$(BLUE)Available tags in main.yml:$(NC)"
	@ansible-playbook $(PLAYBOOK_MAIN) $(INVENTORY_ARGS) --list-tags 2>/dev/null | grep -A 100 "play #" || echo "$(YELLOW)Ensure you're in ansible/talos/ directory$(NC)"

generate-configs: check-talosctl ## Generate Talos machine configurations
	@echo "$(BLUE)🔧 Generating Talos machine configs...$(NC)"
	@echo "$(YELLOW)⚠️  This creates machine configs in $(CONFIGS_DIR)/$(NC)"
	@ansible-playbook $(PLAYBOOK_GENERATE_CONFIGS) $(INVENTORY_ARGS) $(ARGS)
	@echo "$(GREEN)✓ Configs generated in $(CONFIGS_DIR)/$(NC)"

apply-configs: check-talosctl ## Apply Talos configs to nodes via API (syncs inventory first)
	@echo "$(BLUE)📤 Applying configs to Talos nodes...$(NC)"
	@echo "$(YELLOW)⚠️  This pushes configs via talosctl API$(NC)"
	@if [ ! -f "$(CONFIGS_DIR)/talosconfig" ]; then \
		echo "$(RED)✗ talosconfig not found. Run: make generate-configs$(NC)"; \
		exit 1; \
	fi
	@if [ ! -f "$(INVENTORY_HOSTS)" ]; then \
		echo "$(YELLOW)⚠️  Inventory not found, syncing from Terraform...$(NC)"; \
		make inventory; \
	fi
	@ansible-playbook $(PLAYBOOK_APPLY_CONFIGS) $(INVENTORY_ARGS) $(ARGS)

apply-configs-offline: check-talosctl ## Apply Talos configs without syncing inventory (use when GitLab unreachable)
	@echo "$(BLUE)📤 Applying configs to Talos nodes (offline mode)...$(NC)"
	@echo "$(YELLOW)⚠️  Skipping inventory sync - using existing inventory$(NC)"
	@if [ ! -f "$(CONFIGS_DIR)/talosconfig" ]; then \
		echo "$(RED)✗ talosconfig not found. Run: make generate-configs$(NC)"; \
		exit 1; \
	fi
	@if [ ! -f "$(INVENTORY_HOSTS)" ]; then \
		echo "$(RED)✗ Inventory not found at $(INVENTORY_HOSTS)$(NC)"; \
		echo "$(YELLOW)→ Generate it first: cd terraform/talos-vms && make apply$(NC)"; \
		exit 1; \
	fi
	@ansible-playbook $(PLAYBOOK_APPLY_CONFIGS) $(INVENTORY_ARGS) $(ARGS)

bootstrap: apply-configs ## Bootstrap Talos Kubernetes cluster (applies configs first)
	@echo "$(BLUE)🚀 Bootstrapping Talos cluster...$(NC)"
	@echo "$(YELLOW)⚠️  This initializes etcd and Kubernetes$(NC)"
	@ansible-playbook $(PLAYBOOK_BOOTSTRAP) $(INVENTORY_ARGS) $(ARGS)
	@echo "$(GREEN)✓ Cluster bootstrapped!$(NC)"
	@echo "$(YELLOW)→ kubeconfig saved to: $(CONFIGS_DIR)/kubeconfig$(NC)"
	@echo "$(YELLOW)→ Set: export KUBECONFIG=$(shell pwd)/$(CONFIGS_DIR)/kubeconfig$(NC)"

bootstrap-only: check-talosctl ## Bootstrap cluster WITHOUT re-applying configs (use when configs already applied)
	@echo "$(BLUE)🚀 Bootstrapping Talos cluster (skipping config reapplication)...$(NC)"
	@echo "$(YELLOW)⚠️  This initializes etcd and Kubernetes$(NC)"
	@ansible-playbook $(PLAYBOOK_BOOTSTRAP) $(INVENTORY_ARGS) $(ARGS)
	@echo "$(GREEN)✓ Cluster bootstrapped!$(NC)"
	@echo "$(YELLOW)→ kubeconfig saved to: $(CONFIGS_DIR)/kubeconfig$(NC)"
	@echo "$(YELLOW)→ Set: export KUBECONFIG=$(shell pwd)/$(CONFIGS_DIR)/kubeconfig$(NC)"

deploy: bootstrap ## Alias for bootstrap (full deployment)

apply-rbac: ## Apply RBAC patches to cluster (fixes node permission errors)
	@echo "$(BLUE)🔐 Applying RBAC patches...$(NC)"
	@if [ ! -f "$(CONFIGS_DIR)/kubeconfig" ]; then \
		echo "$(RED)✗ kubeconfig not found. Run: make bootstrap$(NC)"; \
		exit 1; \
	fi
	@ansible-playbook $(PLAYBOOK_APPLY_RBAC) $(INVENTORY_ARGS) $(ARGS)
	@echo "$(GREEN)✓ RBAC patches applied!$(NC)"

configure-tiers: ## Configure production workload tiers (labels, taints, PriorityClasses)
	@echo "$(BLUE)🏗️  Configuring production workload tiers...$(NC)"
	@if [ ! -f "$(CONFIGS_DIR)/kubeconfig" ]; then \
		echo "$(RED)✗ kubeconfig not found. Run: make bootstrap$(NC)"; \
		exit 1; \
	fi
	@ansible-playbook $(PLAYBOOK_CONFIGURE_TIERS) $(INVENTORY_ARGS) $(ARGS)
	@echo "$(GREEN)✓ Workload tiers configured!$(NC)"
	@echo "$(YELLOW)→ Infrastructure tier: control-plane nodes$(NC)"
	@echo "$(YELLOW)→ Stateful tier: talos-worker-1$(NC)"
	@echo "$(YELLOW)→ Application tier: talos-worker-2,3$(NC)"

##@ Cluster Management

verify: check-talosctl inventory ## Verify Talos cluster health
	@echo "$(BLUE)🔍 Verifying cluster health...$(NC)"
	@ansible-playbook $(PLAYBOOK_VERIFY) $(INVENTORY_ARGS) $(ARGS)

diagnostics: check-talosctl inventory ## Collect Talos cluster diagnostics
	@echo "$(BLUE)🔬 Collecting cluster diagnostics...$(NC)"
	@ansible-playbook $(PLAYBOOK_DIAGNOSTICS) $(INVENTORY_ARGS) $(ARGS)

upgrade: check-talosctl inventory ## Upgrade Talos OS version
	@echo "$(BLUE)⬆️  Upgrading Talos cluster...$(NC)"
	@echo "$(YELLOW)⚠️  This performs rolling OS upgrades$(NC)"
	@read -p "Upgrade to version (e.g., v1.9.3): " version; \
	if [ -z "$$version" ]; then \
		echo "$(RED)✗ Version required$(NC)"; \
		exit 1; \
	fi; \
	ansible-playbook $(PLAYBOOK_UPGRADE) $(INVENTORY_ARGS) -e "talos_version=$$version" $(ARGS)

health-check: check-talosctl inventory ## Run comprehensive health check
	@echo "$(BLUE)🩺 Running cluster health check...$(NC)"
	@ansible-playbook $(PLAYBOOK_HEALTH_CHECK) $(INVENTORY_ARGS) $(ARGS)

##@ Cluster Operations

reboot: check-talosctl inventory ## Rolling reboot of Talos cluster
	@echo "$(BLUE)🔄 Rebooting cluster nodes...$(NC)"
	@echo "$(YELLOW)⚠️  This performs a rolling reboot via talosctl$(NC)"
	@read -p "Continue? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	@ansible-playbook $(PLAYBOOK_REBOOT) $(INVENTORY_ARGS) $(ARGS)

shutdown: check-talosctl inventory ## Gracefully shutdown Talos cluster
	@echo "$(BLUE)🛑 Shutting down Talos cluster...$(NC)"
	@echo "$(RED)⚠️  This will SHUT DOWN all cluster nodes!$(NC)"
	@echo "$(YELLOW)⚠️  Use this before Proxmox host maintenance$(NC)"
	@read -p "Are you sure? Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ] || exit 1
	@ansible-playbook $(PLAYBOOK_SHUTDOWN) $(INVENTORY_ARGS) $(ARGS)

startup: inventory ## Start up Talos cluster after shutdown
	@echo "$(BLUE)🚀 Starting up Talos cluster...$(NC)"
	@echo "$(YELLOW)⚠️  VMs will be started via Proxmox$(NC)"
	@ansible-playbook $(PLAYBOOK_STARTUP) $(INVENTORY_ARGS) $(ARGS)

reset: check-talosctl inventory ## DESTRUCTIVE: Reset cluster to maintenance mode
	@echo "$(RED)☠️  DESTRUCTIVE OPERATION: Reset Talos Cluster$(NC)"
	@echo "$(RED)⚠️  This will COMPLETELY WIPE the cluster!$(NC)"
	@echo "$(YELLOW)⚠️  All Kubernetes resources will be destroyed$(NC)"
	@echo "$(YELLOW)⚠️  All etcd data will be erased$(NC)"
	@echo "$(YELLOW)⚠️  Nodes will revert to maintenance mode$(NC)"
	@echo ""
	@echo "$(YELLOW)After reset, you must:$(NC)"
	@echo "  1. Re-apply configs: make apply-configs"
	@echo "  2. Re-bootstrap: make bootstrap"
	@echo ""
	@read -p "Type 'yes' to proceed with CLUSTER RESET: " confirm && [ "$$confirm" = "yes" ] || exit 1
	@ansible-playbook $(PLAYBOOK_RESET) $(INVENTORY_ARGS) $(ARGS)

##@ Testing

ping-host: inventory ## Test connectivity to specific host (usage: make ping-host HOST=talos-cp-1)
	@if [ -z "$(HOST)" ]; then \
		echo "$(RED)✗ Error: HOST parameter required$(NC)"; \
		echo "$(YELLOW)Usage: make ping-host HOST=talos-cp-1$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Pinging $(HOST)...$(NC)"
	@ansible $(HOST) -i $(INVENTORY_HOSTS) -m ping

test-talosctl: check-talosctl inventory ## Test talosctl connectivity to first node
	@echo "$(BLUE)Testing talosctl API connectivity...$(NC)"
	@if [ -f "$(CONFIGS_DIR)/talosconfig" ]; then \
		export TALOSCONFIG=$(shell pwd)/$(CONFIGS_DIR)/talosconfig; \
		NODE_IP=$$(ansible-inventory -i $(INVENTORY_HOSTS) --list | grep -oE '"ansible_host":\s*"[0-9.]+' | head -1 | grep -oE '[0-9.]+$$'); \
		talosctl --nodes $$NODE_IP version 2>/dev/null && \
		echo "$(GREEN)✓ talosctl API connectivity successful$(NC)" || \
		echo "$(RED)✗ talosctl API connectivity failed$(NC)"; \
	else \
		echo "$(YELLOW)⚠ talosconfig not found. Run: make generate-configs$(NC)"; \
	fi

##@ Configuration Management

kubeconfig: check-talosctl ## Retrieve kubeconfig from cluster
	@echo "$(BLUE)📥 Retrieving kubeconfig...$(NC)"
	@if [ ! -f "$(CONFIGS_DIR)/talosconfig" ]; then \
		echo "$(RED)✗ talosconfig not found. Run: make generate-configs$(NC)"; \
		exit 1; \
	fi
	@export TALOSCONFIG=$(shell pwd)/$(CONFIGS_DIR)/talosconfig; \
	NODE_IP=$$(ansible-inventory -i $(INVENTORY_HOSTS) --list | grep -oE '"ansible_host":\s*"[0-9.]+' | head -1 | grep -oE '[0-9.]+$$'); \
	talosctl --nodes $$NODE_IP kubeconfig --force $(CONFIGS_DIR)/kubeconfig && \
	echo "$(GREEN)✓ kubeconfig saved to: $(CONFIGS_DIR)/kubeconfig$(NC)" && \
	echo "$(YELLOW)→ Set: export KUBECONFIG=$(shell pwd)/$(CONFIGS_DIR)/kubeconfig$(NC)"

dashboard: check-talosctl ## Open Talos dashboard (TUI)
	@echo "$(BLUE)🖥️  Opening Talos dashboard...$(NC)"
	@if [ ! -f "$(CONFIGS_DIR)/talosconfig" ]; then \
		echo "$(RED)✗ talosconfig not found. Run: make generate-configs$(NC)"; \
		exit 1; \
	fi
	@export TALOSCONFIG=$(shell pwd)/$(CONFIGS_DIR)/talosconfig; \
	NODE_IP=$$(ansible-inventory -i $(INVENTORY_HOSTS) --list | grep -oE '"ansible_host":\s*"[0-9.]+' | head -1 | grep -oE '[0-9.]+$$'); \
	talosctl --nodes $$NODE_IP dashboard

##@ SSH Key Management (Not Applicable to Talos)

accept-host-keys: ## Not applicable - Talos uses API, not SSH
	@echo "$(YELLOW)⚠️  Talos does not use SSH$(NC)"
	@echo "$(BLUE)ℹ️  Talos uses certificate-based API authentication$(NC)"
	@echo "$(GREEN)✓ No SSH keys to manage$(NC)"

remove-host-keys: ## Not applicable - Talos uses API, not SSH
	@echo "$(YELLOW)⚠️  Talos does not use SSH$(NC)"
	@echo "$(BLUE)ℹ️  Talos uses certificate-based API authentication$(NC)"
	@echo "$(GREEN)✓ No SSH keys to manage$(NC)"

##@ Ansible Vault

vault-encrypt: ## Encrypt talos vault file
	@echo "$(BLUE)Encrypting talos vault.yml...$(NC)"
	@if [ -f "$(VAULT_FILE)" ]; then \
		if head -1 $(VAULT_FILE) | grep -q '$$ANSIBLE_VAULT'; then \
			echo "$(YELLOW)⚠ vault.yml is already encrypted$(NC)"; \
		else \
			if [ -f "$(VAULT_PASSWORD_FILE)" ]; then \
				ansible-vault encrypt $(VAULT_FILE) --vault-password-file $(VAULT_PASSWORD_FILE) --encrypt-vault-id default && \
				echo "$(GREEN)✓ talos vault.yml encrypted$(NC)"; \
			else \
				ansible-vault encrypt $(VAULT_FILE) --encrypt-vault-id default && \
				echo "$(GREEN)✓ talos vault.yml encrypted$(NC)"; \
			fi; \
		fi; \
	else \
		echo "$(RED)✗ Error: $(VAULT_FILE) not found$(NC)"; \
		exit 1; \
	fi

vault-decrypt: ## Decrypt talos vault file temporarily (⚠️ re-encrypt before committing!)
	@echo "$(YELLOW)⚠ WARNING: This will decrypt talos vault.yml$(NC)"
	@echo "$(YELLOW)⚠ Remember to re-encrypt before committing!$(NC)"
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "$(RED)✗ Cancelled$(NC)"; \
		exit 1; \
	fi
	@if [ -f "$(VAULT_PASSWORD_FILE)" ]; then \
		ansible-vault decrypt $(VAULT_FILE) --vault-password-file $(VAULT_PASSWORD_FILE); \
	else \
		ansible-vault decrypt $(VAULT_FILE); \
	fi
	@echo "$(RED)⚠ talos vault.yml is now DECRYPTED!$(NC)"
	@echo "$(YELLOW)→ Re-encrypt with: make vault-encrypt$(NC)"

vault-edit: ## Edit talos encrypted vault file (opens editor)
	@echo "$(BLUE)Opening talos vault.yml for editing...$(NC)"
	@if [ -f "$(VAULT_PASSWORD_FILE)" ]; then \
		ansible-vault edit $(VAULT_FILE) --vault-password-file $(VAULT_PASSWORD_FILE); \
	else \
		ansible-vault edit $(VAULT_FILE); \
	fi

vault-view: ## View talos encrypted vault contents (read-only)
	@if [ -f "$(VAULT_PASSWORD_FILE)" ]; then \
		ansible-vault view $(VAULT_FILE) --vault-password-file $(VAULT_PASSWORD_FILE); \
	else \
		ansible-vault view $(VAULT_FILE); \
	fi

vault-rekey: ## Change talos vault password
	@echo "$(BLUE)Changing talos vault password...$(NC)"
	@if [ -f "$(VAULT_PASSWORD_FILE)" ]; then \
		ansible-vault rekey $(VAULT_FILE) --vault-password-file $(VAULT_PASSWORD_FILE); \
	else \
		ansible-vault rekey $(VAULT_FILE); \
	fi
	@echo "$(GREEN)✓ Talos vault password changed$(NC)"

vault-check: ## Check if talos vault.yml is encrypted
	@if [ -f "$(VAULT_FILE)" ]; then \
		if head -1 $(VAULT_FILE) | grep -q '$$ANSIBLE_VAULT'; then \
			echo "$(GREEN)✓ talos vault.yml is encrypted$(NC)"; \
		else \
			echo "$(RED)✗ talos vault.yml is NOT encrypted!$(NC)"; \
			echo "$(YELLOW)→ Encrypt with: make vault-encrypt$(NC)"; \
			exit 1; \
		fi; \
	else \
		echo "$(RED)✗ Error: $(VAULT_FILE) not found$(NC)"; \
		exit 1; \
	fi

##@ Information

info: ## Display Talos cluster information
	@echo "$(BLUE)Talos Cluster Information$(NC)"
	@echo ""
	@echo "  $(GREEN)Config Directory:$(NC) $(CONFIGS_DIR)/"
	@echo "  $(GREEN)Inventory:$(NC) $(INVENTORY_HOSTS)"
	@echo ""
	@if [ -f "$(CONFIGS_DIR)/talosconfig" ]; then \
		echo "  $(GREEN)✓$(NC) talosconfig exists"; \
	else \
		echo "  $(YELLOW)⚠$(NC) talosconfig missing (run: make generate-configs)"; \
	fi
	@if [ -f "$(CONFIGS_DIR)/kubeconfig" ]; then \
		echo "  $(GREEN)✓$(NC) kubeconfig exists"; \
	else \
		echo "  $(YELLOW)⚠$(NC) kubeconfig missing (run: make bootstrap)"; \
	fi
	@echo ""
	@make check-talosctl 2>/dev/null || echo "  $(RED)✗$(NC) talosctl not installed"
