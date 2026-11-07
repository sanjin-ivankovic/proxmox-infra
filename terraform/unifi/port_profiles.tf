# Tagged-only trunk for the pve LAG (USW ports 15/16): MGMT, CORE and SERVER,
# no native network. An untagged frame from the host or a guest missing its
# tag is dropped instead of landing in another network.
#
# The provider omits a null native_networkconf_id instead of sending "", so
# apply cannot clear a native network set elsewhere: plan shows the drift,
# apply leaves it. Clear it on the controller (native_networkconf_id = "").
resource "unifi_port_profile" "trunk_proxmox" {
  name    = "trunk-proxmox"
  forward = "customize"
  excluded_network_ids = [
    unifi_network.net_01_infra.id,
    unifi_network.net_20_admin.id,
    unifi_network.net_30_storage.id,
    unifi_network.net_50_iot.id,
    unifi_network.net_60_user.id,
    unifi_network.net_70_guest.id,
  ]
  tagged_vlan_mgmt = "custom"
}

# Access ports: native network only, tagged frames dropped, so a device cannot
# reach another VLAN by tagging its own frames. The controller rewrites
# forward to agree with tagged_vlan_mgmt and stores block_all as "native";
# any other value plans a permanent diff.
#
# There is no "disabled" profile: a profile cannot turn a port off. The
# controller stores forward = "disabled" as a full trunk with 01_INFRA native.
# Unused ports get Port State: Disabled on the port itself (docs/NETWORK.md).

# IoT access ports (USW 9-12). Port Mode Edge (with BPDU Guard) is set on the
# profile in the UI: the provider has no field for it. Check it is still Edge
# after any apply that changes this resource.
resource "unifi_port_profile" "access_iot" {
  name                  = "access-iot"
  forward               = "native"
  native_networkconf_id = unifi_network.net_50_iot.id
  tagged_vlan_mgmt      = "block_all"
  poe_mode              = "off"
}

# Unraid LAG (USW 1+2). Unraid has no VLAN interfaces; its Docker macvlan (br0)
# and the PBS VM are untagged on STORAGE. A VLAN on Unraid needs this profile
# changed first.
resource "unifi_port_profile" "access_storage" {
  name                  = "access-storage"
  forward               = "native"
  native_networkconf_id = unifi_network.net_30_storage.id
  tagged_vlan_mgmt      = "block_all"
}
