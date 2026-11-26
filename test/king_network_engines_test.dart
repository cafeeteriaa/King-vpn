import 'package:flutter_test/flutter_test.dart';
import '../lib/king_network_engines.dart';

void main() {
  test('catalog contains twelve approved technologies plus conditional Psiphon', () {
    final catalog = KingNetworkEngineCatalog();
    const approved = <String>{
      'xray', 'hysteria2', 'sing_box', 'nthlink', 'shroudly', 'byedpi',
      'powertunnel', 'amneziawg', 'openvpn', 'shadowsocks', 'openconnect',
      'wireguard', 'psiphon',
    };
    expect(catalog.all.map((engine) => engine.id).toSet(), approved);
    expect(catalog.all, hasLength(13));
    expect(catalog['psiphon']!.state, KingIntegrationState.sourceAndLicenseReviewRequired);
    expect(catalog['psiphon']!.requiresProviderBackend, isTrue);
    expect(catalog['xray']!.state, KingIntegrationState.integrated);
    for (final id in ['shroudly', 'byedpi', 'powertunnel']) {
      expect(catalog[id]!.role, KingEngineRole.localTransport);
    }
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
