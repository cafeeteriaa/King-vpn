import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/main.dart';

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

    test('diagnostics never expose raw endpoints or credentials', () {
      final report = KingNationalScannerEngine.diagnostics();
      expect(report, contains('variantCatalogSize'));
      expect(report, contains('realTrafficSuccesses'));
      expect(report, isNot(contains('uuid')));
      expect(report, isNot(contains('host')));
    });
  });
}
