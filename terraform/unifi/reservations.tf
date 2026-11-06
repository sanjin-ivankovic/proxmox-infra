# DHCP reservations. UniFi devices take 10.100.0.2–.9 on INFRA; reservations
# rather than device static IPs, so a wrong value leaves the device on its
# lease instead of stranding it.
resource "unifi_user" "usw_lite_16_poe" {
  name                   = "USW-Lite-16-PoE"
  mac                    = "1c:6a:1b:10:4f:c0"
  network_id             = unifi_network.net_01_infra.id
  fixed_ip               = "10.100.0.2"
  allow_existing         = true
  skip_forget_on_destroy = true
}

resource "unifi_user" "usw_flex_mini" {
  name                   = "USW Flex Mini"
  mac                    = "74:fa:29:30:47:b0"
  network_id             = unifi_network.net_01_infra.id
  fixed_ip               = "10.100.0.3"
  allow_existing         = true
  skip_forget_on_destroy = true
}

resource "unifi_user" "u7_pro_wall" {
  name                   = "U7-Pro-Wall"
  mac                    = "9c:05:d6:b3:9f:6c"
  network_id             = unifi_network.net_01_infra.id
  fixed_ip               = "10.100.0.4"
  allow_existing         = true
  skip_forget_on_destroy = true
}
