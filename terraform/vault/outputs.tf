# The RoleID is an identifier, not a credential: the timer also needs a
# SecretID, which never reaches state.
output "raft_snapshot_role_id" {
  description = "RoleID of the raft-snapshot AppRole"
  value       = vault_approle_auth_backend_role.raft_snapshot.role_id
}

output "mcp_reader_role_id" {
  description = "RoleID of the mcp-reader AppRole (homelab MCP plugin)"
  value       = vault_approle_auth_backend_role.mcp_reader.role_id
}

output "semaphore_role_id" {
  description = "RoleID of the semaphore AppRole"
  value       = vault_approle_auth_backend_role.semaphore.role_id
}
