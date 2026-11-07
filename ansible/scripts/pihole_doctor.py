#!/usr/bin/env python3
"""Verify the live Pi-hole pair against the repo. Read-only.

The repo is the expected state: every FTLCONF_* value in the compose of the
node's Komodo stack (komodo/stacks.toml), rendered with that stack's NODE,
and the lists pihole-updatelists applies from
services/pihole/pihole-updatelists.conf (remote sources are fetched the same
way, /lists/ files come from services/pihole/lists/). The doctor logs in,
only reads, logs out, and exits 1 on any difference, including between the two
nodes.

Pi-hole v6 has no read-only API role; the guarantee is that this script only
sends GET besides the session login and logout.

Credentials: one `<node> <password>` line per Pi-hole (the app password from
Settings > Web interface / API), in PIHOLE_CREDENTIALS or in the file named by
PIHOLE_CREDENTIALS_FILE (which wins). A line without a node applies to every
node not listed explicitly. `make -C ansible pihole-doctor` renders
PIHOLE_CREDENTIALS from vault_pihole_app_passwords.

Usage:
  make -C ansible pihole-doctor                 # both nodes
  make -C ansible pihole-doctor NODES=pihole-2  # only the named nodes
"""

from __future__ import annotations

import json
import os
import re
import sys
import tomllib
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parent.parent.parent
LISTS = REPO / "services" / "pihole" / "lists"
UPDATELISTS_CONF = REPO / "services" / "pihole" / "pihole-updatelists.conf"
STACKS = REPO / "komodo" / "stacks.toml"
# ${VAR}, ${VAR:?msg}, ${VAR:-default}: only the name is resolved.
COMPOSE_VAR = re.compile(r"\$\{(\w+)(?::?[-?][^}]*)?\}")
# Only the Pi-hole LXCs that run (docs/NETWORK.md, Filtering resolvers).
NODES = {"pihole-1": "10.110.0.12", "pihole-2": "10.110.0.13"}


def api_base(node: str) -> str:
    """The node's API URL: by IP by default, so it works while the cluster is
    down. PIHOLE_API_VIA=traefik uses https://pihole<N>.example.com (Traefik's
    lan route) for callers the firewall keeps off the web port, i.e. Semaphore."""
    if os.environ.get("PIHOLE_API_VIA") == "traefik":
        return f"https://{node.replace('-', '')}.example.com/api"
    return f"http://{NODES[node]}/api"
# Write-only or masked in GET /api/config.
SKIP_FTLCONF = {"webserver_api_password"}


class PiholeError(RuntimeError):
    pass


def _load_yaml(path: Path) -> dict[str, Any]:
    """Parse a compose file. PyYAML ships with ansible, which this repo requires."""
    try:
        import yaml
    except ImportError:  # pragma: no cover
        raise PiholeError("PyYAML not available — run inside the ansible venv")
    return yaml.safe_load(path.read_text())


class Client:
    def __init__(self, base: str, password: str) -> None:
        self.base = base
        self.sid = self._call("POST", "auth", {"password": password})["session"]["sid"]
        if not self.sid:
            raise PiholeError("login refused (wrong app password?)")

    def _call(self, method: str, path: str, body: Any = None) -> Any:
        headers = {"Content-Type": "application/json"}
        if getattr(self, "sid", None):
            headers["X-FTL-SID"] = self.sid
        req = urllib.request.Request(
            f"{self.base}/{path}", method=method, headers=headers,
            data=json.dumps(body).encode() if body is not None else None,
        )
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                raw = resp.read()
                return json.loads(raw) if raw.strip() else {}
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode(errors="replace")[:200]
            raise PiholeError(f"{method} {path} -> {exc.code}: {detail}") from exc
        except urllib.error.URLError as exc:
            raise PiholeError(f"{method} {path} unreachable: {exc.reason}") from exc

    def get(self, path: str) -> Any:
        return self._call("GET", path)

    def logout(self) -> None:
        # Sessions are capped (webserver.api.max_sessions); never leave one behind.
        try:
            self._call("DELETE", "auth")
        except PiholeError:
            pass


def parse_entries(text: str) -> set[str]:
    """List entries, parsed the way pihole-updatelists does."""
    entries = set()
    for line in text.splitlines():
        line = re.sub(r"\s+#\s*\S.*$", "", line).strip()
        if line and not line.startswith(("#", "=")):
            entries.add(line)
    return entries


def updatelists_sources() -> dict[str, list[str]]:
    """{key: [source, ...]} from the *_URL keys of pihole-updatelists.conf."""
    sources = {}
    for line in UPDATELISTS_CONF.read_text().splitlines():
        match = re.match(r'^([A-Z_]+_URL)\s*=\s*"?([^"]*)"?\s*$', line.strip())
        if match and match.group(2):
            sources[match.group(1)] = match.group(2).split()
    return sources


def expected(key: str, sources: dict[str, list[str]]) -> set[str]:
    """Merged entries of one *_URL key: remote sources fetched, /lists/ from the repo."""
    entries = set()
    for source in sources.get(key, []):
        if source.startswith("/lists/"):
            entries |= parse_entries((LISTS / source.removeprefix("/lists/")).read_text())
            continue
        try:
            with urllib.request.urlopen(source, timeout=30) as resp:
                entries |= parse_entries(resp.read().decode(errors="replace"))
        except urllib.error.URLError as exc:
            raise PiholeError(f"fetch {source}: {exc.reason}") from exc
    return entries


def ftlconf(node: str) -> dict[str, str]:
    """FTLCONF_* env of a node's Pi-hole service, keyed by config path (dns.upstreams).

    The compose comes from the node's Komodo stack and is rendered with that
    stack's plain environment values (NODE, ...); a value that still needs a
    [[VAR]] or secret is skipped.
    """
    stack = next(s for s in tomllib.loads(STACKS.read_text())["stack"] if s["name"] == node)
    stack_env = {}
    for line in stack["config"].get("environment", "").splitlines():
        key, sep, value = line.partition("=")
        if sep and "[[" not in value:
            stack_env[key.strip()] = value.strip()

    def render(value: Any) -> str:
        return COMPOSE_VAR.sub(lambda m: stack_env.get(m.group(1), m.group(0)), str(value))

    compose = _load_yaml(REPO / stack["config"]["file_paths"][0])
    service = next(s for s in compose["services"].values() if render(s.get("container_name")) == node)
    return {
        key[len("FTLCONF_"):].replace("_", "."): render(value)
        for key, value in service["environment"].items()
        if key.startswith("FTLCONF_") and key[len("FTLCONF_"):] not in SKIP_FTLCONF
        and "${" not in render(value)
    }


def lookup(config: dict, path: str) -> Any:
    for part in path.split("."):
        if not isinstance(config, dict) or part not in config:
            return KeyError
        config = config[part]
    return config


def matches(live: Any, want: str) -> bool:
    if isinstance(live, bool):
        return str(live).lower() == want.lower()
    if isinstance(live, list):
        return live == [v for v in want.split(";") if v]
    return str(live) == want


def check_node(node: str, api: Client, want: dict[str, set[str]]) -> tuple[list[str], dict]:
    problems = []
    blocking = api.get("dns/blocking").get("blocking")
    if blocking != "enabled":
        problems.append(f"blocking is {blocking}")
    gravity = api.get("info/ftl")["ftl"]["database"]["gravity"]
    if not gravity:
        problems.append("gravity is empty")

    config = api.get("config")["config"]
    for path, value in sorted(ftlconf(node).items()):
        live = lookup(config, path)
        if live is KeyError:
            problems.append(f"{path}: not in /api/config (misspelt FTLCONF_ key?)")
        elif not matches(live, value):
            problems.append(f"{path}: live {json.dumps(live)} != compose {json.dumps(value)}")

    lists = [entry for entry in api.get("lists")["lists"] if entry["enabled"]]
    domains = [entry for entry in api.get("domains")["domains"] if entry["enabled"]]
    state = {
        "blocklists": {e["address"] for e in lists if e["type"] == "block"},
        "allowlist": {e["domain"] for e in domains if (e["type"], e["kind"]) == ("allow", "exact")},
        "regex-deny": {e["domain"] for e in domains if (e["type"], e["kind"]) == ("deny", "regex")},
    }
    for name, live in state.items():
        for entry in sorted(want[name] - live):
            problems.append(f"{name}: missing {entry}")
        for entry in sorted(live - want[name]):
            problems.append(f"{name}: not in Git: {entry}")
    # A warning, not drift: remote collections can carry dead lists the repo
    # does not control.
    for entry in lists:
        if entry["type"] == "block" and not entry.get("number"):
            print(f"  ! {node} blocklists: {entry['address']} has no domains (download failed?)")
    print(f"  {node}: blocking {blocking}, gravity {gravity}, {len(lists)} list(s), {len(domains)} domain(s)")
    return problems, state


def load_credentials(text: str) -> dict[str, str]:
    """{node: password}; the key '*' holds a node-less default line."""
    creds: dict[str, str] = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        node, _, secret = line.partition(" ") if " " in line else ("*", "", line)
        creds[node] = secret.strip()
    return creds


def main() -> None:
    path = os.environ.get("PIHOLE_CREDENTIALS_FILE")
    if path:
        try:
            text = Path(path).read_text()
        except OSError as exc:
            sys.exit(f"credentials: {exc}")
    else:
        text = os.environ.get("PIHOLE_CREDENTIALS", "")
        if not text.strip():
            sys.exit("set PIHOLE_CREDENTIALS or PIHOLE_CREDENTIALS_FILE (make -C ansible pihole-doctor does)")
    creds = load_credentials(text)
    nodes = sys.argv[1:] or list(NODES)
    unknown = [n for n in nodes if n not in NODES]
    if unknown:
        sys.exit(f"unknown node(s) {', '.join(unknown)}; known: {', '.join(NODES)}")

    sources = updatelists_sources()
    try:
        want = {
            "blocklists": expected("BLOCKLISTS_URL", sources),
            "allowlist": expected("WHITELIST_URL", sources),
            "regex-deny": expected("REGEX_BLACKLIST_URL", sources),
        }
    except PiholeError as exc:
        sys.exit(f"expected lists: {exc}")

    failed = False
    states = {}
    for node in nodes:
        password = creds.get(node) or creds.get("*")
        if not password:
            print(f"  ERROR {node}: no credentials in {path}", file=sys.stderr)
            failed = True
            continue
        try:
            api = Client(api_base(node), password)
            try:
                problems, states[node] = check_node(node, api, want)
            finally:
                api.logout()
        except (PiholeError, KeyError) as exc:
            print(f"  ERROR {node}: {exc!r}", file=sys.stderr)
            failed = True
            continue
        for problem in problems:
            print(f"  ~ {node} {problem}")
        failed |= bool(problems)

    if len(states) == 2 and len(set(json.dumps(s, sort_keys=True, default=sorted) for s in states.values())) > 1:
        print("  ~ the nodes' lists differ from each other")
        failed = True
    print(f"pihole-doctor: {'drift' if failed else 'ok'} ({', '.join(nodes)})")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
