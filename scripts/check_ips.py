#!/usr/bin/env python3
"""Check that hand-written host IPs match the Terraform host lists.

Terraform's instance tfvars are the source of truth for every guest's IP
(and VMID). Several files repeat those values next to the host's name; this
check fails when one of them drifts after a re-IP or a rebuild:

  komodo/servers.toml                          [[server]] name -> address
  ansible/configs/technitium.yml               hosts: (A) and ptr: records
  ansible/inventory/group_vars/all/patching.yml os_patch_dns_probes
  ansible/inventory/talos/hosts.yml            ansible_host and vmid
  ansible/talos/patches/nodes/<node>.yaml      interface address

Only entries whose name is a Terraform host are compared; network gear,
aliases and service VIPs are out of scope. Runs from the repo root:
`make check-ips`, pre-commit and CI lint:host-ips.
"""

from __future__ import annotations

import json
import re
import sys
import tomllib
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
TFVARS = [
    ROOT / "terraform/lxc/instances/lxc.auto.tfvars",
    ROOT / "terraform/talos/instances/talos.auto.tfvars",
]
HOSTNAME = re.compile(r"^\s*hostname\s*=\s*\"([^\"]+)\"", re.M)


def terraform_hosts() -> dict[str, dict[str, str]]:
    """{hostname: {"ip": ..., "vmid": ...}} from both instance tfvars.

    Each host's attributes are read from its hostname line up to the next
    one; the blocks nest (features, mount points), so brace matching fails.
    """
    hosts: dict[str, dict[str, str]] = {}
    for path in TFVARS:
        text = path.read_text()
        marks = list(HOSTNAME.finditer(text))
        for i, m in enumerate(marks):
            body = text[m.start(): marks[i + 1].start() if i + 1 < len(marks) else len(text)]
            ip = re.search(r"^\s*ip\s*=\s*\"([\d.]+)/\d+\"", body, re.M)
            vmid = re.search(r"^\s*vmid\s*=\s*(\d+)", body, re.M)
            if not ip:
                sys.exit(f"check-ips: {path.name}: no ip for {m.group(1)}")
            hosts[m.group(1)] = {"ip": ip.group(1), "vmid": vmid.group(1) if vmid else ""}
    return hosts


def main() -> int:
    hosts = terraform_hosts()
    if not hosts:
        print("check-ips: no hosts parsed from the Terraform tfvars", file=sys.stderr)
        return 1
    problems: list[str] = []

    def expect(where: str, name: str, got: str, field: str = "ip") -> None:
        want = hosts[name][field]
        if str(got) != want:
            problems.append(f"{where}: {name} has {field} {got}, Terraform says {want}")

    servers = tomllib.loads((ROOT / "komodo/servers.toml").read_text()).get("server", [])
    for srv in servers:
        if srv["name"] in hosts:
            addr = re.search(r"//([\d.]+)", srv.get("config", {}).get("address", ""))
            expect("komodo/servers.toml", srv["name"], addr.group(1) if addr else "(none)")

    tech = yaml.safe_load((ROOT / "ansible/configs/technitium.yml").read_text())
    for name, ip in (tech.get("hosts") or {}).items():
        if name in hosts:
            expect("technitium.yml hosts", name, ip)
    for ip, name in (tech.get("ptr") or {}).items():
        if name in hosts:
            expect("technitium.yml ptr", name, ip)

    patching = yaml.safe_load((ROOT / "ansible/inventory/group_vars/all/patching.yml").read_text())
    for probe in patching.get("os_patch_dns_probes") or []:
        if probe["name"] in hosts:
            expect("patching.yml os_patch_dns_probes", probe["name"], probe["ip"])

    def walk(node: dict) -> None:
        for name, hv in (node.get("hosts") or {}).items():
            if name in hosts and hv:
                if "ansible_host" in hv:
                    expect("inventory/talos/hosts.yml", name, hv["ansible_host"])
                if "vmid" in hv:
                    expect("inventory/talos/hosts.yml", name, hv["vmid"], "vmid")
        for child in (node.get("children") or {}).values():
            walk(child or {})

    walk(yaml.safe_load((ROOT / "ansible/inventory/talos/hosts.yml").read_text())["all"])

    for patch in sorted((ROOT / "ansible/talos/patches/nodes").glob("*.yaml")):
        name = patch.stem
        if name not in hosts:
            continue
        docs = [d for d in yaml.safe_load_all(patch.read_text()) if d]
        addrs = [
            a.split("/")[0]
            for d in docs
            for i in (d.get("machine", {}).get("network", {}).get("interfaces") or [])
            for a in (i.get("addresses") or [])
        ]
        if hosts[name]["ip"] not in addrs:
            problems.append(
                f"talos/patches/nodes/{patch.name}: addresses {addrs}, Terraform says {hosts[name]['ip']}"
            )

    for p in problems:
        print(f"  MISMATCH {p}")
    print(f"check-ips: {len(hosts)} Terraform hosts, {len(problems)} mismatch(es)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
