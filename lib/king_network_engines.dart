/// Registry of VPN engines and local transport helpers.
class KingEngineId {
  static const xray = 'xray';
  static const hysteria2 = 'hysteria2';
  static const singBox = 'singbox';
  static const nthLink = 'nthlink';
  static const shroudly = 'shroudly';
  static const byeDpi = 'byedpi';
  static const powerTunnel = 'powertunnel';
  static const amneziaWg = 'amneziawg';
  static const openVpn = 'openvpn';
  static const shadowsocks = 'shadowsocks';
  static const openConnect = 'openconnect';
  static const wireGuard = 'wireguard';

  static const localTransportIds = <String>{shroudly, byeDpi, powerTunnel};
}

enum KingEngineRole { fullDeviceVpn, localTransport }
enum KingIntegrationState {
  integrated,
  integrationPathVerified,
  sourceAndLicenseReviewRequired,
}

class KingEngineDescriptor {
  const KingEngineDescriptor({
    required this.id,
    required this.name,
    required this.role,
    required this.state,
    required this.priority,
    required this.summary,
  });

  final String id;
  final String name;
  final KingEngineRole role;
  final KingIntegrationState state;
  final int priority;
  final String summary;

  bool get requiresSeparateVpnOwner =>
      role == KingEngineRole.fullDeviceVpn && id != KingEngineId.xray;
}

class KingNetworkEngineCatalog {
  final Map<String, KingEngineDescriptor> _entries = <String, KingEngineDescriptor>{};

  KingNetworkEngineCatalog() {
    const descriptors = <KingEngineDescriptor>[
      KingEngineDescriptor(id: KingEngineId.xray, name: 'Xray', role: KingEngineRole.fullDeviceVpn, state: KingIntegrationState.integrated, priority: 0, summary: 'Current primary Android VPN core.'),
      KingEngineDescriptor(id: KingEngineId.amneziaWg, name: 'AmneziaWG', role: KingEngineRole.fullDeviceVpn, state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 10, summary: 'Requires a native compatible tunnel adapter.'),
      KingEngineDescriptor(id: KingEngineId.wireGuard, name: 'WireGuard', role: KingEngineRole.fullDeviceVpn, state: KingIntegrationState.integrationPathVerified, priority: 20, summary: 'Android integration path identified; runtime adapter not yet wired.'),
      KingEngineDescriptor(id: KingEngineId.singBox, name: 'sing-box', role: KingEngineRole.fullDeviceVpn, state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 30, summary: 'Protocol engine adapter under integration review.'),
      KingEngineDescriptor(id: KingEngineId.hysteria2, name: 'Hysteria 2', role: KingEngineRole.fullDeviceVpn, state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 40, summary: 'Requires a compatible native core adapter.'),
      KingEngineDescriptor(id: KingEngineId.shadowsocks, name: 'Shadowsocks', role: KingEngineRole.fullDeviceVpn, state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 50, summary: 'Protocol adapter under integration review.'),
      KingEngineDescriptor(id: KingEngineId.openConnect, name: 'OpenConnect', role: KingEngineRole.fullDeviceVpn, state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 60, summary: 'Requires a maintained Android VPN adapter.'),
      KingEngineDescriptor(id: KingEngineId.openVpn, name: 'OpenVPN', role: KingEngineRole.fullDeviceVpn, state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 70, summary: 'Retained for compatibility review; not a current active core.'),
      KingEngineDescriptor(id: KingEngineId.nthLink, name: 'nthLink', role: KingEngineRole.fullDeviceVpn, state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 80, summary: 'Provider-managed service; requires its own service infrastructure.'),
      KingEngineDescriptor(id: KingEngineId.shroudly, name: 'Shroudly', role: KingEngineRole.localTransport, state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 90, summary: 'Local transport helper, not a full-device VPN owner.'),
      KingEngineDescriptor(id: KingEngineId.byeDpi, name: 'ByeDPI', role: KingEngineRole.localTransport, state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 91, summary: 'Local DPI transport helper.'),
      KingEngineDescriptor(id: KingEngineId.powerTunnel, name: 'PowerTunnel', role: KingEngineRole.localTransport, state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 92, summary: 'Local proxy/transport helper.'),
    ];
    for (final descriptor in descriptors) {
      register(descriptor);
    }
  }

  Iterable<KingEngineDescriptor> get all => List<KingEngineDescriptor>.unmodifiable(
    _entries.values.toList()..sort((a, b) => a.priority.compareTo(b.priority)),
  );

  KingEngineDescriptor? operator [](String id) => _entries[id];

  void register(KingEngineDescriptor descriptor) {
    if (descriptor.id.trim().isEmpty || descriptor.name.trim().isEmpty) {
      throw ArgumentError('Engine id and name must not be empty.');
    }
    if (_entries.containsKey(descriptor.id)) {
      throw ArgumentError.value(descriptor.id, 'id', 'Duplicate engine identifier.');
    }
    _entries[descriptor.id] = descriptor;
  }
}
