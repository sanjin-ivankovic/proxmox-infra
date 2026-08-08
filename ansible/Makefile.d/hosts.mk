# ============================================================================
# Makefile.d/hosts.mk — host lifecycle (LXC + future Linux VMs).
# Drives the uniform playbooks under playbooks/hosts/ + playbooks/komodo/.
# Included by ansible/Makefile.
# ============================================================================

SITE := playbooks/site.yml
HOSTS_DIR := playbooks/hosts
KOMODO_DIR := playbooks/komodo
HOST_INV := -i $(INVENTORY_ALL)

# Every target below depends on `collection`: the playbooks reference roles by
# FQCN and ansible.cfg resolves them from ./collections, so an un-rebuilt
# collection silently deploys the previously-built role content.

##@ Host Lifecycle

bootstrap-host: collection ## Bootstrap ONE host as root (usage: make bootstrap-host HOST=<name>)
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

configure-host: collection ## Configure ONE host as maintainer (usage: make configure-host HOST=<name>)
	@test -n "$(HOST)" || { echo "$(RED)✗ HOST required: make configure-host HOST=<name>$(NC)"; exit 1; }
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/configure.yml --limit $(HOST) $(ARGS)

verify-host: collection ## Verify ONE host (usage: make verify-host HOST=<name>)
	@test -n "$(HOST)" || { echo "$(RED)✗ HOST required: make verify-host HOST=<name>$(NC)"; exit 1; }
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/verify.yml --limit $(HOST) $(ARGS)

update-hosts: collection ## apt update + dist-upgrade (usage: make update-hosts [HOST=<name>])
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/update.yml $(if $(HOST),--limit $(HOST)) $(ARGS)

diagnostics: collection ## Collect diagnostics (usage: make diagnostics [HOST=<name>])
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/diagnostics.yml $(if $(HOST),--limit $(HOST)) $(ARGS)

restart-docker: collection ## Restart the Docker daemon (usage: make restart-docker [HOST=<name>])
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/restart-docker.yml $(if $(HOST),--limit $(HOST)) $(ARGS)

site: collection ## Run the full host lifecycle via tag group (usage: make site TAGS=deployment [HOST=<name>])
	@test -n "$(TAGS)" || { echo "$(RED)✗ TAGS required (deployment|operations|...)$(NC)"; exit 1; }
	@ansible-playbook $(HOST_INV) $(SITE) --tags "$(TAGS)" $(if $(HOST),--limit $(HOST)) $(ARGS)

##@ Komodo

deploy-komodo-core: collection ## Provision Komodo Core on the komodo host (full run, incl. Docker/system roles)
	@ansible-playbook $(HOST_INV) $(KOMODO_DIR)/core.yml $(ARGS)

install-periphery: collection ## Provision Komodo Periphery on a new host (full run, incl. Docker/system roles) (usage: make install-periphery [HOST=<name>])
	@ansible-playbook $(HOST_INV) $(KOMODO_DIR)/periphery.yml $(if $(HOST),--limit $(HOST)) $(ARGS)

# Version-bump path. Both komodo roles depend on common_docker (which pulls in
# common_system), so the provisioning targets above also reinstall Docker and
# run an apt dist-upgrade on every target — right for a new host, wrong for a
# Renovate bump that only moves an image tag or a binary release.
#
# The skip list must name the DEPENDENCY roles' tags, not the komodo ones: the
# play-level `tags:` propagate down into every dependency task, so common_docker
# tasks are also tagged `komodo`/`periphery` and `--tags periphery` would still
# select them. Tasks tagged `always` (arg-spec validation, OS/version asserts,
# the read-only connectivity check) survive any skip list and are read-only.
#
# Upgrade Core before the agents — Periphery connects to Core, and Renovate's
# `komodo` group bumps both pins in the same MR.
KOMODO_UPGRADE_SKIP_TAGS := docker,packages,update,backup,timezone,capabilities,aliases,directories,users

upgrade-komodo: collection ## Upgrade Komodo Core only, skipping the Docker/system dependency roles
	@ansible-playbook $(HOST_INV) $(KOMODO_DIR)/core.yml --skip-tags $(KOMODO_UPGRADE_SKIP_TAGS) $(ARGS)

upgrade-periphery: collection ## Upgrade the Periphery agents only, skipping the Docker/system dependency roles (usage: make upgrade-periphery [HOST=<name>])
	@ansible-playbook $(HOST_INV) $(KOMODO_DIR)/periphery.yml --skip-tags $(KOMODO_UPGRADE_SKIP_TAGS) $(if $(HOST),--limit $(HOST)) $(ARGS)
