import 'package:flutter_test/flutter_test.dart';
import '../lib/network_health.dart';
import '../lib/self_repair_policy.dart';
import '../lib/errjournal.dart';

void main() {
  group('Domestic/global health separation', () {
    test('global outage does not invalidate proven domestic-only tunnel', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unreachable,
        domesticSamples: 4,
        globalSamples: 4,
        domesticDataPlaneVerified: true,
      );
      expect(evidence.mode, DetectedNetworkMode.domesticOnly);
      expect(evidence.acceptsTunnel(nationalOnly: true), isTrue);
      expect(evidence.acceptsTunnel(nationalOnly: false), isFalse);
      expect(
        choosePilotNetworkStrategy(evidence),
        PilotNetworkStrategy.domestic,
      );
    });

    test('unknown evidence is not treated as successful connectivity', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.unknown,
        global: LinkHealth.unknown,
      );
      expect(evidence.mode, DetectedNetworkMode.unknown);
      expect(evidence.acceptsTunnel(nationalOnly: true), isFalse);
      expect(
        choosePilotNetworkStrategy(evidence),
        PilotNetworkStrategy.preserve,
      );
    });
  });

  test('single failed probe cannot force domestic strategy', () {
    const evidence = NetworkEvidence(
      domestic: LinkHealth.healthy,
      global: LinkHealth.unreachable,
      domesticSamples: 1,
      globalSamples: 1,
    );
    expect(
      choosePilotNetworkStrategy(evidence),
      PilotNetworkStrategy.preserve,
    );
  });

  group('Self repair diagnostics privacy', () {
    test('redacts config links, UUIDs and credential-like values', () {
      final safe = redactSensitiveDiagnostic(
        'vless://secret@example.com:443?uuid=12345678-1234-1234-1234-123456789012 '
        'api_key=supersecretvalue',
      );
      expect(safe, isNot(contains('vless://')));
      expect(safe, isNot(contains('12345678-1234-1234-1234-123456789012')));
      expect(safe, isNot(contains('supersecretvalue')));
    });

    test('runtime report declares that credentials and raw configs are excluded', () {
      final report = buildRepairDiagnosticJson();
      expect(report, contains('raw_config_links_exported'));
      expect(report, contains('credential_values_exported'));
    });
  });

  group('Self repair safety', () {
    test('healthy data plane prevents unnecessary repair', () {
      final decision = decideRepair(const RepairObservation(
        code: 'engine_unhealthy',
        severity: RepairSeverity.warning,
        repeatedCount: 1,
        tunnelDataPlaneHealthy: true,
      ));
      expect(decision.action, RepairAction.none);
    });

    test('repeated failed repair rolls back', () {
      final decision = decideRepair(const RepairObservation(
        code: 'core_stopped',
        severity: RepairSeverity.critical,
        repeatedCount: 3,
        lastActionFailed: true,
      ));
      expect(decision.action, RepairAction.restoreLastKnownGood);
    });

    test('source patch requires signature, tests, analysis and rollback', () {
      final rejected = validateSourcePatch(const PatchGateInput(
        signedByTrustedKey: false,
        testsPassed: true,
        staticAnalysisPassed: true,
        rollbackSnapshotExists: true,
        changedFiles: <String>['lib/example.dart'],
        diffLines: 20,
      ));
      expect(rejected.status, PatchGateStatus.rejected);

      final accepted = validateSourcePatch(const PatchGateInput(
        signedByTrustedKey: true,
        testsPassed: true,
        staticAnalysisPassed: true,
        rollbackSnapshotExists: true,
        changedFiles: <String>['lib/example.dart'],
        diffLines: 20,
      ));
      expect(accepted.status, PatchGateStatus.accepted);
    });

    test('patch gate rejects secrets, path traversal and protected files', () {
      final result = validateSourcePatch(const PatchGateInput(
        signedByTrustedKey: true,
        testsPassed: true,
        staticAnalysisPassed: true,
        rollbackSnapshotExists: true,
        changedFiles: <String>[
          '../outside.dart',
          'android/app/src/main/AndroidManifest.xml',
        ],
        diffLines: 20,
        containsSecret: true,
      ));
      expect(result.status, PatchGateStatus.rejected);
      expect(result.reasons.length, greaterThanOrEqualTo(3));
    });
  });
}
