# Makefile for CheckMK Agent Deployment
# Usage: make deploy-all, make deploy-lxc, make deploy-host HOST=semaphore

.PHONY: help deploy-all deploy-lxc deploy-vms deploy-host remove-all check-vault

# User configuration (after bootstrap, use maintainer user)
ANSIBLE_USER := maintainer

# Default target
help:
	@echo "CheckMK Agent Deployment Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  deploy-all     - Deploy CheckMK agent to all hosts (LXC + VMs)"
	@echo "  deploy-lxc     - Deploy to LXC containers only"
	@echo "  deploy-vms     - Deploy to VMs only"
	@echo "  deploy-host    - Deploy to specific host (make deploy-host HOST=semaphore)"
	@echo "  remove-all     - Remove CheckMK agent from all hosts"
	@echo "  remove-host    - Remove from specific host (make remove-host HOST=semaphore)"
	@echo "  check-vault    - Verify vault password is configured"
	@echo ""
	@echo "Examples:"
	@echo "  make deploy-all"
	@echo "  make deploy-host HOST=semaphore"
	@echo "  make deploy-lxc"

# Check if vault password is available
check-vault:
	@if [ ! -f ../.vault_pass ] && [ ! -f ~/.vault_password ]; then \
		echo "ERROR: Vault password file not found at ../.vault_pass or ~/.vault_password"; \
		exit 1; \
	fi
	@if [ -f ../.vault_pass ]; then \
		echo "✓ Vault password file found at ../.vault_pass"; \
	else \
		echo "✓ Vault password file found at ~/.vault_password"; \
	fi

# Deploy to all hosts
deploy-all: check-vault
	@echo "Deploying CheckMK agent to ALL hosts..."
	cd .. && ansible-playbook \
		-i inventory/all-hosts.yml \
		playbooks/monitoring/deploy-checkmk-agent.yml

# Deploy to LXC containers only
deploy-lxc: check-vault
	@echo "Deploying CheckMK agent to LXC containers..."
	cd .. && ansible-playbook \
		-i lxc/inventory/hosts.yml \
		playbooks/monitoring/deploy-checkmk-agent.yml

# Deploy to VMs only
deploy-vms: check-vault
	@echo "Deploying CheckMK agent to VMs..."
	cd .. && ansible-playbook \
		-i linux-vms/inventory/hosts.yml \
		playbooks/monitoring/deploy-checkmk-agent.yml

# Deploy to specific host
deploy-host: check-vault
	@if [ -z "$(HOST)" ]; then \
		echo "ERROR: HOST variable not set. Usage: make deploy-host HOST=semaphore"; \
		exit 1; \
	fi
	@echo "Deploying CheckMK agent to $(HOST) as $(ANSIBLE_USER) user..."
	cd .. && ansible-playbook \
		-i inventory/all-hosts.yml \
		playbooks/monitoring/deploy-checkmk-agent.yml \
		--limit $(HOST) \
		-e "ansible_user=$(ANSIBLE_USER)"

# Remove from all hosts
remove-all: check-vault
	@echo "Removing CheckMK agent from ALL hosts..."
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		cd .. && ansible-playbook \
			-i inventory/all-hosts.yml \
			playbooks/monitoring/remove-checkmk-agent.yml; \
	fi

# Remove from specific host
remove-host: check-vault
	@if [ -z "$(HOST)" ]; then \
		echo "ERROR: HOST variable not set. Usage: make remove-host HOST=semaphore"; \
		exit 1; \
	fi
	@echo "Removing CheckMK agent from $(HOST)..."
	cd .. && ansible-playbook \
		-i inventory/all-hosts.yml \
		playbooks/monitoring/remove-checkmk-agent.yml \
		--limit $(HOST)

# Dry-run deployment (check mode)
check: check-vault
	@echo "Running deployment in check mode (dry-run)..."
	cd .. && ansible-playbook \
		-i inventory/all-hosts.yml \
		playbooks/monitoring/deploy-checkmk-agent.yml \
		--check
