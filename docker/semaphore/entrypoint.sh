#!/bin/sh
#
# Renders the credential files this repo's tooling reads from disk, then execs
# the upstream entrypoint. Secrets arrive as env vars from the Komodo periphery
# [secrets] block; ansible-vault wants a file, not a variable.

set -eu

umask 077

log() { echo "[entrypoint] $*"; }

# --- Ansible Vault password -------------------------------------------------
if [ -n "${ANSIBLE_VAULT_PASSWORD:-}" ]; then
  printf '%s' "${ANSIBLE_VAULT_PASSWORD}" > "${HOME}/.vault_pass"
  chmod 0600 "${HOME}/.vault_pass"
  log "wrote ~/.vault_pass"
else
  log "WARNING: ANSIBLE_VAULT_PASSWORD not set — plays reading vault.yml will fail"
fi

# --- known_hosts ------------------------------------------------------------
# services/semaphore/known_hosts is bind-mounted here from the repo checkout;
# copied on every start (a restart keeps the old ~/.ssh) so a regenerated file
# takes effect on the restart Komodo runs when it changes.
if [ -f /opt/semaphore/known_hosts ]; then
  mkdir -p "${HOME}/.ssh"
  chmod 0700 "${HOME}/.ssh"
  cp /opt/semaphore/known_hosts "${HOME}/.ssh/known_hosts"
  chmod 0600 "${HOME}/.ssh/known_hosts"
  log "copied known_hosts ($(wc -l < "${HOME}/.ssh/known_hosts") hosts)"
else
  log "WARNING: /opt/semaphore/known_hosts missing - strict host-key checking has nothing to verify against"
fi

exec "$@"
