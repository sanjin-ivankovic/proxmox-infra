#!/usr/bin/env bash
# Run one Komodo execution through km and fail unless Komodo reports success.
#
# km 2.3.4 exits 0 whatever happens: an API error (unknown stack, auth) is
# only an ERROR log line, and a run that fails only prints "EXECUTION FAILED"
# after polling the update. This passes km's output through and exits 1
# unless the run printed "EXECUTION SUCCESSFUL" and neither failure marker.
# Credentials: km's own ~/.config/komodo/ config.
#
# Usage:
#   scripts/km-run.sh deploy-stack pihole-2
#   scripts/km-run.sh run-procedure "GitOps Apply"

set -uo pipefail

if [ $# -eq 0 ]; then
    echo "usage: $0 <km execute subcommand> [args...]" >&2
    exit 2
fi

out=$(mktemp)
trap 'rm -f "$out"' EXIT

km execute --yes "$@" 2>&1 | tee "$out"

if grep -q 'EXECUTION SUCCESSFUL' "$out" && ! grep -qE 'EXECUTION FAILED|ERROR' "$out"; then
    exit 0
fi
echo "km: '$*' did not succeed" >&2
exit 1
