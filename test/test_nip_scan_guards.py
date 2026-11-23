import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class NationalIpScannerGuardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / "lib" / "nip_scan.dart").read_text(encoding="utf-8")

    def test_cidr_sampling_has_hard_ceiling_and_positive_limit(self):
        start = self.source.index("List<String> nipExpandCidr(")
        end = self.source.index("/// اتصال TCP", start)
        block = self.source[start:end]
        self.assertIn("if (maxPerBlock <= 0) return const [];", block)
        self.assertIn("if (maxPerBlock <= 0) return const [];", block)
        self.assertIn("(size + maxPerBlock - 1) ~/ maxPerBlock", block)
        self.assertIn("i += step", block)

    def test_scanner_validates_port_and_time_budgets_before_work(self):
        start = self.source.index("Future<List<NipHit>> nipScan(")
        end = self.source.index("/// همان کانفیگ سرور", start)
        block = self.source[start:end]
        self.assertIn("port < 1 || port > 65535", block)
        self.assertIn("budget <= Duration.zero", block)
        self.assertIn("timeout <= Duration.zero", block)
        self.assertIn("final boundedIps = natBoundScanTargets(ips);", block)

    def test_scan_uses_monotonic_clock_and_enforces_remaining_budget(self):
        start = self.source.index("Future<List<NipHit>> nipScan(")
        end = self.source.index("/// همان کانفیگ سرور", start)
        block = self.source[start:end]
        self.assertIn("final elapsed = Stopwatch()..start();", block)
        self.assertIn("final remaining = budget - elapsed.elapsed;", block)
        self.assertIn("if (remaining <= Duration.zero) return;", block)
        self.assertIn("final probeTimeout = timeout < remaining ? timeout : remaining;", block)
        self.assertIn("nipTcpProbe(ip, port, probeTimeout)", block)

    def test_worker_checks_cancel_budget_and_result_cap(self):
        start = self.source.index("Future<List<NipHit>> nipScan(")
        end = self.source.index("/// همان کانفیگ سرور", start)
        block = self.source[start:end]
        self.assertIn("if (hits.length >= want) return;", block)
        self.assertIn("if (cancelled != null && cancelled()) return;", block)
        self.assertIn("if (elapsed.elapsed >= budget) return;", block)
        self.assertIn("concurrency.clamp(1, 16)", block)

    def test_nat_scan_caps_each_probe_to_remaining_monotonic_budget(self):
        source = (ROOT / "lib" / "nat_ip_scan.dart").read_text(encoding="utf-8")
        start = source.index("Future<List<NatIpHit>> natScanIps(")
        block = source[start:]
        self.assertIn("final remaining = budget - elapsed.elapsed;", block)
        self.assertIn("if (remaining <= Duration.zero) return;", block)
        self.assertIn("final probeTimeout = timeout < remaining ? timeout : remaining;", block)
        self.assertIn("natTcpProbe(ip, port, probeTimeout)", block)
        self.assertIn("Socket.connect itself is not cancellable.", block)

    def test_relay_hosts_are_validated_deduplicated_and_bounded_on_load_and_save(self):
        self.assertIn("const int kNatMaxRelayHosts = 32;", self.source)
        start = self.source.index("Future<void> natRelayHostsLoad()")
        end = self.source.index("Future<String?> nipResolve(", start)
        block = self.source[start:end]
        self.assertEqual(block.count("natBoundScanTargets("), 2)
        self.assertEqual(block.count("maxCount: kNatMaxRelayHosts"), 2)
        self.assertIn("p.getStringList('nat_relay_hosts')", block)
        self.assertIn("p.setStringList('nat_relay_hosts', natRelayHosts)", block)

    def test_tcp_probe_destroys_successful_socket(self):
        start = self.source.index("Future<int?> nipTcpProbe(")
        end = self.source.index("/// اسکن هم‌زمان", start)
        block = self.source[start:end]
        self.assertIn("Socket.connect(ip, port, timeout: timeout)", block)
        self.assertIn("s.destroy();", block)

    def test_explicit_ipv6_cidr_sampling_is_bounded_and_numeric_only(self):
        source = (ROOT / 'lib' / 'nat_ip_scan.dart').read_text(encoding='utf-8')
        start = source.index('List<String> natExpandIpv6Cidr(')
        end = source.index('/// بازه‌ی خطی', start)
        block = source[start:end]
        self.assertIn('InternetAddressType.IPv6', block)
        self.assertIn('prefix < 0 ||', block)
        self.assertIn('if (maxPerBlock <= 0) return const <String>[];', block)
        self.assertIn('final limit = maxPerBlock;', block)
        self.assertIn('out.length < limit', block)
        self.assertIn('BigInt', block)
        self.assertIn('InternetAddress.fromRawAddress', block)

    def test_front_tls_probe_keeps_certificate_validation_and_closes_sockets(self):
        start = self.source.index("Future<String?> nipFrontProbe(")
        end = self.source.index("Future<String?> nipFindFrontSni(", start)
        block = self.source[start:end]
        self.assertIn("SecureSocket.secure(raw, host: sni)", block)
        self.assertNotIn("onBadCertificate:", block)
        self.assertIn("finally", block)
        self.assertIn("sec?.destroy()", block)
        self.assertIn("raw?.destroy()", block)


    def test_front_tls_probe_uses_one_monotonic_deadline_for_tcp_and_tls(self):
        start = self.source.index("Future<String?> nipFrontProbe(")
        end = self.source.index("Future<String?> nipFindFrontSni(", start)
        block = self.source[start:end]
        self.assertIn("final elapsed = Stopwatch()..start();", block)
        self.assertIn("Duration remaining() => timeout - elapsed.elapsed;", block)
        self.assertIn("final connectBudget = remaining();", block)
        self.assertIn("final handshakeBudget = remaining();", block)
        self.assertIn(".timeout(handshakeBudget)", block)
        self.assertNotIn(".timeout(const Duration(seconds: 3))", block)
        self.assertNotIn("onBadCertificate:", block)

    def test_front_sni_search_has_total_budget_and_observes_cancellation(self):
        start = self.source.index("Future<List<String>> nipFindFrontSnis(")
        end = self.source.index("Future<String?> nipFindFrontSni(", start)
        block = self.source[start:end]
        self.assertIn("final elapsed = Stopwatch()..start();", block)
        self.assertIn("final remaining = budget - elapsed.elapsed;", block)
        self.assertIn("cancelled?.call() == true", block)
        self.assertIn("final probeBudget = remaining < perProbeCap ? remaining : perProbeCap;", block)
        self.assertIn("nipFrontProbe(ip, port, sni, timeout: probeBudget)", block)
        self.assertIn("budget = const Duration(seconds: 90)", block)

    def test_front_sni_wrapper_forwards_cancellation_and_budget(self):
        start = self.source.index("Future<String?> nipFindFrontSni(")
        end = self.source.index("/// همان کانفیگ را با IP و SNI جدید", start)
        block = self.source[start:end]
        self.assertIn("nipFindFrontSnis(", block)
        self.assertIn("cancelled: cancelled", block)
        self.assertIn("budget: budget", block)

    def test_front_sni_scan_passes_its_abort_signal_to_each_probe(self):
        self.assertIn("nipFindFrontSnis(", self.source)
        self.assertIn("cancelled: () => abort", self.source)

if __name__ == "__main__":
    unittest.main()
