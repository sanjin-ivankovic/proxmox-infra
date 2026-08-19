# ============================================================================
# LXC Instance Module - Variables
# ============================================================================

variable "instances" {
  description = "Map of LXC container configurations (hostname => config)"
  type = map(object({
    hostname     = string
    vmid         = number
    ip           = string
    gw           = string
    mac          = optional(string, "")
    cores        = number
    memory       = number
    swap         = number
    disk_size    = number
    unprivileged = bool
    start        = bool
    onboot       = bool
    tag          = optional(number, 0)
    nameserver   = optional(string, "")
    searchdomain = optional(string, "")
    tags         = list(string)
    target_node  = optional(string, "")
    storage      = optional(string, "")
    ostemplate   = optional(string, "")
    features = optional(object({
      fuse    = optional(bool, false)
      keyctl  = optional(bool, false)
      mknod   = optional(bool, false)
      mount   = optional(string, "")
      nesting = optional(bool, true)
    }))
  }))
}

variable "ssh_key_directory" {
  description = "Directory to store generated SSH keys (supports ~ expansion)"
  type        = string
  default     = "~/.ssh"
}

variable "target_node" {
  description = "Default Proxmox node to deploy containers on"
  type        = string
  default     = "pve"
}

variable "ostemplate" {
  description = "LXC OS template to use for containers"
  type        = string
}

variable "password" {
  description = "Root password for LXC containers"
  type        = string
  sensitive   = true
}

variable "deploy_public_keys" {
  description = <<-EOT
    Extra SSH public keys to authorize on every container (in addition to each
    container's generated per-host key). Use for any shared key a tool needs
    to SSH into every host.
  EOT
  type        = list(string)
  default     = []
}

variable "default_storage" {
  description = "Default storage backend for container rootfs"
  type        = string
  default     = "local-zfs"
}

variable "default_bridge" {
  description = "Default network bridge for containers"
  type        = string
  default     = "vmbr0"
}
