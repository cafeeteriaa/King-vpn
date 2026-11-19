import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "tools" / "king_ai_training" / "prepare_dataset.py"
spec = importlib.util.spec_from_file_location("prepare_dataset", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class DatasetPreparationTests(unittest.TestCase):
    def test_only_merged_or_reviewed_green_and_secret_free_examples_are_kept(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "examples.jsonl"
            rows = []
            for index in range(10):
                rows.append({
                    "task": f"Fix deterministic issue {index}",
                    "source_files": {"lib/king_ai_ci_policy.dart": f"const oldValue{index} = {index};"},
                    "changes": {"lib/king_ai_ci_policy.dart": f"const newValue{index} = {index};"},
                    "ci_passed": True,
                    "human_reviewed": index != 0,
                    "merged": index == 0,
                    "secret_scan_passed": True,
                })
            rows.append({
                "task": "bad unreviewed",
                "source_files": {"lib/king_ai_ci_policy.dart": "safe"},
                "changes": {"lib/king_ai_ci_policy.dart": "unsafe"},
                "ci_passed": True,
                "human_reviewed": False,
                "merged": False,
                "secret_scan_passed": True,
            })
            rows.append({
                "task": "token leaked",
                "source_files": {"lib/king_ai_ci_policy.dart": "safe"},
                "changes": {"lib/king_ai_ci_policy.dart": "ghp_123456789012345678901234567890"},
                "ci_passed": True,
                "human_reviewed": True,
                "merged": True,
                "secret_scan_passed": True,
            })
            source.write_text("\n".join(json.dumps(row) for row in rows), encoding="utf-8")
            report = module.prepare(source, root / "out")
            self.assertEqual(report["accepted"], 10)
            self.assertEqual(report["rejected"], 2)
            self.assertGreaterEqual(report["train"], 2)
            self.assertGreaterEqual(report["evaluation"], 1)
            self.assertFalse(report["deployment_authorized"])
            sample = json.loads((root / "out" / "train.jsonl").read_text(encoding="utf-8").splitlines()[0])
            self.assertIn("<|im_start|>assistant", sample["text"])
            self.assertIn('"changes"', sample["text"])

    def test_rejects_too_small_dataset(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "examples.jsonl"
            source.write_text(json.dumps({
                "task": "task", "diff": "+change", "ci_passed": True,
                "human_reviewed": True, "secret_scan_passed": True,
            }), encoding="utf-8")
            with self.assertRaises(RuntimeError):
                module.prepare(source, root / "out")


if __name__ == "__main__":
    unittest.main()
