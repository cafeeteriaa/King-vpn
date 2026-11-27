import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class NativeVpnDiagnosticsContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.java = (ROOT / "android_src" / "KingVpnService.java").read_text(encoding="utf-8")
        cls.kotlin = (ROOT / "android_src" / "MainActivity.kt").read_text(encoding="utf-8")
        cls.dart = (ROOT / "lib" / "main.dart").read_text(encoding="utf-8")

    def test_java_service_exports_versioned_operational_snapshot(self):
        self.assertIn('snapshot.put("protocolVersion", 2)', self.java)
        for key in (
            "serviceRunning", "active", "stopping", "retryWaiting",
            "nativeBusy", "recovering", "userStopped", "nationalMode",
            "activeAttempt", "attemptSequence", "inFlightOperations",
            "lastErrorPresent", "lastErrorCategory", "serviceUptimeMs",
            "watchdogChecks", "healthyProbes", "softProbeFailures",
            "hardProbeFailures", "failoverCount", "retryCount",
            "currentFailureStreak", "healthyStreak", "lastProbeResult",
            "lastProbeMode", "lastProbeDurationMs", "lastProbeAgeMs",
        ):
            self.assertIn(f'snapshot.put("{key}"', self.java)

    def test_snapshot_never_exports_connection_secrets_or_server_payloads(self):
        start = self.java.index("public Map<String, Object> diagnosticSnapshot()")
        end = self.java.index("\n    }", start)
        snapshot = self.java[start:end]
        for forbidden_key in (
            "config", "password", "uuid", "address", "backups", "remark", "lastError",
        ):
            self.assertNotIn(f'snapshot.put("{forbidden_key}"', snapshot)

    def test_kotlin_channel_handles_running_and_absent_service(self):
        self.assertIn('"vpnService" -> {', self.kotlin)
        self.assertIn("service?.diagnosticSnapshot()", self.kotlin)
        self.assertIn('"serviceRunning" to false', self.kotlin)
        self.assertIn('"protocolVersion" to 2', self.kotlin)

    def test_watchdog_metrics_use_monotonic_time_and_no_server_payload(self):
        self.assertIn("watchdogChecks.incrementAndGet()", self.java)
        self.assertIn("failoverCount.incrementAndGet()", self.java)
        self.assertIn("retryCount.incrementAndGet()", self.java)
        self.assertIn("SystemClock.elapsedRealtime()", self.java)
        self.assertIn("synchronized (lock)", self.java[self.java.index("public Map<String, Object> diagnosticSnapshot()"):])
        self.assertNotIn('snapshot.put("url"', self.java)
        self.assertNotIn('snapshot.put("config"', self.java)

    def test_dart_consumes_the_same_channel_and_protocol(self):
        self.assertIn("invokeMapMethod<String, dynamic>('vpnService')", self.dart)
        self.assertIn("version != 1 && version != 2", self.dart)
        self.assertIn("version == 2", self.dart)
        self.assertIn("VPN-WATCHDOG-TELEMETRY:", self.dart)
        self.assertIn("await _logVpnServiceDiagnostics();", self.dart)
        self.assertIn("NATIVE-VPN-DIAG:", self.dart)
        self.assertIn("lastErrorCategory", self.dart)
        self.assertNotIn("info['lastError']", self.dart)


if __name__ == "__main__":
    unittest.main()
