from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class AutoScannerTlsSecurityTest(unittest.TestCase):
    def test_auto_sni_probe_does_not_bypass_certificate_validation(self):
        source = (ROOT / "lib" / "auto_scanners.dart").read_text(encoding="utf-8")
        self.assertGreaterEqual(source.count("SecureSocket.secure("), 2)
        self.assertIn("supportedProtocols: [alpn]", source)
        self.assertNotRegex(
            source,
            r"onBadCertificate\s*:\s*\([^)]*\)\s*=>\s*true",
            "SNI probes must not trust invalid TLS certificates.",
        )


if __name__ == "__main__":
    unittest.main()
