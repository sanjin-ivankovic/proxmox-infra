# The homelab MCP plugin (mcp-plugins drift scope `vault`): which secret paths
# exist and their version metadata. kv/metadata never returns secret values;
# kv/data, which does, is not granted.
path "kv/metadata/*" {
  capabilities = ["list", "read"]
}
