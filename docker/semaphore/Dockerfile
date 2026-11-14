# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
#
# semaphore — Ansible runner for this repo's playbooks.
#
# Thin layer over semaphoreui/semaphore, which already ships git,
# openssh-client, python3, rsync and an ansible venv. This adds dig, talosctl,
# the repo's pinned collections, a credential-rendering entrypoint and strict
# host-key checking. Hosts come from the committed inventory snapshot, so the
# runner needs no Terraform state access.

# renovate: datasource=docker depName=semaphoreui/semaphore
ARG SEMAPHORE_VERSION=v2.20.24@sha256:c547d31cba238bee4a9f2b5eec9d0f42b2d5ecb399377a2e63008500d74fbf3a

# Source of the pinned ansible collections (see the COPY below).
FROM registry.example.com/example-org/proxmox-infra/ci:latest@sha256:28635e3c21aa7f671823f65821d3cc2d3c60e7aa988647b7180d8ae86cbda6e9 AS collections

FROM semaphoreui/semaphore:${SEMAPHORE_VERSION}

LABEL maintainer="maintainer@example.io"
LABEL org.opencontainers.image.title="semaphore"
LABEL org.opencontainers.image.description="Semaphore + dig, talosctl, pinned collections and strict host-key checking"
LABEL org.opencontainers.image.source="https://source.example.com/example-org/proxmox-infra"
LABEL org.opencontainers.image.licenses="MIT"

USER root

# bind-tools: the patch playbook's DNS gate queries each surviving HA member by
# IP with dig before the partner is patched.
RUN apk add --no-cache bind-tools

# hvac: community.hashi_vault (bundled with upstream's ansible package) reads
# the playbooks' secrets from Vault. Installed into the venv ansible runs
# from, whose path carries upstream's ansible version.
# renovate: datasource=pypi depName=hvac
ARG HVAC_VERSION=2.4.0
RUN "$(dirname "$(command -v ansible-playbook)")/pip" install --no-cache-dir "hvac==${HVAC_VERSION}"

# The runner only executes Ansible templates; upstream's bundled IaC binaries
# are unused here and carry most of the image's critical CVEs.
RUN rm -f /usr/local/bin/terraform /usr/local/bin/terragrunt /usr/local/bin/tofu

# talosctl: the Talos etcd backup and health templates. Keep it on the
# cluster's Talos version; the client and server minor must match.
# renovate: datasource=github-releases depName=siderolabs/talos
ARG TALOS_VERSION=v1.14.6
RUN cd /tmp && \
  BASE="https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}" && \
  wget -q "${BASE}/talosctl-linux-amd64" && \
  wget -qO- "${BASE}/sha256sum.txt" | grep ' talosctl-linux-amd64$' | sha256sum -c - && \
  install -m 0755 talosctl-linux-amd64 /usr/local/bin/talosctl && \
  rm talosctl-linux-amd64

# Upstream ships this file with `StrictHostKeyChecking no` and
# `UserKnownHostsFile /dev/null` for Host *, silently defeating the repo's
# host_key_checking = True on the runner that holds a fleet-wide SSH key.
RUN printf 'Host *\n  StrictHostKeyChecking accept-new\n  UserKnownHostsFile ~/.ssh/known_hosts\n' \
  > /etc/ssh/ssh_config.d/semaphore.conf


COPY --chown=1001:0 entrypoint.sh /usr/local/bin/semaphore-entrypoint
RUN chmod +x /usr/local/bin/semaphore-entrypoint

# Collections come from the CI image rather than Galaxy: it already carries the
# pinned versions, so the runner and CI resolve identical module behaviour by
# construction, and the build gains no dependency on Galaxy being reachable.
# Renovate maintains the pins in .ci/docker/Dockerfile.
COPY --from=collections --chown=1001:0 \
  /root/.ansible/collections/ansible_collections \
  /home/semaphore/.ansible/collections/ansible_collections

USER 1001

RUN echo "=== semaphore runner layer ===" && \
  echo "ansible:    $(ansible --version | head -n1)" && \
  echo "ssh:        $(ssh -V 2>&1)" && \
  echo "dig:        $(dig -v 2>&1)" && \
  echo "talosctl:   $(talosctl version --client --short 2>&1 | tail -n1)" && \
  echo "collections: $(ansible-galaxy collection list 2>/dev/null | grep -cE 'community.general|community.docker|ansible.posix') installed" && \
  echo "hashi_vault: $(ansible-galaxy collection list community.hashi_vault 2>/dev/null | grep -c community.hashi_vault) installed" && \
  "$(dirname "$(command -v ansible-playbook)")/python3" -c 'import importlib.metadata as m, hvac; print("hvac:       ", m.version("hvac"))' && \
  echo "=============================="

# tini still reaps the ansible processes; our entrypoint execs the upstream CMD.
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/semaphore-entrypoint"]
CMD ["/usr/local/bin/server-wrapper"]
