import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/main.dart';

void main() {
  group('KING Net Melli 13-engine runtime', () {
    test('registers all thirteen internal engines independently of VPN cores', () {
      final diagnostics = KingNatSubsystemEngine.diagnostics();
      final engines = diagnostics['engines'] as List;
      final ids = engines.map((row) => (row as Map)['id']).toSet();
      expect(engines, hasLength(13));
      expect(ids, containsAll(<String>{
        'connection_orchestrator',
        'network_intelligence',
        'discovery',
        'scanner',
        'compatibility',
        'real_traffic_validator',
        'config_intelligence',
        'network_identity',
        'dpi_traffic_transformation',
        'capability_orchestrator',
        'multi_engine_connector',
        'ai_repair_optimization',
        'resource_health_manager',
      }));
    });

    test('routes evidence and phase execution through the thirteen-engine coordinator', () {
      KingNatSubsystemEngine.beginRun(nationalMode: true, sliceBudgetMs: 60000);
      KingNatSubsystemEngine.recordNetworkEvidence(
        domesticTls: 2,
        globalTls: 0,
        domesticIpv6: 1,
        globalIpv6: 0,
        confidence: 0.75,
      );
      KingNatSubsystemEngine.recordDiscoveryInventory(
        ipv4Resources: 2400,
        ipv6Resources: 36,
      );
      KingNatSubsystemEngine.recordNetworkIdentity('mobile|AS12345');
      KingNatSubsystemEngine.recordResourceBudget(
        workers: 8,
        sliceBudgetMs: 60000,
        batchPorts: 4,
      );
      KingNatSubsystemEngine.phaseStarted('config');
      KingNatSubsystemEngine.recordConfigPlan(12);
      KingNatSubsystemEngine.phaseCompleted('config', evidence: 12);
      KingNatSubsystemEngine.recordTrafficValidation(
        true,
        mode: 'national',
        destinations: 2,
      );
      KingNatSubsystemEngine.finishRun(
        cancelled: false,
        yielded: true,
        deferred: false,
        inventoryComplete: false,
      );

      final diagnostics = KingNatSubsystemEngine.diagnostics();
      expect(diagnostics['nationalMode'], isTrue);
      expect(diagnostics['plannedVariants'], 12);
      expect(diagnostics['workers'], 8);
      expect(diagnostics['operatorIdentity'], 'mobile|AS12345');
      expect((diagnostics['trafficValidation'] as Map)['passed'], 1);
      expect((diagnostics['inventory'] as Map)['ipv4Resources'], 2400);

      final engines = {
        for (final row in diagnostics['engines'] as List)
          (row as Map)['id'] as String: row,
      };
      expect(engines['network_intelligence']!['state'], 'completed');
      // A yielded slice is resumable work, not a failed/partial inventory.
      expect(engines['discovery']!['state'], 'deferred');
      expect(engines['scanner']!['state'], 'deferred');
      expect(engines['real_traffic_validator']!['state'], 'partial');
      expect(
        engines['real_traffic_validator']!['detail'],
        'mode_national_passed_destinations_2_probe_only',
      );
      expect(engines['resource_health_manager']!['state'], 'deferred');
      expect(engines['config_intelligence']!['state'], 'completed');
      expect(engines['dpi_traffic_transformation']!['state'], 'partial');
      expect(engines['ai_repair_optimization']!['state'], 'partial');
      expect(engines['compatibility']!['state'], 'partial');
      expect(
        engines.values.every((row) => row['state'] != 'running'),
        isTrue,
      );
    });

    test('preserves adaptive resource budgets without coordinator-level fixed caps', () {
      KingNatSubsystemEngine.beginRun(nationalMode: true, sliceBudgetMs: 30000);
      KingNatSubsystemEngine.recordResourceBudget(
        workers: 256,
        sliceBudgetMs: 7200000,
        batchPorts: 100000,
      );
      final diagnostics = KingNatSubsystemEngine.diagnostics();
      expect(diagnostics['workers'], 256);
      expect(diagnostics['sliceBudgetMs'], 7200000);
      expect(diagnostics['batchPorts'], 100000);
    });

    test('a completed scan phase does not falsely complete the full scanner or inventory', () {
      KingNatSubsystemEngine.beginRun(nationalMode: true, sliceBudgetMs: 30000);
      KingNatSubsystemEngine.recordDiscoveryInventory(
        ipv4Resources: 2400,
        ipv6Resources: 36,
      );
      KingNatSubsystemEngine.phaseStarted('ip');
      KingNatSubsystemEngine.phaseCompleted('ip', evidence: 2400);
      KingNatSubsystemEngine.finishRun(
        cancelled: false,
        yielded: false,
        deferred: false,
        inventoryComplete: false,
      );
      final engines = {
        for (final row in KingNatSubsystemEngine.diagnostics()['engines'] as List)
          (row as Map)['id'] as String: row,
      };
      expect(engines['discovery']!['state'], 'partial');
      expect(engines['scanner']!['state'], 'partial');
      expect(
        engines['discovery']!['detail'],
        'inventory_continues_from_durable_cursor',
      );
    });

    test('clears prior route and inventory evidence at the next scan start', () {
      KingNatSubsystemEngine.beginRun(nationalMode: true, sliceBudgetMs: 30000);
      KingNatSubsystemEngine.recordNetworkEvidence(
        domesticTls: 3,
        globalTls: 1,
        domesticIpv6: 2,
        globalIpv6: 1,
        confidence: 0.9,
      );
      KingNatSubsystemEngine.recordDiscoveryInventory(
        ipv4Resources: 900,
        ipv6Resources: 40,
      );
      KingNatSubsystemEngine.recordNetworkIdentity('mobile|AS64500');

      KingNatSubsystemEngine.beginRun(nationalMode: false, sliceBudgetMs: 45000);
      final diagnostics = KingNatSubsystemEngine.diagnostics();
      expect(diagnostics['nationalMode'], isFalse);
      expect(diagnostics['operatorIdentity'], 'unknown');
      expect(diagnostics['inventory'], <String, int>{
        'ipv4Resources': 0,
        'ipv6Prefixes': 0,
      });
      expect(diagnostics['routeEvidence'], <String, Object?>{
        'domesticTls': 0,
        'globalTls': 0,
        'domesticIpv6': 0,
        'globalIpv6': 0,
        'confidence': 0.0,
      });
    });

    test('scanner completes only after all phases and durable inventory finish', () {
      KingNatSubsystemEngine.beginRun(nationalMode: true, sliceBudgetMs: 30000);
      KingNatSubsystemEngine.recordDiscoveryInventory(
        ipv4Resources: 2400,
        ipv6Resources: 36,
      );
      KingNatSubsystemEngine.recordResourceBudget(
        workers: 8,
        sliceBudgetMs: 30000,
        batchPorts: 4,
      );
      for (final phase in const ['dns', 'domain', 'ip', 'sni']) {
        KingNatSubsystemEngine.phaseStarted(phase);
        KingNatSubsystemEngine.phaseCompleted(phase, evidence: 10);
      }
      KingNatSubsystemEngine.finishRun(
        cancelled: false,
        yielded: false,
        deferred: false,
        inventoryComplete: true,
      );
      final engines = {
        for (final row in KingNatSubsystemEngine.diagnostics()['engines'] as List)
          (row as Map)['id'] as String: row,
      };
      expect(engines['discovery']!['state'], 'completed');
      expect(engines['scanner']!['state'], 'completed');
      expect(engines['resource_health_manager']!['state'], 'completed');
    });

    test('resumed scan restores earlier completed phases from its durable journal', () {
      KingNatSubsystemEngine.beginRun(nationalMode: true, sliceBudgetMs: 30000);
      KingNatSubsystemEngine.restoreCompletedPhases(const ['dns', 'domain']);
      KingNatSubsystemEngine.recordDiscoveryInventory(
        ipv4Resources: 2400,
        ipv6Resources: 36,
      );
      KingNatSubsystemEngine.recordResourceBudget(
        workers: 8,
        sliceBudgetMs: 30000,
        batchPorts: 4,
      );
      for (final phase in const ['ip', 'sni']) {
        KingNatSubsystemEngine.phaseStarted(phase);
        KingNatSubsystemEngine.phaseCompleted(phase, evidence: 10);
      }
      KingNatSubsystemEngine.finishRun(
        cancelled: false,
        yielded: false,
        deferred: false,
        inventoryComplete: true,
      );
      final engines = {
        for (final row in KingNatSubsystemEngine.diagnostics()['engines'] as List)
          (row as Map)['id'] as String: row,
      };
      expect(engines['scanner']!['state'], 'completed');
      expect(
        KingNatSubsystemEngine.diagnostics()['completedPhases'],
        containsAll(const ['dns', 'domain', 'ip', 'sni']),
      );
    });

    test('all phase markers still cannot complete scanner with a pending inventory cursor', () {
      KingNatSubsystemEngine.beginRun(nationalMode: true, sliceBudgetMs: 30000);
      for (final phase in const ['dns', 'domain', 'ip', 'sni']) {
        KingNatSubsystemEngine.phaseStarted(phase);
        KingNatSubsystemEngine.phaseCompleted(phase, evidence: 10);
      }
      KingNatSubsystemEngine.finishRun(
        cancelled: false,
        yielded: false,
        deferred: false,
        inventoryComplete: false,
      );
      final engines = {
        for (final row in KingNatSubsystemEngine.diagnostics()['engines'] as List)
          (row as Map)['id'] as String: row,
      };
      expect(engines['scanner']!['state'], 'partial');
      expect(engines['discovery']!['state'], 'partial');
    });

    test('single-destination traffic success is probe evidence, not stable validation', () {
      KingNatSubsystemEngine.beginRun(nationalMode: true, sliceBudgetMs: 30000);
      KingNatSubsystemEngine.recordTrafficValidation(
        true, mode: 'national', destinations: 1,
      );
      var diagnostics = KingNatSubsystemEngine.diagnostics();
      var validator = (diagnostics['engines'] as List)
          .cast<Map>()
          .firstWhere((row) => row['id'] == 'real_traffic_validator');
      expect(validator['state'], 'partial');
      expect((diagnostics['trafficValidation'] as Map)['passed'], 1);
      expect((diagnostics['trafficValidation'] as Map)['stablePassed'], 0);

      KingNatSubsystemEngine.recordTrafficValidation(
        true, mode: 'national', destinations: 2, stable: true,
      );
      diagnostics = KingNatSubsystemEngine.diagnostics();
      validator = (diagnostics['engines'] as List)
          .cast<Map>()
          .firstWhere((row) => row['id'] == 'real_traffic_validator');
      expect(validator['state'], 'completed');
      expect((diagnostics['trafficValidation'] as Map)['stablePassed'], 1);
    });

    test('stable flag cannot complete validation with fewer than two destinations', () {
      KingNatSubsystemEngine.beginRun(nationalMode: false, sliceBudgetMs: 30000);
      KingNatSubsystemEngine.recordTrafficValidation(
        true, mode: 'global', destinations: 1, stable: true,
      );
      final diagnostics = KingNatSubsystemEngine.diagnostics();
      final validator = (diagnostics['engines'] as List)
          .cast<Map>()
          .firstWhere((row) => row['id'] == 'real_traffic_validator');
      expect(validator['state'], 'partial');
      expect((diagnostics['trafficValidation'] as Map)['stableFailed'], 1);
    });

    test('UDP, CDN, transformation and repair require adapter-backed evidence', () {
      KingNatSubsystemEngine.beginRun(nationalMode: true, sliceBudgetMs: 30000);
      KingNatSubsystemEngine.recordUdpDiscovery(probes: 10, responses: 0, rangeComplete: true, fullInventoryComplete: false);
      KingNatSubsystemEngine.recordCdnValidation(
        candidates: 5, successfulHandshakes: 3, tunnelPasses: 0, inventoryComplete: true,
      );
      KingNatSubsystemEngine.recordTransformationExecution(
        adapterId: 'fragment-v1', applied: true, tunnelTrafficPassed: false, coverageComplete: false,
      );
      KingNatSubsystemEngine.recordRepairEvaluation(
        strategyId: 'repair-a', evaluated: true, changed: true, tunnelImproved: false, coverageComplete: false,
      );
      var engines = {
        for (final row in KingNatSubsystemEngine.diagnostics()['engines'] as List)
          (row as Map)['id'] as String: row,
      };
      expect(engines['dpi_traffic_transformation']!['state'], 'partial');
      expect(engines['ai_repair_optimization']!['state'], 'partial');
      expect(engines['compatibility']!['state'], 'partial');

      KingNatSubsystemEngine.recordUdpDiscovery(probes: 10, responses: 2, rangeComplete: true, fullInventoryComplete: true);
      KingNatSubsystemEngine.recordCdnValidation(
        candidates: 5, successfulHandshakes: 3, tunnelPasses: 2, inventoryComplete: true,
      );
      KingNatSubsystemEngine.recordTransformationExecution(
        adapterId: 'fragment-v1', applied: true, tunnelTrafficPassed: true, coverageComplete: true,
      );
      KingNatSubsystemEngine.recordRepairEvaluation(
        strategyId: 'repair-a', evaluated: true, changed: true, tunnelImproved: true, coverageComplete: true,
      );
      KingNatSubsystemEngine.recordCompatibilityEvaluation(evaluated: 5, accepted: 4, allResolved: true);
      engines = {
        for (final row in KingNatSubsystemEngine.diagnostics()['engines'] as List)
          (row as Map)['id'] as String: row,
      };
      expect(engines['dpi_traffic_transformation']!['state'], 'completed');
      expect(engines['ai_repair_optimization']!['state'], 'completed');
      expect(engines['compatibility']!['state'], 'completed');
      final evidence = KingNatSubsystemEngine.adapterEvidence();
      expect(evidence['udpResponses'], 2);
      expect(evidence['cdnTunnelPasses'], 2);
      expect(evidence['validatedTransformations'], contains('fragment-v1'));
      expect(evidence['validatedRepairs'], contains('repair-a'));
    });

    test('config planning resolves the capability catalog without claiming adapters are active', () {
      KingNatSubsystemEngine.beginRun(nationalMode: true, sliceBudgetMs: 30000);
      KingNatSubsystemEngine.recordConfigPlan(8);
      final diagnostics = KingNatSubsystemEngine.diagnostics();
      final engines = {
        for (final row in diagnostics['engines'] as List)
          (row as Map)['id'] as String: row,
      };
      expect(engines['capability_orchestrator']!['state'], 'completed');
      expect(engines['multi_engine_connector']!['state'], 'running');
      expect((diagnostics['adapterEvidence'] as Map)['adapterInvocations'], 0);
    });

    test('capability and connector engines require successful resolution/invocation', () {
      KingNatSubsystemEngine.beginRun(nationalMode: false, sliceBudgetMs: 30000);
      KingNatSubsystemEngine.recordCapabilityResolution(resolved: 3, unresolved: 1);
      KingNatSubsystemEngine.recordAdapterInvocation(adapterId: 'dns-adapter', succeeded: false, allRequiredAdaptersConnected: false);
      var engines = {
        for (final row in KingNatSubsystemEngine.diagnostics()['engines'] as List)
          (row as Map)['id'] as String: row,
      };
      expect(engines['capability_orchestrator']!['state'], 'partial');
      expect(engines['multi_engine_connector']!['state'], 'partial');
      KingNatSubsystemEngine.recordCapabilityResolution(resolved: 4, unresolved: 0);
      KingNatSubsystemEngine.recordAdapterInvocation(adapterId: 'dns-adapter', succeeded: true, allRequiredAdaptersConnected: true);
      engines = {
        for (final row in KingNatSubsystemEngine.diagnostics()['engines'] as List)
          (row as Map)['id'] as String: row,
      };
      expect(engines['capability_orchestrator']!['state'], 'completed');
      expect(engines['multi_engine_connector']!['state'], 'completed');
    });

    test('adapter evidence is reset between independent network runs', () {
      KingNatSubsystemEngine.beginRun(nationalMode: true, sliceBudgetMs: 30000);
      KingNatSubsystemEngine.recordTransformationExecution(
        adapterId: 'fragment-v1', applied: true, tunnelTrafficPassed: true,
      );
      KingNatSubsystemEngine.beginRun(nationalMode: false, sliceBudgetMs: 30000);
      final evidence = KingNatSubsystemEngine.adapterEvidence();
      expect(evidence['transformAttempts'], 0);
      expect(evidence['validatedTransformations'], isEmpty);
      expect(evidence['validatedRepairs'], isEmpty);
    });

    test('does not mark preflight-only work as real tunnel validation', () {
      KingNatSubsystemEngine.beginRun(nationalMode: true, sliceBudgetMs: 30000);
      KingNatSubsystemEngine.finishRun(
        cancelled: false,
        yielded: false,
        deferred: false,
        inventoryComplete: true,
      );
      final engines = {
        for (final row in KingNatSubsystemEngine.diagnostics()['engines'] as List)
          (row as Map)['id'] as String: row,
      };
      expect(engines['real_traffic_validator']!['state'], 'deferred');
      expect(
        engines['real_traffic_validator']!['detail'],
        'requires_connected_tunnel_probe',
      );
    });
  });
}
