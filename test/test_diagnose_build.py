import importlib.util
from pathlib import Path
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / 'tools' / 'diagnose_build.py'
spec = importlib.util.spec_from_file_location('diagnose_build', MODULE)
diagnose_build = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(diagnose_build)


class DiagnoseBuildTests(unittest.TestCase):
    def test_extracts_plugin_and_dart_locations_without_modifying_sources(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / 'build.log'
            log.write_text(
                "Error: Undefined name 'x' lib/main.dart:42:7\n"
                "MissingPluginException(No implementation found for method vpnSettings)\n",
                encoding='utf-8',
            )
            report = diagnose_build.analyze_logs([log])
        self.assertEqual(report['finding_count'], 2)
        self.assertFalse(report['safety']['source_files_modified'])
        self.assertTrue(any('plugin_channel' in f['categories'] for f in report['findings']))


if __name__ == '__main__':
    unittest.main()
