from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NationalScannerIntegrationGuards(unittest.TestCase):
    def test_coordinator_exposes_ordered_national_phases(self):
        source = (ROOT / "lib" / "king_scan_scheduler.dart").read_text(encoding="utf-8")
        phases = [
            "networkDiagnosis",
            "dnsDiscovery",
            "configuredEndpointDiscovery",
            "configuredRangeDiscovery",
        ]
        positions = [source.index("KingNationalScanPhase." + phase) for phase in phases]
        self.assertEqual(positions, sorted(positions))
        self.assertIn("if (active != null)", source)
        self.assertIn("_rerunRequested = true", source)
        self.assertIn("KingNationalScanStatus.failed", source)

    def test_national_idle_path_reuses_existing_scanners_and_keeps_exact_ip_verifier(self):
        source = (ROOT / "lib" / "ip_auto_scan.dart").read_text(encoding="utf-8")
        self.assertIn("kingNationalScanner.runDiscoveryCycle(", source)
        self.assertIn("NatNetworkDiagnosis.refresh()", source)
        self.assertIn("_natDomainFirst(", source)
        self.assertIn("natRangeScanStep(", source)
        self.assertIn("_ipAutoRunOnce(", source)
        self.assertIn("await _ipAutoSave()", source)

    def test_national_dns_is_diagnosed_before_resolver_selection(self):
        source = (ROOT / "lib" / "dns_scanner.dart").read_text(encoding="utf-8")
        self.assertLess(
            source.index("await NatNetworkDiagnosis.refresh()"),
            source.index("final r = await dnsxScan("),
        )
        self.assertIn("nationalMode != scanNationalMode", source)

    def test_national_range_scanner_retains_rust_fallback_and_isolated_cursor(self):
        source = (ROOT / "lib" / "nat_ultra.dart").read_text(encoding="utf-8")
        self.assertIn("_natNationalRangeCursors", source)
        self.assertIn("natExpandAddressRangeBatchForWorker(", source)
        self.assertIn("KingNativeAccel.disableNative()", source)
        self.assertIn("if (modeSnapshot) ...natRanges", source)


if __name__ == "__main__":
    unittest.main()
