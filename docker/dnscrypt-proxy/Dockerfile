# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
# Dockerfile for dnscrypt-proxy — encrypted DNS proxy with Anonymized DNS support
# Rebuild bump 2026-05-19: post-Harbor-wipe, repopulate :<semver> tag.

# Build arguments for version control and base image selection
ARG DEBIAN_VERSION=trixie-slim@sha256:28de0877c2189802884ccd20f15ee41c203573bd87bb6b883f5f46362d24c5c2
ARG DNSCRYPT_PROXY_VERSION=2.1.16

################################################################################
# Stage 1: Download and verify pre-built binary
################################################################################
FROM debian:${DEBIAN_VERSION} AS download

ARG DNSCRYPT_PROXY_VERSION

ENV DNSCRYPT_PROXY_VERSION=${DNSCRYPT_PROXY_VERSION} \
  DNSCRYPT_PROXY_SHA256=a327b28648b59783ecc4aa2c386543fc08ffa1a11f69c6028af5778771f8a41f \
  DNSCRYPT_PROXY_URL=https://github.com/DNSCrypt/dnscrypt-proxy/releases/download

WORKDIR /tmp/src

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
  set -e -x && \
  DEBIAN_FRONTEND=noninteractive apt-get update && \
  apt-get install -y --no-install-recommends ca-certificates curl && \
  curl -sSL --retry 3 --retry-delay 5 \
  "${DNSCRYPT_PROXY_URL}/${DNSCRYPT_PROXY_VERSION}/dnscrypt-proxy-linux_x86_64-${DNSCRYPT_PROXY_VERSION}.tar.gz" \
  -o dnscrypt-proxy.tar.gz && \
  echo "${DNSCRYPT_PROXY_SHA256}  dnscrypt-proxy.tar.gz" | sha256sum -c - && \
  tar xzf dnscrypt-proxy.tar.gz && \
  mv linux-x86_64/dnscrypt-proxy /usr/local/bin/dnscrypt-proxy && \
  chmod 755 /usr/local/bin/dnscrypt-proxy

################################################################################
# Stage 2: Final runtime image
################################################################################
FROM debian:${DEBIAN_VERSION}

ARG DNSCRYPT_PROXY_VERSION

# Copy binary from download stage
COPY --from=download /usr/local/bin/dnscrypt-proxy /usr/local/bin/dnscrypt-proxy

# Copy entrypoint script
COPY --chmod=755 data/entrypoint.sh /entrypoint.sh

# Install runtime dependencies and create non-root user
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
  set -x && \
  DEBIAN_FRONTEND=noninteractive apt-get update && \
  apt-get install -y --no-install-recommends ca-certificates && \
  groupadd -r dnscrypt && \
  useradd -r -g dnscrypt -s /bin/false -d /var/cache/dnscrypt-proxy dnscrypt && \
  mkdir -p /var/cache/dnscrypt-proxy && \
  chown -R dnscrypt:dnscrypt /var/cache/dnscrypt-proxy && \
  rm -rf /tmp/* /var/tmp/*

# Copy configuration after user creation so ownership can be set correctly
COPY --chmod=644 --chown=dnscrypt:dnscrypt data/dnscrypt-proxy.toml /var/cache/dnscrypt-proxy/dnscrypt-proxy.toml

WORKDIR /var/cache/dnscrypt-proxy

# Run as non-root user (port 5354 is unprivileged)
USER dnscrypt

# Expose DNS port (5354 for co-located Unbound setup) and monitoring UI
EXPOSE 5354/tcp
EXPOSE 5354/udp
EXPOSE 8080/tcp

# Health check using dnscrypt-proxy's built-in resolve command
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD dnscrypt-proxy -resolve example.com -config /var/cache/dnscrypt-proxy/dnscrypt-proxy.toml | grep -q "." || exit 1

# Consolidated labels following OCI image spec
LABEL maintainer="Maintainer Name" \
  org.opencontainers.image.version="${DNSCRYPT_PROXY_VERSION}" \
  org.opencontainers.image.title="example/dnscrypt-proxy" \
  org.opencontainers.image.description="Encrypted DNS proxy with Anonymized DNS support" \
  org.opencontainers.image.url="https://github.com/DNSCrypt/dnscrypt-proxy" \
  org.opencontainers.image.vendor="Maintainer Name" \
  org.opencontainers.image.licenses="ISC" \
  org.opencontainers.image.source="https://source.example.com/example-org/proxmox-infra"

CMD ["/entrypoint.sh"]

#
