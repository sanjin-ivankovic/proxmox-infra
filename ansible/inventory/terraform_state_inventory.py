#!/usr/bin/env python3
"""Dynamic Ansible inventory from Terraform/OpenTofu state (via Terragrunt).

Reads live state straight from the R2 backend with `terragrunt state pull`
(so the R2/S3 endpoint config "just works" — no committed inventory files).
Emits one host per bpg LXC container / VM, named by its real hostname, grouped
by Proxmox tags, with ansible_host + the per-host SSH key Terraform generated.

Why a script and not cloud.terraform.terraform_state: that plugin can only name
hosts by a top-level state attribute (e.g. vm_id) for the bpg provider — it
cannot use the nested initialization.hostname, so hosts come out as 110/417/…
This wrapper produces real names (komodo, adguard-1, …) so `--limit komodo`
and `make ... HOST=komodo` work.

Usage (configured as the inventory in ansible.cfg):
  ansible-inventory -i inventory/terraform_state_inventory.py --graph
  ansible-inventory -i inventory/terraform_state_inventory.py --host komodo

Operational extras (do not affect the emitted inventory contract):
  INVENTORY_CACHE=1    Cache each project's pulled state to a tempfile for
                       INVENTORY_CACHE_TTL seconds (default 60) so a burst of
                       ansible runs doesn't re-pull from R2 every time. Default
                       off — live pull is the proven path.
  --doctor             Validate the inventory instead of emitting it: terragrunt
                       present, every host has an ansible_host + a key file that
                       exists, and no group/host name collisions. Backs
                       `make inventory-doctor`. Exits non-zero on any problem.
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

# Repo-relative Terraform projects. Each is pulled via Terragrunt.
SCRIPT_DIR = Path(__file__).resolve().parent
# `user` is the STEADY-STATE connection user (post-bootstrap). It becomes the
# per-host `ansible_user`, which OUTRANKS `remote_user`/`--user` in Ansible's
# precedence. Bootstrap is the only play that needs root, so 01-bootstrap.yml
# sets `ansible_user: root` as a PLAY VAR (higher precedence than this hostvar)
# to actually force the root connection — `--user root` alone does not. Setting
# maintainer here makes every other play (configure, periphery, updates, …) connect
# correctly by default.
PROJECTS: list[dict[str, Any]] = [
    {"path": "../../terraform/lxc", "group": "lxc_containers", "user": "maintainer"},
    {"path": "../../terraform/talos", "group": "talos_cluster", "talos": True},
]

# bpg resource types we turn into hosts.
HOST_TYPES = {
    "proxmox_virtual_environment_container",
    "proxmox_virtual_environment_vm",
}


def _cache_path(project: dict[str, Any]) -> Path:
    """Stable tempfile path for one project's cached state."""
    key = hashlib.sha256(project["path"].encode()).hexdigest()[:16]
    return Path(tempfile.gettempdir()) / f"ansible-tfstate-{key}.json"


def pull_state(project: dict[str, Any]) -> dict[str, Any]:
    """`terragrunt state pull` for one project; empty dict on any failure.

    With INVENTORY_CACHE=1, a fresh-enough cached copy is reused and a
    successful pull is written back. The cache is purely a latency optimization
    — it never changes WHAT is emitted, only how often R2 is hit.
    """
    cwd = (SCRIPT_DIR / project["path"]).resolve()
    if not cwd.exists():
        return {}

    cache_on = os.environ.get("INVENTORY_CACHE") == "1"
    cache_file = _cache_path(project)
    if cache_on:
        try:
            ttl = int(os.environ.get("INVENTORY_CACHE_TTL", "60"))
        except ValueError:
            ttl = 60
        if cache_file.exists() and (time.time() - cache_file.stat().st_mtime) < ttl:
            try:
                return json.loads(cache_file.read_text() or "{}")
            except json.JSONDecodeError:
                pass  # fall through to a live pull

    try:
        out = subprocess.run(
            ["terragrunt", "state", "pull"],
            cwd=cwd, capture_output=True, text=True, check=True,
        ).stdout
        state = json.loads(out) if out.strip() else {}
    except (subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        sys.stderr.write(f"warn: state pull failed for {project['path']}: {exc}\n")
        return {}

    if cache_on:
        try:
            cache_file.write_text(json.dumps(state))
        except OSError:
            pass  # caching is best-effort
    return state


def first(seq: Any) -> Any:
    """Return seq[0] for the bpg single-nested-block lists, else seq."""
    return seq[0] if isinstance(seq, list) and seq else seq


def safe_group(name: str) -> str:
    """Ansible group names can't contain hyphens — use underscores."""
    return name.replace("-", "_")


def host_from_instance(attrs: dict[str, Any], project: dict[str, Any]) -> tuple[str, dict[str, Any]] | None:
    init = first(attrs.get("initialization")) or {}
    hostname = init.get("hostname")
    # ansible_host: prefer the agent-reported eth0, fall back to the configured CIDR.
    ip = (attrs.get("ipv4") or {}).get("eth0")
    if not ip:
        ipv4 = first(first(init.get("ip_config")) or {})  # ip_config[0]
        addr = first((first(init.get("ip_config")) or {}).get("ipv4")) or {}
        ip = (addr.get("address") or "").split("/")[0] or None
    if not hostname:
        return None

    # Expose as 'proxmox_tags' — 'tags' is a reserved Ansible var name.
    hv: dict[str, Any] = {"proxmox_tags": attrs.get("tags") or []}
    if ip:
        hv["ansible_host"] = ip
    if project.get("talos"):
        # Talos is driven via talosctl/kubectl from the control machine.
        hv["ansible_connection"] = "local"
    else:
        # SSH hosts (LXC): per-host key Terraform generated.
        hv["ansible_user"] = project.get("user", "root")
        hv["ansible_ssh_private_key_file"] = f"~/.ssh/{hostname}_id_ed25519"
    return hostname, hv


def build() -> dict[str, Any]:
    inv: dict[str, Any] = {"_meta": {"hostvars": {}}}
    groups: dict[str, set[str]] = {}

    def add_group(name: str, host: str) -> None:
        groups.setdefault(name, set()).add(host)

    # Pre-declare each project's group so it always resolves, even with zero
    # hosts (e.g. talos_cluster has no SSH hosts in this dynamic inventory; the
    # Talos nodes come from the static inventory/talos/hosts.yml). Empty groups
    # simply list no hosts.
    for project in PROJECTS:
        groups.setdefault(project["group"], set())

    with ThreadPoolExecutor(max_workers=len(PROJECTS)) as pool:
        states = list(pool.map(pull_state, PROJECTS))

    for project, state in zip(PROJECTS, states):
        for res in state.get("resources", []):
            if res.get("type") not in HOST_TYPES:
                continue
            for inst in res.get("instances", []):
                parsed = host_from_instance(inst.get("attributes", {}), project)
                if not parsed:
                    continue
                host, hv = parsed
                inv["_meta"]["hostvars"][host] = hv
                add_group(project["group"], host)
                for tag in hv.get("proxmox_tags", []):
                    # Skip a tag equal to the hostname (avoids a host/group name clash).
                    if str(tag) == host:
                        continue
                    add_group(safe_group(str(tag)), host)

    for name, members in groups.items():
        inv[name] = {"hosts": sorted(members)}
    return inv


def doctor() -> int:
    """Validate the inventory; print findings, return an exit code (0 == ok)."""
    problems: list[str] = []
    notes: list[str] = []

    # 1. terragrunt must be on PATH (the pull would otherwise silently warn).
    from shutil import which
    if which("terragrunt") is None:
        problems.append("terragrunt not found on PATH (state pull will fail)")

    inv = build()
    hostvars = inv["_meta"]["hostvars"]
    groups = {k for k in inv if k != "_meta"}

    if not hostvars:
        problems.append(
            "no hosts resolved — terragrunt auth/state unreachable, or all "
            "projects empty"
        )

    for host, hv in sorted(hostvars.items()):
        if not hv.get("ansible_host"):
            problems.append(f"{host}: missing ansible_host (no IP in state)")
        key = hv.get("ansible_ssh_private_key_file")
        if key:
            key_path = Path(key).expanduser()
            if not key_path.exists():
                problems.append(f"{host}: SSH key not found: {key} ({key_path})")
        # Talos hosts intentionally have no key (local connection).

    # 2. host/group name collisions break --limit semantics.
    collisions = groups & set(hostvars)
    for name in sorted(collisions):
        problems.append(f"name collision: '{name}' is both a host and a group")

    empty = sorted(g for g in groups if not inv[g].get("hosts"))
    if empty:
        notes.append(f"empty groups (expected for unused projects): {', '.join(empty)}")

    sys.stderr.write(f"inventory-doctor: {len(hostvars)} hosts, {len(groups)} groups\n")
    for n in notes:
        sys.stderr.write(f"  note: {n}\n")
    for p in problems:
        sys.stderr.write(f"  PROBLEM: {p}\n")
    if problems:
        sys.stderr.write(f"inventory-doctor: {len(problems)} problem(s) found\n")
        return 1
    sys.stderr.write("inventory-doctor: ok\n")
    return 0


def main() -> None:
    if "--doctor" in sys.argv:
        sys.exit(doctor())
    elif "--host" in sys.argv:
        host = sys.argv[sys.argv.index("--host") + 1]
        print(json.dumps(build()["_meta"]["hostvars"].get(host, {})))
    else:  # --list (default)
        print(json.dumps(build(), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
