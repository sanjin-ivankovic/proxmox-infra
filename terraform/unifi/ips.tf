# Intrusion prevention (blocking mode) on every internal network except
# STORAGE: qBittorrent on Unraid is wanted P2P traffic, and the emerging-p2p
# category would drop it.
resource "unifi_setting_ips" "this" {
  ips_mode                      = "ips"
  advanced_filtering_preference = "manual"
  memory_optimized              = true
  restrict_torrents             = false
  ad_blocked_networks           = []
  dns_filters                   = []
  honeypots                     = []
  # The controller keeps IPS exemptions outside this setting, so the
  # provider cannot write them; the ADMIN/WireGuard allow list is set in the
  # UI (see README).
  suppression = { alerts = [], whitelist = [] }

  enabled_networks = [
    unifi_network.net_01_infra.id,
    unifi_network.net_05_mgmt.id,
    unifi_network.net_10_core.id,
    unifi_network.net_20_admin.id,
    unifi_network.net_40_server.id,
    unifi_network.net_50_iot.id,
    unifi_network.net_60_user.id,
    unifi_network.net_70_guest.id,
  ]

  # Order as the controller stores it; the provider compares the list in order.
  enabled_categories = [
    "botcc", "emerging-mobile", "emerging-netbios", "emerging-webserver",
    "emerging-sql", "emerging-worm", "compromised", "emerging-ftp",
    "emerging-useragent", "emerging-activex", "emerging-imap",
    "emerging-smtp", "emerging-malware", "emerging-attackresponse",
    "emerging-pop3", "dshield", "emerging-dos", "emerging-tftp",
    "emerging-rpc", "malicious-hosts", "dark-web-blocker-list",
    "emerging-scan", "emerging-exploit", "emerging-snmp",
    "emerging-webclient", "ciarmy", "emerging-voip", "emerging-dns",
    "emerging-p2p", "tor", "emerging-shellcode", "emerging-misc",
    "emerging-telnet", "emerging-webapps",
  ]
}
