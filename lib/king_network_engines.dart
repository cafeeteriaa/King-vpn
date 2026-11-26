enum KingEngineRole {
  fullDeviceVpn,
  overlayNetwork,
  localTransport,
  browserNetwork,
  externalService,
}

enum KingIntegrationState {
  integrated,
  integrationPathVerified,
  backendRequired,
  externalClientRequired,
  noPublicEmbeddingApiVerified,
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

/// Open, extensible registry. It has no fixed engine-count ceiling.
/// Entries describe integration evidence; they do not claim an engine is
/// connected until a real adapter is installed and data-plane tested.
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
      id: 'xray',
      name: 'Xray',
      role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.integrated,
      priority: 0,
      summary: 'موتور اصلی فعلی KING VPN؛ مسیر اتصال موجود باید حفظ شود.',
      requiresSeparateVpnOwner: true,
    ),
    KingEngineDescriptor(
      id: 'vpn_gate',
      name: 'VPN Gate',
      role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.integrationPathVerified,
      priority: 10,
      summary: 'قابل استفاده از طریق پروفایل‌های OpenVPN و یک موتور OpenVPN مستقل؛ نیازمند چرخه VPN انحصاری.',
      sourceUrl: 'https://www.vpngate.net/',
      license: 'OpenVPN engine licensing must be reviewed before redistribution',
      requiresSeparateVpnOwner: true,
    ),
    KingEngineDescriptor(
      id: 'calyx_vpn',
      name: 'CalyxVPN',
      role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.backendRequired,
      priority: 20,
      summary: 'کلاینت Bitmask/LEAP؛ برای اتصال واقعی به سرویس، پیکربندی و backend ارائه‌دهنده لازم است.',
      sourceUrl: 'https://gitlab.com/CalyxOS/bitmask_android',
      license: 'GPL-3.0-only',
      requiresProviderBackend: true,
      requiresSeparateVpnOwner: true,
    ),
    KingEngineDescriptor(
      id: 'nthlink',
      name: 'nthLink / Leaf',
      role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.backendRequired,
      priority: 30,
      summary: 'چارچوب Android مبتنی بر Leaf و Outline؛ خود چارچوب جایگزین backend و اطلاعات سرویس نیست.',
      sourceUrl: 'https://github.com/nthlink/nthlink-os-android',
      license: 'BSD-3-Clause (framework)',
      requiresProviderBackend: true,
      requiresSeparateVpnOwner: true,
    ),
    KingEngineDescriptor(
      id: 'tor',
      name: 'Tor / Orbot',
      role: KingEngineRole.overlayNetwork,
      state: KingIntegrationState.integrationPathVerified,
      priority: 40,
      summary: 'شبکه پوششی و پراکسی؛ با Orbot می‌تواند ترافیک برنامه‌ها را از مسیر VPN اندروید عبور دهد، اما VPN تجاری مستقل نیست.',
      sourceUrl: 'https://github.com/guardianproject/orbot',
      license: 'Orbot: BSD-3-Clause; bundled components require separate review',
      requiresSeparateVpnOwner: true,
    ),
    KingEngineDescriptor(
      id: 'i2p',
      name: 'I2P',
      role: KingEngineRole.overlayNetwork,
      state: KingIntegrationState.sourceAndLicenseReviewRequired,
      priority: 50,
      summary: 'شبکه پوششی با پراکسی‌های محلی؛ برای تونل‌کردن کل دستگاه به پل TUN جداگانه نیاز دارد.',
      sourceUrl: 'https://github.com/i2p/i2p.android.base',
      requiresSeparateVpnOwner: true,
    ),
    KingEngineDescriptor(
      id: 'lantern',
      name: 'Lantern',
      role: KingEngineRole.fullDeviceVpn,
      state: KingIntegrationState.sourceAndLicenseReviewRequired,
      priority: 60,
      summary: 'کلاینت Android متن‌باز و مبتنی بر VpnService دارد؛ ادغام سورس به بررسی GPL و مالکیت VPNService نیاز دارد.',
      sourceUrl: 'https://github.com/getlantern/lantern-client',
      license: 'GPL; Android source is distributed as source-dump tarballs',
      requiresSeparateVpnOwner: true,
    ),
    KingEngineDescriptor(
      id: 'cloudflare_warp',
      name: 'Cloudflare WARP',
      role: KingEngineRole.externalService,
      state: KingIntegrationState.externalClientRequired,
      priority: 70,
      summary: 'کلاینت رسمی Android وجود دارد، اما API عمومی برای جاسازی WARP در کلاینت ثالث تأیید نشده است.',
      sourceUrl: 'https://developers.cloudflare.com/warp-client/',
      requiresSeparateVpnOwner: true,
    ),
    KingEngineDescriptor(
      id: 'avira_phantom',
      name: 'Avira Phantom VPN',
      role: KingEngineRole.externalService,
      state: KingIntegrationState.externalClientRequired,
      priority: 80,
      summary: 'سرویس تجاری با کلاینت اختصاصی؛ SDK عمومی قابل‌ادغام در این بررسی تأیید نشد.',
      sourceUrl: 'https://www.avira.com/',
      requiresSeparateVpnOwner: true,
    ),
    KingEngineDescriptor(
      id: 'shroudly',
      name: 'Shroudly',
      role: KingEngineRole.externalService,
      state: KingIntegrationState.sourceAndLicenseReviewRequired,
      priority: 90,
      summary: 'پروژه اشتراک‌گذاری اتصال/سرور شخصی؛ نباید بدون تأیید، VPN عمومی مستقل فرض شود.',
      sourceUrl: 'https://github.com/umutxyp/shroudly',
    ),
    KingEngineDescriptor(
      id: 'ceno',
      name: 'Ceno / Ouinet',
      role: KingEngineRole.browserNetwork,
      state: KingIntegrationState.notAVpnEngine,
      priority: 100,
      summary: 'شبکه P2P برای دسترسی محتوای وب و SDK اپلیکیشنی Ouinet؛ مرورگر یا VPN تمام‌دستگاه نیست.',
      sourceUrl: 'https://github.com/equalitie/ouinet',
      license: 'Ouinet: MIT; Ceno Android app: MPL-2.0',
    ),
    KingEngineDescriptor(
      id: 'byedpi',
      name: 'ByeDPI',
      role: KingEngineRole.localTransport,
      state: KingIntegrationState.notAVpnEngine,
      priority: 110,
      summary: 'لایه محلی دورزدن DPI؛ خود برنامه تصریح می‌کند VPN واقعی نیست، سرور راه‌دور ندارد و IP را پنهان نمی‌کند.',
      sourceUrl: 'https://github.com/romanvht/byebyedpi',
    ),
    KingEngineDescriptor(
      id: 'powertunnel',
      name: 'PowerTunnel',
      role: KingEngineRole.localTransport,
      state: KingIntegrationState.notAVpnEngine,
      priority: 120,
      summary: 'پراکسی ضد DPI محلی که Android VPN API را برای هدایت ترافیک به پراکسی خودش به‌کار می‌گیرد؛ سرویس VPN راه‌دور نیست.',
      sourceUrl: 'https://github.com/krlvm/PowerTunnel-Android',
      license: 'GPL-3.0-only; upstream repository states Google Play redistribution requires permission',
    ),
  ];
}
