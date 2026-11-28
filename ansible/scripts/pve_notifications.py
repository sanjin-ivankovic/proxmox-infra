#!/usr/bin/env python3
"""Converge the Proxmox VE ntfy webhook target and matcher.

The vzdump jobs (terraform/backup) run with notification-mode
notification-system; this script declares where those notifications go,
from configs/notifications.yml through proxmox_notify.py. The bpg/proxmox
Terraform provider has no notification resources.

Usage:
  export PVE_API_TOKEN_ID=<kv/terraform/proxmox api_token_id>
  export PVE_API_TOKEN_SECRET=<kv/terraform/proxmox api_token_secret>
  export NTFY_BACKUPS_TOKEN=<kv/proxmox-infra/ntfy-backups token>
  ./pve_notifications.py                  # apply
  ./pve_notifications.py --dry-run        # print what would change
  ./pve_notifications.py --doctor         # exit 1 if live state differs
  ./pve_notifications.py --rotate-token   # resend the ntfy token

The token and its user need PVEMappingAdmin on /mapping/notifications.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

import proxmox_notify


def _load_yaml(path: Path) -> dict[str, Any]:
    try:
        import yaml
    except ImportError:  # pragma: no cover
        raise RuntimeError("PyYAML not available — run inside the ansible venv")
    return yaml.safe_load(path.read_text())


class Client:
    def __init__(self, url: str, token_id: str, secret: str, dry_run: bool) -> None:
        self.url = url.rstrip("/")
        self.auth = f"PVEAPIToken={token_id}={secret}"
        self.dry_run = dry_run

    def call(self, method: str, path: str, body: dict[str, Any] | None = None) -> Any:
        if method != "GET" and self.dry_run:
            return None
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(
            f"{self.url}/api2/json/{path}", data=data, method=method,
            headers={"Authorization": self.auth, "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.load(resp).get("data")
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode(errors="replace").strip()
            raise RuntimeError(f"{method} {path} -> HTTP {exc.code}: {detail}") from exc
        except urllib.error.URLError as exc:
            raise RuntimeError(f"{method} {path} unreachable: {exc.reason}") from exc


def main() -> None:
    url = os.environ.get("PVE_URL", "https://pve.example.com:8006")
    token_id = os.environ.get("PVE_API_TOKEN_ID")
    secret = os.environ.get("PVE_API_TOKEN_SECRET")
    if not token_id or not secret:
        sys.exit("PVE_API_TOKEN_ID and PVE_API_TOKEN_SECRET must be set")
    doctor = "--doctor" in sys.argv
    api = Client(url, token_id, secret, dry_run=doctor or "--dry-run" in sys.argv)
    changes: list[str] = []

    def change(line: str, method: str, path: str, body: dict[str, Any] | None = None) -> None:
        changes.append(line)
        print(f"  {line}")
        api.call(method, path, body)

    print("notifications")
    try:
        proxmox_notify.sync(api.call, change, "cluster/notifications",
                            proxmox_notify.load(_load_yaml),
                            rotate="--rotate-token" in sys.argv,
                            dry_run=api.dry_run)
    except RuntimeError as exc:
        sys.exit(f"error: {exc}")
    label = "pve-notify-doctor" if doctor else "pve-notify"
    print(f"{label}: {len(changes)} change(s){'' if api.dry_run else ' applied'}")
    sys.exit(1 if doctor and changes else 0)


if __name__ == "__main__":
    main()
