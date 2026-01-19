# ============================================================================
# Compute Base Module - Outputs
# ============================================================================

output "public_keys" {
  description = "Map of hostnames to SSH public keys (OpenSSH format)"
  value = merge(
    # Generated keys for new instances
    {
      for hostname, _ in local.instances_needing_keys :
      hostname => tls_private_key.keys[hostname].public_key_openssh
    },
    # Existing keys read from disk for imported instances
    {
      for hostname, _ in local.instances_with_existing_keys :
      hostname => data.local_file.existing_public_keys[hostname].content
    }
  )
}

output "private_keys_openssh" {
  description = "Map of hostnames to SSH private keys (OpenSSH format) - SENSITIVE (only for generated keys)"
  value = {
    for hostname, _ in local.instances_needing_keys :
    hostname => tls_private_key.keys[hostname].private_key_openssh
  }
  sensitive = true
}

output "ssh_key_paths" {
  description = "Map of hostnames to SSH key file paths (private and public)"
  value = {
    for hostname, _ in var.instances :
    hostname => {
      private = "${local.ssh_key_path}/${hostname}_id_ed25519"
      public  = "${local.ssh_key_path}/${hostname}_id_ed25519.pub"
    }
  }
}

output "ssh_key_directory" {
  description = "Resolved SSH key directory path (with ~ expanded)"
  value       = local.ssh_key_path
}
