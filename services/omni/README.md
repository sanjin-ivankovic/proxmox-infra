# Omni (self-hosted Sidero Talos management plane)

Single-container deployment of Sidero Omni on the `omni` LXC (10.40.0.15),
reachable at `https://omni.example.com`.

Omni terminates its own TLS (no reverse proxy). SideroLink WireGuard runs on
UDP 50180 and advertises this host's LAN IP, so it manages Talos machines on
`10.40.0.0/24` (LAN-only, no public exposure).

Docs: [Omni on-prem][omni-onprem].

[omni-onprem]: https://docs.siderolabs.com/omni/self-hosted/run-omni-on-prem

## What Komodo deploys vs. what is manual (host-side)

Komodo Core reconciles the `omni` stack defined in
[`komodo/stacks.toml`](../../komodo/stacks.toml) by asking the periphery
agent on the `omni` host to run `docker compose up -d` against
`services/omni/docker-compose.yml`. Stack env values come from
[`komodo/variables.toml`](../../komodo/variables.toml) (non-secret pins)
and the host's periphery `[secrets]` block — see
[`host_vars/omni.yml`](../../ansible/inventory/host_vars/omni.yml) and
[`../../docs/ANSIBLE.md#secrets`](../../docs/ANSIBLE.md#secrets).

Three things are NOT in git and must exist on the host first:

- `etc/omni.asc` -- GPG key for etcd encryption (secret).
- `tls/server-chain.pem` -- `*.example.com` fullchain cert.
- `tls/server-key.pem` -- `*.example.com` private key.

### 1. GPG etcd-encryption key (one-time) -- CRITICAL, BACK IT UP

If `omni.asc` is lost, Omni's etcd data is unrecoverable. Back up the exported
key into the secret store (e.g. Bitwarden) the moment it is generated.

```bash
gpg --batch --passphrase '' --quick-generate-key \
  "Omni (etcd encryption) omni@example.com" rsa4096 cert never
gpg --export-secret-key --armor omni@example.com > etc/omni.asc
chmod 600 etc/omni.asc
```

### 2. TLS cert from cert-manager wildcard (plus auto-renewal)

Omni needs a valid cert (no self-signed). Reuse the cluster Let's Encrypt
wildcard. `tls.crt` from the secret is already a fullchain, so use it directly
as `server-chain.pem`.

Initial export (from a machine with cluster kubectl access):

```bash
NS=traefik
SECRET=wildcard-example-com-tls
kubectl get secret "$SECRET" -n "$NS" \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > tls/server-chain.pem
kubectl get secret "$SECRET" -n "$NS" \
  -o jsonpath='{.data.tls\.key}' | base64 -d > tls/server-key.pem
chmod 600 tls/server-key.pem
```

Renewal (LE renews about monthly; the mounted copy goes stale). Install a cron
on the omni host that re-pulls and restarts Omni on change. The cron needs a
scoped read-only token for that one secret. Alternative: issue a dedicated
`omni.example.com` cert on the host via lego/acme.sh DNS-01 (self-contained, no
cluster dependency).

## /dev/net/tun on the host (one-time, MANUAL -- required for WireGuard)

Terraform creates the LXC without TUN: the bpg `device_passthrough` (and any
LXC feature flag beyond `nesting`) needs `root@pam`, which the non-root API
token cannot use. Add TUN by hand on the Proxmox host:

```bash
cat >> /etc/pve/lxc/416.conf <<'EOF'
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
EOF
pct restart 416
pct exec 416 -- ls -l /dev/net/tun
```

Without this, SideroLink (Omni's WireGuard) will not establish and machines
cannot join.

## Networking and DNS

- DNS: `omni.example.com` points to 10.40.0.15 (the LXC), in Technitium. Not
  Traefik.
- Host ports: 443/tcp (UI plus gRPC), 8090/tcp (machine API), 8091/tcp (event
  sink), 8100/tcp (k8s proxy), 50180/udp (WireGuard).
- Confirm intra-VLAN 10.40.0.0/24 allows these to the host (no WAN rule
  needed).

## Auth

Pocket ID OIDC client `omni` (provider URL `https://pocket-id.example.com`,
configured in the Pocket ID admin UI). Redirect URI
`https://omni.example.com/auth/oidc/callback`. The client id/secret reach the
container as `OMNI_OIDC_CLIENT_ID` / `OMNI_OIDC_CLIENT_SECRET` periphery
secrets. Real access is gated by Omni `--initial-users` (`maintainer@example.com`).

## Verify

```bash
docker logs omni
curl -fsS https://omni.example.com/
ls -l /dev/net/tun
```

A clean start shows etcd init, OIDC ready, and WireGuard on 50180/udp. Then
browse `https://omni.example.com`, log in via Pocket ID, and reach the Omni
dashboard.

Do NOT point the production Talos cluster at Omni yet. Validate with a throwaway
machine first. Adopting the live cluster is a separate step.
