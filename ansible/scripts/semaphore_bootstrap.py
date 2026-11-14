#!/usr/bin/env python3
"""Create/update the Semaphore project objects from ansible/configs/semaphore.yml.

Semaphore stores its whole configuration — projects, repositories, inventories,
environments, key store, templates, schedules — in a SQLite DB inside a Docker volume. None
of it is in git, so a lost volume means rebuilding ~15 interlinked objects by
hand. This script makes that state declarative and reproducible.

Idempotent: every object is matched by name, then PUT if it exists or POST if it
does not. Re-running is a no-op.

Renaming: give the object `previous_name: <old name>` for one apply. It is then
matched by either name and updated in place, so it keeps its id; a template
keeps its task history, which a delete-and-create would lose. Drop the key
once the rename is live.

Usage (the make targets set SEMAPHORE_URL and read SEMAPHORE_API_TOKEN from
kv/proxmox-infra/semaphore api_token unless it is already set):
  make -C ansible semaphore-bootstrap ARGS=--dry-run   # print what would change
  make -C ansible semaphore-bootstrap                  # apply
  make -C ansible semaphore-doctor                     # verify, exit 1 if not

Target the host directly, NOT semaphore.example.com: the ingress is behind
Authentik forward-auth, which an API token cannot traverse.

The SSH private key is deliberately NOT managed here — create it once in the UI
so the key material never passes through this script or the repo.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

CONFIG = Path(__file__).resolve().parent.parent / "configs" / "semaphore.yml"


class SemaphoreError(RuntimeError):
    pass


def _load_yaml(path: Path) -> dict[str, Any]:
    """Parse the config. PyYAML ships with ansible, which this repo requires."""
    try:
        import yaml
    except ImportError:  # pragma: no cover
        raise SemaphoreError("PyYAML not available — run inside the ansible venv")
    return yaml.safe_load(path.read_text())


class Client:
    def __init__(self, url: str, token: str, dry_run: bool = False) -> None:
        self.url = url.rstrip("/")
        self.token = token
        self.dry_run = dry_run

    def request(self, method: str, path: str, body: Any = None) -> Any:
        if self.dry_run and method in {"POST", "PUT", "DELETE"}:
            print(f"  DRY-RUN {method} {path} {json.dumps(body) if body else ''}")
            return {}
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(
            f"{self.url}/api{path}", data=data, method=method,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode(errors="replace")[:300]
            raise SemaphoreError(f"{method} {path} -> {exc.code}: {detail}") from exc
        except urllib.error.URLError as exc:
            raise SemaphoreError(f"{method} {path} unreachable: {exc.reason}") from exc

    def find(self, items: list[dict], name: str) -> dict | None:
        return next((i for i in items if i.get("name") == name), None)


def sync_project(api: Client, spec: dict) -> int:
    projects = api.request("GET", "/projects") or []
    existing = api.find(projects, spec["name"])
    if existing:
        print(f"project '{spec['name']}' exists (id {existing['id']})")
        return existing["id"]
    created = api.request("POST", "/projects", {
        "name": spec["name"], "alert": spec.get("alert", False),
    })
    print(f"project '{spec['name']}' created")
    return created.get("id", 0)


def sync_named(
    api: Client, pid: int, kind: str, specs: list[dict],
    build: Any, existing: list[dict] | None = None,
) -> dict[str, int]:
    """POST/PUT each spec by name; return {name: id}."""
    items = existing if existing is not None else (
        api.request("GET", f"/project/{pid}/{kind}") or []
    )
    ids: dict[str, int] = {}
    for spec in specs:
        name = spec["name"]
        found = api.find(items, name)
        if found is None and spec.get("previous_name"):
            found = api.find(items, spec["previous_name"])
        body = build(spec)
        body["project_id"] = pid
        if found:
            body["id"] = found["id"]
            api.request("PUT", f"/project/{pid}/{kind}/{found['id']}", body)
            ids[name] = found["id"]
            if found.get("name") != name:
                print(f"  {kind}: '{found.get('name')}' renamed to '{name}'")
            else:
                print(f"  {kind}: '{name}' updated")
        else:
            created = api.request("POST", f"/project/{pid}/{kind}", body)
            ids[name] = created.get("id", 0)
            print(f"  {kind}: '{name}' created")
    return ids


def apply(api: Client, cfg: dict) -> int:
    pid = sync_project(api, cfg["project"])

    keys = api.request("GET", f"/project/{pid}/keys") or []
    key_ids = {k["name"]: k["id"] for k in keys}
    for spec in cfg.get("keys", []):
        if spec["name"] not in key_ids:
            print(
                f"  MISSING key '{spec['name']}' — create it in the UI "
                "(Key Store, type SSH). Key material is never handled here.",
                file=sys.stderr,
            )
            return 1

    repo_ids = sync_named(
        api, pid, "repositories", cfg.get("repositories", []),
        lambda s: {
            "name": s["name"], "git_url": s["git_url"],
            "git_branch": s["git_branch"], "ssh_key_id": key_ids[s["ssh_key"]],
        },
    )

    inv_ids = sync_named(
        api, pid, "inventory", cfg.get("inventories", []),
        lambda s: {
            "name": s["name"], "type": s["type"], "inventory": s["inventory"],
            "ssh_key_id": key_ids[s["ssh_key"]],
        },
    )

    # `env` and `json` are stored as JSON strings, not objects.
    env_ids = sync_named(
        api, pid, "environment", cfg.get("environments", []),
        lambda s: {
            "name": s["name"],
            "env": json.dumps(s.get("env", {})),
            "json": json.dumps(s.get("json", {})),
        },
    )

    def template(s: dict) -> dict:
        body: dict[str, Any] = {
            "name": s["name"], "playbook": s["playbook"], "app": "ansible",
            "inventory_id": inv_ids[s["inventory"]],
            "repository_id": repo_ids[s["repository"]],
            "environment_id": env_ids[s["environment"]],
            "type": "",
        }
        if s.get("description"):
            body["description"] = s["description"]
        if s.get("arguments"):
            body["arguments"] = json.dumps(s["arguments"])
        if s.get("survey_vars"):
            body["survey_vars"] = s["survey_vars"]
        return body

    live_templates = api.request("GET", f"/project/{pid}/templates") or []
    tmpl_ids = sync_named(api, pid, "templates", cfg.get("templates", []),
                          template, existing=live_templates)

    # Cron is evaluated in SEMAPHORE_SCHEDULE_TIMEZONE (server-side, UTC
    # unless set). A schedule is matched by name like everything else.
    live_schedules = api.request("GET", f"/project/{pid}/schedules") or []
    sync_named(
        api, pid, "schedules", cfg.get("schedules", []),
        lambda s: {
            "name": s["name"], "cron_format": s["cron"],
            "template_id": tmpl_ids[s["template"]],
            "active": s.get("active", True), "type": "",
        },
        existing=live_schedules,
    )

    # Templates and schedules only: the config fully owns them, so one dropped
    # here should disappear from the UI rather than linger as a stale button
    # or a job that still fires. Keys, repositories, inventories and
    # environments are left alone — they may be referenced by objects this
    # config does not describe.
    # `live` was read before any rename, so a previous_name counts as wanted.
    for kind, live in (("templates", live_templates), ("schedules", live_schedules)):
        wanted = {
            n for i in cfg.get(kind, []) for n in (i["name"], i.get("previous_name")) if n
        }
        for item in live:
            if item["name"] not in wanted:
                api.request("DELETE", f"/project/{pid}/{kind}/{item['id']}")
                print(f"  {kind}: '{item['name']}' removed")
    return 0


def doctor(api: Client, cfg: dict) -> int:
    problems: list[str] = []
    projects = api.request("GET", "/projects") or []
    project = api.find(projects, cfg["project"]["name"])
    if not project:
        print(f"  PROBLEM: project '{cfg['project']['name']}' missing", file=sys.stderr)
        return 1
    pid = project["id"]

    for kind, specs in (
        ("keys", cfg.get("keys", [])),
        ("repositories", cfg.get("repositories", [])),
        ("inventory", cfg.get("inventories", [])),
        ("environment", cfg.get("environments", [])),
        ("templates", cfg.get("templates", [])),
        ("schedules", cfg.get("schedules", [])),
    ):
        live = api.request("GET", f"/project/{pid}/{kind}") or []
        names = {i.get("name") for i in live}
        for spec in specs:
            if spec["name"] not in names:
                problems.append(f"{kind}: '{spec['name']}' missing")

    sys.stderr.write(f"semaphore-doctor: project '{project['name']}' (id {pid})\n")
    for p in problems:
        sys.stderr.write(f"  PROBLEM: {p}\n")
    if problems:
        sys.stderr.write(f"semaphore-doctor: {len(problems)} problem(s)\n")
        return 1
    sys.stderr.write("semaphore-doctor: ok\n")
    return 0


def main() -> None:
    url = os.environ.get("SEMAPHORE_URL")
    token = os.environ.get("SEMAPHORE_API_TOKEN")
    if not url or not token:
        sys.exit("SEMAPHORE_URL and SEMAPHORE_API_TOKEN must be set")

    cfg = _load_yaml(CONFIG)
    api = Client(url, token, dry_run="--dry-run" in sys.argv)
    try:
        sys.exit(doctor(api, cfg) if "--doctor" in sys.argv else apply(api, cfg))
    except SemaphoreError as exc:
        sys.exit(f"error: {exc}")


if __name__ == "__main__":
    main()
