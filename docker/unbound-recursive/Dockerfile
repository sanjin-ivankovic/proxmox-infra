# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e

# Build arguments for version control and base image selection
ARG DEBIAN_VERSION=trixie-slim
ARG OPENSSL_VERSION=3.6.5
ARG UNBOUND_VERSION=1.26.2

################################################################################
# Stage 1: Build OpenSSL from source with security hardening
################################################################################
FROM debian:${DEBIAN_VERSION} AS openssl

# Re-declare ARG after FROM to make it available in this stage
ARG OPENSSL_VERSION

ENV VERSION_OPENSSL=openssl-${OPENSSL_VERSION} \
    SHA256_OPENSSL=a2157c2830efdec3788939b00c9b0638306d3f0bbb76dc4832ee503bb397df98 \
    SOURCE_OPENSSL=https://www.openssl.org/source/ \
    # OpenSSL OMC
    OPGP_OPENSSL_1=EFC0A467D613CB83C7ED6D30D894E2CE8B3D79F5 \
    # Richard Levitte
    OPGP_OPENSSL_2=7953AC1FBC3DC8B3B292393ED5E9E43F7DF9EE8C \
    # Matt Caswell
    OPGP_OPENSSL_3=8657ABB260F056B1E5190839D9C4D26D0E604491 \
    # Paul Dale
    OPGP_OPENSSL_4=B7C1C14360F353A36862E4D5231C84CDDCC69C45 \
    # Tomas Mraz
    OPGP_OPENSSL_5=A21FAB74B0088AA361152586B8EF1A6BA9DA2D5C \
    # Tim Hudson
    OPGP_OPENSSL_6=C1F33DD8CE1D4CC613AF14DA9195C48241FBF7DD \
    # Kurt Roeckx
    OPGP_OPENSSL_7=E5E52560DD91C556DDBDA5D02064C53641C25E5D \
    # OpenSSL (key retired 2026-05; still verifies older tarballs)
    OPGP_OPENSSL_8=BA5473A2B0587B07FB27CF2D216094DFD0CB81EF \
    # OpenSSL (current release key, signs 3.6.4+)
    OPGP_OPENSSL_9=B146647E45A7B33947AB226B2A2C87D161692D40

WORKDIR /tmp/src

# Build OpenSSL with BuildKit cache mounts for faster rebuilds
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -e -x && \
    build_deps="build-essential ca-certificates curl dirmngr gnupg libidn2-0-dev libssl-dev" && \
    DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-recommends \
      $build_deps && \
    curl -sSL --retry 3 --retry-delay 5 $SOURCE_OPENSSL$VERSION_OPENSSL.tar.gz -o openssl.tar.gz && \
    echo "${SHA256_OPENSSL} ./openssl.tar.gz" | sha256sum -c - && \
    curl -sSL --retry 3 --retry-delay 5 $SOURCE_OPENSSL$VERSION_OPENSSL.tar.gz.asc -o openssl.tar.gz.asc && \
    GNUPGHOME="$(mktemp -d)" && \
    export GNUPGHOME && \
    ( gpg --no-tty --keyserver hkps://keys.openpgp.org --recv-keys "$OPGP_OPENSSL_1" "$OPGP_OPENSSL_2" "$OPGP_OPENSSL_3" "$OPGP_OPENSSL_4" "$OPGP_OPENSSL_5" "$OPGP_OPENSSL_6" "$OPGP_OPENSSL_7" "$OPGP_OPENSSL_8" "$OPGP_OPENSSL_9" || \
      gpg --no-tty --keyserver hkps://keyserver.ubuntu.com --recv-keys "$OPGP_OPENSSL_1" "$OPGP_OPENSSL_2" "$OPGP_OPENSSL_3" "$OPGP_OPENSSL_4" "$OPGP_OPENSSL_5" "$OPGP_OPENSSL_6" "$OPGP_OPENSSL_7" "$OPGP_OPENSSL_8" "$OPGP_OPENSSL_9" || \
      gpg --no-tty --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys "$OPGP_OPENSSL_1" "$OPGP_OPENSSL_2" "$OPGP_OPENSSL_3" "$OPGP_OPENSSL_4" "$OPGP_OPENSSL_5" "$OPGP_OPENSSL_6" "$OPGP_OPENSSL_7" "$OPGP_OPENSSL_8" "$OPGP_OPENSSL_9" ) && \
    gpg --batch --verify openssl.tar.gz.asc openssl.tar.gz && \
    tar xzf openssl.tar.gz && \
    cd $VERSION_OPENSSL && \
    ./config \
      --prefix=/opt/openssl \
      --openssldir=/opt/openssl \
      no-weak-ssl-ciphers \
      no-ssl3 \
      no-shared \
      enable-ec_nistp_64_gcc_128 \
      -DOPENSSL_NO_HEARTBEATS \
      -fstack-protector-strong && \
    make depend && \
    nproc | xargs -I % make -j% && \
    make install_sw && \
    apt-get purge -y --auto-remove \
      $build_deps && \
    rm -rf \
        /tmp/* \
        /var/tmp/*

################################################################################
# Stage 2: Build Unbound from source
################################################################################
FROM debian:${DEBIAN_VERSION} AS unbound

# Re-declare ARGs after FROM
ARG UNBOUND_VERSION

ENV NAME=unbound \
    UNBOUND_VERSION=${UNBOUND_VERSION} \
    UNBOUND_SHA256=d8ee7aa6bbb3ff1be7d9e57637d0d0ec2f18273a8efff1a0afe2c665858b96f7

WORKDIR /tmp/src

# Copy compiled OpenSSL from previous stage
COPY --from=openssl /opt/openssl /opt/openssl

# Build Unbound with BuildKit cache mounts
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    build_deps="curl gcc libc-dev libevent-dev libexpat1-dev libnghttp2-dev make" && \
    set -x && \
    DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-recommends \
      $build_deps \
      bsdmainutils \
      ca-certificates \
      ldnsutils \
      libevent-2.1-7 \
      libexpat1 \
      libprotobuf-c-dev \
      protobuf-c-compiler && \
    curl -sSL https://nlnetlabs.nl/downloads/unbound/unbound-${UNBOUND_VERSION}.tar.gz -o unbound.tar.gz && \
    echo "${UNBOUND_SHA256} *unbound.tar.gz" | sha256sum -c - && \
    tar xzf unbound.tar.gz && \
    rm -f unbound.tar.gz && \
    cd unbound-${UNBOUND_VERSION} && \
    ./configure \
        --disable-dependency-tracking \
        --prefix=/opt/unbound \
        --with-pthreads \
        --with-username=_unbound \
        --with-ssl=/opt/openssl \
        --with-libevent \
        --with-libnghttp2 \
        --enable-dnstap \
        --enable-tfo-server \
        --enable-tfo-client \
        --enable-event-api \
        --enable-subnet && \
    make install && \
    mv /opt/unbound/etc/unbound/unbound.conf /opt/unbound/etc/unbound/unbound.conf.example && \
    apt-get purge -y --auto-remove \
      $build_deps && \
    rm -rf \
        /opt/unbound/share/man \
        /tmp/* \
        /var/tmp/*

################################################################################
# Stage 3: Final runtime image
################################################################################
FROM debian:${DEBIAN_VERSION}

# Re-declare ARG for metadata
ARG UNBOUND_VERSION

ENV NAME=unbound
ENV SUMMARY="${NAME} is a validating, recursive, and caching DNS resolver." \
    DESCRIPTION="${NAME} is a validating, recursive, and caching DNS resolver."

# Copy compiled artifacts from build stage
COPY --from=unbound /opt /opt

# Copy configuration files. unbound.conf is the static, version-controlled main
# config (also bind-mountable for on-the-fly edits); a-records.conf /
# srv-records.conf are optional templates. The resource-tuned dynamic.conf is
# generated at startup by unbound.sh. There is no forward-records.conf: this
# image recurses from the root servers instead of forwarding to an upstream.
COPY --chmod=644 data/opt/unbound/etc/unbound/unbound.conf \
                 data/opt/unbound/etc/unbound/a-records.conf \
                 data/opt/unbound/etc/unbound/srv-records.conf \
                 /opt/unbound/etc/unbound/

# Install runtime dependencies, create user, and clean up
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -x && \
    DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-recommends \
      bsdmainutils \
      ca-certificates \
      ldnsutils \
      libevent-2.1-7 \
      libnghttp2-14 \
      libexpat1 \
      libprotobuf-c1 && \
    groupadd _unbound && \
    useradd -g _unbound -s /dev/null -d /etc _unbound && \
    rm -rf \
        /tmp/* \
        /var/tmp/*

# Copy entrypoint script with execute permissions
COPY --chmod=755 data/unbound.sh /unbound.sh

WORKDIR /opt/unbound/

# Add unbound binaries to PATH
ENV PATH=/opt/unbound/sbin:"$PATH"

# Expose DNS ports (5335 for the co-located Pi-hole)
EXPOSE 5335/tcp
EXPOSE 5335/udp

# Health check using drill to verify DNS resolution (port 5335)
HEALTHCHECK --interval=30s --timeout=30s --start-period=10s --retries=3 \
    CMD drill @127.0.0.1 -p 5335 cloudflare.com || exit 1

# Consolidated labels following OCI image spec
LABEL maintainer="Maintainer Name" \
      org.opencontainers.image.version="${UNBOUND_VERSION}" \
      org.opencontainers.image.title="example/unbound-recursive" \
      org.opencontainers.image.description="a validating, recursive, and caching DNS resolver" \
      org.opencontainers.image.url="https://source.example.com/homelab/unbound-docker" \
      org.opencontainers.image.vendor="Maintainer Name" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://source.example.com/homelab/unbound-docker"

CMD ["/unbound.sh"]
