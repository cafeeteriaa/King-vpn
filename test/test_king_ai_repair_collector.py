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
        if "/commits/" + "b" * 40 in url:
            return {"parents": [{"sha": "c" * 40}]}
        if "/contents/lib/king_ai_ci_policy.dart?ref=" in url:
            value = "const oldValue = 1;" if "ref=" + "c" * 40 in url else "const newValue = 1;"
            return {
                "encoding": "base64",
                "content": base64.b64encode(value.encode()).decode(),
            }
        raise AssertionError(url)

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
