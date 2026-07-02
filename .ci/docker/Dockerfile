# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
#
# proxmox-infra-ci — CI image for the Proxmox infrastructure pipeline.
#
# THIN LAYER over the shared ci-base (homelab/ci-components): ci-base already
# carries the common toolchain (git, gitleaks, cosign, shellcheck, yamllint,
# markdownlint-cli2, pytest/pyyaml, trivy, yq, docker CLI) + the publish/sanitize
# tooling at /opt/ci. This image only adds what is proxmox-specific: terraform,
# ansible-lint (+ collections), and a few apk extras (jq, rsync,
# docker-cli-compose).
#
# Non-obvious by design (don't "fix" without reading the README):
#   - runs as root, no USER/HEALTHCHECK — ephemeral CI pods, root-writable cache
#   - the ci-base ref is tag@sha256:<digest> so Renovate pins the digest (a
#     ci-base rebuild lands here as a digest-bump PR, never silently)

# renovate: datasource=docker depName=docker versioning=docker
ARG DOCKER_VERSION=29.6.1-cli@sha256:862099ada15c669000bef53aa4cb9d821262829f45b0dda2159ccb276443043b

# fetcher: download + checksum-verify terraform, one RUN so a Renovate bump only
# busts that layer. curl/unzip live here only — never in the final image.
FROM docker:${DOCKER_VERSION} AS fetcher
# renovate: datasource=github-releases depName=hashicorp/terraform
ARG TERRAFORM_VERSION=1.15.7
RUN apk add --no-cache curl unzip && mkdir -p /out/usr/local/bin
RUN cd /tmp && \
  curl -fsSL -O "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" && \
  curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" \
    | grep "terraform_${TERRAFORM_VERSION}_linux_amd64.zip" | sha256sum -c - && \
  unzip -o "terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -d /out/usr/local/bin/ && \
  /out/usr/local/bin/terraform version

# --- final image: ci-base + the proxmox-specific layer ---
# renovate: datasource=docker depName=registry.example.com/homelab/ci-components/ci
FROM registry.example.com/homelab/ci-components/ci:latest@sha256:0644363cfe512c3858cf719485b5d8bb37c61951581d130d3f31628513f7d6e0

LABEL maintainer="maintainer@example.io"
LABEL org.opencontainers.image.title="proxmox-infra-ci"
LABEL org.opencontainers.image.description="CI image: ci-base + Terraform, Ansible for Proxmox infrastructure"
LABEL org.opencontainers.image.source="https://source.example.com/example-org/proxmox-infra"
LABEL org.opencontainers.image.licenses="MIT"

# renovate: datasource=pypi depName=ansible-lint
ARG ANSIBLE_LINT_VERSION=26.4.0
# Molecule + its Docker driver back the test:molecule job (role converge +
# idempotence + verify). The Docker driver talks to the host Docker socket the
# runner mounts. molecule-plugins[docker] pulls in the docker Python SDK.
# renovate: datasource=pypi depName=molecule
ARG MOLECULE_VERSION=26.4.0
# renovate: datasource=pypi depName=molecule-plugins
ARG MOLECULE_PLUGINS_VERSION=25.8.12
# Ansible collections are pinned here (not from the repo-root
# ansible/requirements.yml, which is outside this build context); they back
# ansible-lint's syntax-check. Keep in sync with that file.
# renovate: datasource=galaxy-collection depName=kubernetes.core
ARG KUBERNETES_CORE_VERSION=6.4.0
# renovate: datasource=galaxy-collection depName=community.general
ARG COMMUNITY_GENERAL_VERSION=13.1.0
# renovate: datasource=galaxy-collection depName=community.docker
ARG COMMUNITY_DOCKER_VERSION=5.2.1
# renovate: datasource=galaxy-collection depName=ansible.posix
ARG ANSIBLE_POSIX_VERSION=2.2.0

# apk extras not in ci-base: jq, rsync, docker-cli-compose.
RUN apk add --no-cache jq rsync docker-cli-compose

# terraform from the staged build layer.
COPY --from=fetcher /out/usr/local/bin/terraform /usr/local/bin/

# ansible-lint (pyyaml already in ci-base) + molecule with its Docker driver.
RUN pip3 install --no-cache-dir --break-system-packages \
  "ansible-lint==${ANSIBLE_LINT_VERSION}" \
  "molecule==${MOLECULE_VERSION}" \
  "molecule-plugins[docker]==${MOLECULE_PLUGINS_VERSION}"
RUN ansible-galaxy collection install --no-cache \
  "kubernetes.core:==${KUBERNETES_CORE_VERSION}" \
  "community.general:==${COMMUNITY_GENERAL_VERSION}" \
  "community.docker:==${COMMUNITY_DOCKER_VERSION}" \
  "ansible.posix:==${ANSIBLE_POSIX_VERSION}"

# Smoke-test the proxmox-specific tools (ci-base smoke-tests the rest).
RUN echo "=== proxmox-infra CI layer ===" && \
  echo "terraform: $(terraform version | head -n1)" && \
  echo "ansible-lint: $(ansible-lint --version | head -n1)" && \
  echo "molecule: $(molecule --version | head -n1)" && \
  python3 -c "import molecule_plugins.docker" && echo "molecule docker driver: importable" && \
  echo "collections: $(ansible-galaxy collection list 2>/dev/null | grep -cE 'kubernetes.core|community.general|community.docker|ansible.posix') installed" && \
  echo "docker-compose: $(docker-compose --version)" && \
  echo "=============================="

WORKDIR /workspace
CMD ["/bin/bash"]
