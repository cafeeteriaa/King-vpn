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
        diff = '--- a/lib/../android/AndroidManifest.xml\n+++ b/lib/../android/AndroidManifest.xml\n-old\n+new\n'
        self.assertTrue(any('unsafe path' in e for e in patch_gate.validate(diff)))

    def test_rejects_secret(self):
        diff = '--- a/lib/a.dart\n+++ b/lib/a.dart\n-old\n+api_key="12345678901234567890"\n'
        self.assertTrue(any('secret' in e for e in patch_gate.validate(diff)))

    def test_rejects_android_native_and_root_build_files(self):
        for path in (
            'android/app/src/main/AndroidManifest.xml',
            'android/app/src/main/kotlin/MainActivity.kt',
            'README.md',
            '.github/workflows/build.yml',
            'pubspec.yaml',
        ):
            with self.subTest(path=path):
                diff = f'--- a/{path}\n+++ b/{path}\n-old\n+new\n'
                self.assertTrue(any('outside allowed source roots' in e
                                    for e in patch_gate.validate(diff)))

    def test_accepts_only_lib_and_test_roots(self):
        for path in ('lib/a.dart', 'test/a_test.dart'):
            with self.subTest(path=path):
                diff = f'--- a/{path}\n+++ b/{path}\n-old\n+new\n'
                self.assertEqual(patch_gate.validate(diff), [])

    def test_rejects_tools_root_for_automatic_patches(self):
        diff = '--- a/tools/a.py\n+++ b/tools/a.py\n-old\n+new\n'
        self.assertTrue(any('outside allowed source roots' in e
                            for e in patch_gate.validate(diff)))

    def test_rejects_windows_and_dot_path_variants(self):
        for path in (r'lib\\..\\secret.dart', 'lib/./secret.dart'):
            with self.subTest(path=path):
                diff = f'--- a/{path}\n+++ b/{path}\n-old\n+new\n'
                self.assertTrue(patch_gate.validate(diff))

    def test_rejects_symlink_and_submodule_modes(self):
        for mode in ('120000', '160000'):
            with self.subTest(mode=mode):
                diff = (f'diff --git a/lib/escape b/lib/escape\nnew file mode {mode}\n'
                        '--- /dev/null\n+++ b/lib/escape\n@@ -0,0 +1 @@\n+../../outside\n')
                self.assertTrue(any('mode is forbidden' in e
                                    for e in patch_gate.validate(diff)))

    def test_rejects_executable_file_mode(self):
        diff = ('diff --git a/lib/run.dart b/lib/run.dart\nnew file mode 100755\n'
                '--- /dev/null\n+++ b/lib/run.dart\n@@ -0,0 +1 @@\n+main() {}\n')
        self.assertTrue(any('executable file mode' in e
                            for e in patch_gate.validate(diff)))

    def test_rejects_binary_patch(self):
        diff = 'diff --git a/lib/model.bin b/lib/model.bin\nGIT binary patch\nliteral 4\nabcd\n'
        self.assertIn('binary patches are forbidden', patch_gate.validate(diff))


if __name__ == '__main__':
    unittest.main()
