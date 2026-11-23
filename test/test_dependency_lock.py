import gzip
import hashlib
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class FlutterDependencyLockTests(unittest.TestCase):
    def test_ci_uses_pinned_sdk_and_enforced_lockfile(self):
        workflow = (ROOT / '.github' / 'workflows' / 'build.yml').read_text(encoding='utf-8')
        self.assertIn("flutter-version: '3.50.1'", workflow)
        self.assertIn('cp ci/flutter/pubspec.yaml build_app/pubspec.yaml', workflow)
        self.assertIn('gzip -dc ci/flutter/pubspec.lock.gz > build_app/pubspec.lock', workflow)
        self.assertIn('flutter pub get --enforce-lockfile', workflow)
        self.assertNotIn('flutter pub add', workflow)

    def test_compressed_lock_matches_verified_ci_snapshot(self):
        compressed = ROOT / 'ci' / 'flutter' / 'pubspec.lock.gz'
        lock = gzip.decompress(compressed.read_bytes())
        self.assertEqual(
            hashlib.sha256(lock).hexdigest(),
            'f531c1ac1fcee55851992a6d76bfb3893b7fc4b2508e20e4adb0cedaa0fa159c',
        )
        text = lock.decode('utf-8')
        self.assertEqual(len(re.findall(r'^  [a-zA-Z0-9_]+:$', text, re.MULTILINE)), 116)
        self.assertEqual(len(re.findall(r'^      sha256: ', text, re.MULTILINE)), 111)
        self.assertIn('flutter_v2ray_client', text)
        self.assertIn('local_inference_flutter', text)

    def test_manifest_is_the_exact_verified_ci_manifest(self):
        manifest = (ROOT / 'ci' / 'flutter' / 'pubspec.yaml').read_bytes()
        self.assertEqual(
            hashlib.sha256(manifest).hexdigest(),
            '23dbe34343fdf272e8b69968532d2b00ef57394f639b6f7b424b9ce3e8ffc04f',
        )


if __name__ == '__main__':
    unittest.main()
