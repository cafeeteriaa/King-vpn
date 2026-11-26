/// Shared engine contract for KING VPN.
///
/// This is an integration seam, not an implementation of any third-party VPN.
/// An engine must provide its own reviewed native/core adapter before it can be
/// reported as available or operational. The app must keep exactly one owner of
/// Android's VpnService/TUN at a time.
library king_vpn_engine_contract;

enum KingEngineKind {
  fullDeviceTunnel,
  localProxyTransport,
}

enum KingEngineState {
  idle,
  preparing,
  starting,
  connected,
  degraded,
  stopping,
  stopped,
  failed,
}

enum KingEngineCapability {
  ipv4,
  ipv6,
  udp,
  tcp,
  systemDns,
  perAppRouting,
  customDns,
  bridgeTransport,
  localSocks,
  localHttpProxy,
  trafficStatistics,
  runtimeDiagnostics,
}

class KingVpnEngineDescriptor {
  const KingVpnEngineDescriptor({
    required this.id,
    required this.name,
    required this.kind,
    required this.integrationNote,
    this.upstreamUrl,
    this.capabilities = const <KingEngineCapability>{},
  });

  final String id;
  final String name;
  final KingEngineKind kind;
  final String integrationNote;
  final String? upstreamUrl;
  final Set<KingEngineCapability> capabilities;
}

/// Inventory describes the technology, not whether a native adapter is present.
/// Register additional discovered technologies at runtime; there is no numeric
/// ceiling in this registry.
class KingVpnEngineCatalog {
  KingVpnEngineCatalog() {
    for (final descriptor in knownTechnologies) {
      _descriptors[descriptor.id] = descriptor;
    }
  }

  final Map<String, KingVpnEngineDescriptor> _descriptors = {};

  Iterable<KingVpnEngineDescriptor> get all =>
      List<KingVpnEngineDescriptor>.unmodifiable(_descriptors.values);

  KingVpnEngineDescriptor? operator [](String id) => _descriptors[id];

  void register(KingVpnEngineDescriptor descriptor) {
    final id = descriptor.id.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(descriptor.id, 'id', 'Must not be empty');
    }
    if (_descriptors.containsKey(id)) {
      throw StateError('Engine descriptor already registered: $id');
    }
    _descriptors[id] = descriptor;
  }

  static const List<KingVpnEngineDescriptor> knownTechnologies = [
    KingVpnEngineDescriptor(
      id: 'xray', name: 'Xray', kind: KingEngineKind.fullDeviceTunnel,
      upstreamUrl: 'https://github.com/XTLS/Xray-core',
      integrationNote: 'Existing production path; preserve and regression-test.',
      capabilities: {KingEngineCapability.ipv4, KingEngineCapability.ipv6,
        KingEngineCapability.tcp, KingEngineCapability.udp,
        KingEngineCapability.systemDns, KingEngineCapability.trafficStatistics},
    ),
    KingVpnEngineDescriptor(
      id: 'hysteria2', name: 'Hysteria 2', kind: KingEngineKind.fullDeviceTunnel,
      upstreamUrl: 'https://github.com/apernet/hysteria',
      integrationNote: 'Requires a real Android core adapter and exclusive TUN lifecycle.',
      capabilities: {KingEngineCapability.ipv4, KingEngineCapability.ipv6,
        KingEngineCapability.udp, KingEngineCapability.trafficStatistics},
    ),
    KingVpnEngineDescriptor(
      id: 'sing_box', name: 'sing-box', kind: KingEngineKind.fullDeviceTunnel,
      upstreamUrl: 'https://github.com/SagerNet/sing-box',
      integrationNote: 'Multi-protocol core; pin the version and implement Android lifecycle.',
      capabilities: {KingEngineCapability.ipv4, KingEngineCapability.ipv6,
        KingEngineCapability.tcp, KingEngineCapability.udp,
        KingEngineCapability.customDns, KingEngineCapability.trafficStatistics},
    ),
    KingVpnEngineDescriptor(
      id: 'nthlink', name: 'nthLink / Leaf', kind: KingEngineKind.fullDeviceTunnel,
      upstreamUrl: 'https://github.com/nthlink/nthlink-os-android',
      integrationNote: 'Requires its compatible backend and a real Android adapter.',
      capabilities: {KingEngineCapability.bridgeTransport},
    ),
    KingVpnEngineDescriptor(
      id: 'shroudly', name: 'Shroudly', kind: KingEngineKind.localProxyTransport,
      upstreamUrl: 'https://github.com/umutxyp/Shroudly',
      integrationNote: 'Local transport; do not treat it as an independent VPN server.',
      capabilities: {KingEngineCapability.localSocks, KingEngineCapability.localHttpProxy},
    ),
    KingVpnEngineDescriptor(
      id: 'byedpi', name: 'ByeDPI', kind: KingEngineKind.localProxyTransport,
      upstreamUrl: 'https://github.com/dovecoteescapee/ByeDPIAndroid',
      integrationNote: 'Local DPI transport; integrate behind the shared TUN owner.',
      capabilities: {KingEngineCapability.localSocks, KingEngineCapability.localHttpProxy},
    ),
    KingVpnEngineDescriptor(
      id: 'powertunnel', name: 'PowerTunnel', kind: KingEngineKind.localProxyTransport,
      upstreamUrl: 'https://github.com/krlvm/PowerTunnel-Android',
      integrationNote: 'Local proxy/DPI transport; not a separate full-device VPN engine.',
      capabilities: {KingEngineCapability.localSocks, KingEngineCapability.localHttpProxy},
    ),
    KingVpnEngineDescriptor(
      id: 'amneziawg', name: 'AmneziaWG', kind: KingEngineKind.fullDeviceTunnel,
      upstreamUrl: 'https://github.com/amnezia-vpn/amneziawg-android',
      integrationNote: 'WireGuard-derived tunnel; requires AWG-compatible core and config.',
      capabilities: {KingEngineCapability.ipv4, KingEngineCapability.ipv6,
        KingEngineCapability.udp, KingEngineCapability.trafficStatistics},
    ),
    KingVpnEngineDescriptor(
      id: 'openvpn', name: 'OpenVPN', kind: KingEngineKind.fullDeviceTunnel,
      upstreamUrl: 'https://github.com/OpenVPN/openvpn3',
      integrationNote: 'Requires an actual OpenVPN runtime, credential handling and TUN adapter.',
      capabilities: {KingEngineCapability.ipv4, KingEngineCapability.ipv6,
        KingEngineCapability.tcp, KingEngineCapability.udp,
        KingEngineCapability.trafficStatistics},
    ),
    KingVpnEngineDescriptor(
      id: 'shadowsocks', name: 'Shadowsocks', kind: KingEngineKind.fullDeviceTunnel,
      upstreamUrl: 'https://github.com/shadowsocks/shadowsocks-android',
      integrationNote: 'Encrypted proxy; full-device use requires a compatible TUN adapter.',
      capabilities: {KingEngineCapability.localSocks, KingEngineCapability.udp,
        KingEngineCapability.trafficStatistics},
    ),
    KingVpnEngineDescriptor(
      id: 'openconnect', name: 'OpenConnect', kind: KingEngineKind.fullDeviceTunnel,
      upstreamUrl: 'https://www.infradead.org/openconnect/',
      integrationNote: 'Requires libopenconnect JNI/NDK integration and a compatible gateway.',
      capabilities: {KingEngineCapability.ipv4, KingEngineCapability.ipv6,
        KingEngineCapability.tcp, KingEngineCapability.udp,
        KingEngineCapability.trafficStatistics},
    ),
    KingVpnEngineDescriptor(
      id: 'wireguard', name: 'WireGuard', kind: KingEngineKind.fullDeviceTunnel,
      upstreamUrl: 'https://www.wireguard.com/embedding/',
      integrationNote: 'Official Android tunnel library; coordinate GoBackend TUN handoff.',
      capabilities: {KingEngineCapability.ipv4, KingEngineCapability.ipv6,
        KingEngineCapability.udp, KingEngineCapability.trafficStatistics},
    ),
  ];
}

class KingEngineStartRequest {
  const KingEngineStartRequest({
    required this.configuration,
    this.label = '',
    this.options = const <String, Object?>{},
  });

  /// Opaque engine-specific configuration. The adapter validates its own format.
  final String configuration;
  final String label;
  final Map<String, Object?> options;
}

class KingEngineHealth {
  const KingEngineHealth({
    required this.coreConnected,
    required this.dataPlaneVerified,
    this.detail = '',
    this.bytesIn = 0,
    this.bytesOut = 0,
  });

  final bool coreConnected;

  /// Must represent a real probe/traffic observation through the active path.
  /// A core CONNECTED event alone must never be treated as proof of connectivity.
  final bool dataPlaneVerified;
  final String detail;
  final int bytesIn;
  final int bytesOut;

  bool get operational => coreConnected && dataPlaneVerified;
}

abstract class KingVpnEngineAdapter {
  KingVpnEngineDescriptor get descriptor;

  /// False until the native/core implementation is included and initialized.
  Future<bool> isAvailable();

  Future<void> prepare();

  Future<void> start(KingEngineStartRequest request);

  Future<KingEngineHealth> checkHealth();

  Future<void> stop();

  Future<void> dispose();
}

class KingEngineSession {
  const KingEngineSession({
    required this.engineId,
    required this.state,
    required this.health,
  });

  final String engineId;
  final KingEngineState state;
  final KingEngineHealth? health;

  bool get operational =>
      state == KingEngineState.connected && (health?.operational ?? false);
}

/// Serializes tunnel ownership so two adapters cannot concurrently own TUN.
/// This class does not silently fall back to another engine.
class KingVpnEngineCoordinator {
  KingVpnEngineCoordinator({KingVpnEngineCatalog? catalog})
      : catalog = catalog ?? KingVpnEngineCatalog();

  final KingVpnEngineCatalog catalog;
  final Map<String, KingVpnEngineAdapter> _adapters = {};
  String? _activeEngineId;
  bool _transitioning = false;

  String? get activeEngineId => _activeEngineId;
  bool get transitioning => _transitioning;

  void registerAdapter(KingVpnEngineAdapter adapter) {
    final id = adapter.descriptor.id;
    if (catalog[id] == null) catalog.register(adapter.descriptor);
    if (_adapters.containsKey(id)) {
      throw StateError('Engine adapter already registered: $id');
    }
    _adapters[id] = adapter;
  }

  Iterable<String> get registeredAdapterIds =>
      List<String>.unmodifiable(_adapters.keys);

  Future<KingEngineSession> start(
    String engineId,
    KingEngineStartRequest request,
  ) async {
    if (_transitioning) {
      throw StateError('An engine transition is already in progress');
    }
    final adapter = _adapters[engineId];
    if (adapter == null) {
      throw StateError('No executable adapter registered for $engineId');
    }

    _transitioning = true;
    try {
      final available = await adapter.isAvailable();
      if (!available) {
        throw StateError('Engine $engineId is not installed or initialized');
      }

      var startAttempted = false;
      try {
        final previousId = _activeEngineId;
        if (previousId != null) {
          final previous = _adapters[previousId];
          if (previous != null) await previous.stop();
          _activeEngineId = null;
        }

        await adapter.prepare();
        startAttempted = true;
        await adapter.start(request);
        _activeEngineId = engineId;

        final health = await adapter.checkHealth();
        if (!health.operational) {
          await adapter.stop();
          _activeEngineId = null;
          return KingEngineSession(
            engineId: engineId,
            state: KingEngineState.degraded,
            health: health,
          );
        }

        return KingEngineSession(
          engineId: engineId,
          state: KingEngineState.connected,
          health: health,
        );
      } catch (_) {
        if (startAttempted) {
          try {
            await adapter.stop();
            _activeEngineId = null;
          } catch (_) {
            // Keep ownership marked active when teardown cannot be confirmed.
            // A later engine must not start while this TUN may still be held.
            _activeEngineId = engineId;
          }
        }
        rethrow;
      }
    } finally {
      _transitioning = false;
    }
  }

  Future<void> stopActive() async {
    if (_transitioning) {
      throw StateError('An engine transition is already in progress');
    }
    final id = _activeEngineId;
    if (id == null) return;
    _transitioning = true;
    try {
      await _adapters[id]?.stop();
      _activeEngineId = null;
    } finally {
      _transitioning = false;
    }
  }

  Future<void> dispose() async {
    await stopActive();
    for (final adapter in _adapters.values) {
      await adapter.dispose();
    }
    _adapters.clear();
  }
}
