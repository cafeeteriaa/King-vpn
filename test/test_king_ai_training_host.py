import ast
import importlib.util
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "tools" / "king_ai_training" / "validate_training_host.py"
spec = importlib.util.spec_from_file_location("validate_training_host", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class TrainingHostPreflightTests(unittest.TestCase):
    def test_train_script_is_valid_python_without_loading_gpu_dependencies(self):
        train_script = MODULE_PATH.parent / "train_lora.py"
        ast.parse(train_script.read_text(encoding="utf-8"), filename=str(train_script))

    def test_rejects_nonexistent_base_model_before_gpu_import(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with self.assertRaisesRegex(RuntimeError, "Base model directory does not exist"):
                module.validate(root / "missing-model", root / "dataset.jsonl", root / "prepared")

    def test_rejects_gguf_only_model_directory(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            model = root / "model"
            model.mkdir()
            (model / "model.gguf").write_bytes(b"gguf")
            with self.assertRaisesRegex(RuntimeError, "config.json"):
                module.validate(model, root / "dataset.jsonl", root / "prepared")


if __name__ == "__main__":
    unittest.main()
