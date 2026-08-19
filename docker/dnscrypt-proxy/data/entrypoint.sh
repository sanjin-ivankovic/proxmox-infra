#!/bin/bash

###############################################################################
# Entrypoint for dnscrypt-proxy container
###############################################################################

set -e

CONFIG_FILE="/var/cache/dnscrypt-proxy/dnscrypt-proxy.toml"

echo "==================================================================="
echo "dnscrypt-proxy"
echo "==================================================================="
echo "Config:     ${CONFIG_FILE}"
echo "==================================================================="
echo "Starting dnscrypt-proxy..."
echo "==================================================================="

# Start dnscrypt-proxy in foreground
exec dnscrypt-proxy -config "${CONFIG_FILE}"
