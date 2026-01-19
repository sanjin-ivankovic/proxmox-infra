.PHONY: help inventory bootstrap deploy update verify diagnostics restart reboot shutdown system-update ping-host accept-host-keys remove-host-keys vault-encrypt vault-decrypt vault-edit vault-view vault-rekey vault-check

# Default target
.DEFAULT_GOAL := help

# Color output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Project root (relative to k3s/ directory)
PROJECT_ROOT := $(shell cd ../.. && pwd)
TERRAFORM_LINUX_VMS_DIR := $(PROJECT_ROOT)/terraform/linux-vms
ANSIBLE_DIR := $(PROJECT_ROOT)/ansible

# Ansible user configuration
ANSIBLE_USER := maintainer

# Ansible configuration (point to parent ansible.cfg)
ANSIBLE_CONFIG := ../ansible.cfg
export ANSIBLE_CONFIG

# Inventory file paths (relative to k3s/ directory)
INVENTORY_YAML := inventory/hosts.yml

# Playbook paths (relative to k3s/ directory)
PLAYBOOK_BOOTSTRAP := ../playbooks/k3s/bootstrap-cluster.yml
PLAYBOOK_UPDATE := ../playbooks/k3s/update-cluster.yml
PLAYBOOK_VERIFY := ../playbooks/k3s/verify-cluster.yml
PLAYBOOK_DIAGNOSTICS := ../playbooks/k3s/diagnostics.yml
PLAYBOOK_RESTART := ../playbooks/k3s/restart-k3s.yml
PLAYBOOK_REBOOT := ../playbooks/k3s/reboot-cluster.yml
PLAYBOOK_SHUTDOWN := ../playbooks/k3s/shutdown-cluster.yml
PLAYBOOK_SYSTEM_UPDATE := ../playbooks/k3s/system-update.yml

# Vault configuration
VAULT_PASSWORD_FILE := ../.vault_pass
VAULT_FILE := inventory/group_vars/all/vault.yml

##@ General

help: ## Display this help message
	@echo "$(BLUE)K3s Cluster Makefile - Kubernetes Cluster Management$(NC)"
	@echo ""
	@echo "$(YELLOW)Usage:$(NC)"
	@echo "  cd k3s && make <target>"
	@echo "  OR"
	@echo "  make -C k3s <target>"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Targets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(GREEN)%-25s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(BLUE)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Inventory Management

inventory: ## Sync K3s cluster inventory from Terraform
	@make -C .. inventory-all

##@ Cluster Management

bootstrap: inventory ## Bootstrap K3s cluster (initial deployment)
	@echo "$(BLUE)🚀 Bootstrapping K3s cluster...$(NC)"
	@echo "$(YELLOW)⚠️  This will deploy K3s on all nodes$(NC)"
	@ansible-playbook $(PLAYBOOK_BOOTSTRAP) -i $(INVENTORY_YAML) $(ARGS)

deploy: bootstrap ## Alias for bootstrap

update: inventory ## Update K3s cluster (rolling update)
	@echo "$(BLUE)⬆️  Updating K3s cluster...$(NC)"
	@echo "$(YELLOW)⚠️  This performs a rolling update (one node at a time)$(NC)"
	@read -p "Update to version (default: check defaults/main.yml): " version; \
	if [ -n "$$version" ]; then \
		ansible-playbook $(PLAYBOOK_UPDATE) -i $(INVENTORY_YAML) -e "ansible_user=$(ANSIBLE_USER) k3s_version=$$version" $(ARGS); \
	else \
		ansible-playbook $(PLAYBOOK_UPDATE) -i $(INVENTORY_YAML) -e "ansible_user=$(ANSIBLE_USER)" $(ARGS); \
	fi

verify: inventory ## Verify K3s cluster health
	@echo "$(BLUE)🔍 Verifying cluster health...$(NC)"
	@ansible-playbook $(PLAYBOOK_VERIFY) -i $(INVENTORY_YAML) -e "ansible_user=$(ANSIBLE_USER)" $(ARGS)

diagnostics: inventory ## Collect K3s cluster diagnostics
	@echo "$(BLUE)🔬 Collecting cluster diagnostics...$(NC)"
	@ansible-playbook $(PLAYBOOK_DIAGNOSTICS) -i $(INVENTORY_YAML) -e "ansible_user=$(ANSIBLE_USER)" $(ARGS)

restart: inventory ## Restart K3s services (no reboot)
	@echo "$(BLUE)🔄 Restarting K3s services...$(NC)"
	@echo "$(YELLOW)⚠️  This will restart K3s on all nodes (masters first, then workers)$(NC)"
	@read -p "Continue? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	@ansible-playbook $(PLAYBOOK_RESTART) -i $(INVENTORY_YAML) -e "ansible_user=$(ANSIBLE_USER)" $(ARGS)

reboot: inventory ## Rolling reboot of K3s cluster nodes
	@echo "$(BLUE)🔄 Rebooting cluster nodes...$(NC)"
	@echo "$(YELLOW)⚠️  This will perform a rolling reboot of all nodes$(NC)"
	@echo "$(YELLOW)⚠️  Workers will be drained before reboot, masters reboot in reverse order$(NC)"
	@read -p "Continue? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	@ansible-playbook $(PLAYBOOK_REBOOT) -i $(INVENTORY_YAML) -e "ansible_user=$(ANSIBLE_USER)" $(ARGS)

shutdown: inventory ## Gracefully shutdown K3s cluster
	@echo "$(BLUE)🛑 Shutting down K3s cluster...$(NC)"
	@echo "$(RED)⚠️  This will SHUT DOWN all cluster nodes!$(NC)"
	@echo "$(YELLOW)⚠️  Use this before Proxmox host maintenance$(NC)"
	@read -p "Are you sure? Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ] || exit 1
	@ansible-playbook $(PLAYBOOK_SHUTDOWN) -i $(INVENTORY_YAML) -e "ansible_user=$(ANSIBLE_USER)" $(ARGS)

system-update: inventory ## Update system packages on K3s nodes
	@echo "$(BLUE)🔧 Updating system packages on K3s nodes...$(NC)"
	@ansible-playbook $(PLAYBOOK_SYSTEM_UPDATE) -i $(INVENTORY_YAML) -e "ansible_user=$(ANSIBLE_USER)" $(ARGS)

##@ Testing

ping-host: inventory ## Ping specific host (usage: make ping-host HOST=k3s-master-1)
	@if [ -z "$(HOST)" ]; then \
		echo "$(RED)✗ Error: HOST parameter required$(NC)"; \
		echo "$(YELLOW)Usage: make ping-host HOST=k3s-master-1$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Pinging $(HOST)...$(NC)"
	@ansible $(HOST) -i $(INVENTORY_YAML) -m ping

##@ SSH Key Management

accept-host-keys: inventory ## Accept SSH host keys for K3s hosts (removes old keys, adds new ones)
	@echo "$(BLUE)Updating SSH host keys in known_hosts for K3s hosts...$(NC)"
	@updated=0; \
	removed=0; \
	if [ -f "$(INVENTORY_YAML)" ]; then \
		echo "$(BLUE)Processing $(INVENTORY_YAML)...$(NC)"; \
		ansible-inventory -i $(INVENTORY_YAML) --list 2>/dev/null | \
		grep -oE '"ansible_host":\s*"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' | \
		sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)".*/\1/' | \
		sort -u | \
		while read ip; do \
			if [ -n "$$ip" ] && [ "$$ip" != "N/A" ] && [ "$$ip" != "null" ]; then \
				removed_entry=0; \
				if grep -qE "(^| )$$ip[ ,]|$$ip$$" ~/.ssh/known_hosts 2>/dev/null; then \
					ssh-keygen -R $$ip -f ~/.ssh/known_hosts >/dev/null 2>&1 && removed_entry=1; \
				fi; \
				if [ $$removed_entry -eq 1 ]; then \
					echo "$(YELLOW)↻$(NC) Removed old host key for $$ip"; \
					removed=$$((removed + 1)); \
				fi; \
				if ssh-keyscan -H $$ip 2>/dev/null >> ~/.ssh/known_hosts; then \
					echo "$(GREEN)✓$(NC) Added host key for $$ip"; \
					updated=$$((updated + 1)); \
				else \
					echo "$(RED)✗$(NC) Failed to retrieve host key for $$ip"; \
				fi; \
			fi; \
		done; \
	fi; \
	if [ $$updated -eq 0 ]; then \
		echo "$(YELLOW)⚠ No host keys updated$(NC)"; \
	else \
		echo "$(GREEN)✓ Updated $$updated host key(s)$$([ $$removed -gt 0 ] && echo " (removed $$removed old entries)")$(NC)"; \
	fi

remove-host-keys: inventory ## Remove SSH host keys for K3s hosts in inventory (manual cleanup)
	@echo "$(YELLOW)⚠ Removing SSH host keys from known_hosts for K3s hosts...$(NC)"
	@removed=0; \
	if [ -f "$(INVENTORY_YAML)" ]; then \
		echo "$(BLUE)Processing $(INVENTORY_YAML)...$(NC)"; \
		ansible-inventory -i $(INVENTORY_YAML) --list 2>/dev/null | \
		grep -oE '"ansible_host":\s*"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' | \
		sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)".*/\1/' | \
		sort -u | \
		while read ip; do \
			if [ -n "$$ip" ] && [ "$$ip" != "N/A" ] && [ "$$ip" != "null" ]; then \
				if ssh-keygen -R $$ip -f ~/.ssh/known_hosts >/dev/null 2>&1; then \
					echo "$(GREEN)✓$(NC) Removed host key for $$ip"; \
					removed=$$((removed + 1)); \
				fi; \
			fi; \
		done; \
	fi; \
	if [ $$removed -eq 0 ]; then \
		echo "$(YELLOW)⚠ No host keys removed$(NC)"; \
	else \
		echo "$(GREEN)✓ Removed $$removed host key entry/entries$(NC)"; \
	fi

##@ Ansible Vault

vault-encrypt: ## Encrypt k3s vault file
	@echo "$(BLUE)Encrypting k3s vault.yml...$(NC)"
	@if [ -f "$(VAULT_FILE)" ]; then \
		if head -1 $(VAULT_FILE) | grep -q '$$ANSIBLE_VAULT'; then \
			echo "$(YELLOW)⚠ vault.yml is already encrypted$(NC)"; \
		else \
			if [ -f "$(VAULT_PASSWORD_FILE)" ]; then \
				ansible-vault encrypt $(VAULT_FILE) --vault-password-file $(VAULT_PASSWORD_FILE) && \
				echo "$(GREEN)✓ k3s vault.yml encrypted$(NC)"; \
			else \
				ansible-vault encrypt $(VAULT_FILE) && \
				echo "$(GREEN)✓ k3s vault.yml encrypted$(NC)"; \
			fi; \
		fi; \
	else \
		echo "$(RED)✗ Error: $(VAULT_FILE) not found$(NC)"; \
		exit 1; \
	fi

vault-decrypt: ## Decrypt k3s vault file temporarily (⚠️ re-encrypt before committing!)
	@echo "$(YELLOW)⚠ WARNING: This will decrypt k3s vault.yml$(NC)"
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
	@echo "$(RED)⚠ k3s vault.yml is now DECRYPTED!$(NC)"
	@echo "$(YELLOW)→ Re-encrypt with: make vault-encrypt$(NC)"

vault-edit: ## Edit k3s encrypted vault file (opens editor)
	@echo "$(BLUE)Opening k3s vault.yml for editing...$(NC)"
	@if [ -f "$(VAULT_PASSWORD_FILE)" ]; then \
		ansible-vault edit $(VAULT_FILE) --vault-password-file $(VAULT_PASSWORD_FILE); \
	else \
		ansible-vault edit $(VAULT_FILE); \
	fi

vault-view: ## View k3s encrypted vault contents (read-only)
	@if [ -f "$(VAULT_PASSWORD_FILE)" ]; then \
		ansible-vault view $(VAULT_FILE) --vault-password-file $(VAULT_PASSWORD_FILE); \
	else \
		ansible-vault view $(VAULT_FILE); \
	fi

vault-rekey: ## Change k3s vault password
	@echo "$(BLUE)Changing k3s vault password...$(NC)"
	@if [ -f "$(VAULT_PASSWORD_FILE)" ]; then \
		ansible-vault rekey $(VAULT_FILE) --vault-password-file $(VAULT_PASSWORD_FILE); \
	else \
		ansible-vault rekey $(VAULT_FILE); \
	fi
	@echo "$(GREEN)✓ K3s vault password changed$(NC)"

vault-check: ## Check if k3s vault.yml is encrypted
	@if [ -f "$(VAULT_FILE)" ]; then \
		if head -1 $(VAULT_FILE) | grep -q '$$ANSIBLE_VAULT'; then \
			echo "$(GREEN)✓ k3s vault.yml is encrypted$(NC)"; \
		else \
			echo "$(RED)✗ k3s vault.yml is NOT encrypted!$(NC)"; \
			echo "$(YELLOW)→ Encrypt with: make vault-encrypt$(NC)"; \
			exit 1; \
		fi; \
	else \
		echo "$(RED)✗ Error: $(VAULT_FILE) not found$(NC)"; \
		exit 1; \
	fi

