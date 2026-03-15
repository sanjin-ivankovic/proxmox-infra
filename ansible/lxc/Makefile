.PHONY: help inventory bootstrap bootstrap-host configure configure-host configure-dns configure-except configure-system configure-docker update-packages install-docker harden-ssh ping-host dry-run-host dry-run list-tasks list-tags show-vars accept-host-keys remove-host-keys

# Default target
.DEFAULT_GOAL := help

# Color output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Project root (relative to lxc/ directory)
PROJECT_ROOT := $(shell cd ../.. && pwd)
TERRAFORM_LXC_DIR := $(PROJECT_ROOT)/terraform/lxc
ANSIBLE_DIR := $(PROJECT_ROOT)/ansible

# User configuration (override via ../.env.mk or command line: make target ANSIBLE_USER=myuser)
-include ../.env.mk
ANSIBLE_USER ?= maintainer
ANSIBLE_ROOT_USER ?= root

# Ansible configuration (point to parent ansible.cfg)
ANSIBLE_CONFIG := ../ansible.cfg
export ANSIBLE_CONFIG

# Inventory file paths (relative to lxc/ directory)
INVENTORY_YAML := inventory/hosts.yml
INVENTORY_ALL := ../inventory/all-hosts.yml

# Auto-select inventory: prefer all-hosts.yml if available
INVENTORY := $(shell if [ -f "$(INVENTORY_ALL)" ]; then echo "$(INVENTORY_ALL)"; else echo "$(INVENTORY_YAML)"; fi)

# Playbook paths (relative to lxc/ directory)
PLAYBOOK_BOOTSTRAP := ../playbooks/lxc/01-bootstrap.yml
PLAYBOOK_CONFIGURE := ../playbooks/lxc/02-configure.yml
PLAYBOOK_VERIFY := ../playbooks/lxc/03-verify.yml
PLAYBOOK_SYSTEM_UPDATE := ../playbooks/lxc/04-system-update.yml
PLAYBOOK_DIAGNOSTICS := ../playbooks/lxc/05-diagnostics.yml
PLAYBOOK_RESTART := ../playbooks/lxc/06-restart-services.yml
PLAYBOOK_REBOOT := ../playbooks/lxc/07-reboot.yml
PLAYBOOK_SHUTDOWN := ../playbooks/lxc/08-shutdown.yml

##@ General

help: ## Display this help message
	@echo "$(BLUE)LXC Containers Makefile - Proxmox Infrastructure Management$(NC)"
	@echo ""
	@echo "$(YELLOW)Usage:$(NC)"
	@echo "  cd lxc && make <target>"
	@echo "  OR"
	@echo "  make -C lxc <target>"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Targets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(GREEN)%-25s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(BLUE)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Inventory Management

inventory: ## Sync LXC inventory from Terraform
	@make -C .. inventory-all

##@ Bootstrap & Configuration

bootstrap: inventory ## [NOT RECOMMENDED] Bootstrap all LXC hosts - prefer bootstrap-host
	@echo "$(YELLOW)⚠ WARNING: This will bootstrap ALL LXC hosts!$(NC)"
	@echo "$(YELLOW)⚠ Recommended: Use 'make bootstrap-host HOST=<hostname>' instead$(NC)"
	@read -p "Continue with all hosts? [y/N] " -n 1 -r; \
	echo; \
	if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "$(RED)✗ Cancelled$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)⚠ BOOTSTRAP MODE - Connecting as root to create user$(NC)"
	@echo "$(BLUE)Running bootstrap playbook...$(NC)"
	@ansible-playbook $(PLAYBOOK_BOOTSTRAP) -i $(INVENTORY_YAML) --limit lxc_containers
	@echo "$(GREEN)✓ Bootstrap complete! User created and SSH hardened.$(NC)"
	@echo "$(YELLOW)→ Run 'make configure-host HOST=<hostname>' for each host$(NC)"

bootstrap-host: inventory ## [RECOMMENDED] Bootstrap specific host (usage: make bootstrap-host HOST=semaphore)
	@if [ -z "$(HOST)" ]; then \
		echo "$(RED)✗ Error: HOST parameter required$(NC)"; \
		echo "$(YELLOW)Usage: make bootstrap-host HOST=semaphore$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)⚠ BOOTSTRAP MODE - Connecting to $(HOST) as root$(NC)"
	@echo "$(BLUE)Running bootstrap playbook on $(HOST)...$(NC)"
	@ansible-playbook $(PLAYBOOK_BOOTSTRAP) -i $(INVENTORY_YAML) --limit $(HOST)
	@echo "$(GREEN)✓ Bootstrap complete for $(HOST)!$(NC)"
	@echo "$(YELLOW)→ Run 'make configure-host HOST=$(HOST)' for Docker setup$(NC)"

configure: inventory ## [NOT RECOMMENDED] Configure all hosts - prefer configure-host
	@echo "$(YELLOW)⚠ WARNING: This will configure ALL LXC hosts!$(NC)"
	@echo "$(YELLOW)⚠ Recommended: Use 'make configure-host HOST=<hostname>' instead$(NC)"
	@read -p "Continue with all hosts? [y/N] " -n 1 -r; \
	echo; \
	if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "$(RED)✗ Cancelled$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Running configuration playbook as $(ANSIBLE_USER) user (root login disabled after bootstrap)...$(NC)"
	@ansible-playbook $(PLAYBOOK_CONFIGURE) -i $(INVENTORY)
	@echo "$(GREEN)✓ Configuration complete!$(NC)"

configure-host: inventory ## [RECOMMENDED] Configure specific host (usage: make configure-host HOST=dns-1)
	@if [ -z "$(HOST)" ]; then \
		echo "$(RED)✗ Error: HOST parameter required$(NC)"; \
		echo "$(YELLOW)Usage: make configure-host HOST=dns-1$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Configuring $(HOST) as $(ANSIBLE_USER) user (root login disabled after bootstrap)...$(NC)"
	@ansible-playbook $(PLAYBOOK_CONFIGURE) -i $(INVENTORY) --limit $(HOST)
	@echo "$(GREEN)✓ Configuration complete for $(HOST)!$(NC)"

configure-dns: inventory ## Configure only DNS servers (dns-*)
	@echo "$(BLUE)Configuring DNS servers as $(ANSIBLE_USER) user...$(NC)"
	@ansible-playbook $(PLAYBOOK_CONFIGURE) -i $(INVENTORY) --limit 'dns*'
	@echo "$(GREEN)✓ DNS servers configured!$(NC)"

configure-except: inventory ## Configure all except specific host (usage: make configure-except HOST=semaphore)
	@if [ -z "$(HOST)" ]; then \
		echo "$(RED)✗ Error: HOST parameter required$(NC)"; \
		echo "$(YELLOW)Usage: make configure-except HOST=semaphore$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Configuring all hosts except $(HOST) as $(ANSIBLE_USER) user...$(NC)"
	@ansible-playbook $(PLAYBOOK_CONFIGURE) -i $(INVENTORY) --limit '!$(HOST)'
	@echo "$(GREEN)✓ Configuration complete!$(NC)"

##@ Selective Configuration

configure-system: inventory ## Run only system role
	@echo "$(BLUE)Running system role only...$(NC)"
	@ansible-playbook $(PLAYBOOK_CONFIGURE) -i $(INVENTORY) --tags common_system
	@echo "$(GREEN)✓ System configuration complete$(NC)"

configure-docker: inventory ## Run only docker role
	@echo "$(BLUE)Running docker role only...$(NC)"
	@ansible-playbook $(PLAYBOOK_CONFIGURE) -i $(INVENTORY) --tags common_docker
	@echo "$(GREEN)✓ Docker configuration complete$(NC)"

update-packages: inventory ## Update system packages only
	@echo "$(BLUE)Updating system packages...$(NC)"
	@ansible-playbook $(PLAYBOOK_CONFIGURE) -i $(INVENTORY) --tags update
	@echo "$(GREEN)✓ Packages updated$(NC)"

install-docker: inventory ## Install/update Docker only
	@echo "$(BLUE)Installing Docker...$(NC)"
	@ansible-playbook $(PLAYBOOK_CONFIGURE) -i $(INVENTORY) --tags common_docker,install
	@echo "$(GREEN)✓ Docker installation complete$(NC)"

harden-ssh: inventory ## Harden SSH configuration (bootstrap only)
	@echo "$(YELLOW)⚠ This will disable root SSH access!$(NC)"
	@echo "$(BLUE)Running SSH hardening...$(NC)"
	@ansible-playbook $(PLAYBOOK_BOOTSTRAP) -i $(INVENTORY_YAML) --tags common_ssh
	@echo "$(GREEN)✓ SSH hardened$(NC)"

##@ Operations

system-update: inventory ## Update system packages on all LXC hosts
	@echo "$(BLUE)Updating system packages on all hosts...$(NC)"
	@ansible-playbook $(PLAYBOOK_SYSTEM_UPDATE) -i $(INVENTORY)
	@echo "$(GREEN)✓ Update complete$(NC)"

system-update-host: inventory ## Update system packages on specific host (usage: make system-update-host HOST=name)
	@if [ -z "$(HOST)" ]; then \
		echo "$(RED)✗ Error: HOST parameter required$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Updating system packages on $(HOST)...$(NC)"
	@ansible-playbook $(PLAYBOOK_SYSTEM_UPDATE) -i $(INVENTORY) --limit $(HOST)
	@echo "$(GREEN)✓ Update complete for $(HOST)$(NC)"

verify: inventory ## Verify health of all LXC hosts
	@echo "$(BLUE)Verifying health of all hosts...$(NC)"
	@ansible-playbook $(PLAYBOOK_VERIFY) -i $(INVENTORY)

verify-host: inventory ## Verify health of specific host (usage: make verify-host HOST=name)
	@if [ -z "$(HOST)" ]; then \
		echo "$(RED)✗ Error: HOST parameter required$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Verifying health of $(HOST)...$(NC)"
	@ansible-playbook $(PLAYBOOK_VERIFY) -i $(INVENTORY) --limit $(HOST)

reboot: inventory ## Rolling reboot of LXC hosts
	@echo "$(YELLOW)⚠ WARNING: This will reboot all LXC hosts one by one!$(NC)"
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "$(RED)✗ Cancelled$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Starting rolling reboot...$(NC)"
	@ansible-playbook $(PLAYBOOK_REBOOT) -i $(INVENTORY)

reboot-host: inventory ## Reboot specific host (usage: make reboot-host HOST=name)
	@if [ -z "$(HOST)" ]; then \
		echo "$(RED)✗ Error: HOST parameter required$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Rebooting $(HOST)...$(NC)"
	@ansible-playbook $(PLAYBOOK_REBOOT) -i $(INVENTORY) --limit $(HOST)

shutdown: inventory ## Gracefully shutdown all LXC hosts
	@echo "$(RED)⚠ WARNING: This will SHUTDOWN all LXC hosts!$(NC)"
	@read -p "Are you sure? Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ] || exit 1
	@echo "$(BLUE)Shutting down all hosts...$(NC)"
	@ansible-playbook $(PLAYBOOK_SHUTDOWN) -i $(INVENTORY)

shutdown-host: inventory ## Shutdown specific host (usage: make shutdown-host HOST=name)
	@if [ -z "$(HOST)" ]; then \
		echo "$(RED)✗ Error: HOST parameter required$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Shutting down $(HOST)...$(NC)"
	@ansible-playbook $(PLAYBOOK_SHUTDOWN) -i $(INVENTORY) --limit $(HOST)

restart-services: inventory ## Restart critical services on LXC hosts
	@echo "$(BLUE)Restarting services...$(NC)"
	@ansible-playbook $(PLAYBOOK_RESTART) -i $(INVENTORY)
	@echo "$(GREEN)✓ Services restarted$(NC)"

restart-services-host: inventory ## Restart services on specific host (usage: make restart-services-host HOST=name)
	@if [ -z "$(HOST)" ]; then \
		echo "$(RED)✗ Error: HOST parameter required$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Restarting services on $(HOST)...$(NC)"
	@ansible-playbook $(PLAYBOOK_RESTART) -i $(INVENTORY) --limit $(HOST)
	@echo "$(GREEN)✓ Services restarted for $(HOST)$(NC)"

diagnostics: inventory ## Collect diagnostics from LXC hosts
	@echo "$(BLUE)Collecting diagnostics...$(NC)"
	@ansible-playbook $(PLAYBOOK_DIAGNOSTICS) -i $(INVENTORY)

diagnostics-host: inventory ## Collect diagnostics from specific host (usage: make diagnostics-host HOST=name)
	@if [ -z "$(HOST)" ]; then \
		echo "$(RED)✗ Error: HOST parameter required$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Collecting diagnostics from $(HOST)...$(NC)"
	@ansible-playbook $(PLAYBOOK_DIAGNOSTICS) -i $(INVENTORY) --limit $(HOST)

##@ Testing & Information

ping-host: inventory ## Ping specific host (usage: make ping-host HOST=dns-1)
	@if [ -z "$(HOST)" ]; then \
		echo "$(RED)✗ Error: HOST parameter required$(NC)"; \
		echo "$(YELLOW)Usage: make ping-host HOST=dns-1$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Pinging $(HOST)...$(NC)"
	@ansible $(HOST) -i $(INVENTORY) -m ping

dry-run-host: inventory ## Dry-run on specific host (usage: make dry-run-host HOST=dns-1)
	@if [ -z "$(HOST)" ]; then \
		echo "$(RED)✗ Error: HOST parameter required$(NC)"; \
		echo "$(YELLOW)Usage: make dry-run-host HOST=dns-1$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Running dry-run on $(HOST)...$(NC)"
	@ansible-playbook $(PLAYBOOK_CONFIGURE) -i $(INVENTORY) --limit $(HOST) --check --diff

dry-run: inventory ## Run configuration in check mode (no changes)
	@echo "$(BLUE)Running dry-run (check mode)...$(NC)"
	@ansible-playbook $(PLAYBOOK_CONFIGURE) -i $(INVENTORY) --check --diff

list-tasks: inventory ## List all tasks in configure playbook
	@echo "$(BLUE)Tasks in configure.yml:$(NC)"
	@ansible-playbook $(PLAYBOOK_CONFIGURE) -i $(INVENTORY) --list-tasks

list-tags: inventory ## List all available tags
	@echo "$(BLUE)Tags in bootstrap.yml:$(NC)"
	@ansible-playbook $(PLAYBOOK_BOOTSTRAP) -i $(INVENTORY_YAML) --list-tags
	@echo ""
	@echo "$(BLUE)Tags in configure.yml:$(NC)"
	@ansible-playbook $(PLAYBOOK_CONFIGURE) -i $(INVENTORY) --list-tags

show-vars: inventory ## Show variables for a host (usage: make show-vars HOST=dns-1)
	@if [ -z "$(HOST)" ]; then \
		echo "$(RED)✗ Error: HOST parameter required$(NC)"; \
		echo "$(YELLOW)Usage: make show-vars HOST=dns-1$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Variables for $(HOST):$(NC)"
	@ansible $(HOST) -i $(INVENTORY) -m debug -a "var=hostvars[inventory_hostname]"

##@ SSH Key Management

accept-host-keys: inventory ## Accept SSH host keys for LXC hosts (removes old keys, adds new ones)
	@echo "$(BLUE)Updating SSH host keys in known_hosts for LXC hosts...$(NC)"
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

remove-host-keys: inventory ## Remove SSH host keys for LXC hosts in inventory (manual cleanup)
	@echo "$(YELLOW)⚠ Removing SSH host keys from known_hosts for LXC hosts...$(NC)"
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
