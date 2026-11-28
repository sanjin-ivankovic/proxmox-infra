# Wi-Fi networks. Passphrases come from var.wlan_passphrases (Vault kv/terraform/unifi).

resource "unifi_wlan" "baraddur" {
  ap_group_ids              = ["f85d04f3-9622-4d50-a993-1cc1846d62db"]
  bss_transition            = true
  fast_roaming_enabled      = false
  hide_ssid                 = true
  is_guest                  = false
  l2_isolation              = false
  mac_filter_enabled        = false
  mac_filter_list           = []
  mac_filter_policy         = "deny"
  minimum_data_rate_2g_kbps = 0
  minimum_data_rate_5g_kbps = 0
  multicast_enhance         = false
  name                      = "BaradDur"
  network_id                = "290fffed-b157-48ac-94a6-c0bc299696e2"
  no2ghz_oui                = true
  passphrase                = var.wlan_passphrases["BaradDur"]
  pmf_mode                  = "required"
  proxy_arp                 = false
  security                  = "wpapsk"
  site                      = "default"
  uapsd                     = false
  user_group_id             = "0a42b477-d5c1-4452-9959-7911395eb02a"
  wlan_bands                = ["5g", "6g"]
  wpa3_support              = true
  wpa3_transition           = false
}

resource "unifi_wlan" "isengard" {
  ap_group_ids              = ["f85d04f3-9622-4d50-a993-1cc1846d62db"]
  bss_transition            = false
  fast_roaming_enabled      = false
  hide_ssid                 = false
  is_guest                  = false
  l2_isolation              = true
  mac_filter_enabled        = false
  mac_filter_list           = []
  mac_filter_policy         = "deny"
  minimum_data_rate_2g_kbps = 0
  minimum_data_rate_5g_kbps = 0
  multicast_enhance         = false
  name                      = "Isengard"
  network_id                = "3b57234c-ac59-4b5a-bc05-ce5b809e0caa"
  no2ghz_oui                = false
  passphrase                = var.wlan_passphrases["Isengard"]
  pmf_mode                  = "disabled"
  proxy_arp                 = false
  security                  = "wpapsk"
  site                      = "default"
  uapsd                     = false
  user_group_id             = "0a42b477-d5c1-4452-9959-7911395eb02a"
  wlan_bands                = ["2g"]
  wpa3_support              = false
  wpa3_transition           = false
}

resource "unifi_wlan" "imladris" {
  ap_group_ids              = ["f85d04f3-9622-4d50-a993-1cc1846d62db"]
  bss_transition            = true
  fast_roaming_enabled      = false
  hide_ssid                 = false
  is_guest                  = false
  l2_isolation              = false
  mac_filter_enabled        = false
  mac_filter_list           = []
  mac_filter_policy         = "deny"
  minimum_data_rate_2g_kbps = 0
  minimum_data_rate_5g_kbps = 0
  multicast_enhance         = false
  name                      = "Imladris"
  network_id                = "7d3fc02e-6dba-42c6-8cca-025714a75ad8"
  no2ghz_oui                = true
  passphrase                = var.wlan_passphrases["Imladris"]
  pmf_mode                  = "optional"
  proxy_arp                 = false
  security                  = "wpapsk"
  site                      = "default"
  uapsd                     = false
  user_group_id             = "0a42b477-d5c1-4452-9959-7911395eb02a"
  wlan_bands                = ["2g", "5g"]
  wpa3_support              = true
  wpa3_transition           = true
}

# Per-client bandwidth cap for guests (kbps).
resource "unifi_user_group" "guest" {
  name              = "Guest"
  qos_rate_max_down = 50000
  qos_rate_max_up   = 20000
}

resource "unifi_wlan" "mithlond" {
  ap_group_ids              = ["f85d04f3-9622-4d50-a993-1cc1846d62db"]
  bss_transition            = true
  fast_roaming_enabled      = false
  hide_ssid                 = false
  is_guest                  = false
  l2_isolation              = true
  mac_filter_enabled        = false
  mac_filter_list           = []
  mac_filter_policy         = "deny"
  minimum_data_rate_2g_kbps = 0
  minimum_data_rate_5g_kbps = 0
  multicast_enhance         = false
  name                      = "Mithlond"
  network_id                = "0940393e-b410-4c8e-9442-03c2c71bfe32"
  no2ghz_oui                = true
  passphrase                = var.wlan_passphrases["Mithlond"]
  pmf_mode                  = "optional"
  proxy_arp                 = false
  security                  = "wpapsk"
  site                      = "default"
  uapsd                     = false
  user_group_id             = unifi_user_group.guest.id
  wlan_bands                = ["2g", "5g"]
  wpa3_support              = true
  wpa3_transition           = true
}
