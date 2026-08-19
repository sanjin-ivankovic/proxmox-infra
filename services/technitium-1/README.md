# Technitium (authoritative DNS + DHCP)

HA pair with [`technitium-2`](../technitium-2/) running Technitium DNS Server
on the `technitium-1` (10.10.0.10) and `technitium-2` (10.10.0.11) LXCs.
Web UI on port 5380.

`technitium-1` is the cluster primary (`ns1.dns.example.com`); `technitium-2` is
the secondary (`ns2.dns.example.com`) and pulls zones over AXFR.

These servers are **authoritative only** — they serve the `example.com` zone,
the `10.x` reverse zones, and DHCP for the VLAN scopes. They do not resolve
external names for clients.

## Where external resolution actually happens

Client-facing resolution is the AdGuard pair, not these hosts:

```text
client -> AdGuard (10.10.0.12/.13) -> Unbound (:5335) -> DoT -> Quad9
                                          ^
                          DNSSEC validation happens here
```

See [`adguard-1`](../adguard-1/docker-compose.yml) — each AdGuard host runs a
co-located Unbound configured as a DNS-over-TLS forwarder to Quad9
(`9.9.9.9@853`), which is where DNSSEC validation is performed.

## VLAN egress constraint (load-bearing)

Outbound from the DNS VLAN, **only TCP/853 is permitted**. Ports 53 and 443
are firewalled off; ICMP is allowed. This is deliberate — it forces all
external DNS through Unbound's encrypted DoT path.

**Settings -> Recursion** is therefore set to `Deny Recursion`: the root hints
these servers would otherwise use are unreachable on port 53.

Do **not** "fix" anything here by adding forwarders under
Settings -> Proxy & Forwarders. That would create a second resolution path that
bypasses AdGuard's filtering and Unbound's DoT upstream.

## The KSK on `dns.example.com` must stay manually Active

`dns.example.com` is a **private zone whose parent (`example.com`) is unsigned**,
so a DS record for it will never be published. A signed zone's Key Signing Key
normally advances `Ready -> Active` on its own once the server detects that DS
record in the parent — and until it does, it re-queries for the DS every 15
minutes.

On this VLAN that query cannot leave the host, so the primary logs a
`DnsClientNoResponseException` stack trace (`dns.example.com. DS IN`, then
`. DNSKEY IN`) with every root server timing out, roughly every 15 minutes,
indefinitely. DNS itself is unaffected — the symptom is log noise.

The fix is the option added in Technitium v15.0 for exactly this case: mark the
KSK Active by hand so the detection loop stops.

**Zones -> dns.example.com -> DNSSEC -> Properties -> KSK row -> activate.**

The dialog states the rule directly: *"If this is a private zone, then you
should manually activate the KSK so that the DNS Server stops the detection
process which queries for DS records periodically."*

If the zone is ever re-signed or the KSK rolled over, the new key starts in
`Ready` and the log noise returns until it is activated again.

Two things that do **not** fix this, both ruled out by testing on 2026-08-10:

- `Settings -> General -> DNSSEC -> Enable DNSSEC Validation` — governs
  validation of *responses*, not zone maintenance. Disabling it changed nothing.
- `DNSSEC -> Unsign Zone` — Technitium refuses on a cluster zone
  (*"Cannot unsign the Cluster Primary zone"*). See below.

## Cluster zone: `dns.example.com`

`dns.example.com` is Technitium's own cluster control-plane zone, paired with
the `cluster-catalog.dns.example.com` catalog zone. It is DNSSEC-signed by the
product and its records are tagged *"Cluster managed record. Do not update or
delete."*

The signed cluster zone has an unsigned parent (`example.com`), so its chain of
trust cannot be validated against the public root. That is expected for an
internal-only zone and is not a fault to repair — it is, however, why the KSK
must be activated by hand (above).

Technitium refuses `DNSSEC -> Unsign Zone` on this zone
(*"Cannot unsign the Cluster Primary zone"*). Do not attempt to work around it.

## Deploy

Auto-deployed by Komodo from the `technitium-1` / `technitium-2` stacks in
[`komodo/stacks.toml`](../../komodo/stacks.toml). The pair uses `after = [...]`
for sequential rollout so both nameservers never restart at once — see
[HA pairs](../README.md#ha-pairs).
