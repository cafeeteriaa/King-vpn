import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class AutoTestTlsSafetyAdviceTests(unittest.TestCase):
    def test_removed_allow_insecure_option_never_recommends_core_downgrade(self):
        source = (ROOT / "lib" / "auto_test.dart").read_text(encoding="utf-8")
        start = source.index("String _atCfgNeeds(")
        end = source.index("List<String> _atHelpOf(", start)
        body = source[start:end]
        self.assertIn("allowInsecure", body)
        self.assertIn("Xray 26.9.9", body)
        self.assertIn("گواهی و SNI سرور را اصلاح کن", body)
        self.assertNotIn("با نسخه‌ی ۳.۴.۱ امتحان کن", body)
        self.assertNotIn("install 3.4.1", body.lower())
