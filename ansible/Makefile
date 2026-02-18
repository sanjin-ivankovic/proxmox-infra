.PHONY: help inventory-all ping check gather-facts lint lint-strict yamllint syntax-check clean update-roles list-hosts vault-encrypt vault-decrypt vault-edit vault-view vault-rekey vault-check check-terraform

# Default target
.DEFAULT_GOAL := help

# Color output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Project root
PROJECT_ROOT := $(shell cd .. && pwd)
TERRAFORM_LXC_DIR := $(PROJECT_ROOT)/terraform/lxc
TERRAFORM_LINUX_VMS_DIR := $(PROJECT_ROOT)/terraform/linux-vms
TERRAFORM_TALOS_VMS_DIR := $(PROJECT_ROOT)/terraform/talos-vms
TERRAFORM_WINDOWS_VMS_DIR := $(PROJECT_ROOT)/terraform/windows-vms

# Inventory file paths
INVENTORY_LXC := lxc/inventory/hosts.yml
INVENTORY_LINUX_VMS := linux-vms/inventory/hosts.yml
INVENTORY_TALOS := talos/inventory/hosts.yml
INVENTORY_WINDOWS_VMS := windows-vms/inventory/hosts.yml
INVENTORY_ALL := inventory/all-hosts.yml

# Vault configuration
VAULT_SHARED := inventory/group_vars/all/vault.yml

##@ General

help: ## Display this help message
	@echo "$(BLUE)Ansible Makefile - Proxmox Infrastructure Management$(NC)"
	@echo ""
	@echo "$(YELLOW)This Makefile contains shared commands for all projects.$(NC)"
	@echo "$(YELLOW)For project-specific commands, use the project Makefiles:$(NC)"
	@echo ""
	@echo "  $(GREEN)LXC Containers:$(NC)"
	@echo "    cd lxc && make help"
	@echo "    make -C lxc <target>"
	@echo ""
	@echo "  $(GREEN)Talos Cluster:$(NC)"
	@echo "    cd talos && make help"
	@echo "    make -C talos <target>"
	@echo ""
	@echo "  $(GREEN)Linux VMs:$(NC)"
	@echo "    cd linux-vms && make help"
	@echo "    make -C linux-vms <target>"
	@echo ""
	@echo "$(BLUE)Shared Commands:$(NC)"
	@awk 'BEGIN {FS = ":.*##"; printf ""} /^[a-zA-Z_-]+:.*?##/ { printf "  $(GREEN)%-25s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(BLUE)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Inventory Management

inventory-all: ## Generate inventories via terraform_inventory.py (HTTP backend compatible)
	@echo "$(BLUE)Generating inventories from Terraform (HTTP backend compatible)...$(NC)"
	@command -v python3 >/dev/null 2>&1 || \
		(echo "$(RED)✗ python3 not found. Please install Python 3.$(NC)" && exit 1)
	@python3 inventory/terraform_inventory.py
	@echo "$(GREEN)✓ Inventories generated$(NC)"

check-terraform: ## Verify Terraform outputs are available
	@echo "$(BLUE)Checking Terraform states...$(NC)"
	@failed=0; \
	for dir in $(TERRAFORM_LXC_DIR) $(TERRAFORM_LINUX_VMS_DIR) $(TERRAFORM_TALOS_VMS_DIR) $(TERRAFORM_WINDOWS_VMS_DIR); do \
		if [ -d "$$dir" ] && ([ -f "$$dir/generated/state/terraform.tfstate" ] || [ -f "$$dir/terraform.tfstate" ]); then \
			echo "$(GREEN)✓$(NC) $$(basename $$dir) state found"; \
		else \
			echo "$(YELLOW)⚠$(NC) $$(basename $$dir) state not found (skipping)"; \
			failed=$$((failed + 1)); \
		fi; \
	done; \
	if [ $$failed -eq 4 ]; then \
		echo "$(RED)✗ No Terraform states found$(NC)"; \
		exit 1; \
	fi

##@ Testing

ping: inventory-all ## Test connectivity to all hosts
	@echo "$(BLUE)Pinging all hosts...$(NC)"
	@ansible all -i $(INVENTORY_ALL) -m ping
	@echo "$(GREEN)✓ All hosts reachable$(NC)"

check: ping ## Alias for ping

gather-facts: inventory-all ## Gather facts from all hosts
	@echo "$(BLUE)Gathering facts...$(NC)"
	@ansible all -i $(INVENTORY_ALL) -m setup

##@ Development

lint: ## Run ansible-lint on playbooks and roles (production profile)
	@echo "$(BLUE)Linting playbooks and roles...$(NC)"
	@command -v ansible-lint >/dev/null 2>&1 || \
		(echo "$(YELLOW)⚠ ansible-lint not installed. Install: pip install ansible-lint$(NC)" && exit 1)
	@ANSIBLE_INVENTORY=/dev/null ansible-lint playbooks/ roles/
	@echo "$(GREEN)✓ Lint check passed$(NC)"

lint-strict: ## Run ansible-lint with all rules (no skips)
	@echo "$(BLUE)Running strict lint check...$(NC)"
	@ansible-lint --strict playbooks/ roles/
	@echo "$(GREEN)✓ Strict lint passed$(NC)"

yamllint: ## Run yamllint on YAML files
	@echo "$(BLUE)Running yamllint...$(NC)"
	@command -v yamllint >/dev/null 2>&1 || \
		(echo "$(YELLOW)⚠ yamllint not installed. Install: pip install yamllint$(NC)" && exit 1)
	@yamllint -c .yamllint .
	@echo "$(GREEN)✓ YAML lint passed$(NC)"

syntax-check: inventory-all ## Check playbook syntax for all playbooks
	@echo "$(BLUE)Checking playbook syntax...$(NC)"
	@for playbook in playbooks/lxc/*.yml; do \
		echo "Checking $$playbook..."; \
		ansible-playbook $$playbook --syntax-check -i $(INVENTORY_LXC) || exit 1; \
	done
	@for playbook in playbooks/talos/*.yml; do \
		echo "Checking $$playbook..."; \
		ansible-playbook $$playbook --syntax-check -i $(INVENTORY_TALOS) || exit 1; \
	done
	@for playbook in playbooks/linux-vms/*.yml; do \
		echo "Checking $$playbook..."; \
		ansible-playbook $$playbook --syntax-check -i $(INVENTORY_ALL) || exit 1; \
	done
	@echo "$(GREEN)✓ Syntax check passed$(NC)"

##@ Maintenance

clean: ## Remove generated files and cache
	@echo "$(BLUE)Cleaning generated files...$(NC)"
	@rm -rf .ansible .ansible_facts inventory/*-hosts.yml inventory/*-hosts.ini inventory/all-hosts.yml lxc/inventory/*.yml talos/inventory/*.yml linux-vms/inventory/*.yml windows-vms/inventory/*.yml 2>/dev/null || true
	@echo "$(GREEN)✓ Clean complete$(NC)"

update-roles: ## Update role dependencies (if using ansible-galaxy)
	@echo "$(BLUE)Updating role dependencies...$(NC)"
	@ansible-galaxy install -r requirements.yml --force 2>/dev/null || \
		echo "$(YELLOW)No requirements.yml found$(NC)"

##@ Information

list-hosts: inventory-all ## List all hosts in merged inventory
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
