#!/usr/bin/env python3
"""Run a Komodo Procedure through its GitLab-style webhook listener.

Used by CI (komodo:redeploy-images) and by hand. The listener authenticates
the X-Gitlab-Token header against Core's webhook secret, read here from
KOMODO_WEBHOOK_SECRET (never a command-line argument). Exits non-zero on any
non-2xx answer. A 2xx only means Komodo started the run; its result shows in
komodo_updates and in a ProcedureFailed alert.

Usage:
  KOMODO_WEBHOOK_SECRET=... scripts/komodo_trigger.py "Redeploy Images"
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

KOMODO_URL = os.environ.get("KOMODO_URL", "https://komodo.example.com")
BRANCH = os.environ.get("KOMODO_BRANCH", "main")


def main() -> int:
    if len(sys.argv) != 2:
        sys.exit("usage: komodo_trigger.py <procedure name or id>")
    secret = os.environ.get("KOMODO_WEBHOOK_SECRET")
    if not secret:
        sys.exit("KOMODO_WEBHOOK_SECRET is not set")
    procedure = urllib.parse.quote(sys.argv[1], safe="")
    url = f"{KOMODO_URL}/listener/gitlab/procedure/{procedure}/{BRANCH}"
    request = urllib.request.Request(
        url, method="POST", data=json.dumps({"ref": f"refs/heads/{BRANCH}"}).encode(),
        headers={"Content-Type": "application/json", "X-Gitlab-Token": secret,
                 "X-Gitlab-Event": "Push Hook"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            print(f"komodo: started '{sys.argv[1]}' (HTTP {response.status})")
            return 0
    except urllib.error.HTTPError as exc:
        print(f"komodo: '{sys.argv[1]}' rejected (HTTP {exc.code}): {exc.read()[:200]!r}", file=sys.stderr)
    except urllib.error.URLError as exc:
        print(f"komodo: {KOMODO_URL} unreachable: {exc.reason}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
