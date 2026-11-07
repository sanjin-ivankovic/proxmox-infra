#!/usr/bin/env python3
"""Converge Technitium DNS settings, zones/records and DHCP scopes on ansible/configs/technitium.yml.

Technitium keeps zones, records and DHCP scopes in its own files inside the
container volume. This script makes the parts we own declarative: the server
settings listed under `settings:` (on every node), the zones and their catalog
membership, static A/PTR records, and the DHCP scopes.

Idempotent: every object is compared with the live state and only changed when
it differs. Records registered by the DHCP server are left alone unless the
config claims their name; other undeclared records are reported, not deleted.

Usage:
  export TECHNITIUM_URL=http://10.110.0.10:5380
  export TECHNITIUM_API_TOKEN=<Administration -> Sessions -> Create Token>
  ./technitium_bootstrap.py              # apply
  ./technitium_bootstrap.py --dry-run    # print what would change
  ./technitium_bootstrap.py --doctor     # exit 1 if live state differs

Target technitium-1 directly: it is the cluster primary, and the HTTP API
(5380) is not exposed through Traefik with a token-friendly route.
"""

from __future__ import annotations

import ipaddress
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

CONFIG = Path(__file__).resolve().parent.parent / "configs" / "technitium.yml"
# Comment prefixes Technitium puts on records it owns: DHCP registrations and
# the cluster's own name-server records.
FOREIGN_COMMENTS = ("Via '", "Cluster managed record")


class TechnitiumError(RuntimeError):
    pass


def _load_yaml(path: Path) -> dict[str, Any]:
    """Parse the config. PyYAML ships with ansible, which this repo requires."""
    try:
        import yaml
    except ImportError:  # pragma: no cover
        raise TechnitiumError("PyYAML not available — run inside the ansible venv")
    return yaml.safe_load(path.read_text())


class Client:
    def __init__(self, url: str, token: str, dry_run: bool = False) -> None:
        self.url = url.rstrip("/")
        self.token = token
        self.dry_run = dry_run

    def call(self, path: str, write: bool = False, **params: Any) -> Any:
        if write and self.dry_run:
            return {}
        body = urllib.parse.urlencode(
            {k: _fmt(v) for k, v in params.items() if v is not None}
        ).encode()
        req = urllib.request.Request(
            f"{self.url}/api/{path}", data=body, method="POST",
            headers={
                "Authorization": f"Bearer {self.token}",
                "Content-Type": "application/x-www-form-urlencoded",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.load(resp)
        except urllib.error.HTTPError as exc:
            raise TechnitiumError(f"{path} -> HTTP {exc.code}") from exc
        except urllib.error.URLError as exc:
            raise TechnitiumError(f"{path} unreachable: {exc.reason}") from exc
        if data.get("status") != "ok":
            raise TechnitiumError(
                f"{path} -> {data.get('status')}: {data.get('errorMessage', '')}"
            )
        return data.get("response", {})


def _fmt(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def reverse_name(ip: str) -> tuple[str, str]:
    """10.140.0.41 -> ('41.0.40.10.in-addr.arpa', '0.140.10.in-addr.arpa')."""
    a, b, c, d = ip.split(".")
    zone = f"{c}.{b}.{a}.in-addr.arpa"
    return f"{d}.{zone}", zone


class Run:
    """Collects changes; applies them unless dry-run/doctor."""

    def __init__(self, api: Client) -> None:
        self.api = api
        self.changes: list[str] = []
        self.notes: list[str] = []

    def change(self, line: str, path: str, **params: Any) -> None:
        self.changes.append(line)
        print(f"  {line}")
        self.api.call(path, write=True, **params)


# --- settings ----------------------------------------------------------------

def _networks(values: list[str] | None) -> list[str]:
    """The API may return 10.110.0.12 or 10.110.0.12/32; compare as networks."""
    return sorted(str(ipaddress.ip_network(v, strict=False)) for v in values or [])


def sync_settings(run: Run, cfg: dict, token: str) -> None:
    spec = cfg["settings"]
    want = {
        "forwarders": list(spec["forwarders"]),
        "forwarderProtocol": spec["forwarder_protocol"],
        "qpmLimitBypassList": _networks(spec["rate_limit_bypass"]),
        "recursion": spec["recursion"],
        "recursionNetworkACL": _networks(spec["recursion_acl"]),
        "locallyServedDnsZones": spec["locally_served_zones"],
    }
    for node in spec["nodes"]:
        api = Client(f"http://{node}:5380", token, dry_run=run.api.dry_run)
        live = api.call("settings/get")
        have = {
            "forwarders": list(live.get("forwarders") or []),
            "forwarderProtocol": live.get("forwarderProtocol"),
            "qpmLimitBypassList": _networks(live.get("qpmLimitBypassList")),
            "recursion": live.get("recursion"),
            "recursionNetworkACL": _networks(live.get("recursionNetworkACL")),
            "locallyServedDnsZones": live.get("locallyServedDnsZones"),
        }
        diff = [k for k in want if _norm(have[k]) != _norm(want[k])]
        if not diff:
            continue
        line = f"~ settings {node}: " + ", ".join(
            f"{k} {have[k]} -> {want[k]}" for k in diff
        )
        run.changes.append(line)
        print(f"  {line}")
        api.call(
            "settings/set", write=True,
            forwarders=",".join(want["forwarders"]),
            forwarderProtocol=want["forwarderProtocol"],
            qpmLimitBypassList=",".join(want["qpmLimitBypassList"]),
            recursion=want["recursion"],
            recursionNetworkACL=",".join(want["recursionNetworkACL"]) or "false",
            locallyServedDnsZones=str(want["locallyServedDnsZones"]).lower(),
        )


# --- zones -------------------------------------------------------------------

def sync_zones(run: Run, cfg: dict) -> list[str]:
    zones = [cfg["zones"]["forward"], *cfg["zones"]["reverse"]]
    live = {z["name"]: z for z in run.api.call("zones/list")["zones"]}
    for name in zones:
        if name not in live:
            run.change(f"+ zone {name}", "zones/create", zone=name, type="Primary")
        options = {} if name not in live else run.api.call("zones/options/get", zone=name)
        if options.get("catalog") != cfg["catalog"]:
            run.change(
                f"~ zone {name}: catalog {options.get('catalog')} -> {cfg['catalog']}",
                "zones/options/set", zone=name, catalog=cfg["catalog"],
            )
    return zones


# --- records -----------------------------------------------------------------

def desired_records(cfg: dict) -> dict[tuple[str, str], tuple[str, set[str]]]:
    """{(fqdn, type): (zone, {values})} for every record the config owns."""
    fwd = cfg["zones"]["forward"]
    reverse = set(cfg["zones"]["reverse"])
    want: dict[tuple[str, str], tuple[str, set[str]]] = {}

    def add(fqdn: str, rtype: str, zone: str, value: str) -> None:
        key = (fqdn.lower(), rtype)
        want.setdefault(key, (zone, set()))[1].add(value)

    def add_ptr(ip: str, name: str) -> None:
        ipaddress.IPv4Address(ip)
        rname, rzone = reverse_name(ip)
        if rzone not in reverse:
            raise TechnitiumError(f"{name} ({ip}): no reverse zone {rzone} in config")
        if (rname, "PTR") in want:
            raise TechnitiumError(f"{ip}: PTR declared twice (hosts and ptr)")
        add(rname, "PTR", rzone, f"{name}.{fwd}")

    for host, ip in cfg.get("hosts", {}).items():
        add(f"{host}.{fwd}", "A", fwd, ip)
        add_ptr(ip, host)
    for ip, names in cfg.get("aliases", {}).items():
        for name in names:
            add(f"{name}.{fwd}", "A", fwd, ip)
    for ip, name in cfg.get("ptr", {}).items():
        add_ptr(ip, name)
    return want


def live_records(api: Client, zones: list[str]) -> dict[tuple[str, str], list[dict]]:
    live: dict[tuple[str, str], list[dict]] = {}
    for zone in zones:
        try:
            records = api.call(
                "zones/records/get", domain=zone, zone=zone, listZone=True
            )["records"]
        except TechnitiumError:
            continue  # zone created by this run (dry-run) — nothing live yet
        for r in records:
            if r["type"] in ("A", "PTR"):
                live.setdefault((r["name"].lower(), r["type"]), []).append(r)
    return live


def _value(r: dict) -> str:
    return r["rData"]["ipAddress"] if r["type"] == "A" else r["rData"]["ptrName"]


def sync_records(run: Run, cfg: dict, zones: list[str]) -> None:
    ttl = cfg["ttl"]
    want = desired_records(cfg)
    live = live_records(run.api, zones)
    value_key = {"A": "ipAddress", "PTR": "ptrName"}

    for (fqdn, rtype), (zone, values) in sorted(want.items()):
        have = live.get((fqdn, rtype), [])
        have_vals = {_value(r) for r in have}
        clean = all(r["ttl"] == ttl and not r.get("comments") for r in have)
        if have_vals == values and clean:
            continue
        verb = "~" if have else "+"
        detail = f"{sorted(have_vals)} -> {sorted(values)}" if have else sorted(values)
        for i, value in enumerate(sorted(values)):
            run.change(
                f"{verb} {rtype} {fqdn} {detail}" if i == 0 else f"  (+{value})",
                "zones/records/add", domain=fqdn, zone=zone, type=rtype, ttl=ttl,
                overwrite=(i == 0), **{value_key[rtype]: value},
            )

    absent = {(a["name"].lower(), a["type"]) for a in cfg.get("absent", [])}
    for key in sorted(absent):
        for r in live.get(key, []):
            run.change(
                f"- {key[1]} {key[0]} {_value(r)}", "zones/records/delete",
                domain=r["name"], zone=_zone_of(key[0], zones), type=key[1],
                **{value_key[key[1]]: _value(r)},
            )

    for key, records in sorted(live.items()):
        if key in want or key in absent:
            continue
        static = [r for r in records if not (r.get("comments") or "").startswith(FOREIGN_COMMENTS)]
        for r in static:
            run.notes.append(f"unmanaged {key[1]} {key[0]} {_value(r)}")


def _zone_of(fqdn: str, zones: list[str]) -> str:
    return max((z for z in zones if fqdn == z or fqdn.endswith("." + z)), key=len)


# --- DHCP --------------------------------------------------------------------

def desired_scope(name: str, spec: dict, defaults: dict) -> dict[str, Any]:
    s = {**defaults, **spec}
    net = ipaddress.IPv4Network(s["subnet"])
    base = str(net.network_address).rsplit(".", 1)[0]
    hours = s["lease_hours"]
    return {
        "startingAddress": f"{base}.1",
        "endingAddress": f"{base}.254",
        "subnetMask": str(net.netmask),
        "leaseTimeDays": hours // 24,
        "leaseTimeHours": hours % 24,
        "leaseTimeMinutes": 0,
        "routerAddress": f"{base}.1",
        "useThisDnsServer": False,
        "dnsServers": list(s["dns_servers"]),
        "ntpServers": [],
        "domainName": s["domain"],
        "domainSearchList": [s["domain"]],
        "dnsUpdates": s["dns_updates"],
        "dnsTtl": s["dns_ttl"],
        "exclusions": [
            {"startingAddress": f"{base}.{lo}", "endingAddress": f"{base}.{hi}"}
            for lo, hi in s["exclusions"]
        ],
        "reservedLeases": [
            {"hostName": r["host"], "hardwareAddress": r["mac"].upper(),
             "address": r["ip"], "comments": None}
            for r in s.get("reservations", [])
        ],
        "allowOnlyReservedLeases": s.get("reserved_only", False),
    }


def _scope_params(name: str, d: dict) -> dict[str, Any]:
    return {
        "name": name,
        **{k: d[k] for k in (
            "startingAddress", "endingAddress", "subnetMask", "leaseTimeDays",
            "leaseTimeHours", "leaseTimeMinutes", "routerAddress",
            "useThisDnsServer", "domainName", "dnsUpdates", "dnsTtl",
            "allowOnlyReservedLeases",
        )},
        "dnsServers": ",".join(d["dnsServers"]),
        "ntpServers": ",".join(d["ntpServers"]),
        "domainSearchList": ",".join(d["domainSearchList"]),
        "exclusions": "|".join(
            f"{e['startingAddress']}|{e['endingAddress']}" for e in d["exclusions"]
        ),
        "reservedLeases": "|".join(
            f"{r['hostName']}|{r['hardwareAddress']}|{r['address']}|"
            for r in d["reservedLeases"]
        ),
    }


def sync_dhcp(run: Run, cfg: dict) -> None:
    dhcp = cfg["dhcp"]
    live = {s["name"]: s for s in run.api.call("dhcp/scopes/list")["scopes"]}
    for name, spec in dhcp["scopes"].items():
        want = desired_scope(name, spec, dhcp["defaults"])
        have = run.api.call("dhcp/scopes/get", name=name) if name in live else {}
        diff = [k for k, v in want.items() if _norm(have.get(k)) != _norm(v)]
        if diff:
            run.change(
                f"{'~' if have else '+'} scope {name}: {', '.join(diff)}",
                "dhcp/scopes/set", **_scope_params(name, want),
            )
        if not live.get(name, {}).get("enabled"):
            run.change(f"~ scope {name}: enable", "dhcp/scopes/enable", name=name)
    for name in dhcp.get("absent", []):
        if name in live:
            run.change(f"- scope {name}", "dhcp/scopes/delete", name=name)


def _norm(value: Any) -> Any:
    """Compare API output and config on equal footing (None == [] == '')."""
    if value in (None, "", []):
        return None
    if isinstance(value, list):
        return sorted((_norm(v) for v in value), key=json.dumps)
    if isinstance(value, dict):
        return {k: _norm(v) for k, v in value.items() if _norm(v) is not None}
    if isinstance(value, str):
        return value.lower()
    return value


# --- entry -------------------------------------------------------------------

def main() -> None:
    url = os.environ.get("TECHNITIUM_URL", "http://10.110.0.10:5380")
    token = os.environ.get("TECHNITIUM_API_TOKEN")
    if not token:
        sys.exit("TECHNITIUM_API_TOKEN must be set")
    doctor = "--doctor" in sys.argv
    api = Client(url, token, dry_run=doctor or "--dry-run" in sys.argv)
    run = Run(api)
    try:
        cfg = _load_yaml(CONFIG)
        print("settings")
        sync_settings(run, cfg, token)
        print("zones")
        zones = sync_zones(run, cfg)
        print("records")
        sync_records(run, cfg, zones)
        print("dhcp")
        sync_dhcp(run, cfg)
    except TechnitiumError as exc:
        sys.exit(f"error: {exc}")
    for note in run.notes:
        print(f"  NOTE: {note}")
    label = "technitium-doctor" if doctor else "technitium"
    print(f"{label}: {len(run.changes)} change(s){'' if api.dry_run else ' applied'}")
    sys.exit(1 if doctor and run.changes else 0)


if __name__ == "__main__":
    main()
