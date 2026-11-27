/// Canonical engine identifiers and truthful integration inventory.
class KingEngineId {
  KingEngineId._();

  static const String xray = 'xray';
  static const String hysteria2 = 'hysteria2';
  static const String singBox = 'sing-box';
  static const String nthLink = 'nthlink';
  static const String shroudly = 'shroudly';
  static const String byeDpi = 'byedpi';
  static const String powerTunnel = 'powertunnel';
  static const String amneziaWg = 'amneziawg';
  static const String openVpn = 'openvpn';
  static const String shadowsocks = 'shadowsocks';
  static const String openConnect = 'openconnect';
  static const String wireGuard = 'wireguard';
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
    this.requiresSeparateVpnOwner = false,
  });

  final String id;
  final String name;
  final KingEngineRole role;
  final KingIntegrationState state;
  final int priority;
  final String summary;
  final bool requiresSeparateVpnOwner;
}

class KingNetworkEngineCatalog {
  KingNetworkEngineCatalog() {
    for (final item in _baseline) {
      _items[item.id] = item;
    }
  }

  final Map<String, KingEngineDescriptor> _items = <String, KingEngineDescriptor>{};

  static const List<KingEngineDescriptor> _baseline = <KingEngineDescriptor>[
    KingEngineDescriptor(
      id: KingEngineId.xray, name: 'Xray', role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.integrated, priority: 1000,
      requiresSeparateVpnOwner: true,
      summary: 'موتور اصلی فعلی؛ مسیر اجرایی در برنامه موجود است.',
    ),
    KingEngineDescriptor(
      id: KingEngineId.hysteria2, name: 'Hysteria 2', role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 900,
      requiresSeparateVpnOwner: true, summary: 'نیازمند اتصال هسته و آزمون ترافیک واقعی.',
    ),
    KingEngineDescriptor(
      id: KingEngineId.singBox, name: 'sing-box', role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 890,
      requiresSeparateVpnOwner: true, summary: 'مسیر ادغام و مجوز باید پیش از فعال‌سازی بررسی شود.',
    ),
    KingEngineDescriptor(
      id: KingEngineId.nthLink, name: 'nthLink / Leaf', role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 800,
      requiresSeparateVpnOwner: true, summary: 'نیازمند منبع سرور یا ارائه‌دهنده معتبر.',
    ),
    KingEngineDescriptor(
      id: KingEngineId.shroudly, name: 'Shroudly', role: KingEngineRole.localTransport,
      state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 300,
      summary: 'لایه محلی انتقال؛ مالک مستقل VPN دستگاه نیست.',
    ),
    KingEngineDescriptor(
      id: KingEngineId.byeDpi, name: 'ByeDPI', role: KingEngineRole.localTransport,
      state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 290,
      summary: 'ابزار محلی DPI؛ به‌تنهایی موتور VPN کامل نیست.',
    ),
    KingEngineDescriptor(
      id: KingEngineId.powerTunnel, name: 'PowerTunnel', role: KingEngineRole.localTransport,
      state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 280,
      summary: 'ابزار محلی انتقال؛ مالک مستقل TUN نیست.',
    ),
    KingEngineDescriptor(
      id: KingEngineId.amneziaWg, name: 'AmneziaWG', role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 880,
      requiresSeparateVpnOwner: true, summary: 'نیازمند هسته بومی و تأیید مالکیت TUN.',
    ),
    KingEngineDescriptor(
      id: KingEngineId.openVpn, name: 'OpenVPN', role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 700,
      requiresSeparateVpnOwner: true, summary: 'در فهرست ارزیابی؛ فعال‌سازی هنوز تأیید نشده است.',
    ),
    KingEngineDescriptor(
      id: KingEngineId.shadowsocks, name: 'Shadowsocks', role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 760,
      requiresSeparateVpnOwner: true, summary: 'نیازمند adapter واقعی و آزمون عبور ترافیک.',
    ),
    KingEngineDescriptor(
      id: KingEngineId.openConnect, name: 'OpenConnect', role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 690,
      requiresSeparateVpnOwner: true, summary: 'نیازمند adapter و بررسی مجوز/هسته.',
    ),
    KingEngineDescriptor(
      id: KingEngineId.wireGuard, name: 'WireGuard', role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.integrationPathVerified, priority: 870,
      requiresSeparateVpnOwner: true, summary: 'مسیر ادغام شناسایی شده؛ هنوز موتور فعال تولیدی محسوب نمی‌شود.',
    ),
  ];

  List<KingEngineDescriptor> get all =>
      List<KingEngineDescriptor>.unmodifiable(_items.values);

  KingEngineDescriptor? operator [](String id) => _items[id];

  void register(KingEngineDescriptor descriptor) {
    final id = descriptor.id.trim();
    if (id.isEmpty) throw ArgumentError.value(descriptor.id, 'id');
    if (_items.containsKey(id)) {
      throw ArgumentError.value(id, 'descriptor.id', 'Engine already registered');
    }
    _items[id] = descriptor;
  }
}
