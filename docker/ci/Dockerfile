# syntax=docker/dockerfile:1@sha256:b6afd42430b15f2d2a4c5a02b919e98a525b785b1aaff16747d2f623364e39b6

# Base image version (can be overridden at build time)
ARG DOCKER_VERSION=29.2.1-cli@sha256:1d6d751f1d68d1a5142c23c730ef5ecc976a8e050fa08c3cdb09f7e2e54a4439

FROM docker:${DOCKER_VERSION}

# Metadata
LABEL maintainer="maintainer@example.io"
LABEL org.opencontainers.image.title="proxmox-infra-ci"
LABEL org.opencontainers.image.description="CI image with tools for Proxmox infrastructure management"
LABEL org.opencontainers.image.source="https://gitlab.example.com/homelab/proxmox-infra"
LABEL org.opencontainers.image.licenses="MIT"

# Binary tools
ARG SHELLCHECK_VERSION
ARG GITLEAKS_VERSION

# Python packages
ARG PYYAML_VERSION
ARG TQDM_VERSION
ARG YAMLLINT_VERSION
ARG PYTEST_VERSION
ARG PYTEST_COV_VERSION

# npm packages
ARG MARKDOWNLINT_VERSION

# Install base tools from Alpine packages
RUN apk add --no-cache \
  bash \
  git \
  coreutils \
  yq \
  openssh-client \
  jq \
  rsync \
  docker-cli-compose \
  python3 \
  py3-pip \
  nodejs \
  npm \
  curl

# Install ShellCheck
RUN SHELLCHECK_ARCH="x86_64" && \
  curl -fLs "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.${SHELLCHECK_ARCH}.tar.xz" | tar xJ && \
  mv "shellcheck-${SHELLCHECK_VERSION}/shellcheck" /usr/local/bin/ && \
  rm -rf "shellcheck-${SHELLCHECK_VERSION}" && \
  shellcheck --version

# Install Gitleaks
RUN curl -fLs "https://github.com/gitleaks/gitleaks/releases/download/${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION#v}_linux_x64.tar.gz" | tar xz && \
  mv gitleaks /usr/local/bin/ && \
  gitleaks version

# Install Python packages for pipeline generation and sanitization
RUN pip3 install --no-cache-dir --break-system-packages \
  "pyyaml==${PYYAML_VERSION}" \
  "tqdm==${TQDM_VERSION}" \
  "yamllint==${YAMLLINT_VERSION}" \
  "pytest==${PYTEST_VERSION}" \
  "pytest-cov==${PYTEST_COV_VERSION}"

# Install npm packages for linting
RUN npm install -g "markdownlint-cli2@${MARKDOWNLINT_VERSION}" && \
  npm cache clean --force && \
  markdownlint-cli2 --version

# Verify all tools are installed
RUN echo "=== Installed Tools ===" && \
  echo "shellcheck: $(shellcheck --version | grep version)" && \
  echo "gitleaks: $(gitleaks version)" && \
  echo "yamllint: $(yamllint --version)" && \
  echo "markdownlint-cli2: $(markdownlint-cli2 --version 2>&1 | head -n1)" && \
  echo "python3: $(python3 --version)" && \
  echo "docker: $(docker --version)" && \
  echo "docker-compose: $(docker-compose --version)" && \
  echo "======================="

WORKDIR /workspace

CMD ["/bin/bash"]
