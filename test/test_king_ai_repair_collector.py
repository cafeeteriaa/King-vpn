import base64
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

MODULE_PATH = Path(__file__).resolve().parents[1] / "tools" / "king_ai_training" / "collect_merged_repairs.py"
spec = importlib.util.spec_from_file_location("collect_merged_repairs", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class MergedRepairCollectorTests(unittest.TestCase):
    def setUp(self):
        self.event = {
            "pull_request": {
                "merged": True,
                "number": 17,
                "title": "Fix CI policy",
                "body": "Verified fix",
                "head": {
                    "ref": "king-ai/repair-123",
                    "sha": "a" * 40,
                    "repo": {"full_name": "cafeeteriaa/King-vpn"},
                },
                "base": {
                    "ref": "main",
                    "sha": "d" * 40,
                    "repo": {"full_name": "cafeeteriaa/King-vpn"},
                },
                "merge_commit_sha": "b" * 40,
            }
        }

    def _fake_successful_get(self, url, token):
        if "/pulls/17/files" in url:
            return [{
                "filename": "lib/king_ai_ci_policy.dart",
                "patch": "@@ -1 +1 @@\n-old\n+new",
            }]
        if "/check-runs" in url:
            return {"check_runs": [{
                "status": "completed", "conclusion": "success",
            }]}
        if "/pulls/17/reviews" in url:
            return [{
                "state": "APPROVED",
                "commit_id": "a" * 40,
                "submitted_at": "2026-11-20T01:00:00Z",
                "user": {"login": "reviewer", "type": "User"},
            }]
        if "/commits/" + "b" * 40 in url:
            return {"parents": [{"sha": "c" * 40}]}
        if "/contents/lib/king_ai_ci_policy.dart?ref=" in url:
            value = "const oldValue = 1;" if "ref=" + "c" * 40 in url else "const newValue = 1;"
            return {
                "encoding": "base64",
                "content": base64.b64encode(value.encode()).decode(),
            }
        raise AssertionError(url)

    def test_secret_scan_rejects_common_provider_credentials_and_pem_keys(self):
        secrets = [
            "sk-123456789012345678901234",
            "xoxb-123456789012",
            "AIza1234567890123456789012345678901234",
            "Basic dXNlcjpwYXNzd29yZA==",
            "-----BEGIN PRIVATE KEY-----",
            "AKIA1234567890ABCDEF",
        ]
        for value in secrets:
            with self.subTest(value=value):
                self.assertFalse(module.secret_free(value))

    def test_secret_scan_accepts_non_secret_technical_text(self):
        self.assertTrue(module.secret_free("Flutter build failed: missing class MainActivity"))

    def test_collects_full_source_and_target_for_merged_green_repair(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "data" / "repairs.jsonl"
            with patch.object(module, "github_get", side_effect=self._fake_successful_get):
                result = module.collect(self.event, "cafeeteriaa/King-vpn", "token", output)
            self.assertEqual(result["status"], "collected")
            row = json.loads(output.read_text(encoding="utf-8"))
            self.assertTrue(row["merged"])
            self.assertEqual(row["source_files"]["lib/king_ai_ci_policy.dart"], "const oldValue = 1;")
            self.assertEqual(row["changes"]["lib/king_ai_ci_policy.dart"], "const newValue = 1;")

    def test_rejects_non_allowlisted_paths(self):
        with tempfile.TemporaryDirectory() as temp:
            with patch.object(module, "github_get", return_value=[{
                "filename": "lib/main.dart", "patch": "+unsafe",
            }]):
                result = module.collect(
                    self.event, "cafeeteriaa/King-vpn", "token",
                    Path(temp) / "repairs.jsonl",
                )
            self.assertEqual(result["status"], "skipped")

    def test_rejects_failed_checks(self):
        def fake_get(url, token):
            if "/pulls/17/files" in url:
                return [{
                    "filename": "lib/king_ai_ci_policy.dart",
                    "patch": "+safe",
                }]
            return {"check_runs": [{
                "status": "completed", "conclusion": "failure",
            }]}

        with tempfile.TemporaryDirectory() as temp:
            with patch.object(module, "github_get", side_effect=fake_get):
                result = module.collect(
                    self.event, "cafeeteriaa/King-vpn", "token",
                    Path(temp) / "repairs.jsonl",
                )
            self.assertEqual(result["status"], "skipped")
            self.assertIn("exact head SHA", result["reason"])

    def test_rejects_repair_without_human_approval_for_exact_head_sha(self):
        def fake_get(url, token):
            if "/pulls/17/files" in url:
                return [{"filename": "lib/king_ai_ci_policy.dart", "patch": "+safe"}]
            if "/check-runs" in url:
                return {"check_runs": [{"status": "completed", "conclusion": "success"}]}
            if "/pulls/17/reviews" in url:
                return [{"state": "APPROVED", "commit_id": "older-sha",
                         "submitted_at": "2026-11-20T01:00:00Z",
                         "user": {"login": "reviewer", "type": "User"}}]
            raise AssertionError(url)

        with tempfile.TemporaryDirectory() as temp:
            with patch.object(module, "github_get", side_effect=fake_get):
                result = module.collect(
                    self.event, "cafeeteriaa/King-vpn", "token",
                    Path(temp) / "repairs.jsonl",
                )
            self.assertEqual(result["status"], "skipped")
            self.assertIn("human approval", result["reason"])

    def test_newer_dismissed_review_overrides_older_approval(self):
        def fake_get(url, token):
            if "/pulls/17/files" in url:
                return [{"filename": "lib/king_ai_ci_policy.dart", "patch": "+safe"}]
            if "/check-runs" in url:
                return {"check_runs": [{"status": "completed", "conclusion": "success"}]}
            if "/pulls/17/reviews" in url:
                return [
                    {"state": "APPROVED", "commit_id": "a" * 40,
                     "submitted_at": "2026-11-20T01:00:00Z",
                     "user": {"login": "reviewer", "type": "User"}},
                    {"state": "DISMISSED", "commit_id": "a" * 40,
                     "submitted_at": "2026-11-20T02:00:00Z",
                     "user": {"login": "reviewer", "type": "User"}},
                ]
            raise AssertionError(url)

        with tempfile.TemporaryDirectory() as temp:
            with patch.object(module, "github_get", side_effect=fake_get):
                result = module.collect(
                    self.event, "cafeeteriaa/King-vpn", "token",
                    Path(temp) / "repairs.jsonl",
                )
            self.assertEqual(result["status"], "skipped")
            self.assertIn("human approval", result["reason"])

    def test_rejects_secret_bearing_replacement_file(self):
        def fake_get(url, token):
            if "/pulls/17/files" in url:
                return [{
                    "filename": "lib/king_ai_ci_policy.dart",
                    "patch": "+unsafe",
                }]
            if "/check-runs" in url:
                return {"check_runs": [{
                    "status": "completed", "conclusion": "success",
                }]}
            if "/pulls/17/reviews" in url:
                return [{"state": "APPROVED", "commit_id": "a" * 40,
                         "submitted_at": "2026-11-20T01:00:00Z",
                         "user": {"login": "reviewer", "type": "User"}}]
            if "/commits/" + "b" * 40 in url:
                return {"parents": [{"sha": "c" * 40}]}
            if "/contents/lib/king_ai_ci_policy.dart?ref=" in url:
                value = "safe" if "ref=" + "c" * 40 in url else "ghp_123456789012345678901234567890"
                return {
                    "encoding": "base64",
                    "content": base64.b64encode(value.encode()).decode(),
                }
            raise AssertionError(url)

        with tempfile.TemporaryDirectory() as temp:
            with patch.object(module, "github_get", side_effect=fake_get):
                result = module.collect(
                    self.event, "cafeeteriaa/King-vpn", "token",
                    Path(temp) / "repairs.jsonl",
                )
            self.assertEqual(result["status"], "skipped")
            self.assertEqual(result["reason"], "Secret scan rejected the repair")


if __name__ == "__main__":
    unittest.main()
