# ============================================================================
# Compute Base Module - Variables
# ============================================================================

variable "instances" {
  description = "Map of compute instances (hostname => config). Used to determine which SSH keys to generate. Can be empty if no instances are defined."
  type        = map(any)
  default     = {}
}

variable "ssh_key_directory" {
  description = "Directory to store generated SSH keys (supports ~ expansion)"
  type        = string
  default     = "~/.ssh"

  validation {
    condition     = length(var.ssh_key_directory) > 0
    error_message = "SSH key directory cannot be empty."
  }
}

variable "skip_instances" {
  description = "Map of instances to skip SSH key generation for (typically imported containers). Keys should match instance hostnames."
  type        = set(string)
  default     = []
}
