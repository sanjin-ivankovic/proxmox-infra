.PHONY: help inventory bootstrap-host configure-host ping-host accept-host-keys remove-host-keys

# Default target
.DEFAULT_GOAL := help

# Color output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Project root (relative to linux-vms/ directory)
PROJECT_ROOT := $(shell cd ../.. && pwd)
TERRAFORM_LINUX_VMS_DIR := $(PROJECT_ROOT)/terraform/linux-vms
ANSIBLE_DIR := $(PROJECT_ROOT)/ansible

# Ansible user configuration
ANSIBLE_USER := maintainer
ANSIBLE_ROOT_USER := root

# Ansible configuration (point to parent ansible.cfg)
ANSIBLE_CONFIG := ../ansible.cfg
export ANSIBLE_CONFIG

# Inventory file paths (relative to linux-vms/ directory)
INVENTORY_YAML := inventory/hosts.yml

# Playbook paths (relative to linux-vms/ directory)
PLAYBOOK_BOOTSTRAP := ../playbooks/linux-vms/bootstrap.yml
PLAYBOOK_CONFIGURE := ../playbooks/linux-vms/configure.yml

##@ General

help: ## Display this help message
	@echo "$(BLUE)Linux VMs Makefile - Proxmox Linux VMs Management$(NC)"
	@echo ""
	@echo "$(YELLOW)Usage:$(NC)"
	@echo "  cd linux-vms && make <target>"
	@echo "  OR"
	@echo "  make -C linux-vms <target>"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Targets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(GREEN)%-25s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(BLUE)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Inventory Management

inventory: ## Sync Linux VMs inventory from Terraform
	@make -C .. inventory-all

##@ Bootstrap & Configuration

bootstrap-host: inventory ## [RECOMMENDED] Bootstrap specific Linux VM (usage: make bootstrap-host HOST=pihole-1)
	@if [ -z "$(HOST)" ]; then \
		echo "$(RED)✗ Error: HOST parameter required$(NC)"; \
		echo "$(YELLOW)Usage: make bootstrap-host HOST=pihole-1$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)⚠ BOOTSTRAP MODE - Connecting to $(HOST) as root$(NC)"
	@echo "$(BLUE)Running bootstrap playbook on $(HOST)...$(NC)"
	@ansible-playbook $(PLAYBOOK_BOOTSTRAP) -i $(INVENTORY_YAML) --limit $(HOST) -e "ansible_user=$(ANSIBLE_ROOT_USER)"
	@echo "$(GREEN)✓ Bootstrap complete for $(HOST)!$(NC)"
	@echo "$(YELLOW)→ Run 'make configure-host HOST=$(HOST)' for configuration$(NC)"

configure-host: inventory ## [RECOMMENDED] Configure specific Linux VM (usage: make configure-host HOST=pihole-1)
	@if [ -z "$(HOST)" ]; then \
		echo "$(RED)✗ Error: HOST parameter required$(NC)"; \
		echo "$(YELLOW)Usage: make configure-host HOST=pihole-1$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Configuring $(HOST) as $(ANSIBLE_USER) user (root login disabled after bootstrap)...$(NC)"
	@ansible-playbook $(PLAYBOOK_CONFIGURE) -i $(INVENTORY_YAML) --limit $(HOST) -e "ansible_user=$(ANSIBLE_USER)"
	@echo "$(GREEN)✓ Configuration complete for $(HOST)!$(NC)"

##@ Testing

ping-host: inventory ## Ping specific host (usage: make ping-host HOST=pihole-1)
	@if [ -z "$(HOST)" ]; then \
		echo "$(RED)✗ Error: HOST parameter required$(NC)"; \
		echo "$(YELLOW)Usage: make ping-host HOST=pihole-1$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Pinging $(HOST)...$(NC)"
	@ansible $(HOST) -i $(INVENTORY_YAML) -m ping

##@ SSH Key Management

accept-host-keys: inventory ## Accept SSH host keys for Linux VMs (removes old keys, adds new ones)
	@echo "$(BLUE)Updating SSH host keys in known_hosts for Linux VMs...$(NC)"
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

remove-host-keys: inventory ## Remove SSH host keys for Linux VMs in inventory (manual cleanup)
	@echo "$(YELLOW)⚠ Removing SSH host keys from known_hosts for Linux VMs...$(NC)"
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

