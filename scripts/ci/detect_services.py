#!/usr/bin/env python3
"""
Service Change Detection Script

Auto-discovers changed services based on git diff.
Replaces detect-services.sh with better error handling and type safety.

Usage:
    python3 detect_services.py [--output-file FILE] [--verbose]
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path
from typing import Optional

# Constants
SERVICES_DIR = "services"
GIT_TIMEOUT = 30
SKIP_PATTERNS = [".gitignore", "README"]
TEMPLATE_DIR = "_templates"


class ServiceDetector:
    """Detect changed services based on git diff."""

    def __init__(self, verbose: bool = False):
        self.verbose = verbose
        self.project_root = Path(__file__).parent.parent.parent
        self.services_dir = self.project_root / SERVICES_DIR

    def log(self, message: str, level: str = "INFO"):
        """Print log message if verbose or if it's important."""
        prefix = {
            "INFO": "ℹ️ ",
            "SUCCESS": "✅",
            "WARN": "⚠️ ",
            "ERROR": "❌",
        }.get(level, "")

        if self.verbose or level in ("SUCCESS", "ERROR"):
            print(f"{prefix} {message}", file=sys.stderr)

    def run_git_command(self, cmd: list[str]) -> str:
        """Run git command and return output."""
        try:
            result = subprocess.run(
                cmd,
                cwd=self.project_root,
                capture_output=True,
                text=True,
                timeout=GIT_TIMEOUT,
                check=True,
            )
            return result.stdout.strip()
        except subprocess.CalledProcessError as e:
            self.log(f"Git command failed: {' '.join(cmd)}", "ERROR")
            self.log(f"Error: {e.stderr}", "ERROR")
            raise
        except subprocess.TimeoutExpired:
            self.log(f"Git command timed out: {' '.join(cmd)}", "ERROR")
            raise

    def list_all_services(self) -> list[str]:
        """List all service directories."""
        services: list[str] = []

        if not self.services_dir.exists():
            self.log(f"Services directory not found: {self.services_dir}", "ERROR")
            return services

        for item in self.services_dir.iterdir():
            if item.is_dir() and item.name != TEMPLATE_DIR:
                services.append(item.name)

        return sorted(services)

    def get_changed_files(self, ref: str) -> list[str]:
        """Get list of changed files from git diff."""
        cmd = ["git", "diff", "--name-only", ref]
        output = self.run_git_command(cmd)
        return output.split("\n") if output else []

    def extract_services_from_files(self, files: list[str]) -> list[str]:
        """Extract unique service names from file paths."""
        services: set[str] = set()

        for file_path in files:
            # Check if file is in services directory
            if not file_path.startswith(f"{SERVICES_DIR}/"):
                continue

            # Skip special patterns
            if any(pattern in file_path for pattern in SKIP_PATTERNS):
                continue

            # Extract service name (second path component)
            parts = file_path.split("/")
            if len(parts) >= 2:
                service_name = parts[1]

                # Verify it's actually a directory
                service_path = self.services_dir / service_name
                if service_path.is_dir() and service_name != TEMPLATE_DIR:
                    services.add(service_name)
                else:
                    self.log(
                        f"Skipping non-service: {service_name} (file or template)",
                        "INFO",
                    )

        return sorted(services)

    def detect_changed_services(self) -> list[str]:
        """Detect changed services based on CI environment and git diff."""
        # Check for tag - deploy all services
        ci_commit_tag = os.getenv("CI_COMMIT_TAG")
        if ci_commit_tag:
            self.log(f"Tag detected: {ci_commit_tag} - will process all services")
            return self.list_all_services()

        # Check for DEPLOY_ALL flag
        deploy_all = os.getenv("DEPLOY_ALL")
        if deploy_all:
            self.log("DEPLOY_ALL is set - will process all services")
            return self.list_all_services()

        # Determine comparison reference based on branch
        ci_commit_branch = os.getenv("CI_COMMIT_BRANCH", "")
        ci_commit_before_sha = os.getenv("CI_COMMIT_BEFORE_SHA", "")
        ci_mr_target_branch = os.getenv("CI_MERGE_REQUEST_TARGET_BRANCH_NAME", "main")

        if ci_commit_branch in ("main", "master"):
            # Main branch: compare with previous commit
            if ci_commit_before_sha and ci_commit_before_sha != "0" * 40:
                ref = f"{ci_commit_before_sha}..HEAD"
                self.log(f"Main branch detected - comparing range {ref}")
            else:
                ref = "HEAD~1..HEAD"
                self.log("Main branch detected (no before_sha) - comparing HEAD~1")
        else:
            # Feature branch or MR: compare with target branch
            # Try to fetch target branch
            try:
                if os.getenv("CI"):
                    self.run_git_command(
                        ["git", "fetch", "origin", ci_mr_target_branch, "--depth=50"]
                    )
            except Exception:
                pass  # Fetch may fail, continue anyway

            # Check if target ref exists
            try:
                self.run_git_command(
                    ["git", "rev-parse", f"origin/{ci_mr_target_branch}"]
                )
                ref = f"origin/{ci_mr_target_branch}...HEAD"
                self.log(f"Comparing against base ref: origin/{ci_mr_target_branch}")
            except Exception:
                ref = "HEAD~1..HEAD"
                self.log(
                    f"Could not find origin/{ci_mr_target_branch}, comparing with HEAD~1",
                    "WARN",
                )

        # Get changed files and extract services
        changed_files = self.get_changed_files(ref)
        services = self.extract_services_from_files(changed_files)

        return services

    def run(self, output_file: Optional[str] = None) -> int:
        """Run service detection and output results."""
        try:
            services = self.detect_changed_services()

            if not services:
                self.log("No services changed in this commit", "WARN")
                return 0

            # Output results
            self.log("Found changed services:", "SUCCESS")
            for service in services:
                self.log(f"  - {service}", "SUCCESS")

            # Write to output file or stdout
            output_content = "\n".join(services)
            if output_file:
                output_path = Path(output_file)
                output_path.write_text(output_content + "\n")
                self.log(f"Written to: {output_file}")
            else:
                print(output_content)

            return 0

        except Exception as e:
            self.log(f"Detection failed: {e}", "ERROR")
            if self.verbose:
                import traceback

                traceback.print_exc()
            return 1


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Detect changed services based on git diff"
    )
    parser.add_argument(
        "--output-file", type=str, help="Write service names to file (one per line)"
    )
    parser.add_argument("--verbose", action="store_true", help="Verbose output")

    args = parser.parse_args()

    detector = ServiceDetector(verbose=args.verbose)
    exit_code = detector.run(output_file=args.output_file)
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
