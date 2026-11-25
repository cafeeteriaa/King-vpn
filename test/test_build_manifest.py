import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from tools.write_build_manifest import create_manifest


class BuildManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "build_app/build/app/outputs/flutter-apk").mkdir(parents=True)
        (self.root / "build_app/build/symbols/nested").mkdir(parents=True)
        (self.root / "build_app").mkdir(exist_ok=True)
        (self.root / "build-evidence").mkdir()
        (self.root / "build_app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk").write_bytes(b"apk-binary")
        (self.root / "source.zip").write_bytes(b"source-archive")
        (self.root / "build_app/pubspec.lock").write_text("packages: {}\n", encoding="utf-8")
        (self.root / "build_app/build/symbols/nested/app.symbols").write_bytes(b"symbols")
        (self.root / "build-evidence/toolchain.txt").write_text("Flutter 3.x\nDart 3.x\n", encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    def _create(self, **overrides):
        args = {
            "root": self.root,
            "apk": Path("build_app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"),
            "source_archive": Path("source.zip"),
            "dependency_lock": Path("build_app/pubspec.lock"),
            "symbols_dir": Path("build_app/build/symbols"),
            "toolchain_report": Path("build-evidence/toolchain.txt"),
            "output_dir": Path("build-evidence"),
            "environ": {
                "GITHUB_REPOSITORY": "cafeeteriaa/King-vpn",
                "GITHUB_SHA": "abc123",
                "GITHUB_REF": "refs/pull/48/merge",
                "GITHUB_RUN_ID": "42",
                "GITHUB_RUN_NUMBER": "2586",
                "GITHUB_RUN_ATTEMPT": "1",
                "GITHUB_EVENT_NAME": "pull_request",
                "GITHUB_WORKFLOW": "King VPN Android CI",
                "RUNNER_OS": "Linux",
                "RUNNER_ARCH": "X64",
                "ANDROID_KEYSTORE_PASSWORD": "must-never-be-serialized",
            },
        }
        args.update(overrides)
        return create_manifest(**args)

    def test_manifest_covers_apk_source_lock_toolchain_and_all_symbol_files(self):
        manifest = self._create()
        roles = [item["role"] for item in manifest["artifacts"]]
        self.assertEqual(roles.count("apk"), 1)
        self.assertEqual(roles.count("source-archive"), 1)
        self.assertEqual(roles.count("dependency-lock"), 1)
        self.assertEqual(roles.count("toolchain-report"), 1)
        self.assertEqual(roles.count("obfuscation-symbol"), 1)
        for item in manifest["artifacts"]:
            path = self.root / item["path"]
            self.assertEqual(item["size_bytes"], path.stat().st_size)
            self.assertEqual(item["sha256"], hashlib.sha256(path.read_bytes()).hexdigest())

    def test_checksums_match_manifest_and_manifest_is_deterministic(self):
        first = self._create()
        manifest_bytes = (self.root / "build-evidence/build-manifest.json").read_bytes()
        sums = (self.root / "build-evidence/SHA256SUMS").read_text(encoding="utf-8")
        self.assertEqual(
            sums,
            "".join(f"{item['sha256']}  {item['path']}\n" for item in first["artifacts"]),
        )
        self._create()
        self.assertEqual(
            manifest_bytes,
            (self.root / "build-evidence/build-manifest.json").read_bytes(),
        )

    def test_manifest_contains_build_identity_but_never_environment_secrets(self):
        manifest = self._create()
        self.assertEqual(manifest["source"]["commit"], "abc123")
        self.assertEqual(manifest["workflow"]["run_number"], "2586")
        serialized = json.dumps(manifest)
        self.assertNotIn("must-never-be-serialized", serialized)
        self.assertIn("not production-signed", serialized)

    def test_paths_outside_repository_are_rejected(self):
        with tempfile.NamedTemporaryFile() as outside:
            with self.assertRaisesRegex(ValueError, "escapes repository root"):
                self._create(apk=Path(outside.name))

    def test_missing_symbols_are_a_hard_failure(self):
        (self.root / "build_app/build/symbols/nested/app.symbols").unlink()
        with self.assertRaisesRegex(FileNotFoundError, "no files"):
            self._create()


if __name__ == "__main__":
    unittest.main()
