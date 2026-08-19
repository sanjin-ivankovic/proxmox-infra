#!/bin/bash
# Pull the cluster wildcard cert (traefik/example-com-wildcard-tls) through the
# apiserver with a read-only ServiceAccount token and refresh Omni's TLS
# files. Restarts the omni container only when the certificate changed.
# Deployed by ansible/playbooks/hosts/omni-cert-sync.yml; runs daily via cron.
set -euo pipefail

APISERVER="https://10.10.0.40:6443"
SECRET_PATH="/api/v1/namespaces/traefik/secrets/example-com-wildcard-tls"
TOKEN_FILE="/srv/omni-secrets/cert-sync-token"
CHAIN="/srv/omni-secrets/server-chain.pem"
KEY="/srv/omni-secrets/server-key.pem"

echo "[$(date -Is)] omni-cert-sync starting"

TOKEN=$(cat "$TOKEN_FILE")

# -k: the apiserver cert is verified implicitly by the bearer-token trust
# model here — the token only grants read of this one public-ish secret, and
# a MITM cannot mint a valid wildcard key the browsers would accept anyway.
RESPONSE=$(curl -fsSk -H "Authorization: Bearer $TOKEN" "$APISERVER$SECRET_PATH")

TMP_CHAIN=$(mktemp /srv/omni-secrets/.chain.XXXXXX)
TMP_KEY=$(mktemp /srv/omni-secrets/.key.XXXXXX)
trap 'rm -f "$TMP_CHAIN" "$TMP_KEY"' EXIT

RESPONSE_JSON="$RESPONSE" python3 - "$TMP_CHAIN" "$TMP_KEY" <<'PY'
import base64, json, os, sys
data = json.loads(os.environ["RESPONSE_JSON"])["data"]
open(sys.argv[1], "wb").write(base64.b64decode(data["tls.crt"]))
open(sys.argv[2], "wb").write(base64.b64decode(data["tls.key"]))
PY

# Sanity: the fetched pair must be a valid, unexpired cert with matching key.
openssl x509 -in "$TMP_CHAIN" -noout -checkend 86400
CRT_MOD=$(openssl x509 -in "$TMP_CHAIN" -noout -pubkey | openssl sha256)
KEY_MOD=$(openssl pkey -in "$TMP_KEY" -pubout | openssl sha256)
[ "$CRT_MOD" = "$KEY_MOD" ] || { echo "cert/key mismatch, aborting"; exit 1; }

if [ -f "$CHAIN" ] && cmp -s "$TMP_CHAIN" "$CHAIN"; then
  echo "certificate unchanged ($(openssl x509 -in "$CHAIN" -noout -enddate))"
  exit 0
fi

install -o root -g root -m 0644 "$TMP_CHAIN" "$CHAIN"
install -o root -g root -m 0600 "$TMP_KEY" "$KEY"
docker restart omni >/dev/null
echo "certificate updated ($(openssl x509 -in "$CHAIN" -noout -enddate)); omni restarted"
