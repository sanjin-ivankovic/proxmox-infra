#!/usr/bin/env python3
"""
Terraform Inventory Generator for Ansible.

Generates static YAML inventory files from Terraform state.
Runs 'terraform output -json' in each project directory and writes
per-project and merged Ansible inventory files.
"""

from __future__ import annotations

import json
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

import yaml

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

TERRAFORM_PROJECTS: list[dict[str, Any]] = [
    {
        "path": "../../terraform/lxc",
        "output_file": "../lxc/inventory/hosts.yml",
        "group_name": "lxc_containers",
    },
    {
        "path": "../../terraform/linux-vms",
        "output_file": "../linux-vms/inventory/hosts.yml",
        "group_name": "linux_vms",
    },
    {
        "path": "../../terraform/talos-vms",
        "output_file": "../talos/inventory/hosts.yml",
        "group_name": "talos_cluster",
        "talos": True,
    },
    {
        "path": "../../terraform/windows-vms",
        "output_file": "../windows-vms/inventory/hosts.yml",
        "group_name": "windows_vms",
    },
]

INVENTORY_HEADER = """\
# ============================================================================
# Ansible Inventory ({group})
# ============================================================================
# Auto-generated from Terraform state - DO NOT EDIT MANUALLY
# Regenerate with: cd ansible && make inventory-all
# ============================================================================

"""

# Internal fields from Terraform output that should not appear in host vars
_SKIP_KEYS = frozenset({"type", "groups", "talos_role"})

# Talos group vars appended to the talos inventory file
TALOS_VARS: dict[str, str] = {
    "ansible_connection": "local",
    "ansible_python_interpreter": "/usr/bin/python3",
    "talos_config_dir": "{{ playbook_dir }}/../../talos/configs",
    "talos_config_file": "{{ talos_config_dir }}/talosconfig",
    "talos_kubeconfig_file": "{{ talos_config_dir }}/kubeconfig",
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).resolve().parent


def get_terraform_output(project: dict[str, Any]) -> dict[str, Any]:
    """Run 'terraform output -json' in the given project directory."""
    abs_path = (SCRIPT_DIR / project["path"]).resolve()

    if not abs_path.exists():
        sys.stderr.write(f"Warning: Project path not found: {abs_path}\n")
        return {}

    try:
        result = subprocess.run(
            ["terraform", "output", "-json"],
            cwd=abs_path,
            capture_output=True,
            text=True,
            check=True,
        )
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as exc:
        sys.stderr.write(f"Error running terraform in {project['path']}: {exc.stderr}\n")
        return {}
    except json.JSONDecodeError:
        sys.stderr.write(f"Error decoding JSON from {project['path']}\n")
        return {}


def build_host_vars(host_data: dict[str, Any]) -> dict[str, Any]:
    """Build host vars dict, excluding null/empty values and internal fields."""
    return {
        key: value
        for key, value in host_data.items()
        if key not in _SKIP_KEYS and value is not None and value != ""
    }


def write_inventory_file(
    path: Path,
    group_name: str,
    inventory: dict[str, Any],
    extra_raw: str = "",
) -> None:
    """Write an Ansible YAML inventory file with standard header."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as fh:
        fh.write(INVENTORY_HEADER.format(group=group_name))
        yaml.dump(inventory, fh, default_flow_style=False, sort_keys=False)
        if extra_raw:
            fh.write(extra_raw)


def _build_talos_vars_block() -> str:
    """Build the raw YAML vars block for the Talos inventory."""
    lines = [
        "",
        "  vars:",
        "    # Connection settings (Talos uses API, not SSH)",
    ]
    for key, value in TALOS_VARS.items():
        if key == "talos_config_dir":
            lines.append("")
            lines.append("    # Talos-specific variables")
        lines.append(f'    {key}: "{value}"')
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> None:
    # Fetch Terraform outputs in parallel
    with ThreadPoolExecutor(max_workers=len(TERRAFORM_PROJECTS)) as pool:
        outputs_list = list(pool.map(get_terraform_output, TERRAFORM_PROJECTS))

    project_summaries: list[str] = []
    talos_controlplane: dict[str, Any] = {}
    talos_workers: dict[str, Any] = {}
    merged_groups: dict[str, dict[str, Any]] = {}

    for project, outputs in zip(TERRAFORM_PROJECTS, outputs_list):
        if "ansible_info" not in outputs:
            sys.stderr.write(f"Warning: No ansible_info output in {project['path']}\n")
            continue

        ansible_info = outputs["ansible_info"].get("value", {})
        if not ansible_info:
            sys.stderr.write(f"Warning: Empty ansible_info in {project['path']}\n")
            continue

        is_talos = project.get("talos", False)
        project_hosts: dict[str, Any] = {}

        for hostname, host_data in ansible_info.items():
            host_vars = build_host_vars(host_data)

            if is_talos:
                talos_role = host_data.get("talos_role", "")
                if talos_role == "controlplane":
                    talos_controlplane[hostname] = host_vars
                else:
                    talos_workers[hostname] = host_vars
                    if talos_role != "worker":
                        sys.stderr.write(
                            f"Warning: Unknown talos_role '{talos_role}' for {hostname}, "
                            "treating as worker\n"
                        )
            else:
                project_hosts[hostname] = host_vars

        # Write per-project inventory (non-Talos)
        if not is_talos and project_hosts:
            output_path = SCRIPT_DIR / project["output_file"]
            inventory = {
                "all": {
                    "children": {
                        "proxmox_hosts": {
                            "children": {
                                project["group_name"]: {"hosts": project_hosts}
                            }
                        }
                    }
                }
            }
            write_inventory_file(output_path, project["group_name"], inventory)
            merged_groups[project["group_name"]] = {"hosts": project_hosts}
            project_summaries.append(
                f"  • {project['group_name']:<20} {len(project_hosts)} hosts → {project['output_file']}"
            )

    # Write Talos inventory
    if talos_controlplane or talos_workers:
        talos_project = next(p for p in TERRAFORM_PROJECTS if p.get("talos"))
        talos_children: dict[str, Any] = {}
        if talos_controlplane:
            talos_children["controlplane"] = {"hosts": talos_controlplane}
        if talos_workers:
            talos_children["workers"] = {"hosts": talos_workers}

        inventory = {
            "all": {
                "children": {
                    "proxmox_hosts": {
                        "children": {
                            "talos": {"children": talos_children}
                        }
                    }
                }
            }
        }
        output_path = SCRIPT_DIR / talos_project["output_file"]
        write_inventory_file(output_path, "talos_cluster", inventory, _build_talos_vars_block())

        total = len(talos_controlplane) + len(talos_workers)
        merged_groups["talos_cluster"] = {
            "children": {
                "controlplane": {"hosts": talos_controlplane},
                "workers": {"hosts": talos_workers},
            }
        }
        project_summaries.append(
            f"  • {'talos_cluster':<20} {total} hosts "
            f"({len(talos_controlplane)} controlplane, {len(talos_workers)} workers) → {talos_project['output_file']}"
        )

    # Write merged inventory with preserved group structure
    if merged_groups:
        merged_inventory = {
            "all": {
                "children": {
                    "proxmox_hosts": {
                        "children": merged_groups
                    }
                }
            }
        }
        write_inventory_file(
            SCRIPT_DIR / "all-hosts.yml",
            "Merged - All Hosts",
            merged_inventory,
        )
        total_hosts = sum(
            len(g.get("hosts", {}))
            + sum(len(sg.get("hosts", {})) for sg in g.get("children", {}).values())
            for g in merged_groups.values()
        )
        project_summaries.append(f"  • {'merged (all)':<20} {total_hosts} hosts → all-hosts.yml")

    # Print summary
    sys.stderr.write("\n✓ Inventory files generated:\n")
    for summary in project_summaries:
        sys.stderr.write(f"{summary}\n")
    sys.stderr.write("\n")


if __name__ == "__main__":
    main()
