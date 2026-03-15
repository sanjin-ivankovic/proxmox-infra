#!/usr/bin/env python3
"""
Unit tests for generate_pipeline.py

Tests the dynamic pipeline generation logic for service deployments.
"""

import sys
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch, MagicMock

# Add parent directory to path to import generate_pipeline
sys.path.insert(0, str(Path(__file__).parent))

import generate_pipeline  # type: ignore
import yaml


class TestGenerateServiceJobs(unittest.TestCase):
    """Test job generation for services."""

    def test_job_structure(self):
        """Test that all required jobs are generated."""
        jobs = generate_pipeline.generate_service_jobs("pihole-1")

        # Check all expected jobs exist
        self.assertIn("validate:pihole-1", jobs)
        self.assertIn("preflight:pihole-1", jobs)
        self.assertIn("backup:pihole-1", jobs)
        self.assertIn("deploy:pihole-1", jobs)
        self.assertIn("verify:pihole-1", jobs)

    def test_job_dependencies(self):
        """Test that jobs have correct dependencies with optional flag."""
        jobs = generate_pipeline.generate_service_jobs("pihole-1")

        # Preflight needs validate (with optional: true)
        self.assertEqual(
            jobs["preflight:pihole-1"]["needs"],
            [{"job": "validate:pihole-1", "optional": True}],
        )

        # Backup needs preflight (with optional: true)
        self.assertEqual(
            jobs["backup:pihole-1"]["needs"],
            [{"job": "preflight:pihole-1", "optional": True}],
        )

        # Deploy needs backup (with optional: true)
        self.assertEqual(
            jobs["deploy:pihole-1"]["needs"],
            [{"job": "backup:pihole-1", "optional": True}],
        )

        # Verify needs deploy (with optional: true)
        self.assertEqual(
            jobs["verify:pihole-1"]["needs"],
            [{"job": "deploy:pihole-1", "optional": True}],
        )

    def test_job_stages(self):
        """Test that jobs are assigned to correct stages."""
        jobs = generate_pipeline.generate_service_jobs("pihole-1")

        self.assertEqual(jobs["validate:pihole-1"]["stage"], "validate")
        self.assertEqual(jobs["preflight:pihole-1"]["stage"], "preflight")
        self.assertEqual(jobs["backup:pihole-1"]["stage"], "backup")
        self.assertEqual(jobs["deploy:pihole-1"]["stage"], "deploy")
        self.assertEqual(jobs["verify:pihole-1"]["stage"], "verify")

    def test_service_variable_set(self):
        """Test that SERVICE variable is set in all jobs."""
        jobs = generate_pipeline.generate_service_jobs("test-service")

        for _, job_config in jobs.items():
            if "variables" in job_config:
                self.assertEqual(job_config["variables"]["SERVICE"], "test-service")

    def test_deploy_has_rules(self):
        """Test that deploy job has rules block (not when field)."""
        jobs = generate_pipeline.generate_service_jobs("pihole-1")

        # Deploy job should have rules, not when
        self.assertIn("rules", jobs["deploy:pihole-1"])
        self.assertNotIn("when", jobs["deploy:pihole-1"])

        # Rules should be a list
        self.assertIsInstance(jobs["deploy:pihole-1"]["rules"], list)

    def test_deploy_rules_structure(self):
        """Test that deploy rules have correct structure."""
        jobs = generate_pipeline.generate_service_jobs("pihole-1")
        rules = jobs["deploy:pihole-1"]["rules"]

        # Should have 3 rules (tag, main, never)
        self.assertEqual(len(rules), 3)

        # First rule should handle tags (auto-deploy)
        self.assertEqual(rules[0]["if"], "$CI_COMMIT_TAG")
        self.assertEqual(rules[0]["when"], "always")

        # Second rule should handle main branch (manual)
        self.assertEqual(rules[1]["if"], '$CI_COMMIT_BRANCH == "main"')
        self.assertEqual(rules[1]["when"], "manual")
        self.assertEqual(rules[1]["allow_failure"], False)

        # Third rule should prevent MR deployments
        self.assertEqual(rules[2]["when"], "never")

    def test_resource_group(self):
        """Test that deploy job has resource group for locking."""
        jobs = generate_pipeline.generate_service_jobs("pihole-1")

        # Deploy job should have resource_group
        self.assertIn("resource_group", jobs["deploy:pihole-1"])
        self.assertEqual(jobs["deploy:pihole-1"]["resource_group"], "production")


class TestGenerateChildPipeline(unittest.TestCase):
    """Test complete child pipeline generation."""

    def test_pipeline_with_services(self):
        """Test pipeline generation with services."""
        services = ["pihole-1", "adguard-1"]
        pipeline = generate_pipeline.generate_child_pipeline(services)

        # Check structure
        self.assertIn("variables", pipeline)
        self.assertIn("stages", pipeline)

        # Check stages
        expected_stages = ["validate", "preflight", "backup", "deploy", "verify"]
        self.assertEqual(pipeline["stages"], expected_stages)

        # Check jobs exist for both services
        self.assertIn("validate:pihole-1", pipeline)
        self.assertIn("validate:adguard-1", pipeline)
        self.assertIn("deploy:pihole-1", pipeline)
        self.assertIn("deploy:adguard-1", pipeline)

    def test_pipeline_no_services(self):
        """Test pipeline generation when no services changed."""
        pipeline = generate_pipeline.generate_child_pipeline([])

        # Should have no-changes job
        self.assertIn("no-changes", pipeline)
        self.assertEqual(pipeline["no-changes"]["stage"], "validate")

    def test_pipeline_yaml_valid(self):
        """Test that generated pipeline is valid YAML."""
        services = ["pihole-1"]
        pipeline = generate_pipeline.generate_child_pipeline(services)

        # Add workflow rules (as done in main())
        pipeline["workflow"] = {"rules": [{"when": "always"}]}

        # Try to dump as YAML
        try:
            yaml_str = yaml.dump(pipeline, default_flow_style=False)
            # Try to parse it back
            parsed = yaml.safe_load(yaml_str)
            self.assertIsInstance(parsed, dict)
        except Exception as e:
            self.fail(f"Generated pipeline is not valid YAML: {e}")


class TestMain(unittest.TestCase):
    """Test main function and integration."""

    @patch("subprocess.run")
    def test_main_calls_detect_services(self, mock_run: MagicMock) -> None:
        """Test that main() calls detect_services.py subprocess."""
        # Mock detect_services.py output
        mock_result = MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "pihole-1\nadguard-1"
        mock_run.return_value = mock_result

        # Capture actual file write to verify
        written_content: str | None = None

        def mock_write(content: str) -> None:
            nonlocal written_content
            written_content = content

        with patch("builtins.open", create=True) as mock_open:
            mock_file = MagicMock()
            mock_file.write = mock_write
            mock_open.return_value.__enter__.return_value = mock_file

            generate_pipeline.main()

            # Verify detect_services.py was called
            mock_run.assert_called_once()
            call_args: Any = mock_run.call_args[0][0]  # Get the command list
            # Command is: [sys.executable, 'detect_services.py', '--verbose']
            self.assertIn("detect_services.py", " ".join(call_args))

            # Verify output file was opened for writing (first call)
            # Note: File is opened twice - once for write, once for read (display)
            write_calls = [
                call for call in mock_open.call_args_list if call[0][1] == "w"
            ]
            self.assertEqual(len(write_calls), 1)
            self.assertEqual(write_calls[0][0][0], "child-pipeline.yml")

    @patch("subprocess.run")
    def test_main_handles_no_services(self, mock_run: MagicMock) -> None:
        """Test that main() handles empty service list."""
        # Mock detect_services.py returning no services
        mock_result = MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = ""
        mock_run.return_value = mock_result

        # Mock yaml.dump to capture pipeline content
        with patch("yaml.dump") as mock_yaml_dump:
            mock_yaml_dump.return_value = "mock-yaml-content"

            with patch("builtins.open", create=True) as mock_open:
                mock_file = MagicMock()
                mock_open.return_value.__enter__.return_value = mock_file

                generate_pipeline.main()

                # Verify yaml.dump was called with pipeline dict
                self.assertEqual(mock_yaml_dump.call_count, 1)
                pipeline_dict: Any = mock_yaml_dump.call_args[0][0]

                # Verify no-changes job was generated
                self.assertIn("no-changes", pipeline_dict)


if __name__ == "__main__":
    unittest.main()
