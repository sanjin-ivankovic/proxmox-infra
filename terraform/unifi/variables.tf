variable "unifi_api_url" {
  description = "UniFi controller URL (the UCG Max management address)."
  type        = string
  default     = "https://10.120.0.1"
}

variable "unifi_api_key" {
  description = "UniFi API key (Control Plane → Admins & Users → <admin> → Create API Key)."
  type        = string
  sensitive   = true
}

variable "wlan_passphrases" {
  description = "WPA passphrases keyed by SSID name, from Vault kv/terraform/unifi (terragrunt.hcl)."
  type        = map(string)
  sensitive   = true
}
