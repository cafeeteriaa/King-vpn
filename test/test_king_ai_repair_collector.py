import importlib.util
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
                    "repo": {"full_name": "cafeeteriaa/King-vpn"},
                },
            }
        }

    def test_collects_only_merged_green_allowlisted_secret_free_patch(self):
        def fake_get(url, token):
            if "/pulls/17/files" in url:
                return [{
                    "filename": "lib/king_ai_ci_policy.dart",
                    "patch": "@@ -1 +1 @@\n-old\n+new",
                }]
            if "/check-runs" in url:
                return {"check_runs": [{
                    "status": "completed", "conclusion": "success",
                }]}
            raise AssertionError(url)

        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "data" / "repairs.jsonl"
            with patch.object(module, "github_get", side_effect=fake_get):
                result = module.collect(self.event, "cafeeteriaa/King-vpn", "token", output)
            self.assertEqual(result["status"], "collected")
            self.assertTrue(output.exists())
            self.assertIn('"merged": true', output.read_text(encoding="utf-8"))

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
            self.assertFalse((Path(temp) / "repairs.jsonl").exists())

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

    def test_rejects_secret_bearing_patch(self):
        def fake_get(url, token):
            if "/pulls/17/files" in url:
                return [{
                    "filename": "lib/king_ai_ci_policy.dart",
                    "patch": "+ghp_123456789012345678901234567890",
                }]
            return {"check_runs": [{
                "status": "completed", "conclusion": "success",
            }]}

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
