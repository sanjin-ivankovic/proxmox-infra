# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
#
# proxmox-infra-ci — CI image for the Proxmox infrastructure pipeline.
#
# THIN LAYER over the shared ci-base (homelab/ci-components): ci-base already
# carries the common toolchain (git, gitleaks, cosign, shellcheck, yamllint,
# markdownlint-cli2, pytest/pyyaml, trivy, yq, docker CLI) + the publish/sanitize
# tooling at /opt/ci. This image only adds what is proxmox-specific: OpenTofu,
# ansible-lint (+ collections), and a few apk extras (jq, rsync,
# docker-cli-compose).
#
# Non-obvious by design (don't "fix" without reading the README):
#   - runs as root, no USER/HEALTHCHECK — ephemeral CI pods, root-writable cache
#   - the ci-base ref is tag@sha256:<digest> so Renovate pins the digest (a
#     ci-base rebuild lands here as a digest-bump PR, never silently)

# No `# renovate:` annotation here on purpose: the native dockerfile manager
# already sees this ARG through `FROM docker:${DOCKER_VERSION}` and maintains
# tag+digest. An annotation extracts the same line a second time, and whichever
# write loses the race logs "Cannot find replaceString in current file content".
ARG DOCKER_VERSION=29.9.3-cli@sha256:4d742ab934c2149b628bf26369ac3ec51cb91e2e28fe6722a0e86a6d6efc4bd5

# fetcher: download + checksum-verify OpenTofu, one RUN so a Renovate bump only
# busts that layer. curl/unzip live here only — never in the final image.
# OpenTofu, not Terraform: the lock files record registry.opentofu.org and the
# R2 backend relies on tofu's S3-native locking (use_lockfile, tofu >= 1.10).
FROM docker:${DOCKER_VERSION} AS fetcher
# renovate: datasource=github-releases depName=opentofu/opentofu
ARG TOFU_VERSION=1.13.9
RUN apk add --no-cache curl unzip && mkdir -p /out/usr/local/bin
RUN cd /tmp && \
  BASE="https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}" && \
  curl -fsSL -O "${BASE}/tofu_${TOFU_VERSION}_linux_amd64.zip" && \
  curl -fsSL "${BASE}/tofu_${TOFU_VERSION}_SHA256SUMS" \
    | grep "tofu_${TOFU_VERSION}_linux_amd64.zip$" | sha256sum -c - && \
  unzip -o "tofu_${TOFU_VERSION}_linux_amd64.zip" tofu -d /out/usr/local/bin/ && \
  /out/usr/local/bin/tofu version

# --- final image: ci-base + the proxmox-specific layer ---
# renovate: datasource=docker depName=registry.example.com/homelab/ci-components/ci
FROM registry.example.com/homelab/ci-components/ci:latest@sha256:84e761115bfa4c2c0f29ed5520061db5e7641cb41c657b0a0708b27c775a519f

LABEL maintainer="maintainer@example.io"
LABEL org.opencontainers.image.title="proxmox-infra-ci"
LABEL org.opencontainers.image.description="CI image: ci-base + OpenTofu, Ansible for Proxmox infrastructure"
LABEL org.opencontainers.image.source="https://source.example.com/example-org/proxmox-infra"
LABEL org.opencontainers.image.licenses="MIT"

# renovate: datasource=pypi depName=ansible-lint
ARG ANSIBLE_LINT_VERSION=26.11.0
# Molecule + its Docker driver back the test:molecule job (role converge +
# idempotence + verify). The Docker driver talks to the host Docker socket the
# runner mounts. molecule-plugins[docker] pulls in the docker Python SDK.
# renovate: datasource=pypi depName=molecule
ARG MOLECULE_VERSION=26.11.0
# renovate: datasource=pypi depName=molecule-plugins
ARG MOLECULE_PLUGINS_VERSION=26.11.0
# Ansible collections are pinned here (not from the repo-root
# ansible/requirements.yml, which is outside this build context); they back
# ansible-lint's syntax-check. Keep in sync with that file.
# renovate: datasource=galaxy-collection depName=community.general
ARG COMMUNITY_GENERAL_VERSION=14.0.0
# renovate: datasource=galaxy-collection depName=community.docker
ARG COMMUNITY_DOCKER_VERSION=5.4.0
# renovate: datasource=galaxy-collection depName=ansible.posix
ARG ANSIBLE_POSIX_VERSION=2.2.2

# apk extras not in ci-base: jq, rsync, docker-cli-compose.
RUN apk add --no-cache jq rsync docker-cli-compose

# tofu from the staged build layer.
COPY --from=fetcher /out/usr/local/bin/tofu /usr/local/bin/

# ansible-lint (pyyaml already in ci-base) + molecule with its Docker driver.
RUN pip3 install --no-cache-dir --break-system-packages \
  "ansible-lint==${ANSIBLE_LINT_VERSION}" \
  "molecule==${MOLECULE_VERSION}" \
  "molecule-plugins[docker]==${MOLECULE_PLUGINS_VERSION}"
RUN ansible-galaxy collection install --no-cache \
  "community.general:==${COMMUNITY_GENERAL_VERSION}" \
  "community.docker:==${COMMUNITY_DOCKER_VERSION}" \
  "ansible.posix:==${ANSIBLE_POSIX_VERSION}"

# Smoke-test the proxmox-specific tools (ci-base smoke-tests the rest).
RUN echo "=== proxmox-infra CI layer ===" && \
  echo "tofu: $(tofu version | head -n1)" && \
  echo "ansible-lint: $(ansible-lint --version | head -n1)" && \
  echo "molecule: $(molecule --version | head -n1)" && \
  python3 -c "import molecule_plugins.docker" && echo "molecule docker driver: importable" && \
  echo "collections: $(ansible-galaxy collection list 2>/dev/null | grep -cE 'community.general|community.docker|ansible.posix') installed" && \
  echo "docker-compose: $(docker-compose --version)" && \
  echo "=============================="

WORKDIR /workspace
CMD ["/bin/bash"]
