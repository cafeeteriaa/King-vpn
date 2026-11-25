from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class NetworkResponseSourceGuardTests(unittest.TestCase):
    def test_list_mirror_uses_shared_http_acceptance_policy(self):
        source = (ROOT / "lib" / "iran_ai_extras.dart").read_text(encoding="utf-8")
        start = source.index("Future<http.Response> getListMirror(")
        end = source.index("// ======================= لینک اشتراک", start)
        method = source[start:end]
        self.assertIn("isUsableHttpListResponse(r.statusCode, r.body)", method)
        self.assertIn("_rawFail++;", method)
        self.assertIn("_rawOk++;", method)
        self.assertNotIn("return _safeResp(r);", method)

    def test_mirror_race_uses_the_same_http_acceptance_policy(self):
        source = (ROOT / "lib" / "iran_ai_extras.dart").read_text(encoding="utf-8")
        start = source.index("Future<http.Response?> _raceGet(")
        end = source.index("Future<http.Response> getListMirror(", start)
        self.assertIn(
            "isUsableHttpListResponse(r.statusCode, r.body)",
            source[start:end],
        )

    def test_cloudflare_clean_ip_probe_requires_a_valid_trace_document(self):
        source = (ROOT / "lib" / "npv_am_extras.dart").read_text(encoding="utf-8")
        start = source.index("Future<int?> _cfProbeMs(")
        end = source.index("final ValueNotifier<int> cleanTick", start)
        method = source[start:end]
        self.assertEqual(method.count("isValidCloudflareTraceResponse(txt)"), 2)
        self.assertNotIn("txt.contains('cloudflare')", method)


if __name__ == "__main__":
    unittest.main()
