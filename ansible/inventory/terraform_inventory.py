#!/usr/bin/env python3
"""
Terraform Inventory Generator for Ansible
Generates static YAML inventory files from Terraform state (HTTP backend compatible).
"""

import os
import json
import subprocess
import sys
import yaml
from pathlib import Path

def load_dotenv(dotenv_path):
    """Simple .env loader with variable expansion support."""
    try:
        if not os.path.isfile(dotenv_path):
            return
        with open(dotenv_path, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                if '=' not in line:
                    continue
                key, value = line.split('=', 1)
                key = key.strip()
                value = value.strip().strip('"').strip("'")

                # Expand $VAR and ${VAR} references
                import re
                def expand_var(match):
                    var_name = match.group(1) or match.group(2)
                    return os.environ.get(var_name, match.group(0))
                value = re.sub(r'\$\{([^}]+)\}|\$([A-Z_][A-Z0-9_]*)', expand_var, value)

                os.environ.setdefault(key, value)
    except Exception as e:
        sys.stderr.write(f"Warning: failed to load .env: {e}\n")

# Configuration: List of Terraform project directories
TERRAFORM_PROJECTS = [
    {
        "path": "../../terraform/lxc",
        "env_prefix": "LXC_TF_",
        "output_file": "../lxc/inventory/hosts.yml",
        "group_name": "lxc_containers"
    },
    {
        "path": "../../terraform/linux-vms",
        "env_prefix": "LINUX_TF_",
        "output_file": "../linux-vms/inventory/hosts.yml",
        "group_name": "linux_vms"
    },
    {
        "path": "../../terraform/talos-vms",
        "env_prefix": "TALOS_TF_",
        "output_file": "../talos/inventory/hosts.yml",
        "group_name": "talos_cluster"
    },
    {
        "path": "../../terraform/windows-vms",
        "env_prefix": "WIN_TF_",
        "output_file": "../windows-vms/inventory/hosts.yml",
        "group_name": "windows_vms"
    },
]

def apply_project_backend_env(env_prefix: str):
    """Apply per-project HTTP backend env vars if defined in environment.
    Expected keys: ADDRESS, LOCK_ADDRESS, UNLOCK_ADDRESS, USERNAME, PASSWORD, HEADERS
    Example: LXC_TF_ADDRESS, LXC_TF_USERNAME, ...
    These are mapped to TF_HTTP_* for terraform CLI.
    """
    if not env_prefix:
        return
    mappings = {
        f"{env_prefix}ADDRESS": "TF_HTTP_ADDRESS",
        f"{env_prefix}LOCK_ADDRESS": "TF_HTTP_LOCK_ADDRESS",
        f"{env_prefix}UNLOCK_ADDRESS": "TF_HTTP_UNLOCK_ADDRESS",
        f"{env_prefix}USERNAME": "TF_HTTP_USERNAME",
        f"{env_prefix}PASSWORD": "TF_HTTP_PASSWORD",
        f"{env_prefix}HEADERS": "TF_HTTP_HEADERS",
    }
    for src, dst in mappings.items():
        val = os.environ.get(src)
        if val:
            os.environ[dst] = val

def get_terraform_output(project_path, env_prefix=None):
    """Run 'terraform output -json' in the given directory, applying per-project backend env if provided."""
    try:
        # Resolve absolute path
        path_value = project_path["path"] if isinstance(project_path, dict) else project_path
        abs_path = os.path.abspath(os.path.join(os.path.dirname(__file__), path_value))

        if not os.path.exists(abs_path):
            sys.stderr.write(f"Warning: Project path not found: {abs_path}\n")
            return {}

        # Apply per-project backend env if provided
        prefix_value = project_path.get("env_prefix") if isinstance(project_path, dict) else env_prefix
        apply_project_backend_env(prefix_value)

        cmd = ["terraform", "output", "-json"]
        result = subprocess.run(
            cmd,
            cwd=abs_path,
            capture_output=True,
            text=True,
            check=True,
            env=os.environ.copy()  # Explicitly pass modified environment
        )
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        sys.stderr.write(f"Error running terraform in {project_path}: {e.stderr}\n")
        return {}
    except json.JSONDecodeError:
        sys.stderr.write(f"Error decoding JSON from {project_path}\n")
        return {}

def parse_args():
    """Parse command line arguments (kept for compatibility, not used for static generation)."""
    import argparse
    parser = argparse.ArgumentParser(description="Terraform Inventory Generator")
    parser.add_argument("--list", action="store_true", help="Legacy flag (ignored, generates static files)")
    parser.add_argument("--host", help="Legacy flag (ignored, generates static files)")
    return parser.parse_args()

def write_yaml_inventory(hosts_data, output_path, group_name):
    """Write Ansible inventory YAML file for a project."""
    inventory = {
        "all": {
            "children": {
                "proxmox_hosts": {
                    "children": {
                        group_name: {
                            "hosts": hosts_data
                        }
                    }
                }
            }
        }
    }

    output_file = Path(output_path)
    output_file.parent.mkdir(parents=True, exist_ok=True)

    with open(output_file, 'w') as f:
        f.write("# ============================================================================\n")
        f.write(f"# Ansible Inventory ({group_name})\n")
        f.write("# ============================================================================\n")
        f.write("# Auto-generated from Terraform state - DO NOT EDIT MANUALLY\n")
        f.write("# Regenerate with: cd ansible && make inventory-all\n")
        f.write("# ============================================================================\n\n")
        yaml.dump(inventory, f, default_flow_style=False, sort_keys=False)

    return len(hosts_data)

def write_k3s_yaml_inventory(masters_data, workers_data, output_path):
    """Write K3s inventory YAML file with masters and workers groups."""
    inventory = {
        "all": {
            "children": {
                "proxmox_hosts": {
                    "children": {
                        "k3s_cluster": {
                            "children": {}
                        }
                    }
                }
            }
        }
    }

    # Add masters group if there are any masters
    if masters_data:
        inventory["all"]["children"]["proxmox_hosts"]["children"]["k3s_cluster"]["children"]["masters"] = {
            "hosts": masters_data
        }

    # Add workers group if there are any workers
    if workers_data:
        inventory["all"]["children"]["proxmox_hosts"]["children"]["k3s_cluster"]["children"]["workers"] = {
            "hosts": workers_data
        }

    output_file = Path(output_path)
    output_file.parent.mkdir(parents=True, exist_ok=True)

    with open(output_file, 'w') as f:
        f.write("# ============================================================================\n")
        f.write("# Ansible Inventory (k3s_cluster)\n")
        f.write("# ============================================================================\n")
        f.write("# Auto-generated from Terraform state - DO NOT EDIT MANUALLY\n")
        f.write("# Regenerate with: cd ansible && make inventory-all\n")
        f.write("# ============================================================================\n\n")
        yaml.dump(inventory, f, default_flow_style=False, sort_keys=False)

    return len(masters_data) + len(workers_data)

def main():
    args = parse_args()

    # Load local .env for TF_HTTP_* credentials if present
    script_dir = os.path.dirname(__file__)
    dotenv_path = os.path.join(os.path.dirname(script_dir), '.env')
    load_dotenv(dotenv_path)

    all_hosts = {}
    k3s_masters = {}  # Separate tracking for K3s master nodes
    k3s_workers = {}  # Separate tracking for K3s worker nodes
    project_summaries = []

    # Process each Terraform project
    for project in TERRAFORM_PROJECTS:
        outputs = get_terraform_output(project)

        if "ansible_info" not in outputs:
            sys.stderr.write(f"Warning: No ansible_info output in {project['path']}\n")
            continue

        ansible_info = outputs["ansible_info"].get("value", {})

        if not ansible_info:
            sys.stderr.write(f"Warning: Empty ansible_info in {project['path']}\n")
            continue

        # Prepare hosts data for this project
        project_hosts = {}
        for hostname, host_data in ansible_info.items():
            # Check if this is a K3s node (by k3s_role field or hostname pattern)
            k3s_role = host_data.get("k3s_role")
            is_k3s = (k3s_role is not None and k3s_role != "") or hostname.startswith(("k3s-master-", "k3s-worker-"))

            # Build host vars, excluding null values
            host_vars = {
                "ansible_host": host_data.get("ansible_host"),
                "ansible_user": host_data.get("ansible_user"),
                "ansible_ssh_private_key_file": host_data.get("ansible_ssh_private_key_file"),
            }

            # Add k3s_role if it exists and is not null/empty
            if k3s_role is not None and k3s_role != "":
                host_vars["k3s_role"] = k3s_role

            # Add any other extra vars (excluding null values)
            for key, value in host_data.items():
                if key not in ["ansible_host", "ansible_user", "ansible_ssh_private_key_file", "type", "groups", "k3s_role"]:
                    if value is not None and value != "":
                        host_vars[key] = value

            # Categorize: K3s nodes go to k3s inventory, others to project inventory
            if is_k3s:
                # Determine if master or worker based on k3s_role or hostname pattern
                is_master = False
                is_worker = False

                if k3s_role:
                    # Use k3s_role field if available
                    k3s_role_lower = k3s_role.lower()
                    if k3s_role_lower in ["master", "control-plane", "server"]:
                        is_master = True
                    elif k3s_role_lower in ["worker", "agent", "node"]:
                        is_worker = True
                else:
                    # Fall back to hostname pattern matching
                    if hostname.startswith("k3s-master-"):
                        is_master = True
                    elif hostname.startswith("k3s-worker-"):
                        is_worker = True

                # Add to appropriate group
                if is_master:
                    k3s_masters[hostname] = host_vars.copy()
                elif is_worker:
                    k3s_workers[hostname] = host_vars.copy()
                else:
                    # If we can't determine, default to worker (safer for cluster)
                    sys.stderr.write(f"Warning: Could not determine role for K3s node {hostname}, defaulting to worker\n")
                    k3s_workers[hostname] = host_vars.copy()
            else:
                project_hosts[hostname] = host_vars.copy()

            # Also add to merged inventory
            all_hosts[hostname] = host_vars.copy()        # Write project-specific inventory file (excluding K3s nodes)
        if project_hosts:
            output_path = os.path.join(script_dir, project["output_file"])
            host_count = write_yaml_inventory(project_hosts, output_path, project["group_name"])
            project_summaries.append(f"  • {project['group_name']:<20} {host_count} hosts → {project['output_file']}")

    # Write K3s-specific inventory with masters and workers groups
    if k3s_masters or k3s_workers:
        k3s_output_path = os.path.join(script_dir, "../k3s/inventory/hosts.yml")
        k3s_count = write_k3s_yaml_inventory(k3s_masters, k3s_workers, k3s_output_path)
        master_count = len(k3s_masters)
        worker_count = len(k3s_workers)
        project_summaries.append(f"  • {'k3s_cluster':<20} {k3s_count} hosts ({master_count} masters, {worker_count} workers) → ../k3s/inventory/hosts.yml")

    # Write merged inventory (all hosts)
    if all_hosts:
        merged_path = os.path.join(script_dir, "all-hosts.yml")
        merged_inventory = {
            "all": {
                "children": {
                    "proxmox_hosts": {
                        "hosts": all_hosts
                    }
                }
            }
        }

        with open(merged_path, 'w') as f:
            f.write("# ============================================================================\n")
            f.write("# Ansible Inventory (Merged - All Hosts)\n")
            f.write("# ============================================================================\n")
            f.write("# Auto-generated from Terraform state - DO NOT EDIT MANUALLY\n")
            f.write("# Regenerate with: cd ansible && make inventory-all\n")
            f.write("# ============================================================================\n\n")
            yaml.dump(merged_inventory, f, default_flow_style=False, sort_keys=False)

        project_summaries.append(f"  • {'merged (all)':<20} {len(all_hosts)} hosts → all-hosts.yml")

    # Print summary
    sys.stderr.write("\n✓ Inventory files generated:\n")
    for summary in project_summaries:
        sys.stderr.write(f"{summary}\n")
    sys.stderr.write("\n")

if __name__ == "__main__":
    main()
