# terraform/unifi — UniFi network as code

Manages the UCG Max controller (`https://10.120.0.1`): LAN networks (VLANs),
Wi-Fi networks, firewall zones and custom zone policies, with the
[`filipowm/unifi`](https://registry.terraform.io/providers/filipowm/unifi)
provider. Predefined (built-in) zone policies are controller-managed and are
not in state.

## Setup

```bash
cp terraform.tfvars.secret.example terraform.tfvars.secret
chmod 600 terraform.tfvars.secret   # API key + Wi-Fi passphrases
make init
make plan                           # must say "No changes" on a clean tree
```

The API key comes from Control Plane → Admins & Users → (admin) → Create API
Key; a dedicated Limited Admin with Local Access Only is preferred.

## Files

| File | Contents |
| --- | --- |
| `networks.tf` | LAN networks (VLAN id, subnet, DHCP, mDNS, IGMP) |
| `wlans.tf` | SSIDs → networks; passphrases from `var.wlan_passphrases` |
| `zones.tf` | Firewall zones and their member networks |
| `policy_matrix.tf` | Every allowed inter-zone flow, and per-pair order |
| `groups.tf` | Port groups for multi-port policies |
| `port_profiles.tf` | Switch port profiles (assigned to ports on the switch) |
| `reservations.tf` | DHCP reservations (UniFi devices on INFRA .2–.9) |
| `baseline/` | Redacted controller dump taken before Terraform managed it |

`networks.tf` and `wlans.tf` started as config generated from the live
controller (`tofu plan -generate-config-out`) and imported with a no-change
plan.

## Firewall model

Every inter-zone flow that is allowed has one entry in `policy_matrix.tf`;
anything else hits the controller's predefined "Block All". Mgmt, Core,
Admin, Servers, Storage, IoT and User are custom zones (default deny); GUEST
uses the predefined Hotspot zone for its built-in gateway restrictions;
Internal and Dmz are predefined, empty and unused.

## Gotchas

- Import IDs for zones and policies need the site prefix:
  `default:<uuid>`; networks and WLANs take the bare id.
- Generated config writes empty placeholders (`""`, `0`) that fail the
  provider's own validation; they were stripped.
- `unifi_firewall_zone_policy` with `connection_state_type = "CUSTOM"` hits
  provider bug #205; avoid it or `ignore_changes = [connection_states]`.
- A policy's `port` is a single number. The controller stores lists
  (`"22,80,443"`) that the provider cannot read back, so multi-port rules
  must use a port group (`groups.tf`).
- Predefined zones (Internal, Hotspot, Dmz, Vpn, External, Gateway) cannot be
  renamed or deleted. Policies that match a network explicitly are disabled by
  the controller when that network leaves the zone, and cannot be re-enabled.
- A zone or policy change takes a few seconds to reach the UCG; test after
  that, not straight after `apply`.
- `multicast_dns` on `unifi_network` only mirrors the site-wide mDNS scope
  (UI: Settings → Networks → Global Network Settings → Multicast DNS). The
  provider has no resource for that setting and the controller ignores the
  per-network flag, so change the scope in the UI; the plan then agrees.
- IPS exemptions (allow list / suppressions) are not part of the `ips`
  setting the provider writes; `suppression.whitelist` is silently dropped.
  Exempt in the UI: ADMIN (10.120.0.0/24) and WireGuard (10.106.0.0/24), whose
  SSH to Traefik (git push) trips the scan signatures, and the Pi-hole
  resolvers (10.110.0.12, 10.110.0.13).
