.PHONY: setup help talos inventory-graph inventory-list inventory-doctor ping check gather-facts lint lint-strict yamllint syntax-check validate clean update-roles list-hosts vault-encrypt vault-decrypt vault-edit vault-view vault-rekey vault-check collection collection-doc molecule molecule-scenario bootstrap-host configure-host verify-host update-hosts diagnostics restart-docker site deploy-komodo-core install-periphery

# Default target
.DEFAULT_GOAL := help

# User configuration (override via .env.mk or command line)
-include .env.mk

# Color output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Project root
PROJECT_ROOT := $(shell cd .. && pwd)

# Inventory: a dynamic script that reads live Terraform/OpenTofu state via
# `terragrunt state pull` (all projects) and emits hosts by real hostname,
# grouped by Proxmox tags — no generated files, no `make inventory-all` step.
INVENTORY_ALL := inventory/terraform_state_inventory.py

# Vault configuration
VAULT_SHARED := inventory/group_vars/all/vault.yml

# Domain includes (host lifecycle, komodo, collection/molecule). The help awk
# scans $(MAKEFILE_LIST), so included targets appear in `make help` too.
include Makefile.d/hosts.mk
include Makefile.d/collection.mk

##@ General

setup: ## Install pre-commit hooks and development dependencies
	@echo "$(GREEN)Installing pre-commit hooks...$(NC)"
	@cd $(PROJECT_ROOT) && pre-commit install
	@cd $(PROJECT_ROOT) && pre-commit install --hook-type commit-msg
	@echo "$(GREEN)Done. Pre-commit hooks are now active.$(NC)"

help: ## Display this help message
	@echo "$(BLUE)homelab.proxmox — Ansible collection + control Makefile$(NC)"
	@echo ""
	@echo "$(YELLOW)Hosts (LXC + future Linux VMs) are configured by the uniform$(NC)"
	@echo "$(YELLOW)playbooks under playbooks/hosts/ + playbooks/komodo/, driven by$(NC)"
	@echo "$(YELLOW)playbooks/site.yml. Roles are addressable as homelab.proxmox.<role>.$(NC)"
	@echo ""
	@echo "  $(GREEN)Talos cluster:$(NC) deep lifecycle ops live in the talos sub-Makefile"
	@echo "    make -C talos help        (or: make talos T=<target>)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf ""} /^[a-zA-Z_-]+:.*?##/ { printf "  $(GREEN)%-25s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(BLUE)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

talos: ## Run a talos sub-Makefile target (usage: make talos T=deploy-full)
	@test -n "$(T)" || { echo "$(RED)✗ T required: make talos T=<target> (see make -C talos help)$(NC)"; exit 1; }
	@$(MAKE) -C talos $(T) $(ARGS)

##@ Inventory Management

inventory-graph: ## Show the dynamic inventory as a group graph
	@echo "$(BLUE)Resolving dynamic inventory from Terraform state...$(NC)"
	@ansible-inventory -i $(INVENTORY_ALL) --graph
	@echo "$(GREEN)✓ Inventory resolved$(NC)"

inventory-list: ## Dump the full dynamic inventory (hostvars) as JSON
	@ansible-inventory -i $(INVENTORY_ALL) --list

inventory-doctor: ## Validate the dynamic inventory (terragrunt, IPs, SSH keys, name collisions)
	@python3 $(INVENTORY_ALL) --doctor

##@ Testing

ping: ## Test connectivity to all hosts
	@echo "$(BLUE)Pinging all hosts...$(NC)"
	@ansible all -i $(INVENTORY_ALL) -m ping
	@echo "$(GREEN)✓ All hosts reachable$(NC)"

check: ping ## Alias for ping

gather-facts: ## Gather facts from all hosts
	@echo "$(BLUE)Gathering facts...$(NC)"
	@ansible all -i $(INVENTORY_ALL) -m setup

##@ Development

lint: collection ## Run ansible-lint (production profile, same invocation as CI)
	@echo "$(BLUE)Linting playbooks and roles...$(NC)"
	@command -v ansible-lint >/dev/null 2>&1 || \
		(echo "$(YELLOW)⚠ ansible-lint not installed. Install: pip install ansible-lint$(NC)" && exit 1)
	@cd $(PROJECT_ROOT) && ANSIBLE_COLLECTIONS_PATH=$(COLLECTIONS_PATH_FULL) ANSIBLE_ROLES_PATH=ansible/roles \
		ansible-lint -c ansible/.ansible-lint
	@echo "$(GREEN)✓ Lint check passed$(NC)"

lint-strict: collection ## Run ansible-lint with all rules (no skips)
	@echo "$(BLUE)Running strict lint check...$(NC)"
	@cd $(PROJECT_ROOT) && ANSIBLE_COLLECTIONS_PATH=$(COLLECTIONS_PATH_FULL) ANSIBLE_ROLES_PATH=ansible/roles \
		ansible-lint --strict -c ansible/.ansible-lint
	@echo "$(GREEN)✓ Strict lint passed$(NC)"

yamllint: ## Run yamllint on YAML files
	@echo "$(BLUE)Running yamllint...$(NC)"
	@command -v yamllint >/dev/null 2>&1 || \
		(echo "$(YELLOW)⚠ yamllint not installed. Install: pip install yamllint$(NC)" && exit 1)
	@yamllint -c .yamllint .
	@echo "$(GREEN)✓ YAML lint passed$(NC)"

syntax-check: collection ## Check syntax of all playbooks (builds the collection first)
	@echo "$(BLUE)Checking playbook syntax...$(NC)"
	@export ANSIBLE_COLLECTIONS_PATH=$(COLLECTIONS_PATH_FULL); \
	for playbook in playbooks/site.yml playbooks/hosts/*.yml playbooks/komodo/*.yml; do \
		echo "Checking $$playbook..."; \
		ansible-playbook $$playbook --syntax-check -i $(INVENTORY_ALL) || exit 1; \
	done; \
	for playbook in playbooks/talos/*.yml; do \
		echo "Checking $$playbook..."; \
		ansible-playbook $$playbook --syntax-check -i inventory/talos/hosts.yml || exit 1; \
	done
	@echo "$(GREEN)✓ Syntax check passed$(NC)"

validate: lint yamllint syntax-check ## Run the full local gate (lint + yamllint + collection build + syntax-check) — mirrors CI
	@echo "$(GREEN)✓ All checks passed$(NC)"

##@ Maintenance

clean: ## Remove fact cache and any stale generated inventory files
	@echo "$(BLUE)Cleaning cache + legacy generated inventory...$(NC)"
	@rm -rf .ansible .ansible_facts inventory/all-hosts.yml inventory/*-hosts.ini 2>/dev/null || true
	@echo "$(GREEN)✓ Clean complete$(NC)"

update-roles: ## Update role dependencies (if using ansible-galaxy)
	@echo "$(BLUE)Updating role dependencies...$(NC)"
	@ansible-galaxy install -r requirements.yml --force 2>/dev/null || \
		echo "$(YELLOW)No requirements.yml found$(NC)"

##@ Information

list-hosts: ## List all hosts in merged inventory
	@echo "$(BLUE)Hosts in inventory:$(NC)"
	@ansible all -i $(INVENTORY_ALL) --list-hosts

##@ Ansible Vault

vault-encrypt: ## Encrypt shared vault file (usage: make vault-encrypt)
	@echo "$(BLUE)Encrypting shared vault.yml...$(NC)"
	@if [ -f "$(VAULT_SHARED)" ]; then \
		if head -1 $(VAULT_SHARED) | grep -q '$$ANSIBLE_VAULT'; then \
			echo "$(YELLOW)⚠ vault.yml is already encrypted$(NC)"; \
		else \
			ansible-vault encrypt $(VAULT_SHARED) && \
			echo "$(GREEN)✓ vault.yml encrypted$(NC)"; \
		fi; \
	else \
		echo "$(RED)✗ Error: $(VAULT_SHARED) not found$(NC)"; \
		exit 1; \
	fi

vault-decrypt: ## Decrypt shared vault file temporarily (⚠️ re-encrypt before committing!)
	@echo "$(YELLOW)⚠ WARNING: This will decrypt vault.yml$(NC)"
	@echo "$(YELLOW)⚠ Remember to re-encrypt before committing!$(NC)"
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "$(RED)✗ Cancelled$(NC)"; \
		exit 1; \
	fi
	@ansible-vault decrypt $(VAULT_SHARED)
	@echo "$(RED)⚠ vault.yml is now DECRYPTED!$(NC)"
	@echo "$(YELLOW)→ Re-encrypt with: make vault-encrypt$(NC)"

vault-edit: ## Edit shared encrypted vault file (opens editor)
	@echo "$(BLUE)Opening shared vault.yml for editing...$(NC)"
	@ansible-vault edit $(VAULT_SHARED)

vault-view: ## View shared encrypted vault contents (read-only)
	@ansible-vault view $(VAULT_SHARED)

vault-rekey: ## Change shared vault password
	@echo "$(BLUE)Changing vault password...$(NC)"
	@ansible-vault rekey $(VAULT_SHARED)
	@echo "$(GREEN)✓ Vault password changed$(NC)"

vault-check: ## Check if shared vault.yml is encrypted
	@if [ -f "$(VAULT_SHARED)" ]; then \
		if head -1 $(VAULT_SHARED) | grep -q '$$ANSIBLE_VAULT'; then \
			echo "$(GREEN)✓ vault.yml is encrypted$(NC)"; \
		else \
			echo "$(RED)✗ vault.yml is NOT encrypted!$(NC)"; \
			echo "$(YELLOW)→ Encrypt with: make vault-encrypt$(NC)"; \
			exit 1; \
		fi; \
	else \
		echo "$(RED)✗ Error: $(VAULT_SHARED) not found$(NC)"; \
		exit 1; \
	fi
