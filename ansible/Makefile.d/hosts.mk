# ============================================================================
# Makefile.d/hosts.mk — host lifecycle (LXC + future Linux VMs).
# Drives the uniform playbooks under playbooks/hosts/ + playbooks/komodo/.
# Included by ansible/Makefile.
# ============================================================================

SITE := playbooks/site.yml
HOSTS_DIR := playbooks/hosts
KOMODO_DIR := playbooks/komodo
HOST_INV := -i $(INVENTORY_ALL)

##@ Host Lifecycle

bootstrap-host: ## Bootstrap ONE host as root (usage: make bootstrap-host HOST=<name>)
	@test -n "$(HOST)" || { echo "$(RED)✗ HOST required: make bootstrap-host HOST=<name>$(NC)"; exit 1; }
	@# Bootstrap is the one moment a host is (re)provisioned, so trust-on-first-use
	@# is appropriate here only. A recycled IP leaves a stale known_hosts entry that
	@# trips strict checking, so drop the old key for the target's IP + name first,
	@# then accept the new key. configure/verify/ping keep strict checking intact.
	@host_ip=$$(ansible-inventory $(HOST_INV) --host $(HOST) 2>/dev/null | sed -n 's/.*"ansible_host": *"\([^"]*\)".*/\1/p'); \
	for h in $(HOST) $$host_ip; do \
		[ -n "$$h" ] && ssh-keygen -R "$$h" >/dev/null 2>&1 || true; \
	done; \
	ANSIBLE_HOST_KEY_CHECKING=accept-new \
	ANSIBLE_SSH_ARGS="-o StrictHostKeyChecking=accept-new -o ControlMaster=auto -o ControlPersist=30m -o ConnectionAttempts=10" \
	ansible-playbook $(HOST_INV) $(HOSTS_DIR)/bootstrap.yml --limit $(HOST) $(ARGS)

configure-host: ## Configure ONE host as sanjin (usage: make configure-host HOST=<name>)
	@test -n "$(HOST)" || { echo "$(RED)✗ HOST required: make configure-host HOST=<name>$(NC)"; exit 1; }
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/configure.yml --limit $(HOST) $(ARGS)

verify-host: ## Verify ONE host (usage: make verify-host HOST=<name>)
	@test -n "$(HOST)" || { echo "$(RED)✗ HOST required: make verify-host HOST=<name>$(NC)"; exit 1; }
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/verify.yml --limit $(HOST) $(ARGS)

update-hosts: ## apt update + dist-upgrade (usage: make update-hosts [HOST=<name>])
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/update.yml $(if $(HOST),--limit $(HOST)) $(ARGS)

diagnostics: ## Collect diagnostics (usage: make diagnostics [HOST=<name>])
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/diagnostics.yml $(if $(HOST),--limit $(HOST)) $(ARGS)

restart-docker: ## Restart the Docker daemon (usage: make restart-docker [HOST=<name>])
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/restart-docker.yml $(if $(HOST),--limit $(HOST)) $(ARGS)

site: ## Run the full host lifecycle via tag group (usage: make site TAGS=deployment [HOST=<name>])
	@test -n "$(TAGS)" || { echo "$(RED)✗ TAGS required (deployment|operations|...)$(NC)"; exit 1; }
	@ansible-playbook $(HOST_INV) $(SITE) --tags "$(TAGS)" $(if $(HOST),--limit $(HOST)) $(ARGS)

##@ Komodo

deploy-komodo-core: ## Deploy Komodo Core on the komodo host
	@ansible-playbook $(HOST_INV) $(KOMODO_DIR)/core.yml $(ARGS)

install-periphery: ## Install Komodo Periphery (usage: make install-periphery [HOST=<name>])
	@ansible-playbook $(HOST_INV) $(KOMODO_DIR)/periphery.yml $(if $(HOST),--limit $(HOST)) $(ARGS)
