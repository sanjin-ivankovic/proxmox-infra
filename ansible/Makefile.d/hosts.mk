# ============================================================================
# Makefile.d/hosts.mk — host lifecycle (LXC + future Linux VMs).
# Drives the uniform playbooks under playbooks/hosts/ + playbooks/komodo/.
# Included by ansible/Makefile.
# ============================================================================

SITE := playbooks/site.yml
HOSTS_DIR := playbooks/hosts
KOMODO_DIR := playbooks/komodo
HOST_INV := -i $(INVENTORY_ALL)

.PHONY: host-bootstrap host-configure host-verify host-diagnostics ssh-known-hosts semaphore-bootstrap semaphore-doctor semaphore-files technitium-bootstrap technitium-doctor pbs-bootstrap pbs-doctor pve-notify pve-notify-doctor pihole-doctor pihole-reset system-config docker-install docker-config docker-restart keys-config monitoring-install monitoring-update komodo-install komodo-update periphery-install periphery-update periphery-config vault-host-update patch-check patch-apply patch-report site-run


# Targets are <component>-<action>:
#   -install  the component plus the base it needs (configure.yml); HOST required
#   -update   the component's role alone: version bumps and drift
#   -config   the role's config tasks only (--tags config)
# HOST=<name> limits a fleet-wide target to one host.
REQUIRE_HOST = @test -n "$(HOST)" || { echo "$(RED)✗ HOST required: make $@ HOST=<name>$(NC)"; exit 1; }
LIMIT = $(if $(HOST),--limit $(HOST))

##@ Hosts

host-bootstrap: ## Bootstrap ONE new host as root: user, SSH hardening, full upgrade (HOST=<name>)
	$(REQUIRE_HOST)
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

host-configure: ## Apply the base to ONE host: system packages + Docker (HOST=<name>)
	$(REQUIRE_HOST)
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/configure.yml --limit $(HOST) $(ARGS)

host-verify: ## Read-only health check of ONE host (HOST=<name>)
	$(REQUIRE_HOST)
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/verify.yml --limit $(HOST) $(ARGS)

host-diagnostics: ## Collect diagnostics, read-only ([HOST=<name>])
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/diagnostics.yml $(LIMIT) $(ARGS)

ssh-known-hosts: ## Regenerate services/semaphore/known_hosts from the live fleet
	@# Host public keys are not secrets. The semaphore stack bind-mounts this
	@# file so strict host-key checking has something to verify against;
	@# regenerate it whenever a host is rebuilt or re-IP'd, then commit.
	@# Built in a temp file and moved into place only when the inventory read
	@# and at least one keyscan succeeded: a failed run leaves the file as is.
	@hosts=$$(mktemp); tmp=$$(mktemp); trap 'rm -f "$$hosts" "$$tmp"' EXIT; \
	ansible-inventory $(HOST_INV) --list \
	  | python3 -c 'import json,sys;hv=json.load(sys.stdin)["_meta"]["hostvars"];[print(h+":"+hv[h]["ansible_host"]) for h in sorted(hv) if hv[h].get("ansible_host")]' \
	  > "$$hosts" && [ -s "$$hosts" ] \
	  || { echo "$(RED)✗ inventory read failed; known_hosts left unchanged$(NC)" >&2; exit 1; }; \
	while IFS=: read -r name ip; do \
	  key=$$(ssh-keyscan -t ed25519 -T 5 "$$ip" 2>/dev/null | grep -v '^#' | head -1 | cut -d' ' -f2-); \
	  if [ -n "$$key" ]; then echo "$$name,$$ip $$key"; \
	  else echo "$(RED)✗ no key from $$name ($$ip)$(NC)" >&2; fi; \
	done < "$$hosts" > "$$tmp"; \
	[ -s "$$tmp" ] || { echo "$(RED)✗ no host keys scanned; known_hosts left unchanged$(NC)" >&2; exit 1; }; \
	chmod 644 "$$tmp" && mv "$$tmp" $(PROJECT_ROOT)/services/semaphore/known_hosts
	@echo "$(GREEN)✓ wrote services/semaphore/known_hosts ($$(wc -l < $(PROJECT_ROOT)/services/semaphore/known_hosts | tr -d ' ') hosts)$(NC)"


##@ Semaphore

# $(call KV_GET,<service>,<field>) prints one field of kv/proxmox-infra/<service>:
# a string as-is, a map as "<key> <value>" lines (the Pi-hole credential
# format). Used inside $(...) only, never echoed. Needs `vault login`.
KV_GET = vault kv get -format=json -mount=kv proxmox-infra/$(1) | python3 -c 'import json, sys; \
	v = json.load(sys.stdin)["data"]["data"][sys.argv[1]]; \
	print("\n".join(f"{k} {x}" for k, x in v.items()) if isinstance(v, dict) else v)' $(2)

# SEMAPHORE_URL must target the host directly — the ingress is behind Authentik
# forward-auth, which an API token cannot traverse. The token comes from
# kv/proxmox-infra/semaphore api_token (the maintainer account) unless SEMAPHORE_API_TOKEN is
# already set; the homelab MCP drift check sets both to its read-only token.
SEMAPHORE_URL ?= http://10.140.0.15:3000
SEMAPHORE_ENV = SEMAPHORE_URL=$(SEMAPHORE_URL) \
	SEMAPHORE_API_TOKEN="$${SEMAPHORE_API_TOKEN:-$$($(call KV_GET,semaphore,api_token))}"

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

# The token comes from kv/proxmox-infra/technitium api_token unless TECHNITIUM_API_TOKEN
# is already exported; it never appears on a command line.
TECHNITIUM_TOKEN_ENV = TECHNITIUM_API_TOKEN="$${TECHNITIUM_API_TOKEN:-$$($(call KV_GET,technitium,api_token))}"

technitium-bootstrap: ## Converge Technitium zones, records and DHCP scopes (ARGS=--dry-run to preview)
	@$(TECHNITIUM_TOKEN_ENV) scripts/technitium_bootstrap.py $(ARGS)

technitium-doctor: ## Verify live Technitium state matches configs/technitium.yml
	@$(TECHNITIUM_TOKEN_ENV) scripts/technitium_bootstrap.py --doctor

##@ Proxmox Backup Server

# The token comes from kv/proxmox-infra/pbs unless PBS_API_TOKEN_ID
# and PBS_API_TOKEN_SECRET are already exported; it never appears on a command
# line. PBS is on the storage VLAN: run from the admin network, Semaphore has
# no route to 8007.
PBS_TOKEN_ENV = PBS_API_TOKEN_ID="$${PBS_API_TOKEN_ID:-$$($(call KV_GET,pbs,api_token_id))}" \
	PBS_API_TOKEN_SECRET="$${PBS_API_TOKEN_SECRET:-$$($(call KV_GET,pbs,api_token_secret))}"

# The ntfy token is only sent on create or ARGS=--rotate-token, so the doctor
# does not read it.
NTFY_BACKUPS_ENV = NTFY_BACKUPS_TOKEN="$${NTFY_BACKUPS_TOKEN:-$$($(call KV_GET,ntfy-backups,token))}"

pbs-bootstrap: ## Converge PBS datastores, namespaces, jobs and the ntfy target (ARGS=--dry-run to preview)
	@$(PBS_TOKEN_ENV) $(NTFY_BACKUPS_ENV) scripts/pbs_bootstrap.py $(ARGS)

pbs-doctor: ## Verify live PBS jobs and the ntfy target match configs/pbs.yml and configs/notifications.yml
	@$(PBS_TOKEN_ENV) scripts/pbs_bootstrap.py --doctor

##@ Proxmox VE notifications

# Uses the Terraform token, kv/terraform/proxmox; it and its user need
# PVEMappingAdmin on /mapping/notifications.
PVE_KV = vault kv get -mount=kv -field=$(1) terraform/proxmox
PVE_TOKEN_ENV = PVE_API_TOKEN_ID="$${PVE_API_TOKEN_ID:-$$($(call PVE_KV,api_token_id))}" \
	PVE_API_TOKEN_SECRET="$${PVE_API_TOKEN_SECRET:-$$($(call PVE_KV,api_token_secret))}"

pve-notify: ## Converge the PVE ntfy webhook target and matcher (ARGS=--dry-run to preview)
	@$(PVE_TOKEN_ENV) $(NTFY_BACKUPS_ENV) scripts/pve_notifications.py $(ARGS)

pve-notify-doctor: ## Verify the PVE ntfy target and matcher match configs/notifications.yml
	@$(PVE_TOKEN_ENV) scripts/pve_notifications.py --doctor

##@ Pi-hole

# "<node> <app-password>" lines rendered from kv/proxmox-infra/pihole
# app_passwords (a node -> password map). An exported PIHOLE_CREDENTIALS_FILE
# or PIHOLE_CREDENTIALS wins, and then Vault is not read.
PIHOLE_ENV = PIHOLE_CREDENTIALS="$${PIHOLE_CREDENTIALS:-$$(test -n "$$PIHOLE_CREDENTIALS_FILE" \
	|| $(call KV_GET,pihole,app_passwords))}"

pihole-doctor: ## Verify the Pi-hole pair matches its compose FTLCONF and lists (NODES=pihole-2 for one)
	@$(PIHOLE_ENV) scripts/pihole_doctor.py $(NODES)

# Also a Semaphore template ("Pi-hole: Reset"). The query history cannot be
# recovered, hence CONFIRM.
pihole-reset: ## Wipe query history, stats and logs, one node at a time (CONFIRM=yes; NODES=pihole-2 for one)
	@test "$(CONFIRM)" = yes || { echo "pihole-reset deletes the query history and statistics for good; rerun with CONFIRM=yes"; exit 1; }
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/pihole-reset.yml \
	  -e pihole_reset_confirm=true $(if $(NODES),-e pihole_reset_nodes=$(NODES)) $(ARGS)

##@ Base components

system-config: ## Apply common_system: base packages and OS settings ([HOST=<name>])
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/system.yml $(LIMIT) $(ARGS)

docker-install: ## Install Docker on ONE host: system.yml + docker.yml (HOST=<name>)
	$(REQUIRE_HOST)
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/system.yml $(HOSTS_DIR)/docker.yml --limit $(HOST) $(ARGS)

docker-config: ## Re-apply daemon.json and drop-ins; restarts Docker if daemon.json changed (HOST=<name>)
	$(REQUIRE_HOST)
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/docker.yml --tags config --limit $(HOST) $(ARGS)

docker-restart: ## Restart the Docker daemon ([HOST=<name>])
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/restart-docker.yml $(LIMIT) $(ARGS)

keys-config: ## Authorize the shared automation key ([HOST=<name>])
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/authorized-keys.yml $(LIMIT) $(ARGS)

##@ Monitoring agent

monitoring-install: ## Base + node_exporter, cAdvisor, Alloy on ONE new host (HOST=<name>)
	$(REQUIRE_HOST)
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/configure.yml $(HOSTS_DIR)/monitoring-agent.yml --limit $(HOST) $(ARGS)

monitoring-update: ## node_exporter, cAdvisor, Alloy only; version bumps and config ([HOST=<name>])
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/monitoring-agent.yml $(LIMIT) $(ARGS)

##@ Komodo

# Upgrade Core before the agents: Periphery connects to Core, and Renovate's
# `komodo` group bumps both pins in the same MR.

komodo-install: ## Base + Komodo Core on the komodo host
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/configure.yml $(KOMODO_DIR)/core.yml --limit komodo $(ARGS)

komodo-update: ## Komodo Core only: image bump, config, redeploy
	@ansible-playbook $(HOST_INV) $(KOMODO_DIR)/core.yml $(ARGS)

periphery-install: ## Base + Komodo Periphery on ONE new host (HOST=<name>)
	$(REQUIRE_HOST)
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/configure.yml $(KOMODO_DIR)/periphery.yml --limit $(HOST) $(ARGS)

periphery-update: ## Komodo Periphery only: version bumps ([HOST=<name>])
	@ansible-playbook $(HOST_INV) $(KOMODO_DIR)/periphery.yml $(LIMIT) $(ARGS)

periphery-config: ## Re-render ONE host's Periphery config and [secrets], restart if changed (HOST=<name>)
	$(REQUIRE_HOST)
	@ansible-playbook $(HOST_INV) $(KOMODO_DIR)/periphery.yml --tags config --limit $(HOST) $(ARGS)

##@ Vault host

vault-host-update: ## Vault host: lego certificate + renewal, probe, snapshot timers (never restarts Vault)
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/hashicorp-vault.yml $(ARGS)

##@ Patching

# patch.yml's safety gates (empty wave, wave completed, DNS probe) are localhost
# plays; a --limit without localhost skips them all with "no hosts matched".
PATCH_COMMA := ,
PATCH_LIMIT = $(if $(HOST),--limit $(HOST)$(PATCH_COMMA)localhost)

patch-check: ## Dry-run the patch flow, no changes (usage: make patch-check [WAVE=<name>] [HOST=<name>])
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/patch.yml --check --diff \
	  $(if $(WAVE),-e patch_wave=patch_$(subst -,_,$(WAVE))) $(PATCH_LIMIT) $(ARGS)


patch-apply: ## Wave-sequenced OS patching ([WAVE=<name>] [HOST=<name>])
	@ansible-playbook $(HOST_INV) $(HOSTS_DIR)/patch.yml \
	  $(if $(WAVE),-e patch_wave=patch_$(subst -,_,$(WAVE))) $(PATCH_LIMIT) $(ARGS)

patch-report: ## Show the latest patch report per host (usage: make patch-report [HOST=<name>])
	@ansible $(HOST_INV) $(if $(HOST),$(HOST),patch_all) -b -m ansible.builtin.slurp \
	  -a 'src=/var/log/os-patch/latest.json' 2>/dev/null \
	  | sed -n 's/.*"content": "\(.*\)",/\1/p' | base64 -d 2>/dev/null || \
	  echo "$(RED)✗ no reports found — has a patch run completed?$(NC)"


##@ Site

site-run: ## Run site.yml by stage tag (TAGS=deployment|operations|lifecycle [HOST=<name>])
	@test -n "$(TAGS)" || { echo "$(RED)✗ TAGS required (deployment|operations|lifecycle)$(NC)"; exit 1; }
	@ansible-playbook $(HOST_INV) $(SITE) --tags "$(TAGS)" $(LIMIT) $(ARGS)
