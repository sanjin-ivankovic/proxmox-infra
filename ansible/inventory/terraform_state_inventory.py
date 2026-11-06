#!/usr/bin/env python3
"""Dynamic Ansible inventory from Terraform/OpenTofu state (via Terragrunt).

Reads live state straight from the R2 backend with `terragrunt state pull`
(so the R2/S3 endpoint config "just works" — no committed inventory files).
Emits one host per bpg LXC container / VM, named by its real hostname, grouped
by Proxmox tags, with ansible_host + the per-host SSH key Terraform generated.

Why a script and not cloud.terraform.terraform_state: that plugin can only name
hosts by a top-level state attribute (e.g. vm_id) for the bpg provider — it
cannot use the nested initialization.hostname, so hosts come out as 110/417/…
This wrapper produces real names (komodo, pihole-1, …) so `--limit komodo`
and `make ... HOST=komodo` work.

Usage (configured as the inventory in ansible.cfg):
  ansible-inventory -i inventory/terraform_state_inventory.py --graph
  ansible-inventory -i inventory/terraform_state_inventory.py --host komodo

Sources (INVENTORY_SOURCE):
  state (default)      Pull live state with terragrunt (the laptop).
  snapshot             Read hosts.snapshot.json next to this script instead, so
                       a runner needs no R2 credentials, terragrunt or provider
                       downloads (Semaphore). Patch-wave groups are still built
                       from group_vars/all/patching.yml at run time.
  --render             Write hosts.snapshot.json from live state. Backs
                       `make semaphore-files`; commit the result.

Operational extras (do not affect the emitted inventory contract):
  INVENTORY_CACHE=1    Cache each project's pulled state to a tempfile for
                       INVENTORY_CACHE_TTL seconds (default 60) so a burst of
                       ansible runs doesn't re-pull from R2 every time. Default
                       off — live pull is the proven path.
  ANSIBLE_SHARED_SSH_KEY
                       Path to ONE key used for every host, replacing the
                       per-host ~/.ssh/<hostname>_id_ed25519 default. Set on
                       runners that have no per-host keys (the Semaphore
                       container); unset on the laptop, where Terraform wrote
                       them.
  --doctor             Validate the inventory instead of emitting it: terragrunt
                       present, every host has an ansible_host + a key file that
                       exists, no group/host name collisions, and (state source)
                       hosts.snapshot.json matches live state. Backs
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

# One key for every host, for runners that have no per-host keys (see
# host_vars). Unset on the laptop, where Terraform wrote per-host keys.
SHARED_SSH_KEY = os.environ.get("ANSIBLE_SHARED_SSH_KEY")

SNAPSHOT_FILE = SCRIPT_DIR / "hosts.snapshot.json"
SOURCE = os.environ.get("INVENTORY_SOURCE", "state")

# Patch waves are defined once, in group_vars/all/patching.yml (os_patch_waves),
# and emitted here as real groups patch_<name> so `hosts:` and `--limit` can
# name them: a play's `hosts:` is resolved before group_vars load.
PATCHING_VARS = SCRIPT_DIR / "group_vars" / "all" / "patching.yml"


def patch_waves() -> dict[str, list[str]]:
    """os_patch_waves from patching.yml as {patch_<name>: [hosts]}."""
    import yaml  # PyYAML ships with ansible-core, so every runner has it.

    waves = yaml.safe_load(PATCHING_VARS.read_text())["os_patch_waves"]
    return {"patch_" + w["name"].replace("-", "_"): list(w["hosts"]) for w in waves}

# bpg resource types we turn into hosts.
HOST_TYPES = {
    "proxmox_virtual_environment_container",
    "proxmox_virtual_environment_vm",
}


def _cache_path(project: dict[str, Any]) -> Path:
    """Stable tempfile path for one project's cached state."""
    key = hashlib.sha256(project["path"].encode()).hexdigest()[:16]
    return Path(tempfile.gettempdir()) / f"ansible-tfstate-{key}.json"


def _init(cwd: Path, path: str) -> bool:
    """`terragrunt init` in cwd, retrying once with -upgrade -reconfigure; True on success.

    Semaphore reuses its checkout across runs (git pull, not a fresh clone) and
    .terraform.lock.hcl is gitignored, so after a provider constraint bump the
    stale lock fails plain init ("locked provider ... does not match configured
    version constraint"). -upgrade selects what a fresh clone would. A changed
    backend block in root.hcl (e.g. use_lockfile) fails init with "Backend
    configuration changed"; -reconfigure re-reads it without touching state,
    since bucket and key are unchanged. Trying plain init first keeps a healthy
    warm dir off the registry.
    """
    base = ["terragrunt", "init", "-no-color", "-input=false"]
    err: Exception | None = None
    for cmd in (base, [*base, "-upgrade", "-reconfigure"]):
        try:
            subprocess.run(
                cmd, cwd=cwd, capture_output=True, text=True, check=True, timeout=600,
            )
            return True
        except subprocess.CalledProcessError as exc:
            err = exc
        except (subprocess.TimeoutExpired, FileNotFoundError) as exc:
            err = exc
            break
    # The exception alone reads "exit status 1"; the cause is in tofu's stderr.
    detail = ""
    if isinstance(err, subprocess.CalledProcessError) and err.stderr:
        detail = "\n" + "\n".join(err.stderr.strip().splitlines()[-15:])
    sys.stderr.write(f"warn: init failed for {path}: {err}{detail}\n")
    return False


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

    # A pull needs an initialised working directory, so init on demand. A warm
    # dir is no guarantee: terragrunt auto-inits on pull and trips over the same
    # stale lock, so a pull that fails without a fresh init re-inits and retries.
    inited = not (cwd / ".terragrunt-cache").exists()
    if inited and not _init(cwd, project["path"]):
        return {}

    def pull() -> str:
        return subprocess.run(
            ["terragrunt", "state", "pull"],
            cwd=cwd, capture_output=True, text=True, check=True, timeout=600,
        ).stdout

    try:
        try:
            out = pull()
        except subprocess.CalledProcessError:
            if inited or not _init(cwd, project["path"]):
                raise
            out = pull()
        state = json.loads(out) if out.strip() else {}
    # FileNotFoundError covers terragrunt being absent entirely (CI images carry
    # no terragrunt), which --doctor reports rather than crashes on.
    except (
        subprocess.CalledProcessError,
        json.JSONDecodeError,
        FileNotFoundError,
        subprocess.TimeoutExpired,
    ) as exc:
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


def host_record(attrs: dict[str, Any]) -> dict[str, Any] | None:
    """The facts a host needs from state: hostname, IP, VMID, tags."""
    init = first(attrs.get("initialization")) or {}
    hostname = init.get("hostname")
    if not hostname:
        return None
    # ansible_host: prefer the agent-reported eth0, fall back to the configured CIDR.
    ip = (attrs.get("ipv4") or {}).get("eth0")
    if not ip:
        addr = first((first(init.get("ip_config")) or {}).get("ipv4")) or {}
        ip = (addr.get("address") or "").split("/")[0] or None
    return {
        "hostname": hostname,
        "ip": ip,
        "vmid": attrs.get("vm_id"),
        "tags": attrs.get("tags") or [],
    }


def host_vars(rec: dict[str, Any], project: dict[str, Any]) -> dict[str, Any]:
    # Expose as 'proxmox_tags' — 'tags' is a reserved Ansible var name.
    hv: dict[str, Any] = {"proxmox_tags": rec["tags"]}
    if rec.get("ip"):
        hv["ansible_host"] = rec["ip"]
    # vmid keys the Proxmox API path for per-host operations (e.g. pre-patch
    # snapshots at /nodes/<node>/lxc/<vmid>/snapshot). Emitted for every host so
    # a play never has to duplicate the hostname→vmid map.
    if rec.get("vmid") is not None:
        hv["vmid"] = rec["vmid"]
    if project.get("talos"):
        # Talos is driven via talosctl/kubectl from the control machine.
        hv["ansible_connection"] = "local"
    else:
        # SSH hosts (LXC): per-host key Terraform generated. A shared-key runner
        # (the Semaphore container has no per-host keys) sets
        # ANSIBLE_SHARED_SSH_KEY to one key used for every host; unset, this is
        # byte-identical to the laptop behaviour.
        hv["ansible_user"] = project.get("user", "root")
        hv["ansible_ssh_private_key_file"] = (
            SHARED_SSH_KEY or f"~/.ssh/{rec['hostname']}_id_ed25519"
        )
    return hv


def live_records() -> dict[str, list[dict[str, Any]]]:
    """Host records per project path, pulled from live state."""
    with ThreadPoolExecutor(max_workers=len(PROJECTS)) as pool:
        states = list(pool.map(pull_state, PROJECTS))
    out: dict[str, list[dict[str, Any]]] = {}
    for project, state in zip(PROJECTS, states):
        recs = []
        for res in state.get("resources", []):
            if res.get("type") not in HOST_TYPES:
                continue
            for inst in res.get("instances", []):
                rec = host_record(inst.get("attributes", {}))
                if rec:
                    recs.append(rec)
        out[project["path"]] = sorted(recs, key=lambda r: r["hostname"])
    return out


def snapshot_records() -> dict[str, list[dict[str, Any]]]:
    try:
        return json.loads(SNAPSHOT_FILE.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        sys.stderr.write(f"warn: cannot read {SNAPSHOT_FILE.name}: {exc}\n")
        return {}


def render() -> int:
    """Write hosts.snapshot.json from live state; refuse an empty result."""
    recs = live_records()
    total = sum(len(v) for v in recs.values())
    if not total:
        sys.stderr.write("render: no hosts in live state; snapshot not written\n")
        return 1
    SNAPSHOT_FILE.write_text(json.dumps(recs, indent=2, sort_keys=True) + "\n")
    sys.stderr.write(f"render: wrote {total} hosts to {SNAPSHOT_FILE.name}\n")
    return 0


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

    recs = snapshot_records() if SOURCE == "snapshot" else live_records()
    for project in PROJECTS:
        for rec in recs.get(project["path"], []):
            host = rec["hostname"]
            hv = host_vars(rec, project)
            inv["_meta"]["hostvars"][host] = hv
            add_group(project["group"], host)
            for tag in hv.get("proxmox_tags", []):
                # Skip a tag equal to the hostname (avoids a host/group name clash).
                if str(tag) == host:
                    continue
                add_group(safe_group(str(tag)), host)

    # Waves reference hosts by name; only emit those that actually exist, so a
    # decommissioned host leaves a smaller wave rather than an unresolvable one.
    known = set(inv["_meta"]["hostvars"])
    waves = patch_waves()
    for wave, members in waves.items():
        groups[wave] = {h for h in members if h in known}
    groups["patch_all"] = {h for m in waves.values() for h in m if h in known}
    # Deliberately empty. patch.yml targets this when a play's wave is not the
    # one selected; without it ansible warns "Could not match supplied host
    # pattern" on every single-wave run.
    groups.setdefault("patch_skipped", set())

    for name, members in groups.items():
        inv[name] = {"hosts": sorted(members)}
    return inv


def doctor() -> int:
    """Validate the inventory; print findings, return an exit code (0 == ok)."""
    problems: list[str] = []
    notes: list[str] = []

    # 1. terragrunt must be on PATH (the pull would otherwise silently warn).
    from shutil import which
    if SOURCE != "snapshot" and which("terragrunt") is None:
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

    # 3. The committed snapshot (Semaphore's source) must match live state.
    if SOURCE != "snapshot" and hostvars:
        if snapshot_records() != live_records():
            problems.append(
                f"{SNAPSHOT_FILE.name} differs from live state: run "
                "`make -C ansible semaphore-files` and commit the result"
            )

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
    elif "--render" in sys.argv:
        sys.exit(render())
    elif "--host" in sys.argv:
        host = sys.argv[sys.argv.index("--host") + 1]
        print(json.dumps(build()["_meta"]["hostvars"].get(host, {})))
    else:  # --list (default)
        print(json.dumps(build(), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
