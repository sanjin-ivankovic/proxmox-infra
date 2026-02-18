#!/bin/bash

###############################################################################
# Dynamic Resource Calculation for Unbound DNS Server
###############################################################################

# Get cache percentage from environment variable (default: 40%)
cache_percentage=${UNBOUND_CACHE_PERCENTAGE:-40}

# Detect available memory
availableMemory=$((1024 * $( (grep MemAvailable /proc/meminfo || grep MemTotal /proc/meminfo) | sed 's/[^0-9]//g' ) ))
memoryLimit=$availableMemory

# Check cgroup memory limit (for containers)
[ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ] && memoryLimit=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes | sed 's/[^0-9]//g')
[[ ! -z $memoryLimit && $memoryLimit -gt 0 && $memoryLimit -lt $availableMemory ]] && availableMemory=$memoryLimit

# Calculate reserved memory (10% of total, minimum 256MB)
reserved_mb=$((memoryLimit / 1024 / 1024 / 10))
[[ $reserved_mb -lt 256 ]] && reserved_mb=256
reserved=$((reserved_mb * 1024 * 1024))

# Ensure minimum memory requirement
if [ "$availableMemory" -le $((reserved * 2)) ]; then
    echo "Not enough memory available. Need at least $((reserved * 2 / 1024 / 1024))MB" >&2
    exit 1
fi

# Calculate total cache budget
available_after_reserved=$((availableMemory - reserved))
total_cache=$((available_after_reserved * cache_percentage / 100))

# Distribute cache among 4 types (optimized for DNSSEC-validating recursive resolver)
# rrset: 50% (largest - stores DNS records)
# msg: 25% (complete responses, 2:1 ratio with rrset)
# key: 24% (DNSSEC keys and signatures)
# neg: 1% (NXDOMAIN and negative responses)
rrset_cache=$((total_cache / 2))
msg_cache=$((total_cache / 4))
key_cache=$((total_cache * 24 / 100))
neg_cache=$((total_cache / 100))

# Convert to MB for Unbound config
rrset_cache_mb=$((rrset_cache / 1024 / 1024))
msg_cache_mb=$((msg_cache / 1024 / 1024))
key_cache_mb=$((key_cache / 1024 / 1024))
neg_cache_mb=$((neg_cache / 1024 / 1024))

# Ensure minimum cache sizes
[[ $rrset_cache_mb -lt 16 ]] && rrset_cache_mb=16
[[ $msg_cache_mb -lt 8 ]] && msg_cache_mb=8
[[ $key_cache_mb -lt 8 ]] && key_cache_mb=8
[[ $neg_cache_mb -lt 4 ]] && neg_cache_mb=4

# Thread calculation - use all CPUs for dedicated DNS container
nproc=$(nproc)
threads=${UNBOUND_THREADS:-$nproc}

# Slab calculation - must be power of 2, close to thread count
if [ "$nproc" -gt 1 ]; then
    export nproc
    nproc_log=$(perl -e 'printf "%5.5f\n", log($ENV{nproc})/log(2);')
    rounded_nproc_log="$(printf '%.*f\n' 0 "$nproc_log")"
    slabs=$(( 2 ** rounded_nproc_log ))
else
    slabs=1
fi

# Log calculated values
echo "==================================================================="
echo "Unbound Dynamic Configuration"
echo "==================================================================="
echo "Container Memory:    $((memoryLimit / 1024 / 1024)) MB"
echo "Reserved Memory:     ${reserved_mb} MB"
echo "Cache Percentage:    ${cache_percentage}%"
echo "Total Cache Budget:  $((total_cache / 1024 / 1024)) MB"
echo "-------------------------------------------------------------------"
echo "Cache Allocation:"
echo "  - RRset Cache:     ${rrset_cache_mb} MB (50%)"
echo "  - Message Cache:   ${msg_cache_mb} MB (25%)"
echo "  - Key Cache:       ${key_cache_mb} MB (24%)"
echo "  - Negative Cache:  ${neg_cache_mb} MB (1%)"
echo "-------------------------------------------------------------------"
echo "CPU Configuration:"
echo "  - Threads:         ${threads}"
echo "  - Slabs:           ${slabs}"
echo "==================================================================="

# Generate unbound.conf if it doesn't exist
if [ ! -f /opt/unbound/etc/unbound/unbound.conf ]; then
    sed \
        -e "s/@RRSET_CACHE_SIZE@/${rrset_cache_mb}m/" \
        -e "s/@MSG_CACHE_SIZE@/${msg_cache_mb}m/" \
        -e "s/@KEY_CACHE_SIZE@/${key_cache_mb}m/" \
        -e "s/@NEG_CACHE_SIZE@/${neg_cache_mb}m/" \
        -e "s/@THREADS@/${threads}/" \
        -e "s/@SLABS@/${slabs}/" \
        > /opt/unbound/etc/unbound/unbound.conf << 'EOT'
# Unbound DNS Server Configuration
# Validating, recursive, caching DNS resolver
#
# Documentation: https://unbound.docs.nlnetlabs.nl/
# Generated dynamically based on container resources

server:
    ###########################################################################
    # BASIC SETTINGS
    ###########################################################################

    # Number of threads to create to serve clients
    num-threads: @THREADS@

    # Logging configuration
    verbosity: 1
    # Log queries for debugging (comment out in production for privacy)
    # log-queries: yes
    # log-replies: yes
    # log-local-actions: yes

    # Log to stdout (useful for Docker)
    logfile: ""

    # Set the working directory
    directory: "/opt/unbound/etc/unbound"

    # Drop user privileges after binding the port
    username: "_unbound"

    # Disable chroot - Docker provides container isolation
    chroot: ""

    # Prevent forking into background (Docker needs foreground process)
    do-daemonize: no

    ###########################################################################
    # NETWORK CONFIGURATION
    ###########################################################################

    # Network interfaces to listen on (0.0.0.0 for all IPv4, ::0 for all IPv6)
    # interface: 0.0.0.0@53 (default)
    interface: 127.0.0.1 # (co-located with AdGuard/Pi-hole)
    # interface: ::0@53

    # Port to listen on
    # port: 53 # (default)
    port: 5335 # (co-located with AdGuard/Pi-hole)

    # Enable IPv4 and IPv6
    do-ip4: yes
    do-ip6: no

    # Use TCP and UDP
    do-udp: yes
    do-tcp: yes

    ###########################################################################
    # ACCESS CONTROL
    ###########################################################################

    # Access control - define which clients are allowed to query
    # Allow queries from RFC1918 private networks
    access-control: 10.0.0.0/8 allow
    access-control: 172.16.0.0/12 allow
    access-control: 192.168.0.0/16 allow

    # Allow localhost
    access-control: 127.0.0.0/8 allow
    access-control: ::1 allow
    access-control: ::ffff:127.0.0.1 allow

    # Allow link-local
    access-control: fe80::/10 allow

    # Deny everything else
    access-control: 0.0.0.0/0 refuse
    access-control: ::0/0 refuse

    ###########################################################################
    # PERFORMANCE TUNING
    ###########################################################################

    # Number of slabs for cache (must be power of 2, reduces lock contention)
    msg-cache-slabs: @SLABS@
    rrset-cache-slabs: @SLABS@
    infra-cache-slabs: @SLABS@
    key-cache-slabs: @SLABS@

    # Cache sizes (dynamically calculated based on available memory)
    rrset-cache-size: @RRSET_CACHE_SIZE@
    msg-cache-size: @MSG_CACHE_SIZE@
    key-cache-size: @KEY_CACHE_SIZE@
    neg-cache-size: @NEG_CACHE_SIZE@

    # Number of queries that each thread will service simultaneously
    num-queries-per-thread: 4096

    # Outgoing connections
    outgoing-range: 8192

    # Number of outgoing and incoming TCP buffers to allocate per thread
    outgoing-num-tcp: 200
    incoming-num-tcp: 200

    # TCP timeout
    tcp-idle-timeout: 30000

    # Buffer size for UDP packets (0 = use system defaults, appropriate for containers)
    so-rcvbuf: 0
    so-sndbuf: 0

    # Prefetch cache entries before they expire
    prefetch: yes
    prefetch-key: yes

    # Serve expired entries from cache (RFC 8767)
    serve-expired: yes
    serve-expired-ttl: 86400
    serve-expired-ttl-reset: yes

    # EDNS buffer size (DNS Flag Day 2020 recommendation)
    edns-buffer-size: 1232

    # Rotates RRset order in response
    rrset-roundrobin: yes

    # Minimal responses (reduces response size)
    minimal-responses: yes

    # Extra delay for timed-out UDP ports
    delay-close: 10000

    # UDP queries socket timeout
    sock-queue-timeout: 3

    # Use SO_REUSEPORT for better thread distribution
    so-reuseport: yes

    ###########################################################################
    # PRIVACY AND SECURITY HARDENING
    ###########################################################################

    # Hide server identity and version
    hide-identity: yes
    hide-version: yes
    hide-trustanchor: yes
    hide-http-user-agent: no

    # Custom identity
    identity: "DNS"
    http-user-agent: "DNS"

    # Refuse queries for ANY type (often used in DNS amplification attacks)
    deny-any: yes

    # Minimize queries sent to authoritative servers (qname minimization - RFC 7816)
    qname-minimisation: yes
    qname-minimisation-strict: no

    # Aggressive NSEC (RFC 8198) - use cached NSEC records to generate negative responses
    aggressive-nsec: yes

    # Only trust glue if it is within the servers authority
    harden-glue: yes

    # Require DNSSEC data for trust-anchored zones
    harden-dnssec-stripped: yes

    # Don't trust additional records in authoritative responses
    harden-below-nxdomain: yes

    # Harden against algorithm downgrade attacks
    harden-algo-downgrade: yes

    # Harden against unknown records
    harden-unknown-additional: yes

    # Ignore very large queries
    harden-large-queries: yes

    # Ignore very small EDNS buffer sizes
    harden-short-bufsize: yes

    # Harden referral path (experimental, disabled by default)
    harden-referral-path: no

    # Use 0x20-encoded random bits in the query to foil spoof attempts
    use-caps-for-id: yes

    # Enforce privacy of queries (don't include original query in error responses)
    val-clean-additional: yes

    # TTL settings
    cache-min-ttl: 60
    cache-max-ttl: 86400

    # Limit TTL for negative responses
    val-bogus-ttl: 60

    # Respond with Extended DNS Errors (RFC 8914)
    ede: yes
    ede-serve-expired: yes

    # Rate limiting (queries per second to upstream nameservers)
    ratelimit: 1000

    # Unwanted reply threshold
    unwanted-reply-threshold: 10000

    # Do not query localhost
    do-not-query-localhost: no

    ###########################################################################
    # DNSSEC VALIDATION
    ###########################################################################

    # Enable DNSSEC validation
    module-config: "validator iterator"

    # Automatically trust RFC 5011 trust anchors
    auto-trust-anchor-file: "var/root.key"

    # If DNSSEC validation fails, serve SERVFAIL
    val-permissive-mode: no

    # TLS certificate bundle for DNS-over-TLS
    tls-cert-bundle: /etc/ssl/certs/ca-certificates.crt

    # Ignore DNSSEC for private IP reverse lookups
    domain-insecure: "10.in-addr.arpa."
    domain-insecure: "16.172.in-addr.arpa."
    domain-insecure: "17.172.in-addr.arpa."
    domain-insecure: "18.172.in-addr.arpa."
    domain-insecure: "19.172.in-addr.arpa."
    domain-insecure: "20.172.in-addr.arpa."
    domain-insecure: "21.172.in-addr.arpa."
    domain-insecure: "22.172.in-addr.arpa."
    domain-insecure: "23.172.in-addr.arpa."
    domain-insecure: "24.172.in-addr.arpa."
    domain-insecure: "25.172.in-addr.arpa."
    domain-insecure: "26.172.in-addr.arpa."
    domain-insecure: "27.172.in-addr.arpa."
    domain-insecure: "28.172.in-addr.arpa."
    domain-insecure: "29.172.in-addr.arpa."
    domain-insecure: "30.172.in-addr.arpa."
    domain-insecure: "31.172.in-addr.arpa."
    domain-insecure: "168.192.in-addr.arpa."

    ###########################################################################
    # LOCAL ZONES
    ###########################################################################

    # Private DNS domains (these should not be sent upstream)
    private-address: 10.0.0.0/8
    private-address: 172.16.0.0/12
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: fd00::/8
    private-address: fe80::/10

    # localhost
    private-domain: "localhost."
    private-domain: "local."

    # Allow private IP addresses for example.com (internal AD domain)
    private-domain: "example.com."

    # Standard localhost entries
    local-zone: "localhost." static
    local-data: "localhost. 10800 IN A 127.0.0.1"
    local-data: "localhost. 10800 IN AAAA ::1"

    local-zone: "127.in-addr.arpa." static
    local-data: "1.0.0.127.in-addr.arpa. 10800 IN PTR localhost."

    # Allow forwarding of reverse DNS zones to Windows DNS
    # Set to transparent to allow forward-zones to work
    local-zone: "10.10.in-addr.arpa." transparent
    local-zone: "20.10.in-addr.arpa." transparent
    local-zone: "30.10.in-addr.arpa." transparent
    local-zone: "40.10.in-addr.arpa." transparent
    local-zone: "50.10.in-addr.arpa." transparent
    local-zone: "60.10.in-addr.arpa." transparent

    ###########################################################################
    # INCLUDE CUSTOM CONFIGURATIONS
    ###########################################################################

    # Include local data configurations
    # include: "/opt/unbound/etc/unbound/a-records.conf"
    # include: "/opt/unbound/etc/unbound/srv-records.conf"

###############################################################################
# FORWARDING CONFIGURATION
###############################################################################

# Include forwarding configuration
include: "/opt/unbound/etc/unbound/forward-records.conf"

###############################################################################
# REMOTE CONTROL (for unbound-control)
###############################################################################

# Enable remote control
# Using Unix socket for Docker (simpler and more secure than TCP/IP)
remote-control:
    control-enable: yes # (default is no)
    control-interface: "/opt/unbound/etc/unbound/unbound.sock"
EOT

    echo "Generated /opt/unbound/etc/unbound/unbound.conf"
else
    echo "Using existing /opt/unbound/etc/unbound/unbound.conf (custom configuration)"
fi

# Create var directory for trust anchor
mkdir -p /opt/unbound/etc/unbound/var && \
chmod 700 /opt/unbound/etc/unbound/var && \
chown _unbound:_unbound /opt/unbound/etc/unbound/var && \
/opt/unbound/sbin/unbound-anchor -a /opt/unbound/etc/unbound/var/root.key

echo "==================================================================="
echo "Starting Unbound DNS Server..."
echo "==================================================================="

# Start Unbound in foreground
exec /opt/unbound/sbin/unbound -d -c /opt/unbound/etc/unbound/unbound.conf
