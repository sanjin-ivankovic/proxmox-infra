# ============================================================================
# Windows VM Module - Variables
# ============================================================================

variable "instances" {
  description = "Map of Windows VM configurations (hostname => config)"
  type = map(object({
    hostname         = string
    vmid             = number
    ip               = string
    gw               = string
    mac              = optional(string)
    cores            = number
    memory           = number
    disk_size        = number
    onboot           = bool
    start            = bool
    tags             = list(string)
    target_node      = optional(string)
    storage          = optional(string)
    tag              = optional(number, 0)
    sockets          = optional(number, 1)
    cpu_type         = optional(string, "host")
    bios             = optional(string, "ovmf")
    machine          = optional(string, "q35")
    ssd              = optional(bool, true)
    discard          = optional(bool, true)
    iothread         = optional(bool, true)
    cache            = optional(string, "writeback")
    nameserver       = optional(string)
    searchdomain     = optional(string)
    ciuser           = optional(string, "Administrator")
    full_clone       = optional(bool, true)
    enable_tpm       = optional(bool, true)
    tablet           = optional(bool, true)
    vga_type         = optional(string, "std")
    startup          = optional(string, "")
    description      = optional(string, "")
    preserve_ssh_key = optional(bool, false)
  }))
}

variable "ssh_public_keys" {
  description = "Map of hostnames to SSH public keys (from compute-base module)"
  type        = map(string)
}

variable "target_node" {
  description = "Default Proxmox node to deploy VMs on"
  type        = string
  default     = "pve"
}

variable "clone_template_id" {
  description = "VMID of the Windows VM template to clone from (required for new VMs)"
  type        = number
  default     = null
}

variable "default_storage" {
  description = "Default storage backend for VM disks"
  type        = string
  default     = "local-zfs"
}

variable "default_bridge" {
  description = "Default network bridge for VMs"
  type        = string
  default     = "vmbr0"
}
