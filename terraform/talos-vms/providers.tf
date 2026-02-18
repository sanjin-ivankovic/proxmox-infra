# ============================================================================
# Proxmox Provider Configuration
# ============================================================================

provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret

  # Skip TLS verification (for self-signed certificates in homelab)
  pm_tls_insecure = true

  # Logging (set to DEBUG for troubleshooting)
  pm_log_enable = false
  pm_log_file   = "terraform-plugin-proxmox.log"
  pm_log_levels = {
    _default    = "debug"
    _capturelog = ""
  }
}
