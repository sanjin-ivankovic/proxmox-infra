# ============================================================================
# Talos VM Module - Variables
# ============================================================================

variable "instances" {
  description = "Map of Talos VM configurations (hostname => config)"
  type = map(object({
    hostname     = string
    vmid         = number
    ip           = string
    gw           = string
    mac          = optional(string)
    cores        = number
    memory       = number
    disk_size    = string
    onboot       = bool
    start        = bool
    tags         = list(string)
    target_node  = optional(string)
    storage      = optional(string)
    tag          = optional(number, 0)
    sockets      = optional(number, 1)
    cpu_type     = optional(string, "host")
    bios         = optional(string, "ovmf")
    machine      = optional(string, "q35")
    ssd          = optional(number, 1)
    discard      = optional(string, "on")
    iothread     = optional(number, 1)
    cache        = optional(string, "none")
    startup      = optional(string, "")
    description  = optional(string, "Managed by Terraform")
    talos_role   = optional(string, "worker")
  }))
}

variable "target_node" {
  description = "Default Proxmox node to deploy VMs on"
  type        = string
  default     = "pve"
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

variable "talos_iso_storage" {
  description = "Proxmox storage containing Talos ISO"
  type        = string
  default     = "local"
}

variable "talos_iso_file" {
  description = "Talos ISO filename in Proxmox storage"
  type        = string
  default     = "nocloud-amd64.iso"
}
