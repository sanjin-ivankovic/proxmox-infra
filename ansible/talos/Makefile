.PHONY: help inventory generate-configs apply-configs bootstrap configure-tiers verify diagnostics upgrade upgrade-k8s reboot shutdown startup health-check etcd-backup restricted-configs reset ping-host check-talosctl accept-host-keys

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
TERRAFORM_TALOS_DIR := $(PROJECT_ROOT)/terraform/talos
ANSIBLE_DIR := $(PROJECT_ROOT)/ansible

# Ansible configuration (point to parent ansible.cfg)
ANSIBLE_CONFIG := ../ansible.cfg
export ANSIBLE_CONFIG

# HashiCorp Vault for the secrets lookups
# (inventory/talos/group_vars/all/secrets.yml). On macOS a forked ansible
# worker crashes in hvac's proxy lookup ("A worker was found in a dead state")
# unless fork safety is off.
VAULT_ADDR ?= https://vault.example.com:8200
export VAULT_ADDR
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY := YES

# Inventory file paths (relative to talos/ directory). The static Talos
# inventory now lives under the central ansible/inventory/ tree.
INVENTORY_HOSTS := ../inventory/talos/hosts.yml
INVENTORY_ARGS := -i $(INVENTORY_HOSTS)

# Config directory
CONFIGS_DIR := configs

# Playbook paths (relative to talos/ directory). The old single main.yml is
# replaced by three intent orchestrators (deploy/operate/lifecycle).
PLAYBOOK_DEPLOY := ../playbooks/talos/deploy.yml
PLAYBOOK_OPERATE := ../playbooks/talos/operate.yml
PLAYBOOK_LIFECYCLE := ../playbooks/talos/lifecycle.yml
PLAYBOOK_GENERATE_CONFIGS := ../playbooks/talos/01-generate-configs.yml
PLAYBOOK_APPLY_CONFIGS := ../playbooks/talos/02-apply-configs.yml
PLAYBOOK_BOOTSTRAP := ../playbooks/talos/03-bootstrap.yml
PLAYBOOK_CONFIGURE_TIERS := ../playbooks/talos/04-configure-workload-tiers.yml
PLAYBOOK_VERIFY := ../playbooks/talos/05-verify.yml
PLAYBOOK_DIAGNOSTICS := ../playbooks/talos/06-diagnostics.yml
PLAYBOOK_UPGRADE := ../playbooks/talos/07-upgrade-talos.yml
PLAYBOOK_UPGRADE_K8S := ../playbooks/talos/08-upgrade-k8s.yml
PLAYBOOK_REBOOT := ../playbooks/talos/09-reboot.yml
PLAYBOOK_SHUTDOWN := ../playbooks/talos/10-shutdown.yml
PLAYBOOK_STARTUP := ../playbooks/talos/11-startup.yml
PLAYBOOK_HEALTH_CHECK := ../playbooks/talos/12-health-check.yml
PLAYBOOK_RESET := ../playbooks/talos/13-reset.yml

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

inventory: ## Show the static Talos inventory (group graph)
	@ansible-inventory $(INVENTORY_ARGS) --graph

##@ Cluster Deployment

deploy-full: check-talosctl ## Full deployment via deploy.yml (generate→apply→bootstrap→tiers→verify)
	@echo "$(BLUE)🚀 Full Talos cluster deployment (via deploy.yml)...$(NC)"
	@echo "$(YELLOW)⚠️  Runs: generate-configs → apply-configs → bootstrap → configure-tiers → verify$(NC)"
	@read -p "Continue? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	@ansible-playbook $(PLAYBOOK_DEPLOY) $(INVENTORY_ARGS) --tags deployment $(ARGS)
	@echo "$(GREEN)✓ Deployment complete!$(NC)"

run-tags: check-talosctl ## Run an orchestrator with custom tags (usage: make run-tags PB=operate TAGS="diagnostics")
	@if [ -z "$(TAGS)" ]; then \
		echo "$(RED)✗ Error: TAGS parameter required$(NC)"; \
		echo "$(YELLOW)Usage: make run-tags PB=deploy|operate|lifecycle TAGS=\"...\"$(NC)"; \
		echo "$(YELLOW)Tag groups: deployment (deploy.yml), operations (operate.yml), lifecycle (lifecycle.yml)$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Running $(PB:=deploy).yml with tags: $(TAGS)$(NC)"
	@ansible-playbook ../playbooks/talos/$(PB:=deploy).yml $(INVENTORY_ARGS) --tags "$(TAGS)" $(ARGS)

list-tags: ## List available tags across the deploy/operate/lifecycle orchestrators
	@for pb in deploy operate lifecycle; do \
		echo "$(BLUE)$$pb.yml tags:$(NC)"; \
		ansible-playbook ../playbooks/talos/$$pb.yml $(INVENTORY_ARGS) --list-tags 2>/dev/null | grep -A 100 "play #" || true; \
	done

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
		echo "$(YELLOW)→ Generate it first: cd terraform/talos && make apply$(NC)"; \
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

configure-tiers: ## Configure production workload scheduling (labels, PriorityClasses)
	@echo "$(BLUE)🏗️  Configuring production workload scheduling...$(NC)"
	@if [ ! -f "$(CONFIGS_DIR)/kubeconfig" ]; then \
		echo "$(RED)✗ kubeconfig not found. Run: make bootstrap$(NC)"; \
		exit 1; \
	fi
	@ansible-playbook $(PLAYBOOK_CONFIGURE_TIERS) $(INVENTORY_ARGS) $(ARGS)
	@echo "$(GREEN)✓ Workload scheduling configured!$(NC)"
	@echo "$(YELLOW)→ All workers: node-role.kubernetes.io/worker (equal, no taints)$(NC)"

##@ Cluster Management

verify: check-talosctl inventory ## Verify Talos cluster health
	@echo "$(BLUE)🔍 Verifying cluster health...$(NC)"
	@ansible-playbook $(PLAYBOOK_VERIFY) $(INVENTORY_ARGS) $(ARGS)

diagnostics: check-talosctl inventory ## Collect Talos cluster diagnostics
	@echo "$(BLUE)🔬 Collecting cluster diagnostics...$(NC)"
	@ansible-playbook $(PLAYBOOK_DIAGNOSTICS) $(INVENTORY_ARGS) $(ARGS)

upgrade: check-talosctl inventory ## Upgrade Talos OS version (rolling, one node at a time)
	@echo "$(BLUE)Upgrading Talos OS...$(NC)"
	@echo "$(YELLOW)This performs rolling OS upgrades$(NC)"
	@default_version=$$(grep '^talos_version:' ../inventory/talos/group_vars/all/vars.yml | awk '{print $$2}' | tr -d '"'); \
	read -p "Upgrade to Talos version [$$default_version] (Enter = default): " version; \
	version=$${version:-$$default_version}; \
	if ! echo "$$version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$$'; then \
		echo "$(RED)✗ '$$version' is not a version (vX.Y.Z); press Enter for the default$(NC)"; \
		exit 1; \
	fi; \
	ansible-playbook $(PLAYBOOK_UPGRADE) $(INVENTORY_ARGS) -e "talos_version=$$version" $(ARGS)

upgrade-k8s: check-talosctl inventory ## Upgrade Kubernetes version (control plane + kubelets)
	@echo "$(BLUE)Upgrading Kubernetes...$(NC)"
	@echo "$(YELLOW)Runs upgrade-k8s against the first control plane node$(NC)"
	@default_version=$$(grep '^kubernetes_version:' ../inventory/talos/group_vars/all/vars.yml | awk '{print $$2}' | tr -d '"'); \
	read -p "Upgrade to Kubernetes version [$$default_version] (Enter = default): " version; \
	version=$${version:-$$default_version}; \
	if ! echo "$$version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$$'; then \
		echo "$(RED)✗ '$$version' is not a version (vX.Y.Z); press Enter for the default$(NC)"; \
		exit 1; \
	fi; \
	ansible-playbook $(PLAYBOOK_UPGRADE_K8S) $(INVENTORY_ARGS) -e "kubernetes_version=$$version" $(ARGS)

health-check: check-talosctl inventory ## Run comprehensive health check
	@echo "$(BLUE)🩺 Running cluster health check...$(NC)"
	@ansible-playbook $(PLAYBOOK_HEALTH_CHECK) $(INVENTORY_ARGS) $(ARGS)

etcd-backup: check-talosctl inventory ## Snapshot etcd into configs/backups, keep 14 (Semaphore runs it nightly)
	@ansible-playbook ../playbooks/talos/etcd-backup.yml $(INVENTORY_ARGS) $(ARGS)

# The certificate expires after a year (--crt-ttl); regenerate, then replace
# etcd_backup_talosconfig in kv/proxmox-infra/talos.
restricted-configs: check-talosctl ## Issue the os:etcd:backup talosconfig for Vault
	@out=$(CONFIGS_DIR)/talosconfig-etcd-backup; \
	talosctl --talosconfig $(CONFIGS_DIR)/talosconfig -e 10.140.0.41 -n 10.140.0.41 \
		config new $$out --roles os:etcd:backup --crt-ttl 8760h && chmod 600 $$out && \
	echo "$(GREEN)✓ $$out$(NC)"
	@echo "$(YELLOW)Next: vault kv patch -mount=kv proxmox-infra/talos etcd_backup_talosconfig=@$$out$(NC)"

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
