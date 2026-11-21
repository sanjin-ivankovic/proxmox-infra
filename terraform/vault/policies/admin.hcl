# Operators (userpass). Everything, including sudo paths such as
# sys/storage/raft and sys/audit; the root token is revoked after setup.
path "*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list", "sudo"]
}
