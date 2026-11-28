# `vault operator raft snapshot save`, nothing else.
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}
