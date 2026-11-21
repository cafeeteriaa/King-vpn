import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class NatSniCertificateSafetyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / "lib" / "nat_ultra.dart").read_text(encoding="utf-8")

    def test_automatic_sni_change_does_not_disable_certificate_validation(self):
        start = self.source.index("String _natSmartSni(")
        end = self.source.index("int natSafeVariant(", start)
        body = self.source[start:end]
        self.assertIn("tls['serverName'] = 'cdnjs.cloudflare.com';", body)
        self.assertIn("tls['allowInsecure'] = false;", body)
        self.assertNotIn("tls['allowInsecure'] = true;", body)
        self.assertIn("fail closed", body)

    def test_explicit_sni_swap_keeps_certificate_validation_enabled(self):
        start = self.source.index("String _natApplySniSwap(")
        end = self.source.index("String _natFrag(", start)
        body = self.source[start:end]
        self.assertIn("keep certificate validation enabled", body)
        self.assertNotIn("allowInsecure", body)
