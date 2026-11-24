/// Capability inventory for transport, DPI-adaptation and pluggable transports.
///
/// This registry is deliberately honest: listing a technique does not mean the
/// corresponding native packet engine is bundled or active. Only capabilities
/// backed by the current Xray/V2Ray configuration path are marked as such.
/// IPv4/IPv6 are both address-family targets; packet-level implementations
/// must still pass their native-family integration tests before activation.
enum KingCapabilityState {
  existingCoreConfig,
  requiresNativeEngine,
  researchOnly,
}

enum KingAddressFamily { ipv4, ipv6 }

class KingTransportCapability {
  final String id;
  final String category;
  final String title;
  final KingCapabilityState state;
  /// Intended address families; this is not evidence of runtime support.
  final Set<KingAddressFamily> families;
  /// Families that passed real engine/device integration tests. Empty until proven.
  final Set<KingAddressFamily> verifiedFamilies;
  final String integration;
  const KingTransportCapability({
    required this.id,
    required this.category,
    required this.title,
    required this.state,
    this.families = const {KingAddressFamily.ipv4, KingAddressFamily.ipv6},
    this.verifiedFamilies = const <KingAddressFamily>{},
    required this.integration,
  });
  /// Whether the inventory declares this family as an intended target.
  bool supports(KingAddressFamily family) => families.contains(family);
  /// Whether this exact engine/family pair passed a real integration test.
  bool isVerifiedFor(KingAddressFamily family) => verifiedFamilies.contains(family);
  bool get executableWithCurrentCore =>
      state == KingCapabilityState.existingCoreConfig;
}

const _both = {KingAddressFamily.ipv4, KingAddressFamily.ipv6};

final List<KingTransportCapability> kingTransportCapabilities = [
  // Current Xray/V2Ray configuration family.
  KingTransportCapability(id:'vless',category:'vpn',title:'VLESS',state:KingCapabilityState.existingCoreConfig,families:_both,integration:'Xray/V2Ray core config'),
  KingTransportCapability(id:'vmess',category:'vpn',title:'VMess / V2Ray',state:KingCapabilityState.existingCoreConfig,families:_both,integration:'Xray/V2Ray core config'),
  KingTransportCapability(id:'trojan',category:'vpn',title:'Trojan',state:KingCapabilityState.existingCoreConfig,families:_both,integration:'Xray/V2Ray core config'),
  KingTransportCapability(id:'shadowsocks',category:'vpn',title:'Shadowsocks',state:KingCapabilityState.existingCoreConfig,families:_both,integration:'Xray/V2Ray core config'),
  KingTransportCapability(id:'vless-vision',category:'vpn',title:'VLESS + XTLS Vision',state:KingCapabilityState.existingCoreConfig,families:_both,integration:'Xray/V2Ray flow configuration'),
  KingTransportCapability(id:'reality',category:'vpn',title:'REALITY',state:KingCapabilityState.existingCoreConfig,families:_both,integration:'Xray/V2Ray TLS security configuration'),
  ...[
    'tcp','ws','grpc','http-h2','httpupgrade','quic','xhttp','mkcp'
  ].map((name)=>KingTransportCapability(id:'transport-$name',category:'transport',title:name,state:KingCapabilityState.existingCoreConfig,families:_both,integration:'Xray/V2Ray streamSettings; validate core version')),
  // Additional protocol engines: require a separately packaged, audited adapter.
  ...[
    'hysteria2','hysteria2-udp-acceleration','hysteria2-port-hopping',
    'tuic-v5','tuic-v4','shadow-tls','naiveproxy','anytls','juicity',
    'cloak','brook','mieru','trusttunnel','sudoku','masque-noize',
    'atomicnoize','proteus','upgen','shadowsocks-2022','amneziawg',
    'psiphon','tor'
  ].map((name)=>KingTransportCapability(id:name,category:'vpn',title:name,state:KingCapabilityState.requiresNativeEngine,families:_both,integration:'Add audited native engine, config adapter, lifecycle and IPv4/IPv6 tests')),
  // DPI adaptation strategies. No raw packet manipulation is activated by this registry.
  ...[
    'zapret-fake','zapret-fake-md5sig','zapret-fake-badseq','zapret-fake-badsum',
    'zapret-fake-ts','zapret-fake-autottl','zapret-multisplit','zapret-split-seqovl',
    'zapret-fake-multidisorder','zapret-fakedsplit','zapret-fakeddisorder',
    'zapret-hostfakesplit','zapret-oob','zapret-disoob','zapret-tlsrec',
    'zapret-mod-http','zapret-ipfrag2','zapret-udplen','zapret-syndata',
    'zapret-synack','zapret-fake-quic','zapret-fake-discord','zapret-fake-stun',
    // Additional nfqws/zapret strategy families (catalogued, not auto-enabled).
    'zapret-fakeknown','zapret-fake-tls','zapret-fake-http','zapret-fake-udp',
    'zapret-fake-tcp','zapret-fake-quic-inject','zapret-split','zapret-disorder',
    'zapret-multisplit-seqovl','zapret-multidisorder-seqovl',
    'zapret-hostfakeddisorder','zapret-hostfakesplit-seqovl',
    'zapret-oob-data','zapret-disoob-data','zapret-tlsrec-pos','zapret-tlsrec-random',
    'zapret-tlsrec-split','zapret-ipfrag1','zapret-udp-fake','zapret-udp-split',
    'zapret-udp-disorder','zapret-syndata-seq','zapret-synack-seq',
    'byedpi-split-tunneling','byedpi-dll-injection','byedpi-system-wide','byedpi-domain-rules',
    'byedpi-fake','byedpi-fakeknown','byedpi-disorder','byedpi-multisplit',
    'byedpi-hostfakesplit','byedpi-tlsrec-fragment','byedpi-sni-mutation',
    'byedpi-wrong-sequence','byedpi-wrong-checksum','byedpi-autottl',
    'goodbyedpi-simple','goodbyedpi-advanced','goodbyedpi-fake','goodbyedpi-fakeknown',
    'goodbyedpi-multisplit','goodbyedpi-multidisorder','goodbyedpi-tlsrec',
    'goodbyedpi-https-fragment','goodbyedpi-ttl-adjustment',
    'slipnet-micro','slipnet-multi','slipnet-disorder','slipnet-fake',
    'slipnet-sni-split','slipnet-half',
    'zerodpi-sni-spoof','zerodpi-ip-bypass','zerodpi-ip-bypass-plus',
    'zerodpi-sni-scan','zerodpi-ip-scan','zerodpi-proxy-scan',
    'b4-fakesni','b4-fakesni-1','b4-fakesni-2','sniproxy-tcp-segmentation','sniproxy-fake-rst',
    'sniproxy-wrong-seq','sniproxy-wrong-checksum',
    'ciadpi-byedpi','ciadpi-nfqws','ciadpi-snimod','ciadpi-dns-bridge',
    'spoofdpi','greentunnel','wstunnel','udp2raw','ghostcp','dpi-tunnel',
    'bypass-dpi','egcit','tcp-window-manipulation','sni-mutation',
    'first-byte-desync','ipv6-hopbyhop','ipv6-destopt','wiresock-tunneling'
  ].map((name)=>KingTransportCapability(id:name,category:'dpi',title:name,state:KingCapabilityState.requiresNativeEngine,families:_both,integration:'Native packet engine required; per-family kernel/API support and safety tests required')),
  // Tor pluggable transports and bridges.
  ...[
    'obfs2','obfs3','obfs4','meek','meek-amazon','meek-azure','meek-google',
    'snowflake','webtunnel','scramblesuit','fte','flashproxy','marionette'
  ].map((name)=>KingTransportCapability(id:'pt-$name',category:'pluggable-transport',title:name,state:KingCapabilityState.requiresNativeEngine,families:_both,integration:'Tor bridge/PT binary and bridge configuration required')),
  // Fronting, CDN and domain camouflage.
  ...[
    'domain-fronting-classic','domain-fronting-domainless','domain-fronting-ech',
    'underminr-simple','underminr-split','underminr-ech','underminr-direct-ip',
    'domain-shadowing','cachebrowser','cdnreaper','massbrowser','gae-proxy',
    'goagent','lantern','uproxy','censorless','netshuffle','spotproxy'
  ].map((name)=>KingTransportCapability(id:name,category:'fronting-cdn',title:name,state:KingCapabilityState.requiresNativeEngine,families:_both,integration:'Provider-compatible relay/CDN infrastructure and protocol adapter required')),
  // Refraction, WebRTC/QUIC and AI-assisted strategies.
  ...[
    'conjure','telex','tapdance','slitheen','cirripede','curveball','rebound',
    'protozoa','stegozoa','turnable','olcrtc','vk-turn-proxy','quictor',
    'mirace','hivoid-core','olcbox','circumvolve','geneva','flowpaint',
    'symtcp','geph','xx-net','v2rayng','clash-android','chromego','edgego',
    'psiphon-conduit','amnezia-vpn','incy','hiddify','sing-box','nekobox',
    'streisand','exclave','outline','dnstt','slipstream','iodine',
    'ping-tunnel','dnscat2','dns2tcp','telegram-mtproxy'
  ].map((name)=>KingTransportCapability(id:name,category:'advanced-network',title:name,state:KingCapabilityState.requiresNativeEngine,families:_both,integration:'Independent upstream engine/service, license review and native adapter required')),
];

List<KingTransportCapability> kingCapabilitiesForFamily(KingAddressFamily family) =>
    List.unmodifiable(kingTransportCapabilities.where((item)=>item.supports(family)));

List<KingTransportCapability> kingCapabilitiesByCategory(String category) =>
    List.unmodifiable(kingTransportCapabilities.where((item)=>item.category==category));

KingTransportCapability? kingCapabilityById(String id) {
  for (final item in kingTransportCapabilities) {
    if (item.id==id) return item;
  }
  return null;
}

/// Only explicitly integrated engines can be selected for execution.
bool kingCapabilityCanRun(String id, KingAddressFamily family) {
  final item=kingCapabilityById(id);
  return item!=null && item.supports(family) && item.executableWithCurrentCore;
}
