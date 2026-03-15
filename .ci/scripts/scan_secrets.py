#!/usr/bin/env python3
"""
Secret Scanning Script

Detects hardcoded secrets using Gitleaks with SARIF report output
for GitLab Security Dashboard integration.
"""

import argparse
import os
import shutil
import subprocess
import sys

# Constants
SCAN_TIMEOUT = 300
GITLEAKS_CONFIG = ".config/.gitleaks.toml"
DEFAULT_REPORT_PATH = "gl-secret-detection-report.json"


class SecretScanner:
    """Secret scanning with Gitleaks."""

    def __init__(self, verbose: bool = False):
        self.verbose = verbose
        self.project_root = os.getcwd()

    def log(self, message: str):
        """Print message if verbose mode enabled."""
        if self.verbose:
            print(message)

    def check_gitleaks_available(self) -> bool:
        """Check if gitleaks is installed."""
        return shutil.which("gitleaks") is not None

    def _build_command(self, no_git: bool, report_path: str) -> list[str]:
        """Build the gitleaks command."""
        cmd = [
            "gitleaks", "detect",
            "--source", ".",
            "--config", GITLEAKS_CONFIG,
            "--platform", "gitlab",
            "--report-format", "sarif",
            "--report-path", report_path,
            "-v",
            "--exit-code", "1",
        ]

        if no_git:
            cmd.append("--no-git")

        return cmd

    def scan(self, report_path: str = DEFAULT_REPORT_PATH) -> int:
        """Run Gitleaks secret scan.

        Uses --no-git for github_sync schedules (faster, working tree only).
        Uses full history scan for MR/main (comprehensive security check).
        """
        schedule_type = os.getenv("SCHEDULE_TYPE", "")
        no_git = schedule_type == "github_sync"

        if no_git:
            self.log("Running no-history scan for GitHub publish verification...")
        else:
            self.log("Running full history scan...")

        cmd = self._build_command(no_git=no_git, report_path=report_path)
        self.log(f"Command: {' '.join(cmd)}")

        try:
            result = subprocess.run(
                cmd,
                cwd=self.project_root,
                timeout=SCAN_TIMEOUT,
            )
            return result.returncode
        except subprocess.TimeoutExpired:
            print(f"ERROR: Gitleaks scan timed out after {SCAN_TIMEOUT}s")
            return 1


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(description="Scan for secrets using Gitleaks")
    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Enable verbose output"
    )
    parser.add_argument(
        "--report-path",
        default=DEFAULT_REPORT_PATH,
        help=f"Output report path (default: {DEFAULT_REPORT_PATH})",
    )
    args = parser.parse_args()

    scanner = SecretScanner(verbose=args.verbose)

    if not scanner.check_gitleaks_available():
        print("ERROR: gitleaks is not installed")
        return 1

    return scanner.scan(report_path=args.report_path)


if __name__ == "__main__":
    sys.exit(main())
