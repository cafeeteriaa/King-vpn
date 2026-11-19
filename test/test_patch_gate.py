import importlib.util
from pathlib import Path
import unittest

MODULE = Path(__file__).resolve().parents[1] / 'tools' / 'patch_gate.py'
spec = importlib.util.spec_from_file_location('patch_gate', MODULE)
patch_gate = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(patch_gate)


class PatchGateTests(unittest.TestCase):
    def test_accepts_small_safe_patch(self):
        diff = '--- a/lib/a.dart\n+++ b/lib/a.dart\n-old\n+new\n'
        self.assertEqual(patch_gate.validate(diff), [])

    def test_rejects_path_traversal(self):
        diff = '--- a/../../bad\n+++ b/../../bad\n-old\n+new\n'
        self.assertTrue(any('unsafe path' in e for e in patch_gate.validate(diff)))

    def test_rejects_secret(self):
        diff = '--- a/lib/a.dart\n+++ b/lib/a.dart\n-old\n+api_key="12345678901234567890"\n'
        self.assertTrue(any('secret' in e for e in patch_gate.validate(diff)))

    def test_rejects_protected_android_file(self):
        diff = ('--- a/android/app/src/main/AndroidManifest.xml\n'
                '+++ b/android/app/src/main/AndroidManifest.xml\n-old\n+new\n')
        errors = patch_gate.validate(diff)
        self.assertTrue(any('outside allowed source roots' in e for e in errors))
        self.assertTrue(any('protected file' in e for e in errors))

    def test_rejects_native_kotlin_source_without_human_review(self):
        diff = ('--- a/android/app/src/main/kotlin/MainActivity.kt\n'
                '+++ b/android/app/src/main/kotlin/MainActivity.kt\n-old\n+new\n')
        errors = patch_gate.validate(diff)
        self.assertTrue(any('outside allowed source roots' in e for e in errors))
        self.assertTrue(any('protected file' in e for e in errors))

    def test_rejects_root_docs_and_workflow_changes(self):
        for path in ('README.md', '.github/workflows/build.yml', 'pubspec.yaml'):
            with self.subTest(path=path):
                diff = f'--- a/{path}\n+++ b/{path}\n-old\n+new\n'
                self.assertTrue(any('outside allowed source roots' in e
                                    for e in patch_gate.validate(diff)))

    def test_accepts_only_the_three_explicit_roots(self):
        for path in ('lib/a.dart', 'test/a_test.dart', 'tools/a.py'):
            with self.subTest(path=path):
                diff = f'--- a/{path}\n+++ b/{path}\n-old\n+new\n'
                self.assertEqual(patch_gate.validate(diff), [])

    def test_rejects_windows_and_dot_path_variants(self):
        for path in (r'lib\\..\\secret.dart', 'lib/./secret.dart'):
            with self.subTest(path=path):
                diff = f'--- a/{path}\n+++ b/{path}\n-old\n+new\n'
                self.assertTrue(patch_gate.validate(diff))


if __name__ == '__main__':
    unittest.main()
