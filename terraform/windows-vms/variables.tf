# ============================================================================
# Windows VMs - Variables
# ============================================================================
# This file defines all input variables for Windows VM deployment.
# Variables are organized by:
#   1. Proxmox Connection
#   2. Infrastructure Defaults
#   3. Windows VM-Specific Variables
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
  description = "Default storage backend for Windows VMs (can be overridden per-instance)"
  type        = string
  default     = "local-zfs"
}

variable "default_bridge" {
  description = "Default network bridge for Windows VMs (can be overridden per-instance)"
  type        = string
  default     = "vmbr0"
}

variable "ssh_key_directory" {
  description = "Directory to store generated SSH keys (supports ~ expansion)"
  type        = string
  default     = "~/.ssh"
}

# ============================================================================
# 3. Windows VM-Specific Variables
# ============================================================================

variable "windows_vm_template" {
  description = "Windows VM template to clone from (e.g., 'windows-server-2022-std')"
  type        = string
  default     = "windows-server-2022-std"
}

variable "windows_vm_instances" {
  description = "List of Windows VM configurations"
  type = list(object({
    hostname         = string
    vmid             = number
    ip               = string
    gw               = string
    mac              = optional(string)
    cores            = number
    memory           = number
    disk_size        = string
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
    ssd              = optional(number, 1)
    discard          = optional(string, "on")
    iothread         = optional(number, 1)
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
    preserve_ssh_key = optional(bool, false) # Skip SSH key generation for imported hosts
  }))
  default = []

  validation {
    condition     = alltrue([for inst in var.windows_vm_instances : can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", inst.hostname))])
    error_message = "Hostnames must be lowercase alphanumeric with hyphens, starting and ending with alphanumeric characters."
  }

  validation {
    condition     = alltrue([for inst in var.windows_vm_instances : inst.vmid >= 100 && inst.vmid <= 999999999])
    error_message = "VMID must be between 100 and 999999999."
  }

  validation {
    condition     = alltrue([for inst in var.windows_vm_instances : can(regex("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}/[0-9]{1,2}$", inst.ip))])
    error_message = "IP addresses must be in CIDR notation (e.g., 10.0.0.1/24)."
  }

  validation {
    condition     = alltrue([for inst in var.windows_vm_instances : can(regex("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$", inst.gw))])
    error_message = "Gateway (gw) must be a valid IP address (e.g., 10.0.0.1)."
  }

  validation {
    condition     = alltrue([for inst in var.windows_vm_instances : inst.cores > 0 && inst.cores <= 128])
    error_message = "Cores must be between 1 and 128."
  }

  validation {
    condition     = alltrue([for inst in var.windows_vm_instances : inst.memory >= 2048 && inst.memory <= 4194304])
    error_message = "Memory must be between 2048 MB (2 GB) and 4194304 MB (4 TB) for Windows VMs."
  }

  validation {
    condition     = alltrue([for inst in var.windows_vm_instances : can(regex("^\\d+[KMGT]?$", inst.disk_size))])
    error_message = "Disk size must be a number optionally followed by K/M/G/T (e.g., '100G', '512M', '1T')."
  }

  validation {
    condition     = alltrue([for inst in var.windows_vm_instances : inst.tag >= 0 && inst.tag <= 4094])
    error_message = "VLAN tag must be between 0 and 4094 (0 = no VLAN tagging)."
  }

  validation {
    condition     = alltrue([for inst in var.windows_vm_instances : inst.sockets > 0 && inst.sockets <= 16])
    error_message = "Sockets must be between 1 and 16."
  }

  validation {
    condition     = alltrue([for inst in var.windows_vm_instances : contains(["host", "kvm64", "qemu64", "qemu32"], inst.cpu_type) || can(regex("^custom-", inst.cpu_type))])
    error_message = "CPU type must be 'host', 'kvm64', 'qemu64', 'qemu32', or start with 'custom-'."
  }

  validation {
    condition     = alltrue([for inst in var.windows_vm_instances : contains(["seabios", "ovmf"], inst.bios)])
    error_message = "BIOS must be either 'seabios' (legacy) or 'ovmf' (UEFI). Windows Server 2022 requires 'ovmf'."
  }

  validation {
    condition     = alltrue([for inst in var.windows_vm_instances : contains(["q35", "i440fx"], inst.machine)])
    error_message = "Machine type must be either 'q35' (modern) or 'i440fx' (legacy)."
  }

  validation {
    condition     = alltrue([for inst in var.windows_vm_instances : contains(["none", "writeback", "writethrough", "unsafe", "directsync"], inst.cache)])
    error_message = "Cache mode must be one of: none, writeback, writethrough, unsafe, directsync."
  }

  validation {
    condition     = alltrue([for inst in var.windows_vm_instances : contains(["std", "qxl", "vmware", "cirrus", "virtio", "none"], inst.vga_type)])
    error_message = "VGA type must be one of: std, qxl, vmware, cirrus, virtio, none."
  }

  validation {
    condition     = alltrue([for inst in var.windows_vm_instances : inst.nameserver == null || can(regex("^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})(\\s+[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})*$", inst.nameserver))])
    error_message = "Nameserver must be one or more valid IP addresses separated by spaces (e.g., '8.8.8.8' or '8.8.8.8 8.8.4.4')."
  }

  validation {
    condition     = alltrue([for inst in var.windows_vm_instances : inst.searchdomain == null || can(regex("^([a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$", inst.searchdomain))])
    error_message = "Searchdomain must be a valid domain name (e.g., example.com) or null/omitted."
  }

  validation {
    condition     = alltrue([for inst in var.windows_vm_instances : inst.mac == null || can(regex("^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$", inst.mac))])
    error_message = "MAC address must be in format XX:XX:XX:XX:XX:XX or XX-XX-XX-XX-XX-XX, or null/omitted."
  }

  validation {
    condition     = length(var.windows_vm_instances) == length(distinct([for inst in var.windows_vm_instances : inst.vmid]))
    error_message = "All Windows VM VMIDs must be unique."
  }

  validation {
    condition     = length(var.windows_vm_instances) == length(distinct([for inst in var.windows_vm_instances : inst.hostname]))
    error_message = "All Windows VM hostnames must be unique."
  }
}

# ============================================================================
# SSH Key Management for Imported Resources
# ============================================================================

variable "imported_instances" {
  description = "Set of hostnames for imported instances that already have SSH keys (skip key generation)"
  type        = set(string)
  default     = []
}
