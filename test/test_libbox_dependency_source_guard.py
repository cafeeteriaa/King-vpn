import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class LibboxDependencyGuard(unittest.TestCase):
    def test_dependency_pin_and_gradle_patch_are_exact(self):
        dependency = (ROOT / "tools" / "configure_sing_box_dependency.py").read_text()
        patch = (ROOT / "tools" / "patch_sing_box_gradle.py").read_text()
        workflow = (ROOT / ".github" / "workflows" / "build.yml").read_text()
        self.assertIn("72f76fb714e07637a560774a7f2fdd3ae11884c4", dependency)
        self.assertIn("configure_sing_box_dependency.py", workflow)
        self.assertIn("patch_sing_box_gradle.py", workflow)
        self.assertIn('AGP_VERSION = "9.3.1"', patch)
        self.assertIn('KOTLIN_VERSION = "2.4.20"', patch)
        self.assertIn("minSdk = 24", patch)


    def test_dependency_inserter_handles_dev_dependencies_and_is_idempotent(self):
        import subprocess
        import sys
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            pubspec = pathlib.Path(tmp) / "pubspec.yaml"
            pubspec.write_text(
                "name: test_app\n"
                "dependencies:\n"
                "  flutter:\n"
                "    sdk: flutter\n"
                "dev_dependencies:\n"
                "  flutter_test:\n"
                "    sdk: flutter\n",
                encoding="utf-8",
            )
            script = ROOT / "tools" / "configure_sing_box_dependency.py"
            subprocess.run([sys.executable, str(script), str(pubspec)], check=True)
            first = pubspec.read_text(encoding="utf-8")
            subprocess.run([sys.executable, str(script), str(pubspec)], check=True)
            second = pubspec.read_text(encoding="utf-8")
            self.assertEqual(first, second)
            self.assertLess(first.index("sing_box:"), first.index("dev_dependencies:"))
            self.assertIn("72f76fb714e07637a560774a7f2fdd3ae11884c4", first)

    def test_third_party_license_and_build_provenance_exist(self):
        folder = ROOT / "licenses" / "sing_box"
        for name in ("LICENSE", "THIRD_PARTY_NOTICES.md", "SING_BOX_CORE_LICENSE", "BUILD_PROVENANCE.md"):
            self.assertTrue((folder / name).is_file())
        provenance = (folder / "BUILD_PROVENANCE.md").read_text()
        self.assertIn("1.14.4", provenance)
        self.assertIn("d5511581e6275f10683f57bc8e7263badfa48c720d5d04acc741549fe6a66bae", provenance)

if __name__ == "__main__":
    unittest.main()
