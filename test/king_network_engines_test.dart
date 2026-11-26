import 'package:flutter_test/flutter_test.dart';
import '../lib/king_network_engines.dart';

void main() {
  test('catalog includes every requested technology without misclassifying its role', () {
    final catalog = KingNetworkEngineCatalog();
    const requested = <String>[
      'psiphon',
      'tor',
      'vpn_gate',
      'nthlink',
      'calyx_vpn',
      'cloudflare_warp',
      'lantern',
      'avira_phantom',
      'shroudly',
      'ceno',
      'byedpi',
      'powertunnel',
      'i2p',
    ];

    for (final id in requested) {
      expect(catalog[id], isNotNull, reason: 'Missing requested technology: $id');
    }

    expect(catalog['vpn_gate']!.role, KingEngineRole.relayDirectory);
    expect(catalog['tor']!.role, KingEngineRole.overlayNetwork);
    expect(catalog['i2p']!.role, KingEngineRole.overlayNetwork);
    expect(catalog['ceno']!.role, KingEngineRole.browserNetwork);
    expect(catalog['shroudly']!.role, KingEngineRole.localTransport);
    expect(catalog['byedpi']!.role, KingEngineRole.localTransport);
    expect(catalog['powertunnel']!.role, KingEngineRole.localTransport);
    expect(catalog['cloudflare_warp']!.role, KingEngineRole.externalService);
    expect(catalog['avira_phantom']!.role, KingEngineRole.externalService);
  });

  test('catalog remains extensible and rejects duplicate IDs', () {
    final catalog = KingNetworkEngineCatalog();
    catalog.register(const KingEngineDescriptor(
      id: 'new_protocol',
      name: 'New protocol',
      role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.sourceAndLicenseReviewRequired,
      priority: 500,
      summary: 'Discovered extension',
    ));
    expect(catalog['new_protocol'], isNotNull);
    expect(
      () => catalog.register(const KingEngineDescriptor(
        id: 'new_protocol',
        name: 'Duplicate',
        role: KingEngineRole.fullDeviceVpn,
        state: KingIntegrationState.sourceAndLicenseReviewRequired,
        priority: 501,
        summary: 'Duplicate ID',
      )),
      throwsArgumentError,
    );
  });

  test('only verified existing Xray is labeled integrated', () {
    final catalog = KingNetworkEngineCatalog();
    expect(catalog['xray']!.state, KingIntegrationState.integrated);
    for (final descriptor in catalog.all.where((item) => item.id != 'xray')) {
      expect(
        descriptor.state,
        isNot(KingIntegrationState.integrated),
        reason: '${descriptor.id} has no completed native adapter yet',
      );
    }
  });
}
