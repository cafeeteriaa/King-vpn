from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


class TlsProbeSecurityTest(unittest.TestCase):
    def test_all_application_tls_probes_keep_platform_certificate_validation(self):
        dart_sources = sorted((ROOT / "lib").rglob("*.dart"))
        self.assertTrue(dart_sources, "Dart application sources must be present")
        bypass = re.compile(
            r"onBadCertificate\\s*:\\s*\\([^)]*\\)\\s*=>\\s*true",
            re.MULTILINE,
        )
        violations = []
        for path in dart_sources:
            source = path.read_text(encoding="utf-8")
            if bypass.search(source):
                violations.append(path.relative_to(ROOT).as_posix())
        self.assertEqual(
            violations,
            [],
            "TLS probes must not trust invalid/self-signed certificates: "
            + ", ".join(violations),
        )

    def test_sni_and_alpn_probes_use_secure_sockets(self):
        source = (ROOT / "lib" / "auto_scanners.dart").read_text(encoding="utf-8")
        self.assertGreaterEqual(source.count("SecureSocket.secure("), 2)
        self.assertIn("supportedProtocols: [alpn]", source)
        self.assertIn("Keep platform certificate validation enabled", source)


if __name__ == "__main__":
    unittest.main()
