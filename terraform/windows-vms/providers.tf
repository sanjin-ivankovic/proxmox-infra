# Provider configuration
# Version constraints are defined in versions.tf

# Proxmox provider configuration
provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure     = true # Change to false if using a valid SSL cert

  # Optional: Configure provider timeouts
  pm_timeout = 600

  # Optional: Add provider debug logging
  # pm_debug = true

  # Optional: Configure parallel operations
  # pm_parallel = 4
}
