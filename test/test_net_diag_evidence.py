from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NetworkDiagnosticEvidenceTests(unittest.TestCase):
    def test_filter_layer_classification_uses_multi_endpoint_counts(self):
        source = (ROOT / "lib" / "net_diag.dart").read_text(encoding="utf-8")
        classifier = source.split("_NetClassification _classifyNetEvidence(", 1)[1].split(
            "class _DiagItem", 1
        )[0]
        for category in ("successes(0, 4)", "successes(5, 8)",
                         "successes(9, 13)", "successes(14, 17)",
                         "successes(18, 20)"):
            self.assertIn(category, classifier)
        self.assertIn("tcp >= 3 && tls == 0", classifier)
        self.assertIn("tcp >= 2 && tls >= 2 && web == 0", classifier)
        self.assertIn("web >= 2 && sources == 0", classifier)

    def test_low_confidence_does_not_claim_unfiltered_network(self):
        source = (ROOT / "lib" / "net_diag.dart").read_text(encoding="utf-8")
        self.assertIn("'low'", source)
        self.assertIn("شواهد برای تعیین لایه کافی نیست", source)
        self.assertNotIn("لایه فیلتر مشخصی شناسایی نشد — اینترنت آزاد است", source)

    def test_low_confidence_does_not_mutate_saved_network_settings(self):
        source = (ROOT / "lib" / "net_diag.dart").read_text(encoding="utf-8")
        apply = source.split("List<String> autoNetApply(_NetVerdict v)", 1)[1]
        self.assertIn("if (v.confidence == 'low') return ch;", apply)

    def test_verdict_carries_confidence_and_evidence(self):
        source = (ROOT / "lib" / "net_diag.dart").read_text(encoding="utf-8")
        verdict = source.split("class _NetVerdict {", 1)[1].split(
            "_NetVerdict? lastNetVerdict", 1
        )[0]
        self.assertIn("final String confidence;", verdict)
        self.assertIn("final String evidence;", verdict)
        self.assertIn("classification.confidence", source)
        self.assertIn("classification.evidence", source)


if __name__ == "__main__":
    unittest.main()
