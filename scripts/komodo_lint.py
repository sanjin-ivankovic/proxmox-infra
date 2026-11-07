#!/usr/bin/env python3
"""Lint komodo/*.toml and the compose files its stacks deploy.

Errors (always fatal):
  - a resource file in the sync's resource_path does not parse
  - duplicate names within a resource type
  - a stack's server or linked_repo is not declared
  - a stack's compose file or config_files path is missing from the repo
  - a config_files entry names a service its compose files do not define
  - a procedure execution names a stack that is not declared
  - `docker compose config` rejects a stack's compose file, rendered with the
    stack's environment ([[VAR]] resolved from komodo/variables.toml; secrets
    become dummies)

Policy findings (fatal with --strict):
  - a resource lacks the sync's match tag: with match_tags set, Komodo
    silently ignores an untagged resource instead of creating it (variables
    have no tags and are exempt)
  - a stack does not carry exactly one wave tag (wave-1 or wave-2), which
    the GitOps Apply stages select on
  - a repo file a compose mounts is not in the stack's config_files with
    requires = "Restart": the IfChanged waves would not notice the change,
    and a redeploy alone keeps the old single-file mount

Usage:
  scripts/komodo_lint.py                      # report policy findings
  scripts/komodo_lint.py --strict             # policy findings fail too
  scripts/komodo_lint.py --require-docker     # fail if docker compose is missing
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path
from typing import Any

import yaml

REPO = Path(__file__).resolve().parent.parent
KOMODO = REPO / "komodo"
MATCH_TAG = "iac"
THIS_REPO = "example-org/proxmox-infra"
TYPES = ("server", "stack", "procedure", "repo", "variable", "alerter", "action", "build")
UNTAGGED = ("variable",)
WAVES = ("wave-1", "wave-2")
VAR_REF = re.compile(r"\[\[([A-Za-z0-9_]+)\]\]")


def resource_files() -> list[Path]:
    sync = tomllib.loads((KOMODO / "resource-sync.toml").read_text())
    paths = sync["resource_sync"][0]["config"]["resource_path"]
    return [REPO / p for p in paths]


def stack_env(stack: dict[str, Any], variables: dict[str, str]) -> dict[str, str]:
    env = {}
    for line in stack["config"].get("environment", "").splitlines():
        if "=" not in line or line.lstrip().startswith("#"):
            continue
        key, _, value = line.partition("=")
        value = VAR_REF.sub(lambda m: variables.get(m.group(1), "lint-dummy"), value.strip())
        env[key.strip()] = value
    return env


def repo_mounts(compose_path: Path) -> list[Path]:
    """Repo files a compose bind-mounts (directories expanded to their files)."""
    compose = yaml.safe_load(compose_path.read_text()) or {}
    files: list[Path] = []
    for service in (compose.get("services") or {}).values():
        for volume in service.get("volumes") or []:
            source = volume.get("source") if isinstance(volume, dict) else volume.split(":", 1)[0]
            if not source or not source.startswith("."):
                continue
            target = (compose_path.parent / source).resolve()
            if target.is_dir():
                files.extend(sorted(f for f in target.rglob("*") if f.is_file()))
            elif target.exists():
                files.append(target)
    return files


def compose_config(compose_path: Path, env: dict[str, str]) -> str | None:
    with tempfile.NamedTemporaryFile("w", suffix=".env") as env_file:
        env_file.write("".join(f"{k}={v}\n" for k, v in env.items()))
        env_file.flush()
        result = subprocess.run(
            ["docker", "compose", "-f", str(compose_path), "--env-file", env_file.name, "config", "-q"],
            capture_output=True, text=True,
        )
    return None if result.returncode == 0 else (result.stderr.strip() or "failed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--strict", action="store_true", help="policy findings fail the run")
    parser.add_argument("--require-docker", action="store_true", help="fail if docker compose is unavailable")
    args = parser.parse_args()

    errors: list[str] = []
    findings: list[str] = []
    resources: dict[str, list[dict[str, Any]]] = {t: [] for t in TYPES}
    for path in resource_files():
        try:
            data = tomllib.loads(path.read_text())
        except (OSError, tomllib.TOMLDecodeError) as exc:
            errors.append(f"{path.relative_to(REPO)}: {exc}")
            continue
        for kind in TYPES:
            for item in data.get(kind, []):
                item["_file"] = path.relative_to(REPO)
                resources[kind].append(item)

    for kind, items in resources.items():
        seen: set[str] = set()
        for item in items:
            name = item.get("name", "?")
            if name in seen:
                errors.append(f"{item['_file']}: duplicate {kind} '{name}'")
            seen.add(name)
            tags = item.get("tags") or []
            if kind not in UNTAGGED and MATCH_TAG not in tags:
                findings.append(f"{item['_file']}: {kind} '{name}' lacks tag '{MATCH_TAG}'")
            if kind == "stack" and sum(t in WAVES for t in tags) != 1:
                findings.append(f"{item['_file']}: stack '{name}' needs exactly one of {', '.join(WAVES)}")

    servers = {s["name"] for s in resources["server"]}
    repos = {r["name"] for r in resources["repo"]}
    stacks = {s["name"]: s for s in resources["stack"]}
    variables = {v["name"]: str(v.get("value", "")) for v in resources["variable"]}
    docker = shutil.which("docker") is not None
    if not docker and args.require_docker:
        errors.append("docker compose is required (--require-docker) but docker is not installed")

    for name, stack in stacks.items():
        config = stack.get("config", {})
        where = f"{stack['_file']}: stack '{name}'"
        if config.get("server") not in servers:
            errors.append(f"{where}: unknown server '{config.get('server')}'")
        linked = config.get("linked_repo")
        if linked and linked not in repos:
            errors.append(f"{where}: unknown linked_repo '{linked}'")
        if not (linked or config.get("repo") == THIS_REPO):
            continue
        listed = {}
        compose_services: set[str] = set()
        for entry in config.get("config_files", []):
            listed[entry["path"]] = entry.get("requires", "None")
            if not (REPO / entry["path"]).is_file():
                errors.append(f"{where}: config_files path '{entry['path']}' does not exist")
        for rel in config.get("file_paths", []):
            compose_path = REPO / rel
            if not compose_path.is_file():
                errors.append(f"{where}: compose file '{rel}' does not exist")
                continue
            try:
                mounts = repo_mounts(compose_path)
            except yaml.YAMLError as exc:
                errors.append(f"{where}: '{rel}' is not valid YAML: {exc}".replace("\n", " "))
                continue
            compose_services |= set((yaml.safe_load(compose_path.read_text()) or {}).get("services") or {})
            for mounted in mounts:
                key = str(mounted.relative_to(REPO))
                if listed.get(key) != "Restart":
                    findings.append(f"{where}: mounted '{key}' is not in config_files with requires = \"Restart\"")
            if docker:
                problem = compose_config(compose_path, stack_env(stack, variables))
                if problem:
                    errors.append(f"{where}: docker compose config: {problem}")

        for entry in config.get("config_files", []):
            for service in entry.get("services", []):
                if compose_services and service not in compose_services:
                    errors.append(f"{where}: config_files '{entry['path']}' names unknown service '{service}'")

    for proc in resources["procedure"]:
        for stage in proc.get("config", {}).get("stage", []):
            for execution in stage.get("executions", []):
                target = execution.get("execution", {}).get("params", {}).get("stack")
                if target and target not in stacks:
                    errors.append(f"{proc['_file']}: procedure '{proc['name']}' targets unknown stack '{target}'")

    for line in errors:
        print(f"  ERROR {line}")
    for line in findings:
        print(f"  {'ERROR' if args.strict else 'note '} {line}")
    print(f"komodo-lint: {len(stacks)} stack(s), {len(errors)} error(s), {len(findings)} policy finding(s)"
          + ("" if docker else " (docker missing: compose configs not checked)"))
    return 1 if errors or (args.strict and findings) else 0


if __name__ == "__main__":
    sys.exit(main())
