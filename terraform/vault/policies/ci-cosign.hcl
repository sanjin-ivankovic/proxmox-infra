# GitLab CI signing: cosign `--key hashivault://cosign` reads the public key
# and asks Vault to sign; the private key never leaves Vault.
path "transit/keys/cosign" {
  capabilities = ["read"]
}

path "transit/sign/cosign" {
  capabilities = ["update"]
}

path "transit/sign/cosign/*" {
  capabilities = ["update"]
}
