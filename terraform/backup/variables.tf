variable "proxmox_api_url" {
  description = "Proxmox API URL (e.g., https://proxmox.example.com:8006/api2/json)"
  type        = string

  validation {
    condition     = can(regex("^https?://.*", var.proxmox_api_url))
    error_message = "proxmox_api_url must be a valid URL starting with http:// or https://."
  }
}

variable "proxmox_api_token_id" {
  description = "Proxmox API token ID (format: user@realm!tokenname)"
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^!]+![^!]+$", var.proxmox_api_token_id))
    error_message = "proxmox_api_token_id must be in format: user@realm!tokenname"
  }
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "lxc_vmids" {
  description = "VMIDs of the LXC containers; set by terragrunt.hcl from the lxc unit's state"
  type        = list(string)
  default     = []
}

variable "talos_vmids" {
  description = "VMIDs of the Talos VMs; set by terragrunt.hcl from the talos unit's state"
  type        = list(string)
  default     = []
}

variable "pbs_storage_password" {
  description = "Secret of the PBS API token backup@pbs!pve, shared with the existing PVE storage \"pbs\" (on the PVE host: /etc/pve/priv/storage/pbs.pw)"
  type        = string
  sensitive   = true
}
