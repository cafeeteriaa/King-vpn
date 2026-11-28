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
      expect(engines['network_intelligence']['state'], 'completed');
      expect(engines['discovery']['state'], 'partial');
      expect(engines['real_traffic_validator']['state'], 'completed');
      expect(engines['resource_health_manager']['state'], 'deferred');
      expect(engines['config_intelligence']['state'], 'completed');
      expect(engines['dpi_traffic_transformation']['state'], 'completed');
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
      expect(engines['real_traffic_validator']['state'], 'deferred');
      expect(
        engines['real_traffic_validator']['detail'],
        'requires_connected_tunnel_probe',
      );
    });
  });
}
