# Zone policy matrix. Every inter-zone flow that is allowed is listed here;
# everything else falls through to the controller's predefined "Block All".
#
# Conventions, matching the controller's own behaviour:
#   - ALLOW into an internal zone creates the predefined return policy
#     (auto_allow_return_traffic); towards WAN/Gateway the predefined
#     "Allow Return Traffic" already covers it.
#   - BLOCKs log; ALLOWs do not unless `logging` says so.
#   - Within a zone pair, narrow `early` allows run first, then blocks, then
#     the remaining allows (see unifi_firewall_zone_policy_order below).

locals {
  ip = {
    resolvers = ["10.110.0.12", "10.110.0.13"]
    dns_hosts = ["10.110.0.10", "10.110.0.11", "10.110.0.12", "10.110.0.13"]
    # The LAN address of Traefik (Service traefik-lan). The public entrypoint
    # has no LAN address: the tunnel reaches it by ClusterIP.
    traefik       = ["10.140.0.60"]
    traefik_lan   = ["10.140.0.60"]
    talos_nodes   = ["10.140.0.41", "10.140.0.42", "10.140.0.43", "10.140.0.51", "10.140.0.52", "10.140.0.53"]
    talos_workers = ["10.140.0.51", "10.140.0.52", "10.140.0.53"]
    komodo        = ["10.140.0.14"]
    semaphore     = ["10.140.0.15"]
    pve           = ["10.105.0.4"]
    pbs           = ["10.130.0.50"]
    unraid        = ["10.130.0.30"]
    quad9         = ["9.9.9.9", "149.112.112.112"]
    acme          = ["1.1.1.1", "1.0.0.1"] # cert-manager DNS01 self-check
    # Public DoH endpoints, blocked on 443 so clients cannot bypass Pi-hole.
    public_dns = [
      "1.1.1.1", "1.0.0.1", "1.1.1.2", "1.0.0.2", "1.1.1.3", "1.0.0.3",
      "2606:4700:4700::1111", "2606:4700:4700::1001",
      "8.8.8.8", "8.8.4.4", "2001:4860:4860::8888", "2001:4860:4860::8844",
      "9.9.9.9", "149.112.112.112", "9.9.9.11", "149.112.112.11", "2620:fe::fe", "2620:fe::9",
      "208.67.222.222", "208.67.220.220",
      "94.140.14.14", "94.140.15.15", "2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff",
      "45.90.28.0", "45.90.30.0", "185.228.168.9", "185.228.169.9",
      "194.242.2.2", "76.76.2.0", "76.76.10.0",
    ]
  }

  zone = {
    admin    = unifi_firewall_zone.admin.id
    vpn      = unifi_firewall_zone.vpn.id
    mgmt     = unifi_firewall_zone.mgmt.id
    core     = unifi_firewall_zone.core.id
    servers  = unifi_firewall_zone.servers.id
    storage  = unifi_firewall_zone.storage.id
    iot      = unifi_firewall_zone.iot.id
    user     = unifi_firewall_zone.user.id
    guest    = unifi_firewall_zone.guest.id
    external = unifi_firewall_zone.external.id
    gateway  = unifi_firewall_zone.gateway.id
  }

  label = {
    admin    = "Admin", vpn = "VPN", mgmt = "Mgmt", core = "Core", servers = "Servers",
    storage  = "Storage", iot = "IoT", user = "User", guest = "Guest",
    external = "WAN", gateway = "Gateway",
  }

  rules = merge(
    # Admin and VPN: full access to every internal zone.
    { for z in ["mgmt", "core", "servers", "storage", "iot", "user", "guest"] :
    "admin_${z}_any" => { from = "admin", to = z, action = "ALLOW", what = "ANY (admin full access)" } },
    {
      admin_gateway_any  = { from = "admin", to = "gateway", action = "ALLOW", what = "ANY (admin manage gateway/controller)" }
      admin_external_any = { from = "admin", to = "external", action = "ALLOW", what = "ANY (admin internet)" }
    },
    { for z in ["admin", "mgmt", "core", "servers", "storage", "iot", "user"] :
    "vpn_${z}_any" => { from = "vpn", to = z, action = "ALLOW", what = "ANY (remote full access)" } },
    # The predefined Vpn->Hotspot policy allows everything; guests are never
    # a remote-access target.
    { vpn_guest_block = { from = "vpn", to = "guest", action = "BLOCK", what = "ANY (no remote access to guests)" } },

    # DNS: every zone resolves through Pi-hole only.
    { for z in ["mgmt", "servers", "storage", "iot", "user", "guest"] :
      "${z}_core_dns" => {
        from     = z, to = "core", action = "ALLOW", what = "DNS 53 to resolvers (${z} DNS)",
        protocol = "tcp_udp", dst_ips = local.ip.resolvers, port = 53
    } },

    # Internet. Guest is covered by the predefined Hotspot->External allow.
    { for z in ["mgmt", "core", "servers", "storage", "iot", "user"] :
    "${z}_external_any" => { from = z, to = "external", action = "ALLOW", what = "ANY (general internet)" } },

    # DNS anti-leak: no resolver but Pi-hole, whatever the transport.
    merge([for z in ["mgmt", "core", "servers", "storage", "iot", "user", "guest"] : {
      "${z}_external_block_dns" = { from = z, to = "external", action = "BLOCK", what = "DNS 53 (anti-leak)", protocol = "tcp_udp", port = 53 }
      "${z}_external_block_dot" = { from = z, to = "external", action = "BLOCK", what = "DoT/DoQ 853 (anti-bypass)", protocol = "tcp_udp", port = 853 }
      "${z}_external_block_doh" = { from = z, to = "external", action = "BLOCK", what = "DoH 443 (public resolvers)", protocol = "tcp_udp", dst_ips = local.ip.public_dns, port = 443 }
    }]...),

    # Gateway admin plane and resolver: Admin/VPN only. Mgmt keeps its
    # default access (UniFi devices inform to the controller on the UCG).
    merge([for z in ["core", "servers", "storage", "iot", "user"] : {
      "${z}_gateway_block_admin" = { from = z, to = "gateway", action = "BLOCK", what = "mgmt 22,80,443,8443 (router admin plane)", protocol = "tcp", ports = "gateway_admin" }
      "${z}_gateway_block_dns"   = { from = z, to = "gateway", action = "BLOCK", what = "DNS 53 (no gateway resolver)", protocol = "tcp_udp", port = 53 }
    }]...),

    {
      # Exceptions that must run before the zone's anti-leak blocks.
      core_external_dot_quad9 = {
        from     = "core", to = "external", action = "ALLOW", what = "DoT 853 to Quad9 (resolver upstream)", early = true,
        protocol = "tcp", src_ips = local.ip.resolvers, dst_ips = local.ip.quad9, port = 853
      }
      servers_external_acme_dns = {
        from        = "servers", to = "external", action = "ALLOW", what = "DNS 53 to ACME resolvers (cert-manager DNS01)", early = true,
        protocol    = "tcp_udp", src_ips = local.ip.talos_workers, dst_ips = local.ip.acme, port = 53, logging = true
        description = "Narrow exception to the DNS-53 anti-leak block: lets cert-manager on the Talos workers run its ACME DNS-01 propagation self-check against Cloudflare resolvers."
      }

      mgmt_storage_pbs = {
        from     = "mgmt", to = "storage", action = "ALLOW", what = "PBS 8007 (proxmox backup)",
        protocol = "tcp", src_ips = local.ip.pve, dst_ips = local.ip.pbs, port = 8007
      }
      core_servers_git = {
        from     = "core", to = "servers", action = "ALLOW", what = "git 443 (periphery repo clone)",
        protocol = "tcp", src_ips = local.ip.dns_hosts, dst_ips = local.ip.traefik, port = 443
      }
      servers_core_traefik_backends = {
        from     = "servers", to = "core", action = "ALLOW", what = "Traefik backends (AdGuard 80, Technitium 5380)",
        protocol = "tcp", src_ips = local.ip.talos_nodes, dst_ips = local.ip.dns_hosts, ports = "traefik_backends"
      }
      servers_core_exporters = {
        from     = "servers", to = "core", action = "ALLOW", what = "Prometheus to host exporters (node_exporter, cAdvisor, Alloy)",
        protocol = "tcp", src_ips = local.ip.talos_nodes, dst_ips = local.ip.dns_hosts, ports = "monitoring_exporters"
      }
      servers_core_komodo = {
        from     = "servers", to = "core", action = "ALLOW", what = "Komodo Periphery 8120 (Core hosts)",
        protocol = "tcp", src_ips = local.ip.komodo, dst_ips = local.ip.dns_hosts, port = 8120
      }
      servers_core_semaphore_ssh = {
        from     = "servers", to = "core", action = "ALLOW", what = "Semaphore SSH 22 (Ansible mgmt)",
        protocol = "tcp", src_ips = local.ip.semaphore, port = 22
      }
      servers_mgmt_semaphore_ssh = {
        from     = "servers", to = "mgmt", action = "ALLOW", what = "Semaphore SSH 22 (Ansible mgmt)",
        protocol = "tcp", src_ips = local.ip.semaphore, port = 22
      }
      servers_mgmt_pve_api = {
        from     = "servers", to = "mgmt", action = "ALLOW", what = "Semaphore PVE API 8006 (Terraform/Ansible)",
        protocol = "tcp", src_ips = local.ip.semaphore, dst_ips = local.ip.pve, port = 8006
      }
      servers_mgmt_pve_exporter = {
        from     = "servers", to = "mgmt", action = "ALLOW", what = "pve-exporter PVE API 8006 (Talos nodes)",
        protocol = "tcp", src_ips = local.ip.talos_nodes, dst_ips = local.ip.pve, port = 8006
      }
      servers_storage_unraid_apps = {
        from     = "servers", to = "storage", action = "ALLOW", what = "Traefik to Unraid apps (external-services)",
        protocol = "tcp", src_ips = local.ip.talos_nodes, dst_ips = local.ip.unraid, ports = "unraid_apps"
      }
      storage_servers_nextcloud = {
        from     = "storage", to = "servers", action = "ALLOW", what = "Unraid → Traefik 443 (rclone Nextcloud backup)",
        protocol = "tcp", src_ips = local.ip.unraid, dst_ips = local.ip.traefik_lan, port = 443
      }
      iot_servers_traefik = {
        from     = "iot", to = "servers", action = "ALLOW", what = "Traefik 80,443 (formuler/plex)",
        protocol = "tcp", dst_ips = local.ip.traefik_lan, ports = "web"
      }
      iot_storage_plex = {
        from     = "iot", to = "storage", action = "ALLOW", what = "Plex 32400 + discovery (formuler/IPTV)",
        protocol = "tcp_udp", dst_ips = local.ip.unraid, ports = "plex"
      }
      user_servers_traefik = {
        from     = "user", to = "servers", action = "ALLOW", what = "Traefik 80,443 (user apps)",
        protocol = "tcp", dst_ips = local.ip.traefik, ports = "web"
      }
      user_iot_any = { from = "user", to = "iot", action = "ALLOW", what = "ANY (user→iot casting/control)" }
    },
  )

  policies = { for k, r in local.rules : k => merge({
    protocol = "all", src_ips = null, dst_ips = null, port = null, ports = null,
    early    = false, logging = r.action == "BLOCK", description = null,
  }, r) }

  # Run order inside a zone pair: early allows, blocks, remaining allows.
  rank = { for k, p in local.policies : k => p.early ? 0 : (p.action == "BLOCK" ? 1 : 2) }
}

resource "unifi_firewall_zone_policy" "matrix" {
  for_each = local.policies

  name                      = "${local.label[each.value.from]}→${local.label[each.value.to]} | ${each.value.action} | ${each.value.what}"
  description               = each.value.description
  action                    = each.value.action
  auto_allow_return_traffic = each.value.action == "ALLOW" && !contains(["external", "gateway"], each.value.to)
  connection_state_type     = "ALL"
  enabled                   = true
  ip_version                = "BOTH"
  logging                   = each.value.logging
  match_opposite_protocol   = false
  protocol                  = each.value.protocol
  site                      = "default"
  schedule                  = { mode = "ALWAYS", time_all_day = false }
  source = {
    ips                     = each.value.src_ips
    match_opposite_ips      = false
    match_opposite_networks = false
    match_opposite_ports    = false
    zone_id                 = local.zone[each.value.from]
  }
  destination = {
    ips                     = each.value.dst_ips
    port                    = each.value.port
    port_group_id           = each.value.ports == null ? null : unifi_firewall_group.ports[each.value.ports].id
    match_opposite_ips      = false
    match_opposite_networks = false
    match_opposite_ports    = false
    zone_id                 = local.zone[each.value.to]
  }
}

# Explicit order for the pairs where it matters (allows after the anti-leak
# blocks, Quad9/ACME exceptions before them).
resource "unifi_firewall_zone_policy_order" "external" {
  for_each = toset(["mgmt", "core", "servers", "storage", "iot", "user"])

  source_zone_id      = local.zone[each.key]
  destination_zone_id = local.zone.external
  before_predefined_ids = [
    for k in sort([for k, p in local.policies : "${local.rank[k]}-${k}" if p.from == each.key && p.to == "external"]) :
    unifi_firewall_zone_policy.matrix[split("-", k)[1]].id
  ]
}
