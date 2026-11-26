/// Shared engine contract for KING VPN.
///
/// This is an integration seam, not an implementation of any third-party VPN.
/// An engine must provide its own reviewed native/core adapter before it can be
/// reported as available or operational. The app must keep exactly one owner of
/// Android's VpnService/TUN at a time.
library king_vpn_engine_contract;

enum KingEngineKind {
  fullDeviceTunnel,
  relayDirectory,
  browserNetwork,
  overlayNetwork,
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
  browserScoped,
  relayDiscovery,
  trafficStatistics,
  runtimeDiagnostics,
}

class KingEngineDescriptor {
  const KingEngineDescriptor({
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
  final Uri? upstreamUrl;
  final Set<KingEngineCapability> capabilities;
}

/// Inventory describes the technology, not whether a native adapter is present.
/// Register additional discovered technologies at runtime; there is no numeric
/// ceiling in this registry.
class KingEngineCatalog {
  KingEngineCatalog() {
    for (final descriptor in knownTechnologies) {
      _descriptors[descriptor.id] = descriptor;
    }
  }

  final Map<String, KingEngineDescriptor> _descriptors = {};

  Iterable<KingEngineDescriptor> get all =>
      List<KingEngineDescriptor>.unmodifiable(_descriptors.values);

  KingEngineDescriptor? operator [](String id) => _descriptors[id];

  void register(KingEngineDescriptor descriptor) {
    final id = descriptor.id.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(descriptor.id, 'id', 'Must not be empty');
    }
    if (_descriptors.containsKey(id)) {
      throw StateError('Engine descriptor already registered: $id');
    }
    _descriptors[id] = descriptor;
  }

  static const List<KingEngineDescriptor> knownTechnologies = [
    KingEngineDescriptor(
      id: 'psiphon',
      name: 'Psiphon',
      kind: KingEngineKind.fullDeviceTunnel,
      upstreamUrl: Uri.parse('https://github.com/Psiphon-Inc/psiphon-tunnel-core'),
      integrationNote: 'Requires the official Android library and service adapter.',
      capabilities: {KingEngineCapability.bridgeTransport, KingEngineCapability.trafficStatistics},
    ),
    KingEngineDescriptor(
      id: 'tor',
      name: 'Tor',
      kind: KingEngineKind.overlayNetwork,
      upstreamUrl: Uri.parse('https://gitlab.torproject.org/tpo/core/tor'),
      integrationNote: 'Router/bootstrap integration; SOCKS alone is not a device VPN.',
      capabilities: {KingEngineCapability.localSocks, KingEngineCapability.bridgeTransport},
    ),
    KingEngineDescriptor(
      id: 'vpn_gate',
      name: 'VPN Gate',
      kind: KingEngineKind.relayDirectory,
      upstreamUrl: Uri.parse('https://www.vpngate.net/'),
      integrationNote: 'Directory plus separately implemented protocol clients.',
      capabilities: {KingEngineCapability.relayDiscovery},
    ),
    KingEngineDescriptor(
      id: 'nthlink',
      name: 'nthLink',
      kind: KingEngineKind.fullDeviceTunnel,
      upstreamUrl: Uri.parse('https://github.com/nthlink'),
      integrationNote: 'Audit Leaf/Outline Android components and backend dependencies.',
      capabilities: {KingEngineCapability.bridgeTransport},
    ),
    KingEngineDescriptor(
      id: 'calyx_vpn',
      name: 'CalyxVPN',
      kind: KingEngineKind.fullDeviceTunnel,
      upstreamUrl: Uri.parse('https://github.com/CalyxOS'),
      integrationNote: 'Reuse a protocol core only after source and license review.',
    ),
    KingEngineDescriptor(
      id: 'cloudflare_warp',
      name: 'Cloudflare WARP',
      kind: KingEngineKind.fullDeviceTunnel,
      upstreamUrl: Uri.parse('https://1.1.1.1/'),
      integrationNote: 'Requires a supported partner integration; no private API emulation.',
    ),
    KingEngineDescriptor(
      id: 'lantern',
      name: 'Lantern',
      kind: KingEngineKind.fullDeviceTunnel,
      upstreamUrl: Uri.parse('https://github.com/getlantern'),
      integrationNote: 'Verify a maintained embeddable Android core and redistribution rights.',
    ),
    KingEngineDescriptor(
      id: 'avira_phantom',
      name: 'Avira Phantom VPN',
      kind: KingEngineKind.fullDeviceTunnel,
      upstreamUrl: Uri.parse('https://www.avira.com/'),
      integrationNote: 'Requires an authorized SDK or partner API.',
    ),
    KingEngineDescriptor(
      id: 'shroudly',
      name: 'Shroudly',
      kind: KingEngineKind.localProxyTransport,
      upstreamUrl: Uri.parse('https://github.com/Shroudly'),
      integrationNote: 'Audit native core, proxy/TUN bridge, and redistribution license.',
      capabilities: {KingEngineCapability.localSocks, KingEngineCapability.localHttpProxy},
    ),
    KingEngineDescriptor(
      id: 'ceno',
      name: 'Ceno Browser',
      kind: KingEngineKind.browserNetwork,
      upstreamUrl: Uri.parse('https://censorship.no/'),
      integrationNote: 'Browser-scoped Ouinet capability; not a full-device VPN.',
      capabilities: {KingEngineCapability.browserScoped},
    ),
    KingEngineDescriptor(
      id: 'byedpi',
      name: 'ByeDPI',
      kind: KingEngineKind.localProxyTransport,
      upstreamUrl: Uri.parse('https://github.com/hufrea/byedpi'),
      integrationNote: 'Integrate behind the shared TUN; never start a second VpnService.',
      capabilities: {KingEngineCapability.localSocks, KingEngineCapability.localHttpProxy},
    ),
    KingEngineDescriptor(
      id: 'powertunnel',
      name: 'PowerTunnel',
      kind: KingEngineKind.localProxyTransport,
      upstreamUrl: Uri.parse('https://github.com/krlvm/PowerTunnel'),
      integrationNote: 'Review GPL-3.0 obligations and upstream Android distribution permissions.',
      capabilities: {KingEngineCapability.localSocks, KingEngineCapability.localHttpProxy},
    ),
    KingEngineDescriptor(
      id: 'i2p',
      name: 'I2P',
      kind: KingEngineKind.overlayNetwork,
      upstreamUrl: Uri.parse('https://geti2p.net/'),
      integrationNote: 'Router lifecycle and SAM/I2CP/SOCKS integration; not a VPN by itself.',
      capabilities: {KingEngineCapability.localSocks, KingEngineCapability.bridgeTransport},
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
  KingEngineDescriptor get descriptor;

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
  KingVpnEngineCoordinator({KingEngineCatalog? catalog})
      : catalog = catalog ?? KingEngineCatalog();

  final KingEngineCatalog catalog;
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
          } catch (_) {
            // Preserve the original startup/health error; adapter logs stop failure.
          }
        }
        _activeEngineId = null;
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
