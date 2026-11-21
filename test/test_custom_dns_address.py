import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class CustomDnsAddressTests(unittest.TestCase):
    def test_custom_dns_accepts_both_ip_families_and_https_doh(self):
        source = (ROOT / "lib" / "npv_am_extras.dart").read_text(encoding="utf-8")
        start = source.index("List<String>? customDnsList()")
        end = source.index("Future<int?> _probeDoh(", start)
        validator = source[start:end]
        self.assertIn("InternetAddressType.IPv4", validator)
        self.assertIn("InternetAddressType.IPv6", validator)
        self.assertIn("uri.scheme.toLowerCase() == 'https'", validator)

    def test_custom_dns_ui_documents_ipv6_literal_input(self):
        source = (ROOT / "lib" / "npv_am_extras.dart").read_text(encoding="utf-8")
        self.assertIn("2606:4700:4700::1111", source)

    def test_custom_doh_requires_a_valid_https_authority_without_credentials_or_fragment(self):
        source = (ROOT / "lib" / "npv_am_extras.dart").read_text(encoding="utf-8")
        start = source.index("List<String>? customDnsList()")
        end = source.index("Future<int?> _probeDoh(", start)
        body = source[start:end]
        self.assertIn("Uri.tryParse(a)", body)
        self.assertIn("uri.scheme.toLowerCase() == 'https'", body)
        self.assertIn("uri.host.isNotEmpty", body)
        self.assertIn("uri.userInfo.isEmpty", body)
        self.assertIn("uri.fragment.isEmpty", body)
        self.assertIn("uri.port >= 1", body)
        self.assertIn("RegExp(r'\\s')", body)
