#!/usr/bin/env python3
"""Converge Proxmox Backup Server jobs on ansible/configs/pbs.yml.

PBS keeps its job configuration in /etc/proxmox-backup/*.cfg on the PBS VM.
This script makes the parts we own declarative, through the PBS API:

- datastores: the properties listed per datastore (GC schedule, comment);
  undeclared properties such as the path are left alone
- namespaces: created when missing, never removed
- prune, verify and sync jobs: every declared job is converged property by
  property, and properties the job has live but the config omits are cleared

Idempotent: every object is compared with the live state and only changed when
it differs. Live jobs the config does not declare are reported, not deleted.

Usage:
  export PBS_API_TOKEN_ID='infra@pbs!config'
  export PBS_API_TOKEN_SECRET=<kv/proxmox-infra/pbs api_token_secret>
  ./pbs_bootstrap.py              # apply
  ./pbs_bootstrap.py --dry-run    # print what would change
  ./pbs_bootstrap.py --doctor     # exit 1 if live state differs

The token needs DatastoreAdmin on /datastore and Audit on /. Turning on
remove-vanished for a sync job additionally needs Datastore.Prune on the
target store, which DatastoreAdmin includes.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

CONFIG = Path(__file__).resolve().parent.parent / "configs" / "pbs.yml"
JOB_KINDS = ("prune", "verify", "sync")
# Keys the API returns that are identity or bookkeeping, not settings.
JOB_META = {"id", "digest"}


class PBSError(RuntimeError):
    pass


def _load_yaml(path: Path) -> dict[str, Any]:
    """Parse the config. PyYAML ships with ansible, which this repo requires."""
    try:
        import yaml
    except ImportError:  # pragma: no cover
        raise PBSError("PyYAML not available — run inside the ansible venv")
    return yaml.safe_load(path.read_text())


class Client:
    def __init__(self, url: str, token_id: str, secret: str, dry_run: bool = False) -> None:
        self.url = url.rstrip("/")
        self.auth = f"PBSAPIToken={token_id}:{secret}"
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
            raise PBSError(f"{method} {path} -> HTTP {exc.code}: {detail}") from exc
        except urllib.error.URLError as exc:
            raise PBSError(f"{method} {path} unreachable: {exc.reason}") from exc


class Run:
    """Collects changes; applies them unless dry-run/doctor."""

    def __init__(self, api: Client) -> None:
        self.api = api
        self.changes: list[str] = []
        self.notes: list[str] = []

    def change(self, line: str, method: str, path: str, body: dict[str, Any] | None = None) -> None:
        self.changes.append(line)
        print(f"  {line}")
        self.api.call(method, path, body)


def _norm(value: Any) -> Any:
    """Compare API output and config on equal footing (None == [] == '')."""
    if value in (None, "", []):
        return None
    if isinstance(value, list):
        return sorted((_norm(v) for v in value), key=json.dumps)
    if isinstance(value, dict):
        return {k: _norm(v) for k, v in value.items() if _norm(v) is not None}
    return value


def _diff(want: dict[str, Any], have: dict[str, Any], clear: bool) -> tuple[dict[str, Any], list[str]]:
    """Properties to set, and (when clear) live properties the config omits."""
    sets = {k: v for k, v in want.items() if _norm(v) != _norm(have.get(k))}
    drops = sorted(k for k in have if clear and k not in want and k not in JOB_META
                   and _norm(have[k]) is not None)
    return sets, drops


def _fmt(changes: dict[str, Any], drops: list[str], have: dict[str, Any]) -> str:
    parts = [f"{k}: {have.get(k)!r} -> {v!r}" for k, v in sorted(changes.items())]
    parts += [f"{k}: {have[k]!r} -> (unset)" for k in drops]
    return "; ".join(parts)


def sync_datastores(run: Run, cfg: dict) -> None:
    live = {d["name"]: d for d in run.api.call("GET", "config/datastore")}
    for name, want in (cfg.get("datastores") or {}).items():
        if name not in live:
            raise PBSError(f"datastore {name} does not exist; create it on PBS first")
        have = run.api.call("GET", f"config/datastore/{name}")
        sets, _ = _diff(want or {}, have, clear=False)
        if sets:
            run.change(f"~ datastore {name}: {_fmt(sets, [], have)}",
                       "PUT", f"config/datastore/{name}", sets)


def sync_namespaces(run: Run, cfg: dict) -> None:
    for store, names in (cfg.get("namespaces") or {}).items():
        live = {n["ns"] for n in run.api.call("GET", f"admin/datastore/{store}/namespace")}
        for ns in names or []:
            if ns in live:
                continue
            parent, _, leaf = ns.rpartition("/")
            body = {"name": leaf, **({"parent": parent} if parent else {})}
            run.change(f"+ namespace {store}:{ns}", "POST", f"admin/datastore/{store}/namespace", body)


def sync_jobs(run: Run, cfg: dict, kind: str) -> None:
    want_all = cfg.get(kind) or {}
    live = {j["id"]: j for j in run.api.call("GET", f"config/{kind}")}
    for job_id, want in want_all.items():
        want = dict(want or {})
        if job_id not in live:
            run.change(f"+ {kind} job {job_id}: {json.dumps(want, sort_keys=True)}",
                       "POST", f"config/{kind}", {"id": job_id, **want})
            continue
        have = live[job_id]
        sets, drops = _diff(want, have, clear=True)
        if sets or drops:
            body = dict(sets)
            if drops:
                body["delete"] = drops
            run.change(f"~ {kind} job {job_id}: {_fmt(sets, drops, have)}",
                       "PUT", f"config/{kind}/{job_id}", body)
    for job_id in sorted(set(live) - set(want_all)):
        run.notes.append(f"{kind} job {job_id} exists on PBS but not in pbs.yml (left alone)")


def main() -> None:
    url = os.environ.get("PBS_URL", "https://pbs.example.com:8007")
    token_id = os.environ.get("PBS_API_TOKEN_ID")
    secret = os.environ.get("PBS_API_TOKEN_SECRET")
    if not token_id or not secret:
        sys.exit("PBS_API_TOKEN_ID and PBS_API_TOKEN_SECRET must be set")
    doctor = "--doctor" in sys.argv
    api = Client(url, token_id, secret, dry_run=doctor or "--dry-run" in sys.argv)
    run = Run(api)
    try:
        cfg = _load_yaml(CONFIG)
        print("datastores")
        sync_datastores(run, cfg)
        print("namespaces")
        sync_namespaces(run, cfg)
        for kind in JOB_KINDS:
            print(f"{kind} jobs")
            sync_jobs(run, cfg, kind)
    except PBSError as exc:
        sys.exit(f"error: {exc}")
    for note in run.notes:
        print(f"  NOTE: {note}")
    label = "pbs-doctor" if doctor else "pbs"
    print(f"{label}: {len(run.changes)} change(s){'' if api.dry_run else ' applied'}")
    sys.exit(1 if doctor and run.changes else 0)


if __name__ == "__main__":
    main()
