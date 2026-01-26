# ============================================================================
# LXC Instance Module - Variables
# ============================================================================

variable "instances" {
  description = "Map of LXC container configurations (hostname => config)"
  type = map(object({
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
    preserve_ssh_key = optional(bool, false)
    prevent_destroy  = optional(bool, false)
    features = optional(object({
      fuse    = optional(bool, false)
      keyctl  = optional(bool, false)
      mknod   = optional(bool, false)
      mount   = optional(string, "")
      nesting = optional(bool, true)
    }))
  }))
}

variable "ssh_public_keys" {
  description = "Map of hostnames to SSH public keys (from compute-base module)"
  type        = map(string)
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
