# ============================================================================
# K3s VMs - Variables
# ============================================================================
# This file defines all input variables for K3s VM deployment.
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

# ============================================================================
# 2. Infrastructure Defaults
# ============================================================================

variable "target_node" {
  description = "Default Proxmox node to deploy resources on"
  type        = string
  default     = "pve"
}

variable "default_storage" {
  description = "Default storage backend for K3s VMs"
  type        = string
  default     = "local-zfs"
}

variable "default_bridge" {
  description = "Default network bridge for K3s VMs"
  type        = string
  default     = "vmbr0"
}

variable "ssh_key_directory" {
  description = "Directory to store generated SSH keys (supports ~ expansion)"
  type        = string
  default     = "~/.ssh"
}

# ============================================================================
# 3. K3s VM-Specific Variables
# ============================================================================

variable "k3s_vm_template" {
  description = "Linux VM template to clone from for K3s nodes"
  type        = string
  default     = "debian-12-cloudinit"
}

variable "k3s_vm_install_qemu_guest_agent" {
  description = "Whether to install qemu-guest-agent via cloud-init"
  type        = bool
  default     = true
}

variable "k3s_vm_cicustom" {
  description = "Custom cloud-init snippet path for K3s VMs"
  type        = string
  default     = "vendor=local:snippets/qemu-guest-agent.yml"
}

variable "k3s_vm_instances" {
  description = "List of K3s VM configurations"
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
    bios             = optional(string, "seabios")
    machine          = optional(string, "q35")
    ssd              = optional(bool, true)
    discard          = optional(bool, true)
    iothread         = optional(bool, true)
    cache            = optional(string, "none")
    nameserver       = optional(string)
    searchdomain     = optional(string)
    ciuser           = optional(string, "root")
    full_clone       = optional(bool, true)
    enable_rng       = optional(bool, true)
    startup          = optional(string, "")
    description      = optional(string, "")
    k3s_role         = string # "master" or "worker" — required for K3s nodes
    preserve_ssh_key = optional(bool, false)
    prevent_destroy  = optional(bool, false)
  }))
  default = []

  validation {
    condition     = alltrue([for inst in var.k3s_vm_instances : can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", inst.hostname))])
    error_message = "Hostnames must be lowercase alphanumeric with hyphens, starting and ending with alphanumeric characters."
  }

  validation {
    condition     = alltrue([for inst in var.k3s_vm_instances : inst.vmid >= 100 && inst.vmid <= 999999999])
    error_message = "VMID must be between 100 and 999999999."
  }

  validation {
    condition     = alltrue([for inst in var.k3s_vm_instances : can(regex("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}/[0-9]{1,2}$", inst.ip))])
    error_message = "IP addresses must be in CIDR notation (e.g., 10.0.0.1/24)."
  }

  validation {
    condition     = alltrue([for inst in var.k3s_vm_instances : can(regex("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$", inst.gw))])
    error_message = "Gateway must be a valid IP address."
  }

  validation {
    condition     = alltrue([for inst in var.k3s_vm_instances : contains(["master", "worker"], inst.k3s_role)])
    error_message = "k3s_role must be either 'master' or 'worker'."
  }

  validation {
    condition     = length(var.k3s_vm_instances) == length(distinct([for inst in var.k3s_vm_instances : inst.vmid]))
    error_message = "All K3s VM VMIDs must be unique."
  }

  validation {
    condition     = length(var.k3s_vm_instances) == length(distinct([for inst in var.k3s_vm_instances : inst.hostname]))
    error_message = "All K3s VM hostnames must be unique."
  }
}
