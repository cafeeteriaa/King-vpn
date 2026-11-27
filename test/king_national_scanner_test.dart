import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/main.dart';
import 'package:king_vpn/nnie_core.dart';
import 'package:king_vpn/prefs_store.dart';

void main() {
  group('KING National Scanner Engine capability registry', () {
    test('registers existing SNI, fragmentation and DNS adapters', () {
      final ids = KingNationalScannerEngine.registry.map((e) => e.id).toSet();
      expect(ids, contains('sni_override'));
      expect(ids, contains('tls_hello_fragmentation'));
      expect(ids, contains('doh_resolver'));
      expect(ids, contains('tcp_segmentation_compatibility'));
    });

    test('keeps fake packet techniques explicit and does not mislabel them as implemented', () {
      final rows = {
        for (final row in KingNationalScannerEngine.registry) row.id: row,
      };
      expect(rows, contains('fake_tcp_packet'));
      expect(rows['fake_tcp_packet']!.status,
          KingNatCapabilityStatus.researchOnly);
      expect(rows['fake_tls_packet']!.status,
          KingNatCapabilityStatus.researchOnly);
      expect(rows['multi_disorder']!.status,
          KingNatCapabilityStatus.researchOnly);
    });

    test('distinguishes bridge-dependent transports from client adapters', () {
      final rows = {
        for (final row in KingNationalScannerEngine.registry) row.id: row,
      };
      expect(rows['transport_obfs4']!.status,
          KingNatCapabilityStatus.requiresServerInfrastructure);
      expect(rows['refraction_conjure']!.status,
          KingNatCapabilityStatus.requiresServerInfrastructure);
    });

    test('scanner mode uses independent network evidence and preserves unknown state', () {
      expect(KingNationalScannerEngine.chooseNationalMode(
        diagnosis: NatNetworkClass.domesticOnlyLikely,
        domesticTlsSuccesses: 2,
        globalTlsSuccesses: 0,
      ), isTrue);
      expect(KingNationalScannerEngine.chooseNationalMode(
        diagnosis: NatNetworkClass.globalReachable,
        domesticTlsSuccesses: 0,
        globalTlsSuccesses: 2,
      ), isFalse);
      expect(KingNationalScannerEngine.chooseNationalMode(
        diagnosis: NatNetworkClass.unknown,
        domesticTlsSuccesses: 0,
        globalTlsSuccesses: 0,
      ), isNull);
    });

    test('disabled padding noise and unsupported fake packets are not claimed as ready', () {
      final rows = {
        for (final row in KingNationalScannerEngine.registry) row.id: row,
      };
      expect(rows['padding_noise']!.status, KingNatCapabilityStatus.incompatible);
      expect(rows['fake_tcp_packet']!.status, KingNatCapabilityStatus.researchOnly);
      expect(rows['udp_packet_forgery']!.status, KingNatCapabilityStatus.researchOnly);
    });

    test('restores baseline variant zero and bounds corrupted evidence', () async {
      await KingNationalScannerEngine.resetForTesting();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'king_nat_strategy_memory_v1': jsonEncode(<String, Object?>{
          'version': 3,
          'profiles': <String, Object?>{
            'persisted-baseline-profile': <String, Object?>{
              '0': <String, Object?>{'a': 4, 's': 2, 'f': 2, 'l': 95, 't': 1760000000000},
              '1': <String, Object?>{'a': 2, 's': 99, 'f': 99, 'l': 80, 't': 1760000000001},
            },
          },
          'sni': <String, Object?>{},
          'alpn': <String, Object?>{},
          'sniEvidence': 7,
          'alpnEvidence': 9,
        }),
      });
      await KingNationalScannerEngine.load();
      final report = KingNationalScannerEngine.diagnostics();
      expect(report['attempts'], 6);
      expect(report['realTrafficSuccesses'], 4);
      expect(report['realTrafficFailures'], 2);
      expect(report['sniProbeEvidence'], 7);
      expect(report['alpnProbeEvidence'], 9);
    });

    test('records baseline variant zero in real-traffic learning', () {
      final before = KingNationalScannerEngine.diagnostics();
      KingNationalScannerEngine.recordVariantOutcome(
        0,
        true,
        profile: 'unit-test-baseline-profile',
        latencyMs: 120,
      );
      final after = KingNationalScannerEngine.diagnostics();

      expect(after['attempts'], (before['attempts'] as int) + 1);
      expect(after['realTrafficSuccesses'],
          (before['realTrafficSuccesses'] as int) + 1);
    });

    test('rejects invalid variant outcomes without changing learning counters', () {
      final before = KingNationalScannerEngine.diagnostics();
      KingNationalScannerEngine.recordVariantOutcome(
        -1,
        true,
        profile: 'invalid-negative',
      );
      KingNationalScannerEngine.recordVariantOutcome(
        1 << 30,
        false,
        profile: 'invalid-large',
      );
      final after = KingNationalScannerEngine.diagnostics();

      expect(after['attempts'], before['attempts']);
      expect(after['realTrafficSuccesses'], before['realTrafficSuccesses']);
      expect(after['realTrafficFailures'], before['realTrafficFailures']);
    });

    test('diagnostics never expose raw endpoints or credentials', () {
      final report = KingNationalScannerEngine.diagnostics();
      expect(report, contains('variantCatalogSize'));
      expect(report, contains('realTrafficSuccesses'));
      expect(report, isNot(contains('uuid')));
      expect(report, isNot(contains('vless://')));
      expect(report, isNot(contains('password')));
    });
  });
}
