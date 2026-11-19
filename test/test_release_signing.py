import importlib.util
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "configure_release_signing.py"
SPEC = importlib.util.spec_from_file_location("configure_release_signing", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class ReleaseSigningConfigurationTests(unittest.TestCase):
    def test_kotlin_imports_precede_plugins_and_release_signing_is_configured(self):
        with tempfile.TemporaryDirectory() as directory:
            gradle = pathlib.Path(directory) / "build.gradle.kts"
            gradle.write_text(
                'plugins {\n    id("com.android.application")\n}\n'
                'android { buildTypes { getByName("release") { } } }\n',
                encoding="utf-8",
            )
            MODULE.configure(gradle)
            result = gradle.read_text(encoding="utf-8")
            self.assertTrue(result.startswith("import java.io.FileInputStream"))
            self.assertLess(result.index("import java.util.Properties"), result.index("plugins {"))
            self.assertLess(result.index("plugins {"), result.index("val kingReleaseProperties"))
            self.assertIn('create("kingRelease")', result)
            self.assertIn('getByName("release")', result)
            self.assertIn('rootProject.file("key.properties")', result)

    def test_groovy_release_signing_is_configured(self):
        with tempfile.TemporaryDirectory() as directory:
            gradle = pathlib.Path(directory) / "build.gradle"
            gradle.write_text("plugins { id 'com.android.application' }\n", encoding="utf-8")
            MODULE.configure(gradle)
            result = gradle.read_text(encoding="utf-8")
            self.assertIn("kingRelease {", result)
            self.assertIn("signingConfig signingConfigs.kingRelease", result)

    def test_release_workflow_passes_gist_token_without_literal_backslash(self):
        workflow = (ROOT / ".github" / "workflows" / "signed-release.yml").read_text(encoding="utf-8")
        self.assertIn("KING_UPDATE_GIST_TOKEN: ${{ secrets.KING_UPDATE_GIST_TOKEN }}", workflow)
        self.assertNotIn(r"\${{ secrets.KING_UPDATE_GIST_TOKEN }}", workflow)

    def test_release_is_limited_to_merged_main_and_semver_tags(self):
        workflow = (ROOT / ".github" / "workflows" / "signed-release.yml").read_text(encoding="utf-8")
        self.assertIn("git merge-base --is-ancestor", workflow)
        self.assertIn("Release tags must point to a commit already merged into main.", workflow)
        self.assertIn("^\\\\d+\\\\.[0-9]+\\\\.[0-9]+$", workflow)
        self.assertIn("keytool -list -keystore", workflow)

    def test_signed_release_resolves_package_info_plus_used_by_updater(self):
        workflow = (ROOT / ".github" / "workflows" / "signed-release.yml").read_text(encoding="utf-8")
        self.assertIn("path_provider package_info_plus speech_to_text", workflow)

    def test_duplicate_signing_injection_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            gradle = pathlib.Path(directory) / "build.gradle.kts"
            gradle.write_text(
                'plugins { id("com.android.application") }\n'
                'val kingReleaseProperties = Properties()\n',
                encoding="utf-8",
            )
            with self.assertRaises(SystemExit):
                MODULE.configure(gradle)


if __name__ == "__main__":
    unittest.main()
