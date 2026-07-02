#!/usr/bin/env bash
# Renovate post-upgrade hook: refresh tarball SHA256 in the Dockerfile(s).
#
# Renovate updates the version ARG (e.g. UNBOUND_VERSION=1.25.0) but cannot
# update the matching tarball SHA256, so the build fails the integrity check.
# This script downloads the new tarball, computes its SHA256, and rewrites the
# corresponding *_SHA256 line in every matching Dockerfile. The unbound and
# openssl components span both docker/unbound and docker/unbound-recursive.
#
# Usage: scripts/renovate-update-sha256.sh <component> <new-version>
#   component:   unbound | openssl | dnscrypt-proxy
#   new-version: e.g. 1.25.0 or 3.6.2 (no leading 'v')

set -euo pipefail

COMPONENT="${1:-}"
NEW_VERSION="${2:-}"

if [[ -z "${COMPONENT}" || -z "${NEW_VERSION}" ]]; then
    echo "Usage: $0 <component> <new-version>" >&2
    echo "  component:   unbound | openssl | dnscrypt-proxy" >&2
    exit 2
fi

# unbound and unbound-recursive are independent from-source builds that pin the
# SAME upstream tarball, so a version bump rewrites the SHA256 in both.
case "${COMPONENT}" in
    unbound)
        DOCKERFILES=("docker/unbound/Dockerfile" "docker/unbound-recursive/Dockerfile")
        TARBALL_URL="https://nlnetlabs.nl/downloads/unbound/unbound-${NEW_VERSION}.tar.gz"
        SHA_VAR="UNBOUND_SHA256"
        ;;
    openssl)
        DOCKERFILES=("docker/unbound/Dockerfile" "docker/unbound-recursive/Dockerfile")
        TARBALL_URL="https://www.openssl.org/source/openssl-${NEW_VERSION}.tar.gz"
        SHA_VAR="SHA256_OPENSSL"
        ;;
    dnscrypt-proxy)
        DOCKERFILES=("docker/dnscrypt-proxy/Dockerfile")
        TARBALL_URL="https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/${NEW_VERSION}/dnscrypt-proxy-linux_x86_64-${NEW_VERSION}.tar.gz"
        SHA_VAR="DNSCRYPT_PROXY_SHA256"
        ;;
    *)
        echo "ERROR: Unknown component '${COMPONENT}' (expected: unbound | openssl | dnscrypt-proxy)" >&2
        exit 2
        ;;
esac

for DOCKERFILE in "${DOCKERFILES[@]}"; do
    if [[ ! -f "${DOCKERFILE}" ]]; then
        echo "ERROR: ${DOCKERFILE} not found (cwd: $(pwd))" >&2
        exit 1
    fi
    if ! grep -qE "^[[:space:]]*${SHA_VAR}=" "${DOCKERFILE}"; then
        echo "ERROR: ${SHA_VAR}= line not found in ${DOCKERFILE}" >&2
        exit 1
    fi
done

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

echo "→ Downloading ${TARBALL_URL}"
if ! curl -fsSL --retry 3 --retry-delay 5 "${TARBALL_URL}" -o "${WORKDIR}/tarball.tar.gz"; then
    echo "ERROR: Failed to download ${TARBALL_URL}" >&2
    exit 1
fi

NEW_SHA="$(sha256sum "${WORKDIR}/tarball.tar.gz" | awk '{print $1}')"
if [[ ! "${NEW_SHA}" =~ ^[a-f0-9]{64}$ ]]; then
    echo "ERROR: Computed SHA256 looks invalid: '${NEW_SHA}'" >&2
    exit 1
fi
echo "→ New SHA256: ${NEW_SHA}"

# Rewrite the SHA256 in each target Dockerfile (idempotent per file).
for DOCKERFILE in "${DOCKERFILES[@]}"; do
    OLD_SHA="$(grep -E "^[[:space:]]*${SHA_VAR}=" "${DOCKERFILE}" \
        | head -1 \
        | sed -E "s/.*${SHA_VAR}=([a-f0-9]+).*/\1/")"

    if [[ "${OLD_SHA}" == "${NEW_SHA}" ]]; then
        echo "→ ${SHA_VAR} already up-to-date in ${DOCKERFILE}, no changes."
        continue
    fi

    # Cross-platform sed -i: GNU sed (Linux/Renovate container) needs no suffix
    # arg; BSD sed (macOS local testing) needs '' after -i. Use a portable
    # approach: write to a tmp file then move into place.
    TMPFILE="$(mktemp)"
    sed -E "s/^([[:space:]]*${SHA_VAR}=)[a-f0-9]+/\1${NEW_SHA}/" "${DOCKERFILE}" > "${TMPFILE}"
    mv "${TMPFILE}" "${DOCKERFILE}"

    # Verify the rewrite landed.
    if ! grep -qE "^[[:space:]]*${SHA_VAR}=${NEW_SHA}" "${DOCKERFILE}"; then
        echo "ERROR: Failed to update ${SHA_VAR} in ${DOCKERFILE}" >&2
        exit 1
    fi

    echo "✓ Updated ${SHA_VAR} (${OLD_SHA:0:12}… → ${NEW_SHA:0:12}…) in ${DOCKERFILE}"
done
