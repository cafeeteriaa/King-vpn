import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "tools" / "king_ai_training" / "verify_candidate.py"
spec = importlib.util.spec_from_file_location("verify_candidate", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CandidateManifestTests(unittest.TestCase):
    def test_verifies_candidate_hashes_and_keeps_deployment_disabled(self):
        import hashlib
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            adapter = root / "adapter.bin"
            adapter.write_bytes(b"candidate")
            digest = hashlib.sha256(b"candidate").hexdigest()
            (root / "training_report.json").write_text(json.dumps({
                "status": "candidate_trained",
                "deployment_authorized": False,
                "files_sha256": {"adapter.bin": digest},
            }), encoding="utf-8")
            result = module.verify(root)
            self.assertEqual(result["status"], "verified")
            self.assertEqual(result["files"], 1)
            self.assertFalse(result["deployment_authorized"])

    def test_rejects_tampered_candidate(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "adapter.bin").write_bytes(b"tampered")
            (root / "training_report.json").write_text(json.dumps({
                "status": "candidate_trained",
                "deployment_authorized": False,
                "files_sha256": {"adapter.bin": "0" * 64},
            }), encoding="utf-8")
            with self.assertRaises(RuntimeError):
                module.verify(root)


if __name__ == "__main__":
    unittest.main()
