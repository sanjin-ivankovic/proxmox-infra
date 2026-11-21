# Firewall zones (zone-based firewall). Zone membership is declared here only;
# networks.tf leaves firewall_zone_id to the controller, since referencing in
# both directions is a dependency cycle.

# Networks the controller owns outside this unit (WANs, the WireGuard server).
locals {
  network_ids = {
    wan1_telekom = "299c8652-0446-49a5-8318-cef2e4103922"
    wan2         = "e5c234bc-6618-4012-b265-1177c7c72caf"
    wireguard    = "0dee46e0-a8cd-4580-a59d-4b36f9dcd938"
  }
}

resource "unifi_firewall_zone" "mgmt" {
  name     = "Mgmt"
  networks = [unifi_network.net_01_infra.id, unifi_network.net_05_mgmt.id]
  site     = "default"
}

resource "unifi_firewall_zone" "core" {
  name     = "Core"
  networks = [unifi_network.net_10_core.id]
  site     = "default"
}

resource "unifi_firewall_zone" "admin" {
  name     = "Admin"
  networks = [unifi_network.net_20_admin.id]
  site     = "default"
}

resource "unifi_firewall_zone" "servers" {
  name     = "Servers"
  networks = [unifi_network.net_40_server.id]
  site     = "default"
}

resource "unifi_firewall_zone" "storage" {
  name     = "Storage"
  networks = [unifi_network.net_30_storage.id]
  site     = "default"
}

resource "unifi_firewall_zone" "iot" {
  name     = "IoT"
  networks = [unifi_network.net_50_iot.id]
  site     = "default"
}

resource "unifi_firewall_zone" "user" {
  name     = "User"
  networks = [unifi_network.net_60_user.id]
  site     = "default"
}

resource "unifi_firewall_zone" "internal" {
  name     = "Internal"
  networks = []
  site     = "default"
}

# GUEST lives in the predefined Hotspot zone: towards the gateway it only
# allows DNS, DHCP and ICMP, which custom zones would not get by default. The
# controller refuses to rename predefined zones.
resource "unifi_firewall_zone" "guest" {
  name     = "Hotspot"
  networks = [unifi_network.net_70_guest.id]
  site     = "default"
}

resource "unifi_firewall_zone" "vpn" {
  name     = "Vpn"
  networks = [local.network_ids.wireguard]
  site     = "default"
}

resource "unifi_firewall_zone" "external" {
  name     = "External"
  networks = [local.network_ids.wan1_telekom, local.network_ids.wan2]
  site     = "default"
}

resource "unifi_firewall_zone" "gateway" {
  name     = "Gateway"
  networks = []
  site     = "default"
}

resource "unifi_firewall_zone" "dmz" {
  name     = "Dmz"
  networks = []
  site     = "default"
}
