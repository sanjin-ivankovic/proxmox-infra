# ============================================================================
# LXC Containers - Variables
# ============================================================================
# This file defines all input variables for LXC container deployment.
# Variables are organized by:
#   1. Proxmox Connection
#   2. Infrastructure Defaults
#   3. LXC-Specific Variables
# ============================================================================

# ============================================================================
# 1. Proxmox Connection Variables
# ============================================================================

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

variable "gitlab_api_token" {
  description = "GitLab API token for Terraform backend authentication (used by Makefile, not by Terraform configuration)"
  type        = string
  sensitive   = true
  default     = ""
}

# ============================================================================
# 2. Infrastructure Defaults
# ============================================================================

variable "target_node" {
  description = "Default Proxmox node to deploy resources on (can be overridden per-instance)"
  type        = string
  default     = "pve"
}

variable "default_storage" {
  description = "Default storage backend for LXC containers (can be overridden per-instance)"
  type        = string
  default     = "local-zfs"
}

variable "default_bridge" {
  description = "Default network bridge for LXC containers (can be overridden per-instance)"
  type        = string
  default     = "vmbr0"
}

variable "ssh_key_directory" {
  description = "Directory to store generated SSH keys (supports ~ expansion)"
  type        = string
  default     = "~/.ssh"
}

# ============================================================================
# 3. LXC-Specific Variables
# ============================================================================

variable "lxc_ostemplate" {
  description = "LXC OS template to use for containers"
  type        = string
  default     = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
}

variable "lxc_password" {
  description = "Root password for LXC containers"
  type        = string
  sensitive   = true
  default     = ""
}

variable "lxc_instances" {
  description = "List of LXC container configurations"
  type = list(object({
    hostname         = string
    vmid             = number
    ip               = string
    gw               = string
    mac              = optional(string)
    cores            = number
    memory           = number
    swap             = number
    disk_size        = string
    unprivileged     = bool
    start            = bool
    onboot           = bool
    tag              = optional(number, 0)
    nameserver       = optional(string)
    searchdomain     = optional(string)
    tags             = list(string)
    target_node      = optional(string)
    storage          = optional(string)
    preserve_ssh_key = optional(bool, false) # Skip SSH key generation for imported hosts
    prevent_destroy  = optional(bool, false) # Document intent - manual edit required in modules/lxc-instance/main.tf
    features = optional(object({
      fuse    = optional(bool, false)
      keyctl  = optional(bool, false)
      mknod   = optional(bool, false)
      mount   = optional(string, "")
      nesting = optional(bool, true)
    }))
  }))
  default = []

  validation {
    condition     = alltrue([for inst in var.lxc_instances : can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", inst.hostname))])
    error_message = "Hostnames must be lowercase alphanumeric with hyphens, starting and ending with alphanumeric characters."
  }

  validation {
    condition     = alltrue([for inst in var.lxc_instances : inst.vmid >= 100 && inst.vmid <= 999999999])
    error_message = "VMID must be between 100 and 999999999."
  }

  validation {
    condition     = alltrue([for inst in var.lxc_instances : can(regex("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}/[0-9]{1,2}$", inst.ip))])
    error_message = "IP addresses must be in CIDR notation (e.g., 10.0.0.1/24)."
  }

  validation {
    condition     = alltrue([for inst in var.lxc_instances : can(regex("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$", inst.gw))])
    error_message = "Gateway (gw) must be a valid IP address (e.g., 10.0.0.1)."
  }

  validation {
    condition     = alltrue([for inst in var.lxc_instances : inst.cores > 0 && inst.cores <= 128])
    error_message = "Cores must be between 1 and 128."
  }

  validation {
    condition     = alltrue([for inst in var.lxc_instances : inst.memory >= 128 && inst.memory <= 4194304])
    error_message = "Memory must be between 128 MB and 4194304 MB (4 TB)."
  }

  validation {
    condition     = alltrue([for inst in var.lxc_instances : can(regex("^\\d+[KMGT]?$", inst.disk_size))])
    error_message = "Disk size must be a number optionally followed by K/M/G/T (e.g., '100G', '512M', '1T')."
  }

  validation {
    condition     = alltrue([for inst in var.lxc_instances : inst.tag >= 0 && inst.tag <= 4094])
    error_message = "VLAN tag must be between 0 and 4094 (0 = no VLAN tagging)."
  }

  validation {
    condition     = alltrue([for inst in var.lxc_instances : inst.mac == null || can(regex("^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$", inst.mac))])
    error_message = "MAC address must be in format XX:XX:XX:XX:XX:XX or XX-XX-XX-XX-XX-XX, or null/omitted."
  }

  validation {
    condition     = alltrue([for inst in var.lxc_instances : inst.nameserver == null || can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", inst.nameserver))])
    error_message = "Nameserver must be a valid IP address (e.g., 8.8.8.8) or null/omitted."
  }

  validation {
    condition     = alltrue([for inst in var.lxc_instances : inst.searchdomain == null || can(regex("^([a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$", inst.searchdomain))])
    error_message = "Searchdomain must be a valid domain name (e.g., example.com) or null/omitted."
  }

  validation {
    condition     = length(var.lxc_instances) == length(distinct([for inst in var.lxc_instances : inst.vmid]))
    error_message = "All LXC VMIDs must be unique."
  }

  validation {
    condition     = length(var.lxc_instances) == length(distinct([for inst in var.lxc_instances : inst.hostname]))
    error_message = "All LXC hostnames must be unique."
  }
}
