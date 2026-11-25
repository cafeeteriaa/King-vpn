from pathlib import Path
import tempfile
import unittest
import zipfile

from tools.package_source_archive import create_source_archive


class SourceArchivePackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        for relative in (
            "lib/main.dart",
            "build_app/pubspec.lock",
            ".github/workflows/build.yml",
            "android_src/MainActivity.kt",
            "assets/logo.bin",
        ):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(("source:" + relative).encode())

    def tearDown(self):
        self.temp.cleanup()

    def _package(self, output="build-evidence/source.zip"):
        return create_source_archive(self.root, Path(output))

    def test_archive_contains_complete_required_sources_and_resources(self):
        result = self._package()
        self.assertEqual(result["files"], 5)
        with zipfile.ZipFile(self.root / "build-evidence/source.zip") as archive:
            names = set(archive.namelist())
            self.assertTrue({
                "lib/main.dart",
                "build_app/pubspec.lock",
                ".github/workflows/build.yml",
                "android_src/MainActivity.kt",
                "assets/logo.bin",
            }.issubset(names))

    def test_secret_material_is_excluded_at_root_and_nested_paths(self):
        secrets = (
            ".env", ".env.production", ".envrc", "key.properties", "release.jks",
            "upload.keystore", "client.p12", "client.pfx", "private.pem",
            "signing.key", "AuthKey.p8", "google-services.json",
            "service-account-prod.json", "service_account.json",
            "cloud-credentials.json", "client-credential.json", "api-token.json",
            ".netrc", ".npmrc", ".pypirc", "id_rsa", "id_ed25519",
            ".git-credentials", "config/.env.local", "android/key.properties",
            "keys/nested-release.jks", "nested/private.pem",
            "secrets/api-credentials.json", "config/.npmrc",
            ".docker/config.json", ".aws/credentials",
            ".config/gcloud/application_default_credentials.json",
        )
        for relative in secrets:
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("synthetic-secret", encoding="utf-8")
        self._package()
        with zipfile.ZipFile(self.root / "build-evidence/source.zip") as archive:
            names = set(archive.namelist())
            for relative in secrets:
                self.assertNotIn(relative, names)

    def test_private_key_and_high_confidence_tokens_are_filtered_by_content(self):
        arbitrary = self.root / "docs/opaque.txt"
        arbitrary.parent.mkdir(parents=True)
        arbitrary.write_bytes(
            b"-----BEGIN " + b"PRIVATE KEY-----\nsynthetic-private-material"
        )
        token = self.root / "docs/token.log"
        token.write_text("github_pat_" + "A" * 30, encoding="utf-8")
        self._package()
        with zipfile.ZipFile(self.root / "build-evidence/source.zip") as archive:
            names = set(archive.namelist())
            self.assertNotIn("docs/opaque.txt", names)
            self.assertNotIn("docs/token.log", names)

    def test_private_key_signature_split_across_stream_chunks_is_filtered(self):
        path = self.root / "docs/chunked.dat"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(
            b"x" * (1024 * 1024 - 5) + b"-----BEGIN " + b"PRIVATE KEY-----"
        )
        self._package()
        with zipfile.ZipFile(self.root / "build-evidence/source.zip") as archive:
            self.assertNotIn("docs/chunked.dat", archive.namelist())

    def test_cache_and_generated_machine_local_files_are_excluded(self):
        excluded = (
            ".git/config", ".dart_tool/package_config.json", "build/cache.bin",
            "build_app/android/.gradle/state.bin", "build-evidence/old.zip",
            "build_app/android/local.properties", "build_app/.flutter-plugins-dependencies",
            "module/__pycache__/cache.pyc", "node_modules/pkg/index.js",
            ".terraform/terraform.tfstate",
        )
        for relative in excluded:
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"cache")
        self._package()
        with zipfile.ZipFile(self.root / "build-evidence/source.zip") as archive:
            names = set(archive.namelist())
            for relative in excluded:
                self.assertNotIn(relative, names)

    def test_symlink_files_and_directories_are_never_followed(self):
        outside_temp = tempfile.TemporaryDirectory()
        self.addCleanup(outside_temp.cleanup)
        outside = Path(outside_temp.name)
        (outside / "secret.txt").write_text("secret", encoding="utf-8")
        try:
            (self.root / "linked-file").symlink_to(outside / "secret.txt")
            (self.root / "linked-dir").symlink_to(outside, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("symlinks are unavailable on this platform")
        self._package()
        with zipfile.ZipFile(self.root / "build-evidence/source.zip") as archive:
            names = set(archive.namelist())
            self.assertNotIn("linked-file", names)
            self.assertFalse(any(name.startswith("linked-dir/") for name in names))

    def test_output_outside_repository_is_rejected(self):
        with tempfile.TemporaryDirectory() as outside:
            with self.assertRaisesRegex(ValueError, "escapes repository root"):
                create_source_archive(self.root, Path(outside) / "source.zip")

    def test_missing_required_source_is_a_hard_failure(self):
        (self.root / "android_src/MainActivity.kt").unlink()
        with self.assertRaisesRegex(FileNotFoundError, "required project source files"):
            self._package()

    def test_archive_is_deterministic_and_excludes_its_existing_output(self):
        first = self._package("source.zip")
        first_bytes = (self.root / "source.zip").read_bytes()
        second = self._package("source.zip")
        second_bytes = (self.root / "source.zip").read_bytes()
        self.assertEqual(first["sha256"], second["sha256"])
        self.assertEqual(first_bytes, second_bytes)
        with zipfile.ZipFile(self.root / "source.zip") as archive:
            self.assertNotIn("source.zip", archive.namelist())

    def test_output_symlink_is_rejected(self):
        target = self.root / "existing.zip"
        target.write_bytes(b"keep")
        link = self.root / "linked-output.zip"
        try:
            link.symlink_to(target)
        except (OSError, NotImplementedError):
            self.skipTest("symlinks are unavailable on this platform")
        with self.assertRaisesRegex(ValueError, "must not be a symlink"):
            create_source_archive(self.root, link)


if __name__ == "__main__":
    unittest.main()
