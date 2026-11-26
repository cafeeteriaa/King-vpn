enum KingEngineRole {
  fullDeviceVpn,
  localTransport,
}

enum KingIntegrationState {
  integrated,
  integrationPathVerified,
  backendRequired,
  notAVpnEngine,
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
    this.sourceUrl,
    this.license,
    this.requiresProviderBackend = false,
    this.requiresSeparateVpnOwner = false,
  });

  final String id;
  final String name;
  final KingEngineRole role;
  final KingIntegrationState state;
  final int priority;
  final String summary;
  final String? sourceUrl;
  final String? license;
  final bool requiresProviderBackend;
  final bool requiresSeparateVpnOwner;
}

/// Extensible registry. Descriptors are not proof of a working adapter.
class KingNetworkEngineCatalog {
  KingNetworkEngineCatalog([Iterable<KingEngineDescriptor> initial = defaultEngines])
      : _engines = {for (final engine in initial) engine.id: engine};

  final Map<String, KingEngineDescriptor> _engines;

  Iterable<KingEngineDescriptor> get all =>
      List<KingEngineDescriptor>.unmodifiable(_engines.values);

  KingEngineDescriptor? operator [](String id) => _engines[id];

  void register(KingEngineDescriptor engine) {
    if (_engines.containsKey(engine.id)) {
      throw ArgumentError('Engine already registered: ${engine.id}');
    }
    _engines[engine.id] = engine;
  }

  int priorityOf(String id) => _engines[id]?.priority ?? 1 << 30;

  static const List<KingEngineDescriptor> defaultEngines = [
    KingEngineDescriptor(
      id: 'xray', name: 'Xray', role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.integrated, priority: 0,
      summary: 'موتور اصلی فعلی؛ مسیر اتصال موجود باید بدون regression حفظ شود.',
      sourceUrl: 'https://github.com/XTLS/Xray-core',
      license: 'MPL-2.0', requiresSeparateVpnOwner: true,
    ),
    KingEngineDescriptor(
      id: 'hysteria2', name: 'Hysteria 2', role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.integrationPathVerified, priority: 10,
      summary: 'موتور QUIC مستقل؛ به کانفیگ hysteria2:// یا adapter سازگار و مالکیت انحصاری VPNService نیاز دارد.',
      sourceUrl: 'https://github.com/apernet/hysteria', license: 'MIT',
      requiresSeparateVpnOwner: true,
    ),
    KingEngineDescriptor(
      id: 'sing_box', name: 'sing-box', role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 20,
      summary: 'موتور چندپروتکلی مستقل؛ نیازمند نسخه پین‌شده، بررسی GPL-3.0 و adapter اندروید است.',
      sourceUrl: 'https://github.com/SagerNet/sing-box', license: 'GPL-3.0',
      requiresSeparateVpnOwner: true,
    ),
    KingEngineDescriptor(
      id: 'nthlink', name: 'nthLink / Leaf', role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.backendRequired, priority: 30,
      summary: 'به backend و زیرساخت سازگار خود سرویس نیاز دارد؛ فهرست عمومی سرور مستقل تأیید نشده است.',
      sourceUrl: 'https://github.com/nthlink/nthlink-os-android',
      license: 'BSD-3-Clause (framework)', requiresProviderBackend: true,
      requiresSeparateVpnOwner: true,
    ),
    KingEngineDescriptor(
      id: 'shroudly', name: 'Shroudly', role: KingEngineRole.localTransport,
      state: KingIntegrationState.notAVpnEngine, priority: 40,
      summary: 'ابزار محلی ضد DPI است، نه VPN یا شبکه سرور عمومی؛ می‌تواند از پراکسی شخصی بالادستی پشتیبانی کند. ادغام Android باید جداگانه بررسی شود.',
      sourceUrl: 'https://github.com/umutxyp/Shroudly', license: 'MIT',
    ),
    KingEngineDescriptor(
      id: 'byedpi', name: 'ByeDPI', role: KingEngineRole.localTransport,
      state: KingIntegrationState.notAVpnEngine, priority: 50,
      summary: 'ماژول محلی ضد DPI؛ سرور خروجی اختصاصی ندارد و در صورت نیاز از پراکسی بالادستی استفاده می‌کند.',
      sourceUrl: 'https://github.com/dovecoteescapee/ByeDPIAndroid',
    ),
    KingEngineDescriptor(
      id: 'powertunnel', name: 'PowerTunnel', role: KingEngineRole.localTransport,
      state: KingIntegrationState.notAVpnEngine, priority: 60,
      summary: 'پراکسی محلی/ماژول ضد DPI؛ سرور راه‌دور اختصاصی ندارد و باید در مسیر شبکه موجود ایزوله شود.',
      sourceUrl: 'https://github.com/krlvm/PowerTunnel-Android',
      license: 'GPL-3.0-only',
    ),
    KingEngineDescriptor(
      id: 'amneziawg', name: 'AmneziaWG', role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 70,
      summary: 'پروتکل مستقل مبتنی بر WireGuard با پارامترهای obfuscation؛ نیازمند سرور AWG و فایل .conf معتبر است.',
      sourceUrl: 'https://github.com/amnezia-vpn/amneziawg-android',
      license: 'MIT (core; verify bundled components)', requiresSeparateVpnOwner: true,
    ),
    KingEngineDescriptor(
      id: 'shadowsocks', name: 'Shadowsocks', role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 90,
      summary: 'پروکسی رمزنگاری‌شده؛ برای تونل تمام دستگاه به TUN adapter و کانفیگ ss:// یا JSON نیاز دارد.',
      sourceUrl: 'https://github.com/shadowsocks/shadowsocks-android',
      license: 'GPL-3.0', requiresSeparateVpnOwner: true,
    ),
    KingEngineDescriptor(
      id: 'openconnect', name: 'OpenConnect', role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.sourceAndLicenseReviewRequired, priority: 100,
      summary: 'کلاینت مستقل SSL VPN سازگار با چند خانواده سرور؛ به آدرس و روش احراز هویت سرور نیاز دارد.',
      sourceUrl: 'https://www.infradead.org/openconnect/',
      license: 'LGPL-2.1-or-later', requiresSeparateVpnOwner: true,
    ),
    KingEngineDescriptor(
      id: 'wireguard', name: 'WireGuard', role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.integrationPathVerified, priority: 110,
      summary: 'مسیر رسمی embedding اندروید با com.wireguard.android:tunnel نسخه 1.0.20260102 و GoBackend تأیید شده؛ GoBackend سرویس VpnService مستقل خود را راه‌اندازی می‌کند، بنابراین handoff سریالی و تأیید آزادشدن TUN پیش از اتصال Xray/موتور بعدی الزامی است. هنوز adapter اجرایی KING تکمیل نشده است.',
      sourceUrl: 'https://www.wireguard.com/embedding/',
      license: 'Apache-2.0', requiresSeparateVpnOwner: true,
    ),

  ];
}
