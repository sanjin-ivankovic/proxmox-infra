# Unbound DNS Server - Custom Docker Image

Optimized Unbound DNS resolver with custom-built OpenSSL, DNSSEC validation,
DNS-over-TLS forwarding to Quad9, and resource-aware cache sizing. This instance
forwards all queries to Quad9 over DoT rather than recursing from the root.

## Overview

This custom Docker image builds Unbound from source with:

- **Custom OpenSSL 3.6.2** - Built from source with security hardening and
  signature verification
- **Unbound 1.25.1** - Compiled with full feature support
- **Multi-stage Build** - Minimal runtime image with BuildKit optimizations
- **Version-controlled config** - A static, annotated `unbound.conf` (editable
  and bind-mountable); only resource-tuned values are generated at startup
- **Production Ready** - DNSSEC validation, DNS-over-TLS, comprehensive
  security hardening

## Key Features

### Security Hardening

- ✅ **DNSSEC Validation** - Full DNSSEC validation with automatic trust
  anchor updates
- ✅ **DNS-over-TLS (DoT)** - Encrypted upstream queries to Quad9 and
  Cloudflare
- ✅ **Query Privacy** - QNAME minimization (RFC 7816) to minimize
  information leakage
- ✅ **Anti-Spoofing** - 0x20 encoding for query randomization
- ✅ **Attack Mitigation**:
  - Refuses ANY queries (prevents amplification attacks)
  - Harden-glue, harden-dnssec-stripped, harden-below-nxdomain
  - Rate limiting (1000 queries/second per nameserver)
- ✅ **Privacy Protection**:
  - Hides server identity and version
  - Private address filtering (RFC 1918)
  - Aggressive NSEC caching (RFC 8198)

### Performance Optimization

- **Dynamic Resource Allocation** - Automatically adapts cache sizes and
  thread count based on container resources
- **Intelligent Caching**:
  - RRset, message, key, and negative caching with optimized sizes
  - Prefetching enabled for both records and DNSSEC keys
  - Serve expired records during upstream failures (RFC 8767)
- **Optimized Thread/Slab Configuration** - Auto-detects CPU cores and
  allocates threads
- **BuildKit Cache Mounts** - Faster rebuilds with layer caching

### Static config + generated resource tuning

The main `unbound.conf` is a **static, version-controlled, fully annotated
file** under `data/opt/unbound/etc/unbound/`. At container start, `unbound.sh`
detects CPU/memory and writes **only** the resource-tuned values to
`dynamic.conf`, which `unbound.conf` pulls in via `include:` inside its
`server:` clause:

- `num-threads` and the `*-cache-slabs` (a power of 2 near the thread count)
- `rrset` / `msg` / `key` / `neg` cache sizes, split **50% / 25% / 10% / 15%**
  of the cache budget (keeps the docs' `rrset ~= 2x msg` ratio; the negative
  cache is enlarged because `aggressive-nsec` synthesises negatives from cached
  NSEC)

```bash
# Example, ~2GB container at the default 40% cache budget:
# - Reserved:     256MB (10% minimum)
# - Cache budget: ~717MB
# - rrset ~358MB / msg ~179MB / key ~71MB / neg ~107MB
# - Threads:      auto-detected from CPU cores
```

All security settings, DNSSEC validation, and DNS-over-TLS forwarding live in
the static `unbound.conf` and stay consistent regardless of container size.

## Quick Start

### Build

```bash
cd docker/unbound
DOCKER_BUILDKIT=1 docker build -t unbound:latest .
```

### Build with Custom Versions

```bash
DOCKER_BUILDKIT=1 docker build \
  --build-arg OPENSSL_VERSION=3.6.1 \
  --build-arg UNBOUND_VERSION=1.24.2 \
  --build-arg DEBIAN_VERSION=trixie-slim \
  -t unbound:1.24.2 .
```

### Run

```bash
docker run -d \
  --name unbound \
  -p 53:5053/tcp \
  -p 53:5053/udp \
  --restart unless-stopped \
  unbound:latest
```

### Run with Custom Resources

```bash
docker run -d \
  --name unbound \
  -p 53:5053/tcp \
  -p 53:5053/udp \
  --memory=4g \
  --cpus=4 \
  --restart unless-stopped \
  unbound:latest
```

Configuration will automatically adapt to the allocated resources.

## Configuration

### Directory Structure

```text
data/
├── unbound.sh                  # Entrypoint: detects resources, writes dynamic.conf
└── opt/unbound/etc/unbound/
    ├── unbound.conf            # Main config (static, version-controlled, annotated)
    ├── dynamic.conf            # Generated at startup (threads + cache sizes/slabs)
    ├── a-records.conf          # Local A and PTR records (optional template)
    ├── srv-records.conf        # SRV records (optional template)
    └── forward-records.conf    # DNS-over-TLS forwarding to Quad9
```

`dynamic.conf` is created at container start and is not committed; everything
else is version-controlled. `unbound.conf` includes both `dynamic.conf` and
`forward-records.conf`.

### DNS-over-TLS Upstreams

Configured to use encrypted DNS-over-TLS forwarding:

- **Quad9** - 9.9.9.9@853 (dns.quad9.net)
- **Cloudflare** - 1.1.1.1@853 (cloudflare-dns.com)

All upstream queries are encrypted using TLS 1.3 with strict certificate
validation.

### Environment Variables

`unbound.sh` reads two variables to tune `dynamic.conf`:

```bash
# Percentage of available memory (after the reserved headroom) used for cache.
# Validated to 1-90; falls back to 40 if unset or out of range.
UNBOUND_CACHE_PERCENTAGE=40

# Number of resolver threads. Defaults to the detected CPU count (nproc).
# Cache slabs are derived as the nearest power of 2 <= the thread count.
UNBOUND_THREADS=4
```

Everything else is set in the static `unbound.conf`. To change a non-tunable
setting, edit that file (see [Updating the config](#updating-the-config)).

### Local DNS Records

Add custom DNS records by mounting volumes:

```bash
docker run -d \
  --name unbound \
  --network host \
  -v /path/to/a-records.conf:/opt/unbound/etc/unbound/a-records.conf:ro \
  -v /path/to/srv-records.conf:/opt/unbound/etc/unbound/srv-records.conf:ro \
  unbound:latest
```

Then uncomment the matching `include:` lines for `a-records.conf` /
`srv-records.conf` in `unbound.conf`.

### Updating the config

In the homelab, both `unbound-1` and `unbound-2` bind-mount `unbound.conf` and
`forward-records.conf` read-only from this repo (see the `adguard-*` compose
files under `services/`). The loop to change a setting is:

1. Edit `data/opt/unbound/etc/unbound/unbound.conf` (or `forward-records.conf`).
2. Validate it (see [Testing](#testing)).
3. Commit and push to `main`.
4. Komodo redeploys the `adguard-*` stacks and restarts the containers with the
   new config.

No image rebuild is needed for config changes; rebuild only for an Unbound or
OpenSSL version bump. Because the files are mounted read-only, a malformed
config fails fast at container start rather than being silently regenerated.

## Architecture

### Multi-Stage Build

1. **Stage 1: OpenSSL** - Build OpenSSL 3.6.2 from source with signature
   verification
2. **Stage 2: Unbound** - Build Unbound 1.25.1 with custom OpenSSL
3. **Stage 3: Runtime** - Minimal Debian Trixie Slim with only runtime
   dependencies

### Dynamic Resource Allocation

The `unbound.sh` startup script:

1. **Detects Resources** - Reads cgroup memory limits and CPU count
2. **Calculates Cache Budget**:

   ```text
   reserved_mb   = max(256MB, memory_limit / 10)
   cache_budget  = (memory_limit - reserved) * cache_percentage / 100
   ```

3. **Distributes Cache**:
   - RRset cache: 50%
   - Message cache: 25%
   - Key cache: 10%
   - Negative cache: 15%
4. **Allocates Threads** - Defaults to the detected CPU count (`nproc`)
5. **Writes `dynamic.conf`** - The only generated file, pulled in by
   `unbound.conf`
6. **Starts Unbound** - In the foreground with the static `unbound.conf`

### Security Verification

OpenSSL build includes PGP signature verification against trusted keys:

- **OpenSSL OMC** - EFC0A467D613CB83C7ED6D30D894E2CE8B3D79F5
- **Richard Levitte** - 7953AC1FBC3DC8B3B292393ED5E9E43F7DF9EE8C
- **Matt Caswell** - 8657ABB260F056B1E5190839D9C4D26D0E604491
- **Paul Dale** - B7C1C14360F353A36862E4D5231C84CDDCC69C45
- **Tomas Mraz** - A21FAB74B0088AA361152586B8EF1A6BA9DA2D5C

Unbound build verifies against NLnet Labs PGP keys.

## Deployment Recommendations

### Platform: LXC vs VM

#### Recommended: LXC Container

For DNS workloads, LXC provides superior performance:

| Metric                  | LXC                 | VM               | Advantage |
| ----------------------- | ------------------- | ---------------- | --------- |
| **Latency**             | ~0.5-2ms lower      | Baseline         | **LXC**   |
| **Network Performance** | Native kernel stack | Virtualized NIC  | **LXC**   |
| **Resource Efficiency** | Minimal overhead    | Hypervisor layer | **LXC**   |
| **Boot Time**           | Seconds             | Minutes          | **LXC**   |

DNS queries are latency-sensitive and network I/O intensive, making LXC's
direct kernel access ideal.

### Resource Guidelines

<!-- markdownlint-disable MD013 -->

| Container Size  | Use Case                | Cache Budget | Concurrent Queries |
| --------------- | ----------------------- | ------------ | ------------------ |
| 2GB RAM, 2 CPUs | Home/Small Office       | ~700MB       | ~5,000             |
| 4GB RAM, 4 CPUs | SMB/Branch Office       | ~1.5GB       | ~15,000            |
| 8GB RAM, 8 CPUs | Enterprise/High Traffic | ~3.2GB       | ~40,000+           |

<!-- markdownlint-enable MD013 -->

Configuration automatically adapts to allocated resources.

## BuildKit Optimizations

The Dockerfile uses BuildKit features for optimal build performance:

```text
# Syntax directive enables BuildKit
# syntax=docker/dockerfile:1

# Cache mounts for faster rebuilds
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y ...
```

**Benefits:**

- Persistent package cache across builds
- Parallel dependency resolution
- Layer caching with cache invalidation
- ~60% faster rebuilds

## Testing

### Verify DNSSEC

```bash
docker exec unbound unbound-host -C /opt/unbound/etc/unbound/unbound.conf -v sigok.verteiltesysteme.net
```

Expected: `sigok.verteiltesysteme.net has address 134.91.78.139 (secure)`

### Check DNS-over-TLS

```bash
docker exec unbound unbound-control status
docker logs unbound | grep -i tls
```

### Query Performance

```bash
dig @localhost -p 53 example.com
dig @localhost -p 53 example.com  # Should be cached, faster response
```

## License

Part of the proxmox-infra repository. See repository root for license
information.

---

**Built with:** Docker BuildKit, Debian Trixie Slim, OpenSSL 3.6.2,
Unbound 1.25.1
