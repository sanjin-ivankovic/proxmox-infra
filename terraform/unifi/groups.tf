# Port groups for multi-port policies. A zone policy's `port` takes one number;
# the controller stores lists ("22,80,443,8443") that this provider cannot read
# back, so every multi-port rule goes through a group instead.
locals {
  port_groups = {
    gateway_admin    = ["22", "80", "443", "8443"]
    web              = ["80", "443"]
    traefik_backends = ["80", "5380"] # Pi-hole UI, Technitium UI
    # Prometheus (argo-apps kube-prometheus-stack) scraping host agents:
    # node_exporter 9100, cAdvisor 9338 (8080 is taken on several hosts),
    # Alloy 12345.
    monitoring_exporters = ["9100", "9338", "12345"]
    plex                 = ["1900", "32400", "32410", "32412", "32413", "32414", "32469"]
    # Unraid apps behind Traefik (argo-apps apps/infra/external-services).
    unraid_apps = [
      "80", "4096", "5000", "5055", "5454", "6767", "7878", "8008",
      "8080", "8081", "8082", "8989", "9696", "32400",
    ]
  }
}

resource "unifi_firewall_group" "ports" {
  for_each = local.port_groups

  name    = replace(each.key, "_", "-")
  type    = "port-group"
  members = each.value
}
