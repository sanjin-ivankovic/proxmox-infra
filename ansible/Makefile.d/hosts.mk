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

configure-host: ## Configure ONE host as maintainer (usage: make configure-host HOST=<name>)
	@test -n "$(HOST)" || { echo "$(RED)✗ HOST required: make configure-host HOST=<name>$(NC)"; exit 1; }
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/configure.yml --limit $(HOST) $(ARGS)

##@ Semaphore

# Prints one vault value: a string as-is, a map as "<key> <value>" lines (the
# Pi-hole credential format). Used inside $(...) only, never echoed.
VAULT_GET = ansible-vault view $(VAULT_SHARED) | python3 -c 'import sys, yaml; \
	v = yaml.safe_load(sys.stdin)[sys.argv[1]]; \
	print("\n".join(f"{k} {x}" for k, x in v.items()) if isinstance(v, dict) else v)'

# SEMAPHORE_URL must target the host directly — the ingress is behind Authentik
# forward-auth, which an API token cannot traverse. The token comes from
# vault_semaphore_api_token (the maintainer account) unless SEMAPHORE_API_TOKEN is
# already set; the homelab MCP drift check sets both to its read-only token.
SEMAPHORE_URL ?= http://10.140.0.16:3000
SEMAPHORE_ENV = SEMAPHORE_URL=$(SEMAPHORE_URL) \
	SEMAPHORE_API_TOKEN="$${SEMAPHORE_API_TOKEN:-$$($(VAULT_GET) vault_semaphore_api_token)}"

semaphore-bootstrap: ## Create/update the Semaphore project objects (ARGS=--dry-run to preview)
	@$(SEMAPHORE_ENV) scripts/semaphore_bootstrap.py $(ARGS)

semaphore-doctor: ## Verify live Semaphore objects match configs/semaphore.yml
	@$(SEMAPHORE_ENV) scripts/semaphore_bootstrap.py --doctor

# Semaphore reads hosts from this committed snapshot instead of Terraform
# state. Re-run after a host is added, removed, re-IP'd or re-tagged, then
# commit; make inventory-doctor fails while the snapshot is stale.
semaphore-files: ## Render inventory/hosts.snapshot.json from live Terraform state
	@./inventory/terraform_state_inventory.py --render

##@ Technitium

# The token comes from vault_technitium_api_token unless TECHNITIUM_API_TOKEN
# is already exported; it never appears on a command line.
TECHNITIUM_TOKEN_ENV = TECHNITIUM_API_TOKEN="$${TECHNITIUM_API_TOKEN:-$$($(VAULT_GET) vault_technitium_api_token)}"

technitium-bootstrap: ## Converge Technitium zones, records and DHCP scopes (ARGS=--dry-run to preview)
	@$(TECHNITIUM_TOKEN_ENV) scripts/technitium_bootstrap.py $(ARGS)

technitium-doctor: ## Verify live Technitium state matches configs/technitium.yml
	@$(TECHNITIUM_TOKEN_ENV) scripts/technitium_bootstrap.py --doctor

##@ Pi-hole

# "<node> <app-password>" lines rendered from vault_pihole_app_passwords
# (a node -> password map). An exported PIHOLE_CREDENTIALS_FILE or
# PIHOLE_CREDENTIALS wins, and then the vault is not read.
PIHOLE_ENV = PIHOLE_CREDENTIALS="$${PIHOLE_CREDENTIALS:-$$(test -n "$$PIHOLE_CREDENTIALS_FILE" \
	|| $(VAULT_GET) vault_pihole_app_passwords)}"

pihole-doctor: ## Verify the Pi-hole pair matches its compose FTLCONF and lists (NODES=pihole-2 for one)
	@$(PIHOLE_ENV) scripts/pihole_doctor.py $(NODES)

# Also a Semaphore template ("Pi-hole: Reset"). The query history cannot be
# recovered, hence CONFIRM.
pihole-reset: ## Wipe query history, stats and logs, one node at a time (CONFIRM=yes; NODES=pihole-2 for one)
	@test "$(CONFIRM)" = yes || { echo "pihole-reset deletes the query history and statistics for good; rerun with CONFIRM=yes"; exit 1; }
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/pihole-reset.yml \
	  -e pihole_reset_confirm=true $(if $(NODES),-e pihole_reset_nodes=$(NODES)) $(ARGS)

##@ Host Lifecycle

ssh-known-hosts: ## Regenerate services/semaphore/known_hosts from the live fleet
	@# Host public keys are not secrets. The semaphore stack bind-mounts this
	@# file so strict host-key checking has something to verify against;
	@# regenerate it whenever a host is rebuilt or re-IP'd, then commit.
	@ansible-inventory $(HOST_INV) --list 2>/dev/null \
	  | python3 -c 'import json,sys;hv=json.load(sys.stdin)["_meta"]["hostvars"];[print(h+":"+hv[h]["ansible_host"]) for h in sorted(hv) if hv[h].get("ansible_host")]' \
	  | while IFS=: read -r name ip; do \
	      key=$$(ssh-keyscan -t ed25519 -T 5 "$$ip" 2>/dev/null | grep -v '^#' | head -1 | cut -d' ' -f2-); \
	      if [ -n "$$key" ]; then echo "$$name,$$ip $$key"; \
	      else echo "$(RED)✗ no key from $$name ($$ip)$(NC)" >&2; fi; \
	    done > $(PROJECT_ROOT)/services/semaphore/known_hosts
	@echo "$(GREEN)✓ wrote services/semaphore/known_hosts ($$(wc -l < $(PROJECT_ROOT)/services/semaphore/known_hosts | tr -d ' ') hosts)$(NC)"

authorized-keys: ## Authorize the shared automation key (usage: make authorized-keys [HOST=<name>])
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/authorized-keys.yml $(if $(HOST),--limit $(HOST)) $(ARGS)

monitoring-agent: ## Install node_exporter + cAdvisor on Docker hosts (usage: make monitoring-agent [HOST=<name>])
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/monitoring-agent.yml $(if $(HOST),--limit $(HOST)) $(ARGS)

verify-host: ## Verify ONE host (usage: make verify-host HOST=<name>)
	@test -n "$(HOST)" || { echo "$(RED)✗ HOST required: make verify-host HOST=<name>$(NC)"; exit 1; }
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/verify.yml --limit $(HOST) $(ARGS)

# patch.yml's safety gates (empty wave, wave completed, DNS probe) are localhost
# plays; a --limit without localhost skips them all with "no hosts matched".
PATCH_COMMA := ,
PATCH_LIMIT = $(if $(HOST),--limit $(HOST)$(PATCH_COMMA)localhost)

patch-check: ## Dry-run the patch flow, no changes (usage: make patch-check [WAVE=<name>] [HOST=<name>])
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/patch.yml --check --diff \
	  $(if $(WAVE),-e patch_wave=patch_$(subst -,_,$(WAVE))) $(PATCH_LIMIT) $(ARGS)

patch-hosts: ## Wave-sequenced OS patching (usage: make patch-hosts [WAVE=<name>] [HOST=<name>])
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/patch.yml \
	  $(if $(WAVE),-e patch_wave=patch_$(subst -,_,$(WAVE))) $(PATCH_LIMIT) $(ARGS)

patch-report: ## Show the latest patch report per host (usage: make patch-report [HOST=<name>])
	@ansible $(HOST_INV) $(if $(HOST),$(HOST),patch_all) -b -m ansible.builtin.slurp \
	  -a 'src=/var/log/os-patch/latest.json' 2>/dev/null \
	  | sed -n 's/.*"content": "\(.*\)",/\1/p' | base64 -d 2>/dev/null || \
	  echo "$(RED)✗ no reports found — has a patch run completed?$(NC)"

diagnostics: ## Collect diagnostics (usage: make diagnostics [HOST=<name>])
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/diagnostics.yml $(if $(HOST),--limit $(HOST)) $(ARGS)

restart-docker: ## Restart the Docker daemon (usage: make restart-docker [HOST=<name>])
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/restart-docker.yml $(if $(HOST),--limit $(HOST)) $(ARGS)

site: ## Run the full host lifecycle via tag group (usage: make site TAGS=deployment [HOST=<name>])
	@test -n "$(TAGS)" || { echo "$(RED)✗ TAGS required (deployment|operations|...)$(NC)"; exit 1; }
	@ansible-playbook $(HOST_INV) $(SITE) --tags "$(TAGS)" $(if $(HOST),--limit $(HOST)) $(ARGS)

##@ Komodo

deploy-komodo-core: ## Provision Komodo Core on the komodo host (full run, incl. Docker/system roles)
	@ansible-playbook $(HOST_INV) $(KOMODO_DIR)/core.yml $(ARGS)

install-periphery: ## Provision Komodo Periphery on a new host (full run, incl. Docker/system roles) (usage: make install-periphery [HOST=<name>])
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

upgrade-komodo: ## Upgrade Komodo Core only, skipping the Docker/system dependency roles
	@ansible-playbook $(HOST_INV) $(KOMODO_DIR)/core.yml --skip-tags $(KOMODO_UPGRADE_SKIP_TAGS) $(ARGS)

upgrade-periphery: ## Upgrade the Periphery agents only, skipping the Docker/system dependency roles (usage: make upgrade-periphery [HOST=<name>])
	@ansible-playbook $(HOST_INV) $(KOMODO_DIR)/periphery.yml --skip-tags $(KOMODO_UPGRADE_SKIP_TAGS) $(if $(HOST),--limit $(HOST)) $(ARGS)

# Secret-change path: re-render periphery.config.toml on ONE host, restarting
# Periphery only if it changed. common_docker's daemon tasks are tagged
# `config` too, so `--tags config` needs the same skip list as the upgrades.
periphery-secrets: ## Re-render ONE host's Periphery config and [secrets], restart if changed (usage: make periphery-secrets HOST=<name>)
	@test -n "$(HOST)" || { echo "$(RED)✗ HOST required: make periphery-secrets HOST=<name>$(NC)"; exit 1; }
	@ansible-playbook $(HOST_INV) $(KOMODO_DIR)/periphery.yml --tags config --skip-tags $(KOMODO_UPGRADE_SKIP_TAGS) --limit $(HOST) $(ARGS)
