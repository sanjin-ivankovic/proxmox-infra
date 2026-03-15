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

.PHONY: setup help

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
