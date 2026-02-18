#!/usr/bin/env python3
"""
Generate dynamic GitLab CI child pipeline based on detected service changes.

This script analyzes changed files in the services/ directory and generates
deployment jobs only for the affected services, following GitOps best practices.
"""

import sys
import subprocess
from typing import Any, Dict, List

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed. Run: pip3 install PyYAML", file=sys.stderr)
    sys.exit(1)

# Constants
SERVICES_DIR = "services"
GIT_TIMEOUT = 30
DEFAULT_RUNNER_TAG = "talos"
CI_IMAGE = "${CI_IMAGE}"


def generate_service_jobs(service: str) -> Dict[str, Any]:
    """Generate all CI jobs for a single service."""
    jobs: Dict[str, Any] = {}

    # Validation job - Validate docker-compose.yml and service configuration
    jobs[f"validate:{service}"] = {
        "stage": "validate",
        "image": CI_IMAGE,
        "tags": [DEFAULT_RUNNER_TAG],
        "script": [f"./scripts/ci/validate-service.sh {service}"],
        "variables": {"SERVICE": service},
    }

    # Preflight checks job - Verify SSH connectivity, Docker daemon, disk space
    jobs[f"preflight:{service}"] = {
        "stage": "preflight",
        "image": CI_IMAGE,
        "tags": [DEFAULT_RUNNER_TAG],
        "script": [f"./scripts/ci/preflight-check.sh {service}"],
        "needs": [{"job": f"validate:{service}", "optional": True}],
        "variables": {"SERVICE": service},
    }

    # Backup job - Create backup before deployment
    jobs[f"backup:{service}"] = {
        "stage": "backup",
        "image": CI_IMAGE,
        "tags": [DEFAULT_RUNNER_TAG],
        "script": [f"./scripts/ci/backup-service.sh {service}"],
        "needs": [{"job": f"preflight:{service}", "optional": True}],
        "variables": {"SERVICE": service},
    }

    # Deploy job - Deploy service to target host (manual on main, auto on tags)
    jobs[f"deploy:{service}"] = {
        "stage": "deploy",
        "image": CI_IMAGE,
        "tags": [DEFAULT_RUNNER_TAG],
        "script": [f"./scripts/ci/deploy_service.sh {service}"],
        "needs": [{"job": f"backup:{service}", "optional": True}],
        "variables": {"SERVICE": service},
        "resource_group": "production",
        "rules": [
            # Auto-deploy on git tags
            {"if": "$CI_COMMIT_TAG", "when": "always"},
            # Manual approval required on main branch
            {
                "if": '$CI_COMMIT_BRANCH == "main"',
                "when": "manual",
                "allow_failure": False,
            },
            # Never deploy on merge requests
            {"when": "never"},
        ],
    }

    # Verify job - Run health checks after deployment
    jobs[f"verify:{service}"] = {
        "stage": "verify",
        "image": CI_IMAGE,
        "tags": [DEFAULT_RUNNER_TAG],
        "script": [f"./scripts/ci/health-check.sh {service}"],
        "needs": [{"job": f"deploy:{service}", "optional": True}],
        "variables": {"SERVICE": service},
        "rules": [
            # Run verification after tag deployments
            {"if": "$CI_COMMIT_TAG", "when": "always"},
            # Run verification if main branch deploy succeeded
            {"if": '$CI_COMMIT_BRANCH == "main"', "when": "on_success"},
            # Never run on merge requests
            {"when": "never"},
        ],
    }

    return jobs


def generate_child_pipeline(services: List[str]) -> Dict[str, Any]:
    """Generate the complete child pipeline configuration."""
    pipeline: Dict[str, Any] = {
        "variables": {
            "CI_IMAGE": CI_IMAGE,
            "SERVICES_DIR": SERVICES_DIR,
            "DOCKER_COMPOSE_DIR": "${DOCKER_COMPOSE_DIR}",
            "SSH_USER": "${SSH_USER}",
        },
        "stages": ["validate", "preflight", "backup", "deploy", "verify"],
    }

    if not services:
        # No services changed - create a no-op job
        pipeline["no-changes"] = {
            "stage": "validate",
            "image": CI_IMAGE,
            "tags": [DEFAULT_RUNNER_TAG],
            "script": [
                "echo '=========================================='",
                "echo 'No service changes detected'",
                "echo 'Validation skipped'",
                "echo '=========================================='",
            ],
        }
        return pipeline

    # Generate jobs for each service
    for service in services:
        service_jobs = generate_service_jobs(service)
        pipeline.update(service_jobs)

    return pipeline


def main():
    """Main entry point."""
    print("=" * 70, file=sys.stderr)
    print("🚀 Generating Dynamic Service Deployment Pipeline", file=sys.stderr)
    print("=" * 70, file=sys.stderr)

    # Use detect_services.py script for service detection
    # This ensures consistency between parent and child pipelines
    try:
        result = subprocess.run(
            ["python3", "scripts/ci/detect_services.py", "--verbose"],
            check=True,
            capture_output=True,
            text=True,
            timeout=GIT_TIMEOUT,
        )
        # Parse output (one service per line)
        services = [s.strip() for s in result.stdout.strip().split("\n") if s.strip()]

        # Print detect_services.py stderr output for visibility
        if result.stderr:
            print(result.stderr, file=sys.stderr, end="")
    except subprocess.CalledProcessError as e:
        print(f"\n❌ Error running detect_services.py: {e}", file=sys.stderr)
        print(f"   stderr: {e.stderr}", file=sys.stderr)
        services = []
    except subprocess.TimeoutExpired:
        print(f"\n⚠️  Timeout running detect_services.py", file=sys.stderr)
        services = []

    print(f"\n🎯 Services to process ({len(services)}):", file=sys.stderr)
    if services:
        for service in services:
            print(f"  • {service}", file=sys.stderr)
    else:
        print("  (none)", file=sys.stderr)

    # Generate child pipeline
    child_pipeline = generate_child_pipeline(services)

    # Add workflow rules to ensure pipeline always runs
    child_pipeline["workflow"] = {"rules": [{"when": "always"}]}

    # Safety check: ensure pipeline has at least one job
    job_count = len(
        [
            k
            for k in child_pipeline.keys()
            if k not in ("variables", "stages", "workflow")
        ]
    )
    if job_count == 0:
        print("\n⚠️  WARNING: No jobs generated! Adding fallback job.", file=sys.stderr)
        child_pipeline["fallback-job"] = {
            "stage": "validate",
            "image": CI_IMAGE,
            "tags": [DEFAULT_RUNNER_TAG],
            "script": [
                "echo 'ERROR: Pipeline generation failed - no jobs created'",
                "exit 1",
            ],
        }

    # Write output file
    output_file = "child-pipeline.yml"
    with open(output_file, "w") as f:
        f.write("---\n")
        yaml.dump(
            child_pipeline,
            f,
            default_flow_style=False,
            sort_keys=False,
            indent=2,
            width=1000,
            allow_unicode=True,
            explicit_start=False,
        )

    print("\n" + "=" * 70, file=sys.stderr)
    print(f"✅ Generated Child Pipeline: {output_file}", file=sys.stderr)
    print("=" * 70, file=sys.stderr)

    # Display generated pipeline
    with open(output_file, "r") as f:
        print(f.read(), file=sys.stderr)

    print("-" * 70, file=sys.stderr)
    print(
        f"✓ Pipeline contains {job_count} job(s) for {len(services)} service(s)",
        file=sys.stderr,
    )
    print("=" * 70, file=sys.stderr)


if __name__ == "__main__":
    main()
