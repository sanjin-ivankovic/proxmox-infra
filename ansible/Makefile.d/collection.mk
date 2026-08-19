# ============================================================================
# Makefile.d/collection.mk — build/install the homelab.proxmox collection
# and run Molecule role tests. Included by ansible/Makefile.
# ============================================================================

COLLECTION_BUILD_DIR := /tmp/homelab-proxmox-build
COLLECTION_PATH := ./collections
MOLECULE_SCENARIOS := common_system common_users common_ssh

# The local collection sits in ./collections, but its community.* deps live in
# the user/system paths — a search path covering both is needed so FQCN roles
# AND their deps resolve. Used by lint/syntax-check/molecule below.
COLLECTIONS_PATH_FULL := $(abspath $(COLLECTION_PATH)):$(HOME)/.ansible/collections:/usr/share/ansible/collections

##@ Collection

collection: ## Build + install the homelab.proxmox collection into ./collections
	@echo "$(BLUE)Building homelab.proxmox collection...$(NC)"
	@ansible-galaxy collection build --force --output-path $(COLLECTION_BUILD_DIR)
	@ansible-galaxy collection install $(COLLECTION_BUILD_DIR)/homelab-proxmox-*.tar.gz \
		-p $(COLLECTION_PATH) --force
	@echo "$(GREEN)✓ Collection installed into $(COLLECTION_PATH)$(NC)"

collection-doc: collection ## Show a role's argument_specs (usage: make collection-doc ROLE=common_ssh)
	@ANSIBLE_COLLECTIONS_PATH=$(COLLECTIONS_PATH_FULL) ansible-doc -t role homelab.proxmox.$(or $(ROLE),common_ssh)

molecule: collection ## Run all Molecule scenarios (requires molecule + docker)
	@command -v molecule >/dev/null || { echo "$(RED)✗ molecule not installed$(NC)"; exit 1; }
	@for s in $(MOLECULE_SCENARIOS); do \
		echo "$(BLUE)molecule test -s $$s$(NC)"; \
		ANSIBLE_COLLECTIONS_PATH=$(COLLECTIONS_PATH_FULL) molecule test -s $$s || exit 1; \
	done
	@echo "$(GREEN)✓ All Molecule scenarios passed$(NC)"

molecule-scenario: collection ## Run one Molecule scenario (usage: make molecule-scenario S=common_ssh)
	@command -v molecule >/dev/null || { echo "$(RED)✗ molecule not installed$(NC)"; exit 1; }
	@ANSIBLE_COLLECTIONS_PATH=$(COLLECTIONS_PATH_FULL) molecule test -s $(or $(S),common_ssh)
