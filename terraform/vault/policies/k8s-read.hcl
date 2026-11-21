# The External Secrets Operator: read the cluster's secrets, kv/k8s/*.
path "kv/data/k8s/*" {
  capabilities = ["read"]
}
