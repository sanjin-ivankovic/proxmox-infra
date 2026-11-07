# ============================================================================
# Proxmox Infrastructure Root Makefile
# ============================================================================
#
# Entry point for common development tasks. For infrastructure-specific
# commands, use the sub-project Makefiles:
#
#   cd ansible/       && make help
#   cd terraform/lxc/ && make help
#
# ============================================================================

.PHONY: setup help diagrams check-ips komodo-deploy komodo-sync komodo-run

.DEFAULT_GOAL := help

# Color output
GREEN := \033[0;32m
BLUE  := \033[0;34m
NC    := \033[0m

help: ## Show this help message
	@echo "$(BLUE)Proxmox Infrastructure - Available Commands:$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(BLUE)Sub-project Makefiles:$(NC)"
	@echo "  cd ansible/        && make help"
	@echo "  cd terraform/lxc/  && make help"
	@echo ""

setup: ## Install pre-commit hooks and development dependencies
	@echo "$(GREEN)Installing pre-commit hooks...$(NC)"
	@pre-commit install
	@pre-commit install --hook-type commit-msg
	@echo "$(GREEN)Done. Pre-commit hooks are now active.$(NC)"

# Komodo by hand (km, configured in ~/.config/komodo/). GitOps Apply covers
# every push; these are for a deploy the sync cannot see, such as a changed
# secret value behind an unchanged [[NAME]]. scripts/km-run.sh turns km's
# always-0 exit code into the run's real result.
komodo-deploy: ## Deploy one Komodo stack, fail if the deploy fails (usage: make komodo-deploy STACK=<name>)
	@test -n "$(STACK)" || { echo "STACK required: make komodo-deploy STACK=<name>"; exit 1; }
	@scripts/km-run.sh deploy-stack "$(STACK)"

komodo-sync: ## Run the proxmox-infra ResourceSync (komodo/*.toml), fail if it fails
	@scripts/km-run.sh run-sync proxmox-infra

komodo-run: ## Run a Komodo Procedure, fail if it fails (usage: make komodo-run PROC="Redeploy Images")
	@test -n "$(PROC)" || { echo 'PROC required: make komodo-run PROC="<name>"'; exit 1; }
	@scripts/km-run.sh run-procedure "$(PROC)"

check-ips: ## Check that hand-written host IPs match the Terraform tfvars
	@python3 scripts/check_ips.py

# One SVG per page of docs/diagrams/network.drawio, embedded by docs/NETWORK.md.
# Needs the draw.io desktop app (brew install --cask drawio).
DIAGRAM_PAGES := 1-physical 2-zones 3-dns-dhcp 4-exposure

diagrams: ## Export docs/diagrams/network.drawio pages to SVG
	@for page in $(DIAGRAM_PAGES); do \
		drawio --export --format svg --embed-svg-fonts false --theme light --page-index $${page%%-*} \
			--output docs/diagrams/network-$$page.svg docs/diagrams/network.drawio >/dev/null 2>&1 || exit 1; \
		echo >> docs/diagrams/network-$$page.svg; \
		echo "  docs/diagrams/network-$$page.svg"; \
	done
