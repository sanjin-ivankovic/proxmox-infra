# Unbound DNS Server (recursive) - Custom Docker Image

Optimized Unbound DNS resolver with custom-built OpenSSL, DNSSEC validation,
and resource-aware cache sizing. This variant **recurses from the root
servers** itself - it does not forward to any upstream.

It is the recursive sibling of [`docker/unbound/`](../unbound/), the
DNS-over-TLS forwarder to an encrypted upstream resolver. Both are
kept side-by-side so the upstream strategy can be switched deliberately. The
forwarder is the **currently active deployment**; this recursive image is
**available but not deployed**. See
[Switching to recursive](#switching-to-recursive).

## Forwarder vs recursive - the tradeoffs

<!-- markdownlint-disable MD013 -->

| | `unbound` (forwarder) | `unbound-recursive` (this image) |
| --- | --- | --- |
| Upstream | Encrypted DoT to an upstream resolver | Root -> TLD -> authoritative servers |
| On-path privacy | ISP sees only encrypted DoT to the upstream | Queries to authoritatives are **plaintext** (ISP/on-path can observe) |
| Trust | The upstream resolver sees all forwarded queries | No single resolver sees everything |
| Egress | Outbound TCP/853 to the upstream | Outbound **UDP+TCP/53 to the whole internet** (host firewall must allow it) |
| DNSSEC | Validated locally | Validated locally |

<!-- markdownlint-enable MD013 -->

Both listen on `127.0.0.1:5335` (AdGuard's upstream), so switching needs no
AdGuard change. This variant is **IPv4-only** (`do-ip6: no`) to match the
homelab.

## Overview

This custom Docker image builds Unbound from source with:

- **Custom OpenSSL 3.6.2** - Built from source with security hardening and
  signature verification
- **Unbound 1.25.1** - Compiled with full feature support
- **Multi-stage Build** - Minimal runtime image with BuildKit optimizations
- **Version-controlled config** - A static, annotated `unbound.conf` (editable
  and bind-mountable); only resource-tuned values are generated at startup
- **Recursive + validating** - `module-config: "validator iterator"`, recursing
  from the root with full DNSSEC validation

## Static config + generated resource tuning

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

Compared with the forwarder config, the recursive config drops the
`forward-records.conf` include and the `tls-cert-bundle` (no DoT upstream),
uses Unbound's built-in root hints, and re-activates the recursion-path knobs
that are inert when forwarding (`use-caps-for-id`, `ratelimit`,
`unwanted-reply-threshold`, `fast-server-*`, glue/referral hardening). Each
setting is annotated inline.

### Directory structure

```text
data/
├── unbound.sh                  # Entrypoint: detects resources, writes dynamic.conf
└── opt/unbound/etc/unbound/
    ├── unbound.conf            # Main config (static, recursive, annotated)
    ├── dynamic.conf            # Generated at startup (threads + cache sizes/slabs)
    ├── a-records.conf          # Local A and PTR records (optional template)
    ├── srv-records.conf        # SRV records (optional template)
    └── .gitignore              # ignores dynamic.conf, unbound.sock, var/
```

There is no `forward-records.conf` - recursion is handled by the `iterator`
module. `dynamic.conf` is generated at container start and not committed.

### Environment variables

`unbound.sh` reads two variables to tune `dynamic.conf`:

```bash
# Percentage of available memory (after the reserved headroom) used for cache.
# Validated to 1-90; falls back to 40 if unset or out of range.
UNBOUND_CACHE_PERCENTAGE=40

# Number of resolver threads. Defaults to the detected CPU count (nproc).
UNBOUND_THREADS=4
```

## Build

```bash
cd docker/unbound-recursive
DOCKER_BUILDKIT=1 docker build -t unbound-recursive:1.25.1 .
```

On push to `main`, CI publishes the image to Harbor as
`unbound-recursive:<tag>` (under `registry.example.com/example-org/proxmox-infra`).
Versions stay in lockstep with the forwarder image via Renovate.

## Switching to recursive

The forwarder stays active by default. To switch the homelab to recursive:

1. In `services/adguard-<n>/docker-compose.yml`, swap the `unbound-<n>` image to
   `${REGISTRY_IMAGE}/unbound-recursive:<ver>` and **drop** the
   `forward-records.conf` bind-mount (keep the `unbound.conf` mount, now
   pointing at this variant's config). Ready-made service blocks live in
   `services/_templates/unbound-recursive.example`.
2. Ensure the adguard hosts' firewall allows **outbound UDP+TCP/53** to the
   internet (recursion talks directly to root/TLD/authoritative servers).
3. No AdGuard change is needed (upstream stays `127.0.0.1:5335`).
4. Commit, push, and let Komodo redeploy the `adguard-*` stacks.

## Testing

```bash
# DNSSEC-secure name: expect NOERROR with the 'ad' (authenticated data) flag
docker exec unbound-recursive \
  drill @127.0.0.1 -p 5335 cloudflare.com A

# DNSSEC-bogus name: expect SERVFAIL
docker exec unbound-recursive \
  drill @127.0.0.1 -p 5335 dnssec-failed.org A

# Resolver status over the unix control socket
docker exec unbound-recursive \
  unbound-control -c /opt/unbound/etc/unbound/unbound.conf status
```

## License

Part of the proxmox-infra repository. See repository root for license
information.

---

**Built with:** Docker BuildKit, Debian Trixie Slim, OpenSSL 3.6.2,
Unbound 1.25.1
