# Unbound DNS Server - Custom Docker Image

Optimized Unbound DNS recursive resolver with custom-built OpenSSL, DNSSEC
validation, DNS-over-TLS forwarding, and dynamic resource allocation.

## Overview

This custom Docker image builds Unbound from source with:

- **Custom OpenSSL 3.6.1** - Built from source with security hardening and
  signature verification
- **Latest Unbound 1.24.2** - Compiled with full feature support
- **Multi-stage Build** - Minimal runtime image (~50MB) with BuildKit
  optimizations
- **Dynamic Configuration** - Auto-adapts to container CPU/memory resources
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

### Dynamic Configuration

Configuration is **generated at startup** based on detected resources:

```bash
# 2GB Container Example:
# - Reserved: 256MB (10% minimum)
# - Cache Budget: ~716MB (41% of total)
# - Distribution: RRset (50%), Msg (25%), Key (20%), Neg (5%)
# - Threads: Auto-detected from CPU cores

# 4GB Container Example:
# - Reserved: 400MB (10%)
# - Cache Budget: ~1.5GB (41% of total)
# - Auto-scales with available resources
```

All security settings, DNSSEC validation, and DNS-over-TLS configuration
remain consistent regardless of container size.

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
├── unbound.sh                              # Startup script with dynamic config generation
└── opt/unbound/etc/unbound/
    ├── unbound.conf                        # Main configuration (generated at startup)
    ├── a-records.conf                      # Local A and PTR records
    ├── srv-records.conf                    # SRV records
    └── forward-records.conf                # DNS-over-TLS forwarding
```

### DNS-over-TLS Upstreams

Configured to use encrypted DNS-over-TLS forwarding:

- **Quad9** - 9.9.9.9@853 (dns.quad9.net)
- **Cloudflare** - 1.1.1.1@853 (cloudflare-dns.com)

All upstream queries are encrypted using TLS 1.3 with strict certificate
validation.

### Environment Variables

Control dynamic configuration via environment variables:

```bash
# Cache sizing (percentage of available memory after reserved)
UNBOUND_CACHE_PERCENT=41        # Default: 41% of memory for cache

# Reserved memory (minimum 256MB or 10% of total)
UNBOUND_RESERVED_MB=256         # Override auto-calculation

# Thread configuration
UNBOUND_THREADS=auto            # auto, or specific number (1-8)

# Logging
UNBOUND_VERBOSITY=1             # 0-5, default: 1
```

### Local DNS Records

Add custom DNS records by mounting volumes:

```bash
docker run -d \
  --name unbound \
  -p 53:5053/tcp -p 53:5053/udp \
  -v /path/to/a-records.conf:/opt/unbound/etc/unbound/a-records.conf:ro \
  -v /path/to/srv-records.conf:/opt/unbound/etc/unbound/srv-records.conf:ro \
  unbound:latest
```

## Architecture

### Multi-Stage Build

1. **Stage 1: OpenSSL** - Build OpenSSL 3.6.0 from source with signature
   verification
2. **Stage 2: Unbound** - Build Unbound 1.24.2 with custom OpenSSL
3. **Stage 3: Runtime** - Minimal Debian Trixie Slim with only runtime
   dependencies

### Dynamic Resource Allocation

The `unbound.sh` startup script:

1. **Detects Resources** - Reads cgroup memory limits and CPU count
2. **Calculates Cache Budget**:

   ```bash
   reserved_mb = max(256MB, memory_limit / 10)
   cache_budget = (memory_limit - reserved) × cache_percentage / 100
   ```

3. **Distributes Cache**:
   - RRset cache: 50%
   - Message cache: 25%
   - Key cache: 20%
   - Negative cache: 5%
4. **Allocates Threads** - Based on CPU cores (1-8 threads)
5. **Generates Configuration** - Creates `unbound.conf` from template
6. **Starts Unbound** - With optimized settings

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

**Built with:** Docker BuildKit • Debian Trixie Slim • OpenSSL 3.6.0 •
Unbound 1.24.2
