part of 'main.dart';

// NATULTRA ==================================================================
// نت ملی / اینترنت کند: هر سرور فقط با «یک» حالت تست نمی‌شود؛ حالت‌های مختلف
// (آدرس دامنه/IP، Fragment با اندازه‌های مختلف، fingerprint ها، ALPN، پورت CDN،
// IP تمیز، Mux، DNS-over-HTTPS، Noise، TCP FastOpen ...) پشت‌سرهم امتحان می‌شوند.
// حالتی که جواب داد برای اتصال واقعی هم همان استفاده می‌شود.
//
// V7: Port Hopping · Dynamic DNS Fallback · Aggressive TLS Fragment · IP-Scan=ON
// =============================================================================

int natLevel = 1;
int natRound = 1; // V12: 1 = pass 1 (skip failed), 2 = pass 2 (retry all)
const int natMaxVariants = 5000; // V8 • فیکس ۱۷: قبلاً 0x7FFFFFFF
int natFloor = 0;
List<Server> natRestPending = [];

const int _natCodeBase = 100000;
const int _natBaseCount = 54; // V13: +4 SNI swap
// V7: bumped to 3 because the meaning of the port-hopping index changed
// (port 80 added to the CF port list), so old saved generated variants
// no longer point at the same meaning.
const int _natGenVer = 3;

final Map<String, int> natVar = {};
// NORMALCACHE: variant موفق در حالت عادی (جدا از natVar نت ملی).
// بعد از موفقیت ladder، اینجا ذخیره می‌شود تا اتصال بعدی
// مستقیم با همان variant شروع شود و ۱۵ ثانیه هدر نرود.
final Map<String, int> natVarNormal = {};

// ---------------------------------------------------------------------------
// جدول Fragment: [length, interval, packets]
const List<List<String>> _natFragBase = [
  ['10-30', '5-10', 'tlshello'], // 0
  ['100-200', '10-20', 'tlshello'], // 1
  ['50-100', '5-10', 'tlshello'], // 2
  ['1-5', '1-2', 'tlshello'], // 3
  ['50-100', '5-10', '1-3'], // 4
  ['20-50', '1-3', 'tlshello'], // 5
  ['5-15', '20-40', 'tlshello'], // 6
  ['200-400', '5-10', 'tlshello'], // 7
  ['30-60', '10-20', '1-2'], // 8
];

final List<List<String>> _natFrags = _natBuildFrags();

List<List<String>> _natBuildFrags() {
  final out = <List<String>>[..._natFragBase];
  final seen = <String>{
    for (final f in _natFragBase) '${f[0]}|${f[1]}|${f[2]}'
  };
  const lens = [
    '1-2', '1-3', '2-5', '2-8', '5-15', '10-30', '20-50', '30-60', '50-100',
    '100-200', '200-400', '400-800'
  ];
  const ints = ['1-1', '1-2', '2-5', '5-10', '10-20', '20-40', '40-80'];
  const pks = ['tlshello', '1-1', '1-2', '1-3', '1-5'];
  for (final pk in pks) {
    for (final l in lens) {
      for (final i in ints) {
        if (seen.add('$l|$i|$pk')) out.add([l, i, pk]);
      }
    }
  }
  return out;
}

const List<List<String>> _natNoises = [
  ['10-20', '10-16'],
  ['5-10', '5-10'],
  ['30-60', '20-40'],
  ['50-100', '10-30'],
  ['1-5', '1-5'],
];

const List<String> _natDnsList = [
  '178.22.122.100',
  '185.51.200.2',
  '78.157.42.100',
  '78.157.42.101',
  '10.202.10.10',
  '10.202.10.11',
  '10.202.10.202',
  'https+local://1.1.1.1/dns-query',
  'https+local://8.8.8.8/dns-query',
  'https+local://9.9.9.9/dns-query',
  'https+local://1.0.0.1/dns-query',
  'https+local://8.8.4.4/dns-query',
  'https+local://149.112.112.112/dns-query',
  'https+local://94.140.14.14/dns-query',
  'https+local://208.67.222.222/dns-query',
  'https+local://208.67.220.220/dns-query',
  '1.1.1.1',
  '8.8.8.8',
  '9.9.9.9',
  '94.140.14.14',
  '208.67.222.222',
  'https+local://[2606:4700:4700::1111]/dns-query',
  'https+local://[2001:4860:4860::8888]/dns-query',
  '2606:4700:4700::1111',
  '2606:4700:4700::1001',
  '2001:4860:4860::8888',
  '2001:4860:4860::8844',
  '2620:fe::fe',
  '2620:fe::9',
  'https+local://[2620:fe::fe]/dns-query',
];

class _NatSpec {
  final String name;
  final bool other;
  final String? fp, alpn;
  final int? frag;
  final bool port, clean, mux, sniHost, v4, tfo, ed, noise;
  final String? doh;
  final int muxN;
  final int noiseK;
  final bool nodelay;
  final String? mode;
  final int? edN;
  final int? portIdx;
  final int? cleanIdx;
  final int? keep;
  final int? mss;
  final String? sniSwap; // exact hostname; stable across later inventory growth
  const _NatSpec(this.name,
      {this.other = false,
      this.fp,
      this.alpn,
      this.frag,
      this.port = false,
      this.clean = false,
      this.mux = false,
      this.sniHost = false,
      this.v4 = false,
      this.tfo = false,
      this.ed = false,
      this.noise = false,
      this.doh,
      this.muxN = 0,
      this.noiseK = 0,
      this.nodelay = false,
      this.mode,
      this.edN,
      this.portIdx,
      this.cleanIdx,
      this.keep,
      this.mss,
      this.sniSwap});
}

const List<_NatSpec> _natBase = [
  _NatSpec('عادی'),
  _NatSpec('آدرس دیگر', other: true),
  _NatSpec('Fragment ریز', frag: 0),
  _NatSpec('Fragment متوسط', frag: 1),
  _NatSpec('fp=firefox', fp: 'firefox'),
  _NatSpec('fp=randomized + Fragment', fp: 'randomized', frag: 2),
  _NatSpec('fp=ios', fp: 'ios'),
  _NatSpec('alpn=http/1.1', alpn: 'http/1.1'),
  _NatSpec('Fragment خیلی ریز', frag: 3),
  _NatSpec('Fragment چندبسته‌ای', frag: 4),
  _NatSpec('پورت دیگر CDN', port: true),
  _NatSpec('IP تمیز Cloudflare', clean: true),
  _NatSpec('Mux', mux: true),
  _NatSpec('fp=chrome', fp: 'chrome'),
  _NatSpec('fp=safari', fp: 'safari'),
  _NatSpec('fp=edge', fp: 'edge'),
  _NatSpec('fp=android', fp: 'android'),
  _NatSpec('fp=random', fp: 'random'),
  _NatSpec('fp=qq', fp: 'qq'),
  _NatSpec('fp=360', fp: '360'),
  _NatSpec('alpn=h2', alpn: 'h2'),
  _NatSpec('alpn=h2,http/1.1', alpn: 'h2,http/1.1'),
  _NatSpec('Fragment 20-50', frag: 5),
  _NatSpec('Fragment ریز و کند', frag: 6),
  _NatSpec('Fragment درشت', frag: 7),
  _NatSpec('Fragment ۱-۲ بسته', frag: 8),
  _NatSpec('fp=chrome + Fragment', fp: 'chrome', frag: 0),
  _NatSpec('fp=firefox + Fragment خیلی ریز', fp: 'firefox', frag: 3),
  _NatSpec('fp=randomized + Fragment متوسط', fp: 'randomized', frag: 1),
  _NatSpec('fp=ios + Fragment', fp: 'ios', frag: 2),
  _NatSpec('Fragment + Mux', frag: 0, mux: true),
  _NatSpec('Fragment + IP تمیز', frag: 0, clean: true),
  _NatSpec('Fragment + پورت دیگر', frag: 0, port: true),
  _NatSpec('SNI = Host', sniHost: true),
  _NatSpec('SNI = Host + Fragment', sniHost: true, frag: 0),
  _NatSpec('DoH کلودفلر', doh: 'https+local://1.1.1.1/dns-query'),
  _NatSpec('DoH گوگل', doh: 'https+local://8.8.8.8/dns-query'),
  _NatSpec('DoH Quad9', doh: 'https+local://9.9.9.9/dns-query'),
  _NatSpec('فقط IPv4', v4: true),
  _NatSpec('Fragment + Noise', frag: 0, noise: true),
  _NatSpec('TCP FastOpen', tfo: true),
  _NatSpec('Fragment + TCP FastOpen', frag: 0, tfo: true),
  _NatSpec('WebSocket early-data', ed: true),
  _NatSpec('alpn=h2 + Fragment', alpn: 'h2', frag: 0),
  _NatSpec('fp=chrome + alpn=h2,http/1.1', fp: 'chrome', alpn: 'h2,http/1.1'),
  _NatSpec('DoH + Fragment', doh: 'https+local://1.1.1.1/dns-query', frag: 0),
  _NatSpec('WebSocket early-data + Fragment', ed: true, frag: 0),
  _NatSpec('آدرس دیگر + Fragment', other: true, frag: 0),
  _NatSpec('آدرس دیگر + fp=chrome', other: true, fp: 'chrome'),
  _NatSpec('آدرس دیگر + Fragment خیلی ریز', other: true, frag: 3),
  // V13: SNI swap variants (CDN bypass by masking SNI, keeping Host header).
  _NatSpec('SNI>cdnjs', sniSwap: 'cdnjs.cloudflare.com'),
  _NatSpec('SNI>cloudflare', sniSwap: 'www.cloudflare.com'),
  _NatSpec('SNI>speed', sniSwap: 'speed.cloudflare.com'),
  _NatSpec('SNI>divar.ir', sniSwap: 'divar.ir'),
];

final List<_NatSpec> _natSpecs = [..._natBase, ..._natGenerate(), ..._natExtra];

const List<_NatSpec> _natExtra = [
  _NatSpec('MTU 1280 (MSS 1240)', mss: 1240),
  _NatSpec('MTU 1320 (MSS 1280)', mss: 1280),
  _NatSpec('MTU 1360 (MSS 1320)', mss: 1320),
  _NatSpec('MTU 1400 (MSS 1360)', mss: 1360),
  _NatSpec('Keep-Alive 5s', keep: 5),
  _NatSpec('Keep-Alive 8s', keep: 8),
  _NatSpec('MSS 1240 + Fragment', frag: 0, mss: 1240),
  _NatSpec('MSS 1320 + Fragment', frag: 0, mss: 1320),
  _NatSpec('MSS 1320 + fp=chrome', fp: 'chrome', mss: 1320),
  _NatSpec('MSS 1320 + Mux', mux: true, mss: 1320),
  _NatSpec('Keep-Alive 5s + Fragment', frag: 0, keep: 5),
  _NatSpec('Keep-Alive 8s + fp=chrome', fp: 'chrome', keep: 8),
  _NatSpec('mKCP (UDP)', mode: 'kcp:none'),
  _NatSpec('fp=360', fp: '360'),
  _NatSpec('fp=qq', fp: 'qq'),
];

String _natSig(_NatSpec x) =>
    '${x.fp}|${x.alpn}|${x.frag}|${x.other}|${x.port}|${x.portIdx}|${x.clean}|'
    '${x.cleanIdx}|${x.mux}|${x.muxN}|${x.sniHost}|${x.v4}|${x.tfo}|${x.ed}|'
    '${x.edN}|${x.noise}|${x.noiseK}|${x.nodelay}|${x.doh}|${x.mode}|${x.keep}|${x.sniSwap}';

_NatSpec _natMk(
    {String? fp,
    String? alpn,
    int? frag,
    bool other = false,
    bool port = false,
    int? portIdx,
    bool clean = false,
    int? cleanIdx,
    bool mux = false,
    int muxN = 0,
    bool sniHost = false,
    bool v4 = false,
    bool tfo = false,
    bool ed = false,
    int? edN,
    bool noise = false,
    int noiseK = 0,
    bool nodelay = false,
    String? doh,
    String? mode,
    int? keep,
    String? sniSwap}) {
  final n = <String>[];
  if (other) n.add('آدرس دیگر');
  if (fp != null) n.add('fp=$fp');
  if (alpn != null) n.add('alpn=$alpn');
  if (frag != null) {
    final f = _natFrags[frag];
    n.add('Frag ${f[0]}/${f[1]}/${f[2]}');
  }
  if (noise) n.add('Noise${noiseK + 1}');
  if (mux) n.add('Mux${muxN > 0 ? muxN : 8}');
  if (sniHost) n.add('SNI=Host');
  if (v4) n.add('IPv4');
  if (tfo) n.add('TFO');
  if (nodelay) n.add('NoDelay');
  if (keep != null) n.add('KeepAlive$keep');
  if (ed) n.add('ED${edN ?? 2048}');
  if (port) {
    final pi = portIdx;
    n.add(pi == null ? 'پورت دیگر' : 'پورت ${_natCfPorts[pi % _natCfPorts.length]}');
  }
  if (clean) {
    final ci = cleanIdx;
    n.add(ci == null ? 'IP تمیز' : 'IP تمیز #${ci + 1}');
  }
  if (doh != null) {
    var dn = doh.replaceFirst('https+local://', '');
    dn = dn.replaceFirst('/dns-query', '');
    n.add('DNS $dn');
  }
  if (mode != null) n.add(mode);
  if (sniSwap != null) n.add('SNI>$sniSwap');
  return _NatSpec(n.isEmpty ? 'عادی+' : n.join(' + '),
      other: other,
      fp: fp,
      alpn: alpn,
      frag: frag,
      port: port,
      portIdx: portIdx,
      clean: clean,
      cleanIdx: cleanIdx,
      mux: mux,
      muxN: muxN,
      sniHost: sniHost,
      v4: v4,
      tfo: tfo,
      ed: ed,
      edN: edN,
      noise: noise,
      noiseK: noiseK,
      nodelay: nodelay,
      doh: doh,
      mode: mode,
      keep: keep,
      sniSwap: sniSwap);
}

List<_NatSpec> _natGenerate() {
  final out = <_NatSpec>[];
  final seen = <String>{for (final b in _natBase) _natSig(b)};
  void add(_NatSpec x) {
    if (seen.add(_natSig(x))) out.add(x);
  }

  const fps = [
    'chrome', 'firefox', 'randomized', 'ios', 'android', 'safari', 'edge',
    'random', 'qq', '360',
    'hellogolang', 'hellochrome', 'hellofirefox', 'hellosafari', 'helloios',
    'helloandroid', 'helloedge', 'hello360', 'helloqq', 'hellorandomized',
    'hellorandomizedalpn', 'hellorandomizednoalpn',
  ];
  const alpns = ['h2', 'http/1.1', 'h2,http/1.1'];

  final top = <int>[for (var i = 0; i < _natFragBase.length; i++) i];
  for (var i = _natFragBase.length; i < _natFrags.length; i++) {
    final f = _natFrags[i];
    if (f[2] == 'tlshello' &&
        (f[1] == '1-2' || f[1] == '5-10' || f[1] == '10-20')) {
      top.add(i);
    }
  }
  final topSet = top.toSet();
  final rest = <int>[
    for (var i = _natFragBase.length; i < _natFrags.length; i++)
      if (!topSet.contains(i)) i
  ];

  // SNI-swap x fragment combos use stable hostname values, not mutable
  // offsets into a list that can grow after a later scan.
  const sniNames = <String>[
    'cdnjs.cloudflare.com',
    'www.cloudflare.com',
    'speed.cloudflare.com',
    'divar.ir',
  ];
  for (final sni in sniNames) {
    for (var fi = 0; fi < _natFragBase.length; fi++) {
      add(_natMk(frag: fi, sniSwap: sni));
    }
  }

  for (final p in fps) {
    add(_natMk(fp: p));
  }
  for (final a in alpns) {
    add(_natMk(alpn: a));
  }
  for (final g in top) {
    add(_natMk(frag: g));
  }
  for (final g in top) {
    for (final p in fps.take(7)) {
      add(_natMk(frag: g, fp: p));
    }
  }
  for (final g in top) {
    for (final a in alpns) {
      add(_natMk(frag: g, alpn: a));
    }
  }
  for (final p in fps) {
    for (final a in alpns) {
      add(_natMk(fp: p, alpn: a));
    }
  }
  final mods = <_NatSpec Function(int?, String?)>[];
  mods.add((f, p) => _natMk(frag: f, fp: p, v4: true));
  mods.add((f, p) => _natMk(frag: f, fp: p, tfo: true));
  mods.add((f, p) => _natMk(frag: f, fp: p, nodelay: true));
  mods.add((f, p) => _natMk(frag: f, fp: p, keep: 15));
  for (final n in const [512, 1024, 4096]) {
    mods.add((f, p) => _natMk(frag: f, fp: p, ed: true, edN: n));
  }
  mods.add((f, p) => _natMk(frag: f, fp: p, other: true));
  mods.add((f, p) => _natMk(frag: f, fp: p, sniHost: true));
  for (var k = 0; k < _natCfPorts.length; k++) {
    mods.add((f, p) => _natMk(frag: f, fp: p, port: true, portIdx: k));
  }
  for (var k = 0; k < 5; k++) {
    mods.add((f, p) => _natMk(frag: f, fp: p, clean: true, cleanIdx: k));
  }
  for (final d in _natDnsList) {
    mods.add((f, p) => _natMk(frag: f, fp: p, doh: d));
  }
  for (final m in mods) {
    add(m(null, null));
  }
  for (final m in mods) {
    for (final g in top.take(12)) {
      add(m(g, null));
    }
  }
  for (final m in mods) {
    for (final p in const ['chrome', 'firefox', 'randomized', 'ios']) {
      add(m(null, p));
    }
  }
  for (final m in mods) {
    for (final g in top.take(6)) {
      for (final p in const ['chrome', 'firefox', 'randomized']) {
        add(m(g, p));
      }
    }
  }
  for (final g in top.take(20)) {
    for (final p in fps.take(5)) {
      for (final a in alpns) {
        add(_natMk(frag: g, fp: p, alpn: a));
      }
    }
  }
  for (final g in rest) {
    add(_natMk(frag: g));
  }
  for (final g in rest) {
    add(_natMk(frag: g, fp: 'chrome'));
  }
  for (final g in rest) {
    add(_natMk(frag: g, fp: 'firefox'));
  }
  return out;
}

int _natGrowCounter = 0;

// Keep the static front-SNI prefix stable for persisted variant indices,
// then append the complete project domain inventory and discovered names.
String? _natNormalizeSniHostname(String raw) {
  final name = raw.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  if (name.isEmpty || name.length > 253 || InternetAddress.tryParse(name) != null) {
    return null;
  }
  final labels = name.split('.');
  if (labels.length < 2) return null;
  final labelPattern = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');
  if (!labels.every((label) => labelPattern.hasMatch(label))) return null;
  return name;
}

List<String>? _natSniCatalogCache;

List<String> _natSniCatalog() {
  final cached = _natSniCatalogCache;
  if (cached != null) return cached;
  final out = <String>{};
  void addNames(Iterable<String> names) {
    for (final raw in names) {
      final name = _natNormalizeSniHostname(raw);
      if (name != null) out.add(name);
    }
  }

  // Static project catalogs are built once; preserve historical front-SNI
  // ordering so previously persisted variant indices remain stable.
  addNames(natFrontSnis);
  addNames(kAutoSniDomains);
  addNames(dnsxFullDomains());
  final built = out.toList(growable: false);
  _natSniCatalogCache = built;
  return built;
}

List<String> _natSniPool() {
  final out = <String>{..._natSniCatalog()};
  void addNames(Iterable<String> names) {
    for (final raw in names) {
      final name = _natNormalizeSniHostname(raw);
      if (name != null) out.add(name);
    }
  }

  // Append user relays and every persisted SNI discovery observation.
  addNames(natRelayHosts);
  addNames(_goldScan['sni'] ?? const <String>[]);
  addNames(_goldScan['sni_candidates'] ?? const <String>[]);
  return out.toList(growable: false);
}

int natGrow(int n) {
  if (_natSpecs.length > 500000) return 0;
  final rnd = Random(DateTime.now().millisecondsSinceEpoch + _natGrowCounter++);
  var added = 0;
  const fps = ['chrome', 'firefox', 'randomized', 'ios', 'android', 'safari', 'edge', 'random', 'qq', '360', 'hellogolang', 'hellochrome', 'hellofirefox', 'hellosafari', 'helloios', 'helloandroid', 'helloedge', 'hello360', 'helloqq', 'hellorandomized', 'hellorandomizedalpn', 'hellorandomizednoalpn'];
  const alpns = <String?>[null, 'h2', 'http/1.1', 'h2,http/1.1'];
  // Build the potentially large SNI inventory once per growth batch.
  final sniPool = _natSniPool();
  for (var i = 0; i < n; i++) {
    final fp = fps[rnd.nextInt(fps.length)];
    final alpn = alpns[rnd.nextInt(alpns.length)];
    final frag = rnd.nextInt(_natFrags.length);
    final port = rnd.nextBool();
    final portIdx = port ? rnd.nextInt(_natCfPorts.length) : null;
    final clean = rnd.nextBool();
    final cleanIdx = clean ? rnd.nextInt(10) : null;
    // DNSNAT: جایگزین‌ها از DNSهای سالم اسکن (اگر هست) انتخاب می‌شوند
    // نیمی از انتخاب‌ها از DNSهای اسکن‌شده و نیمی از لیست ثابت، تا تنوع حفظ شود
    final dnsPool = (dnsxBestCache.isNotEmpty && rnd.nextBool()) ? dnsxBestCache : _natDnsList;
    final doh = rnd.nextBool() ? dnsPool[rnd.nextInt(dnsPool.length)] : null;
    final v4 = rnd.nextBool();
    final tfo = rnd.nextBool();
    final keep = rnd.nextBool() ? rnd.nextInt(30) + 1 : null;
    final sniSwap =
        sniPool.isNotEmpty && rnd.nextBool() ? sniPool[rnd.nextInt(sniPool.length)] : null;
    _natSpecs.add(_natMk(
      fp: fp, alpn: alpn, frag: frag, port: port, portIdx: portIdx,
      clean: clean, cleanIdx: cleanIdx, v4: v4, tfo: tfo, keep: keep, doh: doh,
      sniSwap: sniSwap,
    ));
    added++;
  }
  if (added > 0) { _natNamesC = null; _natGenRankKey = ''; }
  return added;
}

List<String>? _natNamesC;
List<String> get _natVarNames =>
    _natNamesC ??= [for (final x in _natSpecs) x.name];

const List<String> _natTestUrls = [
  'http://cp.cloudflare.com/generate_204',
  'http://www.msftconnecttest.com/connecttest.txt',
  'http://connectivitycheck.gstatic.com/generate_204',
  'http://clients3.google.com/generate_204',
  'http://www.google.com/generate_204',
  'http://detectportal.firefox.com/success.txt',
  'http://captive.apple.com/hotspot-detect.html',
  'http://www.apple.com/library/test/success.html',
  'http://edge-http.microsoft.com/captiveportal/generate_204',
  'http://play.googleapis.com/generate_204',
  'http://www.gstatic.com/generate_204',
  'http://nmcheck.gnome.org/check_network_status.txt',
  'http://connectivity-check.ubuntu.com/',
  'http://www.cloudflare.com/cdn-cgi/trace',
  'http://neverssl.com/',
  'http://example.com/',
  'https://cp.cloudflare.com/generate_204',
  'https://www.google.com/generate_204',
  'https://www.youtube.com/generate_204',
  'https://one.one.one.one/',
  'https://dns.google/',
  'https://www.bing.com/',
  'https://www.wikipedia.org/',
  'https://www.cloudflare.com/cdn-cgi/trace',
];

String? _natUrlFor(int code, String? url) {
  final i = code ~/ _natCodeBase;
  if (i == 0) return url;
  if (nationalMode) {
    // NATDOMESTIC: در نت ملی یکی در میان مقصد داخلی (فرد) و جهانی (زوج).
    // FIXNATURL: قبلاً برای i زوج همیشه (i-1)%8 (اندیس فرد) انتخاب می‌شد، پس نیمی از
    // مقصدهای جهانی (cp.cloudflare، one.one.one.one، dns.google، wikipedia) هرگز تست نمی‌شدند.
    if (i % 2 == 1) {
      final d = _tunnelTestUrlsNational;
      return d[(i ~/ 2) % d.length];
    }
    return _natTestUrls[(i ~/ 2 - 1) % _natTestUrls.length];
  }
  return _natTestUrls[(i - 1) % _natTestUrls.length];
}

// V7-PORT: priority-ordered list for port hopping, tuned for Iranian operators.
// 443 (default HTTPS), 80 (plain HTTP often passes when 443 is throttled),
// then alternate CDN ports that Cloudflare accepts (8443, 2053, 2083, 2087, 2096).
const List<int> _natCfPorts = [443, 80, 8443, 2053, 2083, 2087, 2096];
const Set<String> _natCdnNets = {
  'ws', 'grpc', 'httpupgrade', 'xhttp', 'splithttp', 'h2'
};
int _natRot = 0;

final Map<String, String> _natPick = {};

String _natPickOf(String k, bool reuse, String Function() gen) {
  if (reuse) {
    final old = _natPick[k];
    if (old != null) return old;
  }
  final v = gen();
  _natPick[k] = v;
  return v;
}

int _natNextPort(Server s) {
  // V7-PORT: strict priority walk over _natCfPorts. Starting from the port
  // right after the server's current port, walk the list once and return
  // the first port that is different.
  final idx = _natCfPorts.indexOf(s.port);
  final start = idx < 0 ? 0 : (idx + 1) % _natCfPorts.length;
  for (var k = 0; k < _natCfPorts.length; k++) {
    final cand = _natCfPorts[(start + k) % _natCfPorts.length];
    if (cand != s.port) return cand;
  }
  return 443;
}

bool _natIsSecure(Server s) {
  final l = s.link.toLowerCase();
  if (l.startsWith('ss://')) return false;
  return s.tls || s.reality || l.contains('security=tls') || l.contains('"tls":"tls"');
}

class _NatFacts {
  final bool sec,
      ss,
      hasOther,
      reality,
      isIp,
      cdnLike,
      cdnNet,
      cfPort,
      ws,
      xh,
      grpc,
      vmess,
      hasClean;
  final int port;
  _NatFacts(Server s)
      : sec = _natIsSecure(s),
        ss = s.link.toLowerCase().startsWith('ss://'),
        hasOther = s.ipLink != null && s.ipLink != s.link,
        reality = s.reality,
        isIp = s.isIp,
        cdnLike = s.cdn || s.net == 'ws',
        cdnNet = _natCdnNets.contains(s.net),
        cfPort = _natCfPorts.contains(s.port),
        ws = s.net == 'ws',
        xh = s.net == 'xhttp' || s.net == 'splithttp',
        grpc = s.net == 'grpc',
        vmess = s.link.toLowerCase().startsWith('vmess://'),
        hasClean = cleanIps.isNotEmpty,
        port = s.port;
}

const Set<String> _natRetiredNames = {
  'Fragment ریز و کند',
  'fp=android',
};

bool natRetired(int v) =>
    v > 0 && v < _natSpecs.length && _natRetiredNames.contains(_natSpecs[v].name);

// VARCB: circuit breaker برای variantها (فقط نت ملی)
// هر variant بعد از ۲۰ شکست پشت‌سرهم، یک ساعت غیرفعال می‌شود
const int _varcbLimit = 20;
const Duration _varcbCooldown = Duration(hours: 1);
final Map<int, int> _variantFailStreak = {};
final Map<int, DateTime> _variantCooldown = {};

void natVariantResult(int v, bool ok) {
  if (v <= 0) return;
  final cd = _variantCooldown[v];
  if (cd != null && DateTime.now().isBefore(cd)) return;
  if (ok) {
    _variantFailStreak.remove(v);
    _variantCooldown.remove(v);
    return;
  }
  final n = (_variantFailStreak[v] ?? 0) + 1;
  if (n >= _varcbLimit) {
    _variantFailStreak.remove(v);
    _variantCooldown[v] = DateTime.now().add(_varcbCooldown);
    dbg('VARCB: حالت #$v بعد از $n شکست پیاپی، یک ساعت غیرفعال شد');
  } else {
    _variantFailStreak[v] = n;
  }
}

bool natVariantCooling(int v) {
  final cd = _variantCooldown[v];
  return cd != null && DateTime.now().isBefore(cd);
}

bool _natAppliesF(_NatFacts f, int v) {
  if (v < 0 || v >= _natSpecs.length) return false;
  if (v == 0) return true;
  if (natDisabled.contains(v)) return false;
  if (natVariantCooling(v)) return false; // VARCB
  if (natRetired(v)) return false;
  final x = _natSpecs[v];
  if (x.other && !f.hasOther) return false;
  if ((x.fp != null || x.alpn != null || x.frag != null || x.noise) &&
      !f.sec) {
    return false;
  }
  if (x.sniHost && !(f.sec && !f.reality)) return false;
  if (x.ed && !(f.sec && !f.reality && f.ws)) return false;
  if (x.port && !(f.sec && !f.reality && f.cdnNet && f.cfPort)) return false;
  final pi = x.portIdx;
  if (x.port && pi != null && _natCfPorts[pi % _natCfPorts.length] == f.port) {
    return false;
  }
  if (x.clean && !(f.sec && !f.reality && f.hasClean && f.cdnLike)) {
    return false;
  }
  if (x.mux) return false;
  if (x.noise) return false;
  if (x.mode != null && (!x.mode!.startsWith('kcp:') || f.reality)) return false;
  if (x.doh != null && f.isIp) return false;
  // SNI replacement is valid for any TLS transport supported by the core;
  // CDN classification is not a protocol requirement. Reality/ECH remain excluded.
  if (x.sniSwap != null && !(f.sec && !f.reality)) return false;
  return true;
}

bool _natChangesAddr(int v) {
  if (v <= 0 || v >= _natSpecs.length) return false;
  final x = _natSpecs[v];
  return x.other || x.port || x.clean;
}

final Map<String, int> natDimWins = {};
int _natLearnVer = 0;

List<String> _natDims(_NatSpec x) {
  final d = <String>[];
  if (x.fp != null) d.add('fp=${x.fp}');
  if (x.alpn != null) d.add('al=${x.alpn}');
  final f = x.frag;
  if (f != null) {
    d.add('fl=${_natFrags[f][0]}');
    d.add('fi=${_natFrags[f][1]}');
    d.add('fk=${_natFrags[f][2]}');
  }
  if (x.mux) d.add('mux');
  if (x.v4) d.add('v4');
  if (x.tfo) d.add('tfo');
  if (x.nodelay) d.add('nd');
  if (x.noise) d.add('noise');
  if (x.ed) d.add('ed');
  if (x.other) d.add('other');
  if (x.port) d.add('port');
  if (x.clean) d.add('clean');
  if (x.sniHost) d.add('sni');
  if (x.doh != null) d.add('dns=${x.doh}');
  if (x.mode != null) d.add('mode=${x.mode}');
  if (x.mss != null) d.add('mss=${x.mss}');
  if (x.keep != null) d.add('ka=${x.keep}');
  if (x.sniSwap != null) d.add('sni=${x.sniSwap}');
  return d;
}

List<int> _natGenRank = [];
String _natGenRankKey = '';
DateTime? _natGenLastSortAt; // GENTHROTTLE

List<int> _natGenRanked() {
  final hb = DateTime.now().hour ~/ 3; // V13: 3-hour bucket
  final key = '$natOpKey|$_natLearnVer|${_natSpecs.length}|h$hb';
  if (key == _natGenRankKey) return _natGenRank;
  // GENTHROTTLE: اگر کمتر از ۳۰ ثانیه از sort قبلی گذشته و تعداد specها
  // تغییر نکرده، cache را برگردان (natVarSet پشت‌سرهم می‌آید)
  final now = DateTime.now();
  final parts = _natGenRankKey.split('|');
  if (_natGenRank.isNotEmpty &&
      _natGenLastSortAt != null &&
      now.difference(_natGenLastSortAt!) < const Duration(seconds: 30) &&
      parts.length > 2 &&
      parts[2] == '${_natSpecs.length}') {
    _natGenRankKey = key;
    return _natGenRank;
  }
  final idx = <int>[for (var i = _natBaseCount; i < _natSpecs.length; i++) i];
  final sc = <int, int>{};
  for (final i in idx) {
    var s = 0;
    for (final d in _natDims(_natSpecs[i])) {
      s += natDimWins['$natOpKey#$d'] ?? 0;
      s += (natDimWins['$natOpKey#h$hb#$d'] ?? 0) * 2;
    }
    sc[i] = s;
  }
  idx.sort((a, b) {
    final d = (sc[b] ?? 0) - (sc[a] ?? 0);
    return d != 0 ? d : a - b;
  });
  _natGenRank = idx;
  _natGenRankKey = key;
  _natGenLastSortAt = now; // GENTHROTTLE
  return idx;
}

// TOPWIN: کش برترین‌ها؛ با تغییر natWins، natOpKey یا تعداد specها باطل می‌شود
int _natWinsVer = 0;
List<int>? _topWinCache;
String _topWinKey = '';

List<int> _natTopWinners(int n) {
  final key = '$natOpKey|$_natWinsVer|${_natSpecs.length}';
  if (_topWinCache == null || _topWinKey != key) {
    final pre = '$natOpKey#';
    final rows = <MapEntry<int, int>>[];
    natWins.forEach((k, c) {
      if (!k.startsWith(pre)) return;
      final v = int.tryParse(k.substring(pre.length));
      if (v != null && v > 0 && v < _natSpecs.length) rows.add(MapEntry(v, c));
    });
    rows.sort((a, b) => b.value.compareTo(a.value));
    _topWinCache = [for (final r in rows) r.key];
    _topWinKey = key;
  }
  return _topWinCache!.take(n).toList();
}

final Map<String, int> _natCursor = {};
String _natCk(Server s) => '$natOpKey#${s.key}';

void natCursorAdvance(Server s, int n) {
  if (n <= 0) return;
  final k = _natCk(s);
  _natCursor[k] = (_natCursor[k] ?? 0) + n;
}

Duration natBudget({bool full = false}) {
  // NATFIRST: نت ملی، دور اول: هر سرور فقط ۲۰ ثانیه برای حالت‌ها وقت دارد و بقیه‌ی حالت‌ها
  // در دور بعد ادامه می‌یابند (natCursor). اولین سرور سالم فوراً وصل می‌شود.
  if (nationalMode && !full && natRound == 1) return const Duration(seconds: 20);
  final l = full ? 3 : natLevel;
  // V12: at lvl 10 (national default) give a generous budget so the FULL
  // matrix (Fragment, DNS, port, FP, ALPN, clean IP, host, SNI...) is tested
  // against every server. No variant is skipped due to short budget.
  // فیکس ۶: بودجه‌ها کاهش یافتند (قبلاً 60/120/240/900/480) تا یک سرور خراب دقیقه‌ها گیر نکند.
  if (l <= 1) return const Duration(seconds: 30);
  if (l == 2) return const Duration(seconds: 60);
  if (l == 3) return const Duration(seconds: 120);
  // هم‌اندازه با سقف واچ‌داگ نت ملی (main.dart: wdSecs = 150)؛ بودجه‌ی بالاتر هیچ‌وقت کامل نمی‌شد
  if (l >= 9) return const Duration(seconds: 150);
  return const Duration(seconds: 240);
}

// فیکس ۱۷: سقف‌ها کاهش یافت (قبلاً: 0, 0, 200, 1200, 6000, 15000, 30000, 60000, 100000, 150000, 200000)
const List<int> _natGenCap = [
  0, 0, 100, 500, 1500, 4000, 8000, 15000, 20000, 30000, 40000
];

// فقط mKCP (UDP) «سنگین و کند» حساب می‌شود؛ Fragment و بقیه در اتصال عادی مجازند
bool _natIsSlowHeavy(int v) {
  final base = v % _natCodeBase;
  if (base <= 0 || base >= _natSpecs.length) return false;
  final x = _natSpecs[base];
  return x.mode != null && x.mode!.startsWith('kcp:');
}

List<int> _natOrder(Server s, {bool full = false}) {
  goldPrepareNational();
  var lvl = full ? 3 : natLevel;
  if (lvl < 1) lvl = 1;
  if (lvl > 10) lvl = 10;
  final f = _NatFacts(s);
  final known = natVar[_nk(s)];
  final cursor = _natCursor[_natCk(s)] ?? 0;
  final again = cursor > 0 && lvl >= 2;
  final out = <int>[];
  final used = <int>{};
  void put(int c) {
    if (used.add(c)) out.add(c);
  }

  final preferLight = !nationalMode;
  final skipHeavy = !nationalMode;

  final knownOk = known != null && _natAppliesF(f, known);
  if (knownOk && (!skipHeavy || !_natIsSlowHeavy(known!))) put(known!);

  if (preferLight) {
    // FRAGLADDER: Fragment variants در رأس لیست تا ladder حالت عادی
    // واقعاً DPI را دور بزند. ترتیب: fp سریع، بعد Fragment، بعد بقیه.
    final lightFirst = <int>[
      if (f.cdnLike && f.sec && !f.reality) ...[50, 51, 52, 53],
      0,     // normal (already tried, filtered by tried-set)
      4,     // firefox (cheap)
      2,     // Fragment ریز (DPI bypass) — index 2 = 'Fragment ریز'
      13,    // chrome
      8,     // Fragment خیلی ریز (DPI bypass aggressive)
      22,    // Fragment 20-50
      1,     // آدرس دیگر
      7,     // alpn http/1.1
      20,    // alpn h2
      33,    // SNI=Host
      38,    // IPv4
      40,    // TFO
      44,    // fp=chrome+alpn
    ];
    for (final w in _natTopWinners(8)) {
      if (!_natIsSlowHeavy(w) && !lightFirst.contains(w)) lightFirst.add(w);
    }
    for (final v in lightFirst) {
      if (_natAppliesF(f, v)) put(v);
    }
  }

  // NNIE: KCP is expensive and UDP may be filtered. Do not put it ahead of
  // cheap compatible variants on every fresh network. A previously learned
  // winner can still be tried first through knownOk above; otherwise KCP stays
  // in the later generated matrix rather than being an unconditional first pick.

  if (lvl >= 2) {
    for (final w in _natTopWinners(6)) {
      if (skipHeavy && _natIsSlowHeavy(w)) continue;
      if (_natAppliesF(f, w)) put(w);
    }
  }

  final cand = (lvl >= 2
      ? <int>[for (var i = 0; i < _natBaseCount; i++) i]
      : <int>[0, 1, 2, 8])
    ..sort((a, b) {
      final d = (natWins['$natOpKey#$b'] ?? 0) -
          (natWins['$natOpKey#$a'] ?? 0);
      return d != 0 ? d : a - b;
    });
  if (!again) {
    if (!knownOk || (preferLight && knownOk && _natIsSlowHeavy(known!))) {
      for (final v in cand) {
        if (skipHeavy && _natIsSlowHeavy(v)) continue;
        if (_natAppliesF(f, v)) {
          put(v);
          break;
        }
      }
    }
    if (lvl >= 2) {
      for (final i in const <int>[1, 2, 3]) {
        put(i * _natCodeBase);
      }
    }
    for (final v in cand) {
      if (skipHeavy && _natIsSlowHeavy(v)) continue;
      if (v != known && _natAppliesF(f, v)) put(v);
    }
  } else if (_natAppliesF(f, 0)) {
    put(0);
  }

  final gens = <int>[];
  final cap = _natGenCap[lvl];
  if (cap > 0) {
    final app = <int>[];
    for (final v in _natGenRanked()) {
      if (_natAppliesF(f, v)) app.add(v);
    }
    // NNIE staged scheduler: retain every compatible variant, but try cheap
    // options before expensive KCP unless a real winner was learned earlier.
    natStableSort(app, (a, b) {
      final sa = NationalNetworkIntelligence.stageFor(
        variantIndex: a % _natCodeBase,
        isKcp: _natIsSlowHeavy(a),
        isKnownWinner: knownOk && a == known,
        isCdnCompatible: f.cdnLike,
      ).index;
      final sb = NationalNetworkIntelligence.stageFor(
        variantIndex: b % _natCodeBase,
        isKcp: _natIsSlowHeavy(b),
        isKnownWinner: knownOk && b == known,
        isCdnCompatible: f.cdnLike,
      ).index;
      return sa.compareTo(sb);
    });
    if (cursor >= app.length && lvl >= 2) {
      natGrow(1000);
      app.clear();
      for (final v in _natGenRanked()) {
        if (_natAppliesF(f, v)) app.add(v);
      }
    }
    if (app.isNotEmpty && cursor < app.length) {
      final end = min(app.length, cursor + cap);
      for (var k = cursor; k < end; k++) {
        final gv = app[k];
        if (skipHeavy && _natIsSlowHeavy(gv)) continue;
        gens.add(gv);
      }
    }
  }
  final head = gens.length < 30 ? gens.length : 30;
  for (var k = 0; k < head; k++) {
    put(gens[k]);
  }
  if (lvl >= 2 && !again) {
    for (var i = 4; i <= 8; i++) {
      put(i * _natCodeBase);
    }
  }
  if (lvl >= 3 && !again) {
    for (var i = 9; i <= _natTestUrls.length; i++) {
      put(i * _natCodeBase);
    }
  }
  for (var k = head; k < gens.length; k++) {
    put(gens[k]);
  }
  if (lvl >= 3 && !again) {
    for (var i = 1; i <= _natTestUrls.length; i++) {
      for (final v in const [2, 8, 13]) {
        if (_natAppliesF(f, v)) put(i * _natCodeBase + v);
      }
    }
  }
  if (lvl >= 4 && !again) {
    for (final w in _natTopWinners(3)) {
      for (var i = 1; i <= 8; i++) {
        if (_natAppliesF(f, w)) put(i * _natCodeBase + w);
      }
    }
  }
  return out;
}

String _natSetParam(String link, String key, String val) {
  try {
    if (link.toLowerCase().startsWith('vmess://')) {
      var b = natB64Normalize(link.substring(8));
      final j = jsonDecode(utf8.decode(base64.decode(b)));
      j[key] = val;
      return 'vmess://${base64.encode(utf8.encode(jsonEncode(j)))}';
    }
    final u = Uri.parse(link);
    final q = Map<String, String>.from(u.queryParameters);
    q[key] = val;
    return u.replace(queryParameters: q).toString();
  } catch (e, stk) {
    logError(e, stk);
    return link;
  }
}

String _natGetParam(String link, String key) {
  try {
    if (link.toLowerCase().startsWith('vmess://')) {
      var b = natB64Normalize(link.substring(8));
      final j = jsonDecode(utf8.decode(base64.decode(b)));
      return (j[key] ?? '').toString();
    }
    return Uri.parse(link).queryParameters[key] ?? '';
  } catch (e, stk) {
    logError(e, stk);
    return '';
  }
}

String _natSetPort(String link, int port) {
  try {
    if (link.toLowerCase().startsWith('vmess://')) {
      var b = natB64Normalize(link.substring(8));
      final j = jsonDecode(utf8.decode(base64.decode(b)));
      j['port'] = port;
      return 'vmess://${base64.encode(utf8.encode(jsonEncode(j)))}';
    }
    return Uri.parse(link).replace(port: port).toString();
  } catch (e, stk) {
    logError(e, stk);
    return link;
  }
}

String _natSetHost(String link, String ip, String host) {
  try {
    if (link.toLowerCase().startsWith('vmess://')) {
      var b = natB64Normalize(link.substring(8));
      final j = jsonDecode(utf8.decode(base64.decode(b)));
      j['add'] = ip;
      if ((j['sni'] ?? '').toString().isEmpty) j['sni'] = host;
      if ((j['host'] ?? '').toString().isEmpty && j['net'] == 'ws') {
        j['host'] = host;
      }
      return 'vmess://${base64.encode(utf8.encode(jsonEncode(j)))}';
    }
    final u = Uri.parse(link);
    final q = Map<String, String>.from(u.queryParameters);
    if ((q['sni'] ?? '').isEmpty) q['sni'] = host;
    if (q['type'] == 'ws' && (q['host'] ?? '').isEmpty) q['host'] = host;
    return u.replace(host: ip, queryParameters: q).toString();
  } catch (e, stk) {
    logError(e, stk);
    return link;
  }
}

String _natLinkFor(Server s, int v, {bool reuse = false}) {
  goldPrepareNational();
  if (v < 0 || v >= _natSpecs.length) return s.useLink;
  final x = _natSpecs[v];
  var link = (x.other && s.ipLink != null) ? s.link : s.useLink;
  link = _natApplyTweaks(link, x, s);
  String portPick(String tag) => _natPickOf(
      '${s.key}#$v#$tag',
      reuse,
      () => '${x.portIdx != null ? _natCfPorts[x.portIdx! % _natCfPorts.length] : _natNextPort(s)}');
  if (x.port) {
    link = _natSetPort(link, int.tryParse(portPick('p')) ?? 2053);
  }
  if (x.clean && cleanIps.isNotEmpty) {
    final ip = _natPickOf('${s.key}#$v#c', reuse, () {
      final ci = x.cleanIdx;
      return ci != null
          ? cleanIps[ci % cleanIps.length].ip
          : cleanIps[_natRot++ % cleanIps.length].ip;
    });
    link = _natSetHost(s.link, ip, s.host);
    link = _natApplyTweaks(link, x, s);
    var ipPort = 443;
    for (final c in cleanIps) {
      if (c.ip == ip) {
        ipPort = c.port;
        break;
      }
    }
    if (x.port) {
      link = _natSetPort(link, int.tryParse(portPick('p2')) ?? 2053);
    } else if (ipPort != 443) {
      link = _natSetPort(link, ipPort);
    }
  }
  return link;
}

final Map<int, bool> dohPreOk = {};
final Map<int, DateTime> _dohPreAt = {};
int _dohGen = 0; // نسل کش: هر تغییر شبکه آن را بالا می‌برد
// نتیجه‌ی probe به شبکه‌ی فعلی وابسته است؛ با تغییر شبکه باید پاک شود.
void natDohCacheClear() {
  _dohGen++;
  dohPreOk.clear();
  _dohPreAt.clear();
}
Future<bool> natDohUsable(int v) async {
  if (v < 0 || v >= _natSpecs.length) return false;
  final doh = _natSpecs[v].doh;
  if (doh == null) return true;
  final cached = dohPreOk[v];
  final at = _dohPreAt[v];
  if (cached != null &&
      at != null &&
      DateTime.now().difference(at) < const Duration(minutes: 10)) {
    return cached;
  }
  var host = doh;
  final u = Uri.tryParse(doh);
  if (u != null && u.hasAuthority) host = u.host;
  final gen = _dohGen; // نسل قبل از probe گرفته می‌شود
  // A TCP-open port or successful TLS handshake is not proof of DoH.
  // Require a valid DNS-over-HTTPS JSON response for a mode-appropriate name.
  final path = (u?.path.isNotEmpty ?? false) ? u!.path : '/dns-query';
  final queryParameters = <String, String>{
    'name': nationalMode ? 'nic.ir' : 'google.com',
    'type': 'A',
  };
  // Preserve IPv6-literal HTTPS authority (brackets and port) as parsed.
  final query = (u != null && u.scheme == 'https' && u.hasAuthority)
      ? u.replace(path: path, queryParameters: queryParameters).toString()
      : Uri.https(host, path, queryParameters).toString();
  final ms = await _probeDoh(query, expectedDomain: nationalMode ? 'nic.ir' : 'google.com');
  final ok = ms != null;
  // ج-۱: اگر در این فاصله شبکه عوض شده، نتیجه مربوط به شبکه‌ی قبلی است؛ ننویس
  if (gen == _dohGen) {
    dohPreOk[v] = ok;
    _dohPreAt[v] = DateTime.now();
  }
  return ok;
}

String _natApplyTweaks(String link, _NatSpec x, Server s) {
  if (x.fp != null) link = _natSetParam(link, 'fp', x.fp!);
  if (x.alpn != null) link = _natSetParam(link, 'alpn', x.alpn!);
  final md = x.mode;
  if (md != null && md.startsWith('kcp:')) {
    if (link.toLowerCase().startsWith('vmess://')) {
      // VMess JSON: transport = net, header type = type
      link = _natSetParam(link, 'net', 'kcp');
      link = _natSetParam(link, 'type', md.substring(4));
    } else {
      link = _natSetParam(link, 'type', 'kcp');
      link = _natSetParam(link, 'headerType', md.substring(4));
    }
  } else if (md != null) {
    link = _natSetParam(link, 'mode', md.substring(md.indexOf(':') + 1));
  }
  if (x.sniHost && echFromLink(link).isEmpty) {
    final h = _natGetParam(link, 'host');
    link = _natSetParam(link, 'sni', h.isEmpty ? s.host : h);
  }
  if (x.ed) {
    final p0 = _natGetParam(link, 'path');
    if (!p0.contains('ed=')) {
      final p1 = p0.isEmpty ? '/' : p0;
      link = _natSetParam(link, 'path',
          p1 + (p1.contains('?') ? '&' : '?') + 'ed=${x.edN ?? 2048}');
    }
  }
  return link;
}

String? natChainCfg(String exitCfg, String relayCfg, {bool keepInbounds = false}) {
  try {
    final ej = jsonDecode(exitCfg);
    final rj = jsonDecode(relayCfg);
    if (ej is! Map<String, dynamic> || rj is! Map<String, dynamic>) return null;
    final exitOut = _natProxyOut(ej);
    final relayOut = _natProxyOut(rj);
    if (exitOut == null || relayOut == null) return null;
    final hop = Map<String, dynamic>.from(relayOut)..['tag'] = 'relay-hop';
    final hopSt = hop['streamSettings'];
    if (hopSt is Map && hopSt['sockopt'] is Map) {
      (hopSt['sockopt'] as Map).remove('dialerProxy');
    }
    final st = exitOut['streamSettings'] is Map
        ? Map<String, dynamic>.from(exitOut['streamSettings'] as Map)
        : <String, dynamic>{};
    final so = st['sockopt'] is Map
        ? Map<String, dynamic>.from(st['sockopt'] as Map)
        : <String, dynamic>{};
    so['dialerProxy'] = 'relay-hop';
    st['sockopt'] = so;
    exitOut['streamSettings'] = st;
    final outs = List<dynamic>.from((ej['outbounds'] as List?) ?? <dynamic>[]);
    outs.add(hop);
    ej['outbounds'] = outs;
    if (!keepInbounds) ej.remove('inbounds');
    return jsonEncode(ej);
  } catch (_) {
    return null;
  }
}

Map? _natProxyOut(Map<String, dynamic> j) {
  for (final o in (j['outbounds'] as List?) ?? <dynamic>[]) {
    if (o is Map &&
        const {'vmess', 'vless', 'trojan', 'shadowsocks'}
            .contains(o['protocol'])) {
      return o;
    }
  }
  return null;
}

// V7-FRAG: Fragment on the TLS Hello with deterministic jitter seeded by
// (server key, variant). Same (server, variant) pair always gets the SAME
// jitter, so the test and the real connection use identical byte counts.
String _natApplySniSwap(String cfg, String rawSni) {
  try {
    final sni = _natNormalizeSniHostname(rawSni);
    if (sni == null) return cfg;
    final j = jsonDecode(cfg);
    if (j is! Map<String, dynamic>) return cfg;
    // Change only the actual proxy outbound; unrelated TLS outbounds retain
    // their own server names and routing semantics.
    final proxy = _natProxyOut(j);
    if (proxy == null) return cfg;
    final st = proxy['streamSettings'];
    if (st is! Map || st['security'] != 'tls') return cfg;
    final tls = st['tlsSettings'];
    if (tls is! Map || tlsHasEch(tls)) return cfg;
    tls['serverName'] = sni; // certificate validation remains enabled
    return jsonEncode(j);
  } catch (_) {
    return cfg;
  }
}

String _natFrag(String cfg, int fi,
    {bool noise = false, int noiseK = 0, int seed = 0}) {
  if (fi < 0 || fi >= _natFrags.length) return cfg;
  final p = _natFrags[fi];

  final rnd = Random(seed ^ (fi << 8) ^ (noiseK << 16));
  String jitter(String range, int maxShift) {
    final dash = range.indexOf('-');
    if (dash < 0) return range;
    final a = int.tryParse(range.substring(0, dash));
    final b = int.tryParse(range.substring(dash + 1));
    if (a == null || b == null) return range;
    final shift = rnd.nextInt(2 * maxShift + 1) - maxShift;
    final na = (a + shift).clamp(1, 1400);
    final nb = (b + shift).clamp(na + 1, 1500);
    return '$na-$nb';
  }

  final lengthRange = jitter(p[0], 6);
  final intervalRange = jitter(p[1], 3);

  try {
    final j = jsonDecode(cfg);
    if (j is! Map<String, dynamic>) return cfg;
    final outs = (j['outbounds'] as List?) ?? <dynamic>[];
    final proxy = _natProxyOut(j);
    if (proxy == null) return cfg;
    final st = proxy['streamSettings'];
    if (st is! Map) return cfg;
    final sec = (st['security'] ?? 'none').toString();
    if (sec != 'tls' && sec != 'reality') return cfg;
    outs.removeWhere((o) => o is Map && o['tag'] == 'frag-out');
    final set = <String, dynamic>{
      'fragment': {
        'packets': p[2],
        'length': lengthRange,
        'interval': intervalRange,
      }
    };
    if (noise) {
      final nz = _natNoises[noiseK % _natNoises.length];
      set['noises'] = [
        {'type': 'rand', 'packet': nz[0], 'delay': nz[1]}
      ];
    }
    outs.add({'tag': 'frag-out', 'protocol': 'freedom', 'settings': set});
    final so = st['sockopt'] is Map ? st['sockopt'] as Map : <String, dynamic>{};
    so['dialerProxy'] = 'frag-out';
    st['sockopt'] = so;
    j['outbounds'] = outs;
    return jsonEncode(j);
  } catch (e, stk) {
    logError(e, stk);
    return cfg;
  }
}

String _natMux(String cfg, [int n = 0]) {
  try {
    final j = jsonDecode(cfg);
    if (j is! Map<String, dynamic>) return cfg;
    final o = _natProxyOut(j);
    if (o == null) return cfg;
    if (_isWorkerOutbound(o)) return cfg; // MUXWORKER
    if (RegExp(r'"flow"\s*:\s*"xtls').hasMatch(cfg)) return cfg;
    o['mux'] = {'enabled': true, 'concurrency': n > 0 ? n : 16};
    return jsonEncode(j);
  } catch (e, stk) {
    logError(e, stk);
    return cfg;
  }
}

// V7-DNS: the core resolves names through a CHAIN of DNS servers. The primary
// DoH comes first; if it is blocked, Cloudflare and Google DoH come next; plain
// IP DNS is the last resort. A single blocked DoH never breaks resolution.
String _natDns(String cfg, String doh) {
  try {
    final j = jsonDecode(cfg);
    if (j is! Map<String, dynamic>) return cfg;
    final d = j['dns'] is Map ? j['dns'] as Map : <String, dynamic>{};
    final servers = <String>[];
    void add(String s) {
      if (s.isNotEmpty && !servers.contains(s)) servers.add(s);
    }
    // DNSNAT: بهترین DNSهای داخلی که اسکن خودکار پیدا کرده اول می‌آیند
    for (final x in dnsxBestCache) {
      add(x);
    }
    // DNSNAT: DNSهای داخلی ثابت پروژه قبل از DNSهای خارجی (که در نت ملی جواب نمی‌دهند)
    for (final x in _natDnsList) {
      if (!x.startsWith('https')) add(x);
    }
    add(doh);
    add('https+local://1.1.1.1/dns-query');
    add('https+local://8.8.8.8/dns-query');
    add('1.1.1.1');
    add('8.8.8.8');
    add('localhost');
    d['servers'] = servers;
    j['dns'] = d;
    return jsonEncode(j);
  } catch (e, stk) {
    logError(e, stk);
    return cfg;
  }
}

String _natSock(String cfg,
    {bool v4 = false, bool tfo = false, bool nodelay = false, int? keep, int? mss}) {
  try {
    final j = jsonDecode(cfg);
    if (j is! Map<String, dynamic>) return cfg;
    final o = _natProxyOut(j);
    if (o == null) return cfg;
    final st = o['streamSettings'];
    if (st is! Map) return cfg;
    final so = st['sockopt'] is Map ? st['sockopt'] as Map : <String, dynamic>{};
    if (tfo) so['tcpFastOpen'] = true;
    if (nodelay) so['tcpNoDelay'] = true;
    if (keep != null) so['tcpKeepAliveInterval'] = keep;
    if (mss != null) so['tcpMaxSeg'] = mss;
    if (v4) so['domainStrategy'] = 'UseIPv4';
    st['sockopt'] = so;
    return jsonEncode(j);
  } catch (e, stk) {
    logError(e, stk);
    return cfg;
  }
}

String natCfg(Server s, int v, {bool reuse = false}) =>
    _stripWorkerMux(sanitizeCfg(_natCfgRaw(s, v, reuse: reuse)));

// MUXWORKER: هر حالت (عادی و نت ملی) هنگام شروع هسته از این مسیر می‌گذرد.
// برای کانفیگ Worker کلودفلر mux باید خاموش باشد، در هر حالتی.
String _stripWorkerMux(String cfg) {
  try {
    final j = jsonDecode(cfg);
    if (j is! Map<String, dynamic>) return cfg;
    final outs = j['outbounds'];
    if (outs is! List) return cfg;
    var changed = false;
    for (final o in outs) {
      if (o is! Map) continue;
      if (o['protocol'] != 'vless' && o['protocol'] != 'vmess') continue;
      if (!_isWorkerOutbound(o)) continue;
      // حتی اگر mux در JSON نباشد، صریحاً خاموش می‌شود
      o['mux'] = {'enabled': false, 'concurrency': -1};
      changed = true;
    }
    return changed ? jsonEncode(j) : cfg;
  } catch (e, stk) {
    logError(e, stk);
    return cfg;
  }
}

String _natCfgRaw(Server s, int v, {bool reuse = false}) {
  var cfg = buildCoreConfig(_natLinkFor(s, v, reuse: reuse));
  if (v <= 0 || v >= _natSpecs.length) {
    return _natSmartSni(cfg, s, forceAll: sniSpoofAll);
  }
  final x = _natSpecs[v];
  if (x.frag != null) {
    // V7-FRAG: seed = server key hash XOR variant number.
    cfg = _natFrag(cfg, x.frag!,
        noise: x.noise, noiseK: x.noiseK, seed: s.key.hashCode ^ v);
  }
  if (x.mux) cfg = _natMux(cfg, x.muxN);
  if (x.doh != null) cfg = _natDns(cfg, x.doh!);
  if (x.v4 || x.tfo || x.nodelay || x.keep != null || x.mss != null) {
    cfg = _natSock(cfg,
        v4: x.v4, tfo: x.tfo, nodelay: x.nodelay, keep: x.keep, mss: x.mss);
  }
  if (x.sniSwap != null) cfg = _natApplySniSwap(cfg, x.sniSwap!);
  return cfg;
}

// V13/V16: automatically apply SNI swap if the host is workers.dev
// (always), or any CDN host when sniSpoofAll is on (V16).
String _natSmartSni(String cfg, Server s, {bool forceAll = false}) {
  try {
    final h = s.host.toLowerCase();
    final isWorker = h.endsWith('workers.dev') || h.endsWith('pages.dev');
    // SNICF: کلودفلر (workers.dev/pages.dev یا IP کلودفلر) فقط با sniCfOn؛ بقیه‌ی CDNها با sniSpoofAll
    final isCf = isWorker || _isCfIp(h);
    final isCdn = isCf || s.cdn;
    if (!s.tls && !s.reality) return cfg;
    if (!isCdn) return cfg;
    if (isCf) {
      if (!sniCfOn) return cfg;
    } else if (!forceAll) {
      return cfg;
    }
    final j = jsonDecode(cfg);
    if (j is! Map<String, dynamic>) return cfg;
    final outs = (j['outbounds'] as List?) ?? <dynamic>[];
    for (final o in outs) {
      if (o is! Map) continue;
      final st = o['streamSettings'];
      if (st is! Map || st['security'] != 'tls') continue;
      final tls = st['tlsSettings'];
      if (tls is! Map) continue;
      if (tlsHasEch(tls)) continue;
      tls['serverName'] = 'cdnjs.cloudflare.com';
      tls['allowInsecure'] = true;
    }
    return jsonEncode(j);
  } catch (_) { return cfg; }
}

int natSafeVariant(int v) {
  if (v < 0) return 0;
  if (v >= _natSpecs.length) return 0;
  return v;
}
int natVarFor(Server s) {
  // NATONLYVAR: اتصال عادی هیچ حالتی (fp / Fragment / نردبان) ندارد؛ فقط نت ملی
  if (!nationalMode) return 0;
  final rawV = natVar[_nk(s)] ?? 0;
  final v = natSafeVariant(rawV);
  if (v <= 0) return 0;
  final x = _natSpecs[v];
  if (x.mux || x.noise) return 0;
  if (x.mode != null && !x.mode!.startsWith('kcp:')) return 0;
  return v;
}

bool natIsHeavy(int v) {
  final base = v % _natCodeBase;
  if (base <= 0 || base >= _natSpecs.length) return false;
  final x = _natSpecs[base];
  return x.frag != null || x.noise || (x.mode != null && x.mode!.startsWith('kcp:'));
}

int? natSpeedVariant(Server s, {int prefer = 0}) {
  final f = _NatFacts(s);
  final known = natVar[_nk(s)];
  if (known != null &&
      !natIsHeavy(known) &&
      _natAppliesF(f, known % _natCodeBase)) {
    return known % _natCodeBase;
  }
  final cand = <int>[0, 1, 4, 13, 7, 20, 12, 33, 38, 40];
  for (final w in _natTopWinners(8)) {
    if (!cand.contains(w)) cand.add(w);
  }
  for (final v in cand) {
    if (v == prefer) continue;
    if (natIsHeavy(v)) continue;
    if (_natAppliesF(f, v)) return v;
  }
  for (var i = 0; i < _natBaseCount; i++) {
    if (i == prefer) continue;
    if (!natIsHeavy(i) && _natAppliesF(f, i)) return i;
  }
  return null;
}

const List<String> _dohEps = [
  'https://1.1.1.1/dns-query?name=%N&type=A',
  'https://8.8.8.8/resolve?name=%N&type=A',
  'https://1.0.0.1/dns-query?name=%N&type=A',
  'https://9.9.9.9:5053/dns-query?name=%N&type=A',
  'https://[2606:4700:4700::1111]/dns-query?name=%N&type=A',
  'https://[2001:4860:4860::8888]/resolve?name=%N&type=A',
  'https://[2606:4700:4700::1111]/dns-query?name=%N&type=AAAA',
  'https://[2001:4860:4860::8888]/resolve?name=%N&type=AAAA',
  'https://1.1.1.1/dns-query?name=%N&type=AAAA',
  'https://8.8.8.8/resolve?name=%N&type=AAAA',
  'https://1.0.0.1/dns-query?name=%N&type=AAAA',
  'https://9.9.9.9:5053/dns-query?name=%N&type=AAAA',
  'https://[2620:fe::fe]/dns-query?name=%N&type=A',
  'https://[2620:fe::fe]/dns-query?name=%N&type=AAAA',
];

String natOpKey = 'x';
final Map<String, String> _natAsnByType = {};
final Map<String, DateTime> _natAsnTry = {};

Future<String> _natNetType() async {
  try {
    final l = await NetworkInterface.list(includeLoopback: false);
    var wifi = false, mob = false;
    for (final i in l) {
      if (i.addresses.isEmpty) continue;
      final n = i.name.toLowerCase();
      if (n.startsWith('wlan') || n.startsWith('wifi')) {
        wifi = true;
      } else if (n.contains('rmnet') ||
          n.startsWith('ccmni') ||
          n.startsWith('pdp')) {
        mob = true;
      }
    }
    return wifi ? 'wifi' : (mob ? 'mob' : 'net');
  } catch (e, stk) {
    logError(e, stk);
    return 'net';
  }
}

Future<String?> _natAsnFrom(String url, String field) async {
  final c = HttpClient()
    ..findProxy = ((_) => 'DIRECT')
    ..connectionTimeout = const Duration(seconds: 3);
  try {
    final req =
        await c.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 3));
    final res = await req.close().timeout(const Duration(seconds: 3));
    final body =
        await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 3));
    final t = body.trimLeft();
    if (!t.startsWith('{')) return null;
    final j = jsonDecode(t);
    if (j is! Map) return null;
    final raw = '${j[field] ?? ''}';
    final m = RegExp(r'(\d{3,7})').firstMatch(raw);
    return m?.group(1);
  } catch (e, stk) {
    logError(e, stk);
    return null;
  } finally {
    c.close(force: true);
  }
}

Future<void> natDetectOperator() async {
  try {
    final type = await _natNetType();
    final tried = _natAsnTry[type];
    final stale = tried == null ||
        DateTime.now().difference(tried) > const Duration(minutes: 10);
    var asn = stale ? '' : (_natAsnByType[type] ?? '');
    if (stale) {
      _natAsnTry[type] = DateTime.now();
      final r = await Future.wait([
        _natAsnFrom('http://ip-api.com/json/?fields=as', 'as'),
        _natAsnFrom('https://ipinfo.io/json', 'org'),
        _natAsnFrom('https://api.ip.sb/geoip', 'asn'),
      ]);
      var fresh = '';
      for (final x in r) {
        if (x != null && x.isNotEmpty) {
          fresh = x;
          break;
        }
      }
      if (fresh.isNotEmpty) {
        asn = fresh;
        _natAsnByType[type] = asn;
      } else {
        asn = _natAsnByType[type] ?? '';
      }
    }
    final k = asn.isEmpty ? type : '$type|AS$asn';
    if (k != natOpKey) {
      natOpKey = k;
      dbg('شبکه/اپراتور: $k');
    }
  } catch (e, stk) { logError(e, stk); }
}

final Map<String, int> natWins = {};
Timer? _natSaveT;

final Map<int, int> natTryCount = {};
final Map<int, int> natWinCount = {};

String _nk(Server s) => '$natOpKey#${s.key}';

void natVarSet(Server s, int v) {
  natVar.remove(_nk(s));
  natVar[_nk(s)] = v;
  final wk = '$natOpKey#$v';
  natWins[wk] = (natWins[wk] ?? 0) + 1;
  _natWinsVer++; // TOPWIN: کش برترین‌ها را باطل کن
  if (v > 0 && v < _natSpecs.length) {
    final hb = DateTime.now().hour ~/ 3; // V13: 3-hour bucket (0-7)
    for (final d in _natDims(_natSpecs[v])) {
      final dk = '$natOpKey#$d';
      natDimWins[dk] = (natDimWins[dk] ?? 0) + 1;
      final hk = '$natOpKey#h$hb#$d';
      natDimWins[hk] = (natDimWins[hk] ?? 0) + 1;
    }
    _natLearnVer++;
  }
  _natCursor.remove(_natCk(s));
  if (natDimWins.length > 6000) natDimWins.remove(natDimWins.keys.first);
  while (natVar.length > 4000) {
    natVar.remove(natVar.keys.first);
  }
  _natSaveT ??= Timer(const Duration(seconds: 5), () {
    _natSaveT = null;
    natSavePersisted();
  });
}

// NORMALCACHE: زمان‌بندی ذخیره‌ی debounced از بیرون هم قابل صداست
void natSaveSoon() {
  _natSaveT ??= Timer(const Duration(seconds: 5), () {
    _natSaveT = null;
    natSavePersisted();
  });
}

Future<void> natSavePersisted() async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString('natvar2',
        jsonEncode({
          'v': natVar,
          'w': natWins,
          'd': natDimWins,
          'g': _natGenVer,
          'n': natVarNormal, // NORMALCACHE: پایدار بین session‌ها
        }));
  } catch (e, stk) {
    logError(e, stk);
  }
}

// NATLOADED-ONCE: natLoadPersisted runs from _loadCache and again from _natDetect;
// only the first run is needed.
bool _natPersistedLoaded = false;

Future<void> natLoadPersisted() async {
  if (_natPersistedLoaded) return;
  _natPersistedLoaded = true; // NATLOADED-ONCE: set before any await
  await plusLoad();
  await natIpMemLoad();
  await natDomMemLoad();
  await userListsLoad();
  try {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('natvar2');
    if (s == null) return;
    final j = jsonDecode(s);
    (j['v'] as Map).forEach((k, v) => natVar['$k'] = (v as num).toInt());
    (j['w'] as Map).forEach((k, v) => natWins['$k'] = (v as num).toInt());
    _natWinsVer++; // TOPWIN
    final d = j['d'];
    if (d is Map) {
      d.forEach((k, v) => natDimWins['$k'] = (v as num).toInt());
    }
    // NORMALCACHE: بازیابی variant موفق حالت عادی
    final nMap = j['n'];
    if (nMap is Map) {
      natVarNormal.clear();
      nMap.forEach((k, v) {
        if (v is num) {
          final val = v.toInt();
          if (val > 0 && val < _natSpecs.length) {
            // NORMALKEY-MIGRATION: old keys were 'operator#host:port'; drop the prefix.
            var key = '$k';
            final hash = key.indexOf('#');
            if (hash >= 0) key = key.substring(hash + 1);
            natVarNormal[key] = val;
          }
        }
      });
      while (natVarNormal.length > 3000) {
        natVarNormal.remove(natVarNormal.keys.first);
      }
    }
    if (((j['g'] ?? 0) as num).toInt() != _natGenVer) {
      natVar.removeWhere((k, v) => v >= _natBaseCount);
      _natWinsVer++; // TOPWIN
      natWins.removeWhere((k, v) {
        final n = int.tryParse(k.substring(k.lastIndexOf('#') + 1));
        return n != null && n >= _natBaseCount;
      });
    }
    _natLearnVer++;
  } catch (e, stk) {
    logError(e, stk);
  }
}

const String _ipMemKey = 'natIpMem';
const String _rangeKey = 'natRanges';
const int _ipMemMax = 200;

final List<Map<String, dynamic>> natIpMem = [];
final Set<String> natIpDeadRun = {};
List<String> natRanges = [];
int natRangeCursor = 0; // generic range cursor
int _natConfiguredRangeCursor = 0; // next range index for fair round-robin coverage
final Map<String, dynamic> _natConfiguredRangeOffsets = {}; // per-range address cursor
DateTime natRangeLast = DateTime.fromMillisecondsSinceEpoch(0);

Set<String> natIpMemHosts() => {for (final e in natIpMem) '${e['ip']}'};

Future<void> natIpMemLoad() async {
  try {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_ipMemKey);
    if (s != null) {
      natIpMem
        ..clear()
        ..addAll((jsonDecode(s) as List).cast<Map<String, dynamic>>());
      final cutoff = DateTime.now()
          .subtract(const Duration(days: 14))
          .millisecondsSinceEpoch;
      natIpMem.removeWhere((e) => ((e['t'] as num?)?.toInt() ?? 0) < cutoff);
    }
    natRanges = (p.getString(_rangeKey) ?? '')
        .split(RegExp(r'[\r\n,; ]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .where((value) => natExpandIpRangeCursor(
              value,
              '0',
              maxPerBlock: 1,
              wrap: false,
            ).addresses.isNotEmpty)
        .toList(growable: false);
    _natConfiguredRangeCursor = (p.getInt('natConfiguredRangeCursor') ?? 0).clamp(0, 1 << 31).toInt();
    _natConfiguredRangeOffsets.clear();
    final savedOffsets = p.getString('natConfiguredRangeOffsetsV1');
    if (savedOffsets != null && savedOffsets.isNotEmpty) {
      try {
        final decoded = jsonDecode(savedOffsets);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.value is num || entry.value is String) {
              _natConfiguredRangeOffsets['${entry.key}'] = '${entry.value}';
            }
          }
        }
      } catch (e, stk) {
        logError(e, stk);
      }
    }
  } catch (e, stk) {
    logError(e, stk);
  }
}

const String _domMemKey = 'natDomMem';
const int _domMemMax = 200;
const int natDelaySecs = 14;
final List<Map<String, dynamic>> natDomMem = [];

Set<String> natDomMemHosts() => {for (final e in natDomMem) '${e['h']}:${e['port']}'};

Future<void> natDomMemLoad() async {
  try {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_domMemKey);
    if (s != null) {
      natDomMem
        ..clear()
        ..addAll((jsonDecode(s) as List).cast<Map<String, dynamic>>());
      final cutoff = DateTime.now()
          .subtract(const Duration(days: 14))
          .millisecondsSinceEpoch;
      natDomMem.removeWhere((e) => ((e['t'] as num?)?.toInt() ?? 0) < cutoff);
    }
  } catch (e, stk) {
    logError(e, stk);
  }
}

Future<void> natDomMemSave(String host, int port) async {
  natDomMem.removeWhere((e) => e['h'] == host && e['port'] == port);
  natDomMem.insert(0, {'h': host, 'port': port, 't': DateTime.now().millisecondsSinceEpoch});
  if (natDomMem.length > _domMemMax) {
    natDomMem.removeRange(_domMemMax, natDomMem.length);
  }
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(_domMemKey, jsonEncode(natDomMem));
  } catch (e, stk) {
    logError(e, stk);
  }
}

Future<bool> natIpMemSaveMany(Iterable<String> ips, int port) async {
  final values = ips.toSet().toList(growable: false);
  if (values.isEmpty) return true;
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  for (final ip in values.reversed) {
    natIpMem.removeWhere((entry) => entry['ip'] == ip && entry['port'] == port);
    natIpMem.insert(0, {'ip': ip, 'port': port, 't': timestamp});
  }
  if (natIpMem.length > _ipMemMax) {
    natIpMem.removeRange(_ipMemMax, natIpMem.length);
  }
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ipMemKey, jsonEncode(natIpMem));
    return true;
  } catch (e, stk) {
    logError(e, stk);
    return false;
  }
}

Future<void> natIpMemSave(String ip, int port) async {
  natIpMem.removeWhere((e) => e['ip'] == ip && e['port'] == port);
  natIpMem.insert(0, {'ip': ip, 'port': port, 't': DateTime.now().millisecondsSinceEpoch});
  if (natIpMem.length > _ipMemMax) {
    natIpMem.removeRange(_ipMemMax, natIpMem.length);
  }
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(_ipMemKey, jsonEncode(natIpMem));
  } catch (e, stk) {
    logError(e, stk);
  }
}


/// Next bounded, fair sample from every configured National Net range.
/// Range rotation and per-range address offsets prevent large early ranges from
/// starving later entries; memory stays proportional to the requested batch.
({List<String> addresses, int nextCursor, Map<String, dynamic> nextOffsets})
    _natConfiguredRangeBatch(
  int limit, {
  Map<String, dynamic>? initialOffsets,
  int? startCursor,
}) {
  final offsets = Map<String, dynamic>.of(
    initialOffsets ?? _natConfiguredRangeOffsets,
  );
  if (limit <= 0 || natRanges.isEmpty) {
    return (
      addresses: const <String>[],
      nextCursor: _natConfiguredRangeCursor,
      nextOffsets: offsets,
    );
  }

  final start = natCursorIndex(startCursor ?? _natConfiguredRangeCursor, natRanges.length);
  final activeRanges = min(limit, natRanges.length).toInt();
  final perRange = max(1, (limit + activeRanges - 1) ~/ activeRanges).toInt();
  final candidates = <String>{};
  var scanned = 0;
  var visited = 0;

  while (visited < natRanges.length && scanned < limit) {
    final index = (start + visited) % natRanges.length;
    final range = natRanges[index];
    final quota = min(perRange, limit - scanned).toInt();
    final expanded = _natExpandAnyCursorWide(
      range,
      offsets[range] ?? 0,
      quota,
    );
    if (expanded.$1.isNotEmpty) {
      candidates.addAll(expanded.$1);
      offsets[range] = expanded.$2;
      scanned += expanded.$1.length;
    }
    visited++;
  }

  // Commit both cursors only after the corresponding network scan succeeds.
  return (
    addresses: candidates.toList(growable: false),
    nextCursor: (start + max(1, visited).toInt()) % natRanges.length,
    nextOffsets: offsets,
  );
}

Future<void> natRangesSave(String text) async {
  natRanges = text
      .split(RegExp(r'[\r\n,; ]+'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .where((value) => natExpandIpRangeCursor(
            value,
            '0',
            maxPerBlock: 1,
            wrap: false,
          ).addresses.isNotEmpty)
      .toList(growable: false);
  _natConfiguredRangeCursor = 0;
  _natConfiguredRangeOffsets.clear();
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(_rangeKey, natRanges.join('\n'));
    await p.setInt('natConfiguredRangeCursor', 0);
    await p.setString('natConfiguredRangeOffsetsV1', '{}');
  } catch (e, stk) {
    logError(e, stk);
  }
}

/// Fast first-pass shortlist for manual IP checks. This is not the exhaustive
/// background scan's port filter; natRangeScanStep uses natFullPortInventory.
const List<int> natCommonPorts = [
  443, 2053, 2083, 2087, 2096, 8443, 80, 8080, 8880, 2052, 2082, 2086, 2095,
  8444, 9443, 4443, 5443, 6443, 7443, 10443, 2222, 8000, 8008, 8888, 3128, 1080,
];

List<int> natAutoPorts(List<Server> known) {
  final cnt = <int, int>{};
  for (final s in known) {
    if (s.port > 0 && s.port < 65536) cnt[s.port] = (cnt[s.port] ?? 0) + 1;
  }
  for (final e in natIpMem) {
    final p = (e['port'] as num?)?.toInt() ?? 0;
    if (p > 0 && p < 65536) cnt[p] = (cnt[p] ?? 0) + 5;
  }
  final ports = natStableSorted<int>(
      cnt.keys, (x, y) => cnt[y]! - cnt[x]!);
  final out = <int>[...ports];
  for (final p in natCommonPorts) {
    if (!out.contains(p)) out.add(p);
  }
  return out;
}

/// Complete port sweep for the resumable NAT range scanner.
/// Observed ports and common ports are priorities, never exclusions.
List<int> natFullPortInventory(List<Server> known) {
  final counts = <int, int>{};
  for (final server in known) {
    if (server.port > 0 && server.port <= 65535) {
      counts[server.port] = (counts[server.port] ?? 0) + 1;
    }
  }
  for (final entry in natIpMem) {
    final port = (entry['port'] as num?)?.toInt() ?? 0;
    if (port > 0 && port <= 65535) {
      counts[port] = (counts[port] ?? 0) + 5;
    }
  }
  final observed = natStableSorted<int>(
    counts.keys,
    (a, b) => counts[b]! - counts[a]!,
  );
  return natBuildFullPortInventory(
    [...observed, ...natCommonPorts],
    firstPort: 1, // TCP connect() cannot target port zero.
    lastPort: 65535,
  );
}

List<int>? _ipTriple(String host) {
  final p = host.split('.');
  if (p.length != 4 || InternetAddress.tryParse(host) == null) return null;
  return [for (final x in p.take(3)) int.parse(x)];
}

/// Candidate inventory only: retain exact observed/configured IPs.
/// A remembered public address does not authorize probing its neighbouring /24.
/// Wider prefixes must come from an explicitly supplied range or an authorized
/// range source, not be inferred from a single endpoint.
List<String> natAutoBlocks(List<Server> known) {
  // A neighboring prefix must not be inferred from a single endpoint.
  final out = <String>{};
  for (final entry in natIpMem) {
    final parsed = InternetAddress.tryParse('${entry['ip']}');
    if (parsed == null) continue;
    if (parsed.type == InternetAddressType.IPv4 ||
        parsed.type == InternetAddressType.IPv6) {
      out.add('${parsed.address}/${parsed.type == InternetAddressType.IPv6 ? 128 : 32}');
    }
  }
  for (final server in known) {
    final parsed = InternetAddress.tryParse(server.host.trim());
    if (parsed == null) continue;
    if (parsed.type == InternetAddressType.IPv4 ||
        parsed.type == InternetAddressType.IPv6) {
      out.add('${parsed.address}/${parsed.type == InternetAddressType.IPv6 ? 128 : 32}');
    }
  }
  return out.toList()..sort();
}

BigInt _natIpv6ToBigInt(InternetAddress address) {
  var value = BigInt.zero;
  for (final byte in address.rawAddress) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}


int _ipToInt(String ip) {
  final p = ip.split('.').map(int.parse).toList();
  return (p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3];
}

String _intToIp(int v) =>
    '${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}';

List<String> natExpandAny(String item, {int maxPerBlock = 65536}) {
  if (maxPerBlock <= 0) return const [];
  return _natExpandAnyCursorWide(item, '0', maxPerBlock).$1;
}

const List<String> natIranDnsHosts = [
  '178.22.122.100', '185.51.200.2', '78.157.42.100', '78.157.42.101',
  '10.202.10.10', '10.202.10.11',
];

const List<String> natIrDomains = [
  'irna.ir', 'isna.ir', 'irib.ir', 'snapp.ir', 'divar.ir', 'iran.ir',
  'gov.ir', 'mci.ir', 'ut.ac.ir', 'bmi.ir', 'tci.ir', 'ict.gov.ir',
  'tehran.ir', 'mashhad.ir', 'isfahan.ir', 'shiraz.ir', 'tabriz.ir',
  'bsi.ir', 'ir-ms.ir', 'konkur-hesabdari.blog.ir', 'khoshenevis.blog.ir',
  'kerman-econtent.blog.ir', 'karunposter.blog.ir', 'kaliuser.blog.ir',
  'kafeserial.blog.ir', 'jooshkarii.blog.ir', 'gholamreza-test.blog.ir',
  'ghalamchi-gaj-gozinedo-sanjesh.blog.ir', 'gardeshgari2.blog.ir',
  'gamepersian.blog.ir', 'game-star.blog.ir', 'funtab.blog.ir',
  'thermocouple.blog.ir', 'thematic-commentary-quran.blog.ir',
  'testdownload.blog.ir', 'telecomp.blog.ir', 'technology-articles.blog.ir',
  'tblabkhand.blog.ir', 'maroon.blog.ir', 'majestic.blog.ir',
  'majalemashin.blog.ir', 'majaleie-sanati.blog.ir', 'mahdikeikha.blog.ir',
  'm-a-amjadi.blog.ir', 'lyrics4u.blog.ir', 'hesare-aseman.blog.ir',
  'hesabdaritosee.blog.ir', 'hello.blog.ir', 'helli5school.blog.ir',
  'heiatozahra.blog.ir', 'heiat-graph.blog.ir', 'hedeshamlak.blog.ir',
  'pmis1.blog.ir', 'f-p-c.blog.ir', 'explosionproof.blog.ir',
  'exceliran.blog.ir', 'evermotion3d.blog.ir', 'esfahanrepair.blog.ir',
  'erfaneabjad.blog.ir', 'galebbeton-sabbagi-tabriz.blog.ir',
  'freepikdl.blog.ir', 'doorbin123.blog.ir', 'chini1.blog.ir',
  'breachgame.blog.ir', 'berozbash.blog.ir', 'capitan-irani-pilot.blog.ir',
  'calisthenics.blog.ir', 'c2soundgm.blog.ir', 'buysellscorpions.blog.ir',
  'businesssoftware.blog.ir', 'bourseban.blog.ir', 'farsijani.blog.ir',
  'farsi-kawthar-ilc.blog.ir', 'farshidjanati.blog.ir',
  'fardadfariba.blog.ir', 'fakkar.blog.ir', 'computermiyandoab.blog.ir',
  'yousha.blog.ir', 'youfiles.blog.ir', 'yaddasht1.blog.ir',
  'worldwisdom.blog.ir', 'world-music.blog.ir', 'withtech.blog.ir',
  'wiring.blog.ir', 'wikilib.blog.ir', 'bestmuzic.blog.ir', 'ben20.blog.ir',
  'behdadteb.blog.ir', 'bearing1.blog.ir', 'bazibebazi.blog.ir',
  'bankmoshtari.blog.ir', 'bache-heiaty.blog.ir', 'ebpnovin.blog.ir',
  'drtandorosti.blog.ir', 'drmortezaheidari.blog.ir', 'downloadicon.blog.ir',
  'downloadfile98.blog.ir', 'downloadbookpdfketab2.blog.ir', 'time.ir',
  'imna.ir',
];

Future<List<String>> _natDomainFirst(List<Server> known,
    {required int conc, bool Function()? stop}) async {
  final out = <String>[];
  if (!kNatIpScanOn || known.isEmpty) return out;
  // Bound endpoint collection, DNS resolution, and TCP probes together.
  // Starting the monotonic clock only after DNS resolution allowed a slow
  // resolver to keep this background phase alive far beyond its advertised cap.
  const scanBudget = Duration(seconds: 45);
  final scanClock = Stopwatch()..start();
  bool expired() => scanClock.elapsed >= scanBudget;
  bool cancelled() => (stop != null && stop()) || expired();
  try {
    // Only inspect hosts and ports explicitly present in the user's/current
    // server configurations. Do not scan unrelated public domains or all
    // 65,535 ports on third-party hosts.
    final endpoints = <String, Set<int>>{};
    for (final server in known) {
      if (cancelled()) return const <String>[];
      final host = server.host.trim();
      final port = server.port;
      if (host.isEmpty || port <= 0 || port > 65535) continue;
      (endpoints[host] ??= <int>{}).add(port);
    }
    natDomainHosts = endpoints.length;
    final resolved = <String, Set<int>>{};
    for (final entry in endpoints.entries) {
      if (cancelled()) return const <String>[];
      final parsed = InternetAddress.tryParse(entry.key);
      var addresses = parsed == null
          ? await safeLookup(entry.key)
          : <InternetAddress>[parsed];
      if (addresses.isEmpty && !NatNetworkDiagnosis.preferDomestic) {
        final dohAddresses = await dohResolveAll(entry.key);
        addresses = dohAddresses
            .map(InternetAddress.tryParse)
            .whereType<InternetAddress>()
            .toList(growable: false);
      }
      if (cancelled()) return const <String>[];
      for (final address in addresses) {
        if (address.type != InternetAddressType.IPv4 &&
            address.type != InternetAddressType.IPv6) continue;
        (resolved[address.address] ??= <int>{}).addAll(entry.value);
      }
    }
    natDomainIps = resolved.length;
    natDomainOpen = 0;
    dbg('بررسی endpointهای کانفیگ: ${endpoints.length} دامنه/IP • ${resolved.length} IP • فقط پورت‌های تعریف‌شده');
    final grouped = <int, List<String>>{};
    for (final entry in resolved.entries) {
      for (final port in entry.value) {
        (grouped[port] ??= <String>[]).add(entry.key);
      }
    }
    for (final entry in grouped.entries) {
      if (cancelled()) {
        return const <String>[];
      }
      final hits = await natScanIps(
        entry.value,
        port: entry.key,
        concurrency: conc.clamp(1, 32).toInt(),
        // Probe every resolved endpoint in this port group; the shared 45s
        // deadline and adaptive concurrency bound the discovery phase.
        want: entry.value.length,
        budget: const Duration(seconds: 5),
        timeout: const Duration(milliseconds: 1200),
        cancelled: cancelled,
      );
      // A cancelled or expired scan must not leak its partial hits to the
      // caller, which may otherwise persist them as newly discovered servers.
      if (cancelled()) {
        return const <String>[];
      }
      for (final hit in hits) {
        out.add('${hit.ip}|${entry.key}');
        natDomainOpen = out.length;
      }
    }
    if (cancelled()) {
      return const <String>[];
    }
  } catch (e, stk) {
    logError(e, stk);
  }
  // Exceptions can race the deadline/cancel signal too; never return a partial
  // result set once the caller has invalidated this discovery batch.
  if (cancelled()) return const <String>[];
  return out;
}

Future<List<String>> natDeviceHosts() async {
  final out = <String>[];
  try {
    final interfaces = await NetworkInterface.list(includeLoopback: false);
    for (final i in interfaces) {
      for (final a in i.addresses) {
        final h = a.address;
        if (a.type == InternetAddressType.IPv6) {
          if (_privateIp(a)) continue;
          if (!out.contains(h)) out.add(h);
          continue;
        }
        if (a.type != InternetAddressType.IPv4) continue;
        final p = h.split('.').map(int.tryParse).toList();
        if (p.length != 4 || p.any((x) => x == null)) continue;
        final private = p[0] == 10 ||
            p[0] == 127 ||
            (p[0] == 172 && p[1]! >= 16 && p[1]! <= 31) ||
            (p[0] == 192 && p[1] == 168) ||
            (p[0] == 100 && p[1]! >= 64 && p[1]! <= 127) ||
            (p[0] == 169 && p[1] == 254);
        if (!private && !out.contains(h)) out.add(h);
      }
    }
  } catch (e, stk) {
    logError(e, stk);
  }
  return out;
}

List<String> natSeedBlocks(List<String> hosts) {
  // Seed discovered IPv4 hosts with their /24 and IPv6 hosts with exact /128s.
  // Do not infer an enormous neighbouring IPv6 /64 from one endpoint.
  final out = <String>{};
  for (final host in hosts) {
    final parsed = InternetAddress.tryParse(host.trim());
    if (parsed == null) continue;
    if (parsed.type == InternetAddressType.IPv6) {
      out.add('${parsed.address}/128');
      continue;
    }
    if (parsed.type != InternetAddressType.IPv4) continue;
    final octets = parsed.address.split('.');
    out.add('${octets[0]}.${octets[1]}.${octets[2]}.0/24');
  }
  return out.toList()..sort();
}

int natMemQueued = 0;
int natRandomLast = 0;
final Set<String> natScanHits = {};
Set<String> natFreshHosts = {};
int natDomainHosts = 0;
int natDomainIps = 0;
int natDomainOpen = 0;

List<Server> natTemplateSeeds = [];

// V7: IP scanning is required by v7 (Layer 1 filter = IP/Port). Set to true.
bool kNatIpScanOn = true;

final Map<String, dynamic> _cfRangeCursors = {};
final Map<String, int> _natRangePortCursors = <String, int>{'nat': 0, 'global': 0};
bool _natRangeCursorsLoaded = false;

Future<void> _natLoadRangeCursors() async {
  if (_natRangeCursorsLoaded) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    // V3 stores the last completed TCP port value, not an index into a
    // changing priority list. Legacy V1/V2 values were indexes and are reset.
    final rawPortCursors = prefs.getString('natRangePortCursorsV3');
    if (rawPortCursors != null && rawPortCursors.isNotEmpty) {
      final decodedPorts = jsonDecode(rawPortCursors);
      if (decodedPorts is Map) {
        for (final entry in decodedPorts.entries) {
          if (entry.value is num) {
            final port = (entry.value as num).toInt();
            if (port >= 0 && port <= 65535) {
              _natRangePortCursors['${entry.key}'] = port;
            }
          }
        }
      }
    }
    final raw = prefs.getString('natRangeScanCursorsV2');
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          if (entry.value is num || entry.value is String) {
            _cfRangeCursors['${entry.key}'] = entry.value;
          }
        }
      }
    }
    _natRangeCursorsLoaded = true;
  } catch (e, stk) {
    logError(e, stk);
  }
}
List<String> _getCfIps({
  int batchSize = 160000,
  List<String>? liveRanges,
  Map<String, dynamic>? cursors,
}) {
  if (cursors == null) unawaited(refreshCdnRanges());
  final out = <String>{};
  final ranges = liveRanges ?? _liveCdnRanges;
  final cursorMap = cursors ?? _cfRangeCursors;
  if (batchSize <= 0 || ranges.isEmpty) return const <String>[];

  // Rotate the starting range on every completed slice. Without this outer
  // cursor, a few huge IPv6/IPv4 CIDRs at the front would starve every later
  // announced range forever, even though each individual range had a cursor.
  final start = natCursorIndex(cursorMap['__cdn_range_cursor'], ranges.length);
  var visited = 0;
  for (; visited < ranges.length && out.length < batchSize; visited++) {
    final index = (start + visited) % ranges.length;
    final range = ranges[index];
    final remaining = batchSize - out.length;
    final rangesLeft = ranges.length - visited;
    final quota = max(1, (remaining + rangesLeft - 1) ~/ rangesLeft);
    final expanded = _natExpandAnyCursorWide(
      range,
      cursorMap[range] ?? 0,
      quota,
    );
    if (expanded.$1.isEmpty) continue;
    out.addAll(expanded.$1);
    cursorMap[range] = expanded.$2;
  }
  if (visited > 0) {
    cursorMap['__cdn_range_cursor'] = (start + visited) % ranges.length;
  }
  return out.toList(growable: false);
}

// 128-bit cursor persistence: IPv6 /0..128 and dash ranges must not be
// narrowed to a platform int. Store their decimal cursor as a JSON string.
(List<String>, String) _natExpandAnyCursorWide(
    String item, Object? cursorValue, int maxPerBlock) {
  final batch = natExpandIpRangeCursor(
    item,
    cursorValue?.toString() ?? '0',
    maxPerBlock: maxPerBlock,
  );
  return (batch.addresses, batch.nextCursor);
}

// فیکس ۳: ساخت رشته‌های IP (صدها هزار تا چند میلیون) از ترد UI به isolate منتقل شد.
// args: {cfIpsBatch:int, blocks:List<String>, nationalMode:bool,
//        liveRanges:List<String>, cursors:Map<String,dynamic> (IPv6 offsets are decimal strings)}
// خروجی: {'addrs': List<String>, 'cursors': Map<String,dynamic>} — cursor به‌روزشده باید
// به ترد اصلی برگردد چون isolate نسخه‌ی کپی را تغییر می‌دهد (بدون آن اسکن هر دور از اول شروع می‌شد).
Map<String, dynamic> _genAddrsIso(Map<String, dynamic> args) {
  final int cfIpsBatch = args['cfIpsBatch'] as int;
  final int cap = max(0, args['maxAddrs'] as int);
  final List<String> blocks = List<String>.from(args['blocks'] as List);
  final bool nationalMode = args['nationalMode'] as bool;
  final List<String> liveRanges = List<String>.from(args['liveRanges'] as List);
  final Map<String, dynamic> cursors = Map<String, dynamic>.from(args['cursors'] as Map);
  final addrs = <String>[];

  // Generate exactly the batch that will be scanned. Cursor advancement and
  // returned addresses therefore describe the same work; no generated tail is lost.
  void addBlocks() {
    if (blocks.isEmpty || addrs.length >= cap) return;
    final start = natCursorIndex(cursors['__block_cursor'], blocks.length);
    var processed = 0;
    for (var offset = 0; offset < blocks.length && addrs.length < cap; offset++) {
      final index = (start + offset) % blocks.length;
      final range = blocks[index];
      final key = 'block:$range';
      final cursor = cursors[key] ?? 0;
      final remaining = cap - addrs.length;
      final rangesLeft = blocks.length - offset;
      final quota = max(1, (remaining + rangesLeft - 1) ~/ rangesLeft);
      final generated = _natExpandAnyCursorWide(range, cursor, quota);
      if (generated.$1.isNotEmpty) {
        addrs.addAll(generated.$1);
        cursors[key] = generated.$2;
      }
      processed++;
    }
    if (processed > 0) {
      cursors['__block_cursor'] = (start + processed) % blocks.length;
    }
  }

  if (nationalMode) {
    final cfBatch = min(cfIpsBatch, cap);
    if (cfBatch > 0) {
      addrs.addAll(_getCfIps(
        batchSize: cfBatch,
        liveRanges: liveRanges,
        cursors: cursors,
      ));
    }
    addBlocks();
  } else {
    addBlocks();
    final remaining = cap - addrs.length;
    if (remaining > 0 && cfIpsBatch > 0) {
      addrs.addAll(_getCfIps(
        batchSize: min(cfIpsBatch, remaining),
        liveRanges: liveRanges,
        cursors: cursors,
      ));
    }
  }
  return {'addrs': addrs, 'cursors': cursors};
}

// RANGEGUARD: یک اسکن بازه در هر لحظه؛ _natKeep و _natEscalate روی cursors مشترک نمی‌نویسند
bool _natRangeScanBusy = false;

Future<List<String>> natRangeScanStep({
  required List<Server> known,
  int maxAddrs = 8192,
  int conc = 4,
  bool Function()? stop,
  Duration budget = const Duration(minutes: 2),
}) async {
  if (_natRangeScanBusy) return const <String>[];
  _natRangeScanBusy = true;
  try {
    return await _natRangeScanStepBody(
        known: known, maxAddrs: maxAddrs, conc: conc, stop: stop, budget: budget);
  } finally {
    _natRangeScanBusy = false;
  }
}

Future<List<String>> _natRangeScanStepBody({
  required List<Server> known,
  int maxAddrs = 2048,
  int conc = 4,
  bool Function()? stop,
  Duration budget = const Duration(minutes: 2),
}) async {
  final modeSnapshot = nationalMode;
  bool shouldAbort() =>
      (stop?.call() ?? false) || nationalMode != modeSnapshot;
  if (!kNatIpScanOn || shouldAbort() || budget <= Duration.zero || maxAddrs <= 0) {
    return const <String>[];
  }

  await _natLoadRangeCursors();
  if (shouldAbort()) return const <String>[];

  // Active probes are scoped to endpoints supplied in the current saved
  // server configurations and explicitly configured address ranges. Historical
  // natIpMem observations and fetched hot-list entries are discovery evidence,
  // not authorization to scan those hosts or their other ports.
  final seeds = known;
  if (shouldAbort()) return const <String>[];
  final hosts = <String>{
    for (final server in seeds)
      if (server.isIp) server.host,
  }.toList(growable: false);
  final blocks = natSeedBlocks(hosts);

  // Explicitly saved IP Clean ranges are an intentional scan scope: rotate
  // through the complete valid TCP port inventory. Exact server IPs outside
  // those ranges are still probed only on their declared endpoint ports.
  final configuredPorts = seeds
      .map((server) => server.port)
      .where((port) => port >= 1 && port <= 65535)
      .toSet();
  final hasExplicitRanges = natRanges.isNotEmpty;
  final portList = natPortsForActiveScan(
    fullInventory: natFullPortInventory(seeds),
    configuredEndpointPorts: configuredPorts,
    hasExplicitRanges: hasExplicitRanges,
  );
  if (portList.isEmpty) return const <String>[];
  final modeKey = modeSnapshot ? 'nat' : 'global';
  final lastPort = _natRangePortCursors[modeKey] ?? 0;
  final previousPortIndex = portList.indexOf(lastPort);
  final portIndex = previousPortIndex < 0
      ? 0
      : (previousPortIndex + 1) % portList.length;
  final port = portList[portIndex];
  final portPrefix = '$modeKey:port:$port:';

  final localCursors = <String, dynamic>{
    for (final entry in _cfRangeCursors.entries)
      if (entry.key.startsWith(portPrefix))
        entry.key.substring(portPrefix.length): entry.value,
  };
  final localOffsets = <String, dynamic>{
    for (final entry in _natConfiguredRangeOffsets.entries)
      if (entry.key.startsWith(portPrefix))
        entry.key.substring(portPrefix.length): entry.value,
  };

  // Choose a batch that can normally finish inside this run's time budget.
  // This is a continuation slice, not a total address-space limit.
  const probeTimeout = Duration(milliseconds: 1500);
  final effectiveConcurrency = natAdaptiveConcurrency(conc);
  final estimatedCapacity = max(
    1,
    (budget.inMilliseconds / probeTimeout.inMilliseconds *
            effectiveConcurrency * 0.65)
        .floor(),
  );
  final scanLimit = min(maxAddrs, estimatedCapacity).toInt();

  final configuredStart =
      int.tryParse(localOffsets['__range_cursor']?.toString() ?? '') ?? 0;
  final configuredBatch = _natConfiguredRangeBatch(
    scanLimit,
    initialOffsets: localOffsets,
    startCursor: configuredStart,
  );
  final configuredRanges = configuredBatch.addresses;

  final args = <String, dynamic>{
    'cfIpsBatch': 0,
    'maxAddrs': max(0, scanLimit - configuredRanges.length),
    'blocks': blocks,
    'nationalMode': modeSnapshot,
    'liveRanges': <String>[],
    'cursors': localCursors,
  };
  Map<String, dynamic> generated = {
    'addrs': const <String>[],
    'cursors': localCursors,
  };
  // The generated block inventory contains exact configured server IPs;
  // never test their undeclared ports merely because a separate range exists.
  if (configuredPorts.contains(port)) {
    generated = await compute(_genAddrsIso, args);
  }
  if (shouldAbort()) return const <String>[];
  final generatedCursors =
      Map<String, dynamic>.from(generated['cursors'] as Map);
  final addresses = <String>{
    ...configuredRanges,
    ...(generated['addrs'] as List).cast<String>(),
  }.toList(growable: false);
  if (addresses.isEmpty) return const <String>[];
  final slice = addresses.take(scanLimit).toList(growable: false);

  // One port per invocation, with an independent address cursor for that port.
  // This prevents a short global deadline from silently skipping the tail of
  // a port's batch or repeatedly restarting the first port.
  var completed = 0;
  final hits = await natScanIps(
    slice,
    port: port,
    concurrency: effectiveConcurrency,
    want: slice.length,
    budget: budget,
    timeout: probeTimeout,
    cancelled: shouldAbort,
    onProgress: (done, total, _) => completed = done,
  );
  if (shouldAbort() || completed < slice.length) {
    return const <String>[];
  }
  // Persist discoveries before advancing their address cursor. If persistence
  // fails or the app closes, the same batch is retried instead of losing hits.
  final savedHits = await natIpMemSaveMany(
    hits.map((hit) => hit.ip),
    port,
  );
  if (!savedHits || shouldAbort()) return const <String>[];

  // Commit only this port's cursors after every address in its slice finished.
  _cfRangeCursors.removeWhere((key, _) => key.startsWith(portPrefix));
  for (final entry in generatedCursors.entries) {
    _cfRangeCursors['$portPrefix${entry.key}'] = entry.value;
  }
  if (configuredRanges.isNotEmpty) {
    _natConfiguredRangeOffsets.removeWhere((key, _) => key.startsWith(portPrefix));
    for (final entry in configuredBatch.nextOffsets.entries) {
      _natConfiguredRangeOffsets['$portPrefix${entry.key}'] = entry.value;
    }
    _natConfiguredRangeOffsets[portPrefix + '__range_cursor'] =
        configuredBatch.nextCursor.toString();
    _natConfiguredRangeCursor = configuredBatch.nextCursor;
  }
  _natRangePortCursors[modeKey] = port;

  natTemplateSeeds = seeds.take(2).toList();
  natRandomLast = 0;
  natIpScanned += slice.length;

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('natRangeScanCursorsV2', jsonEncode(_cfRangeCursors));
    await prefs.setString('natRangePortCursorsV3', jsonEncode(_natRangePortCursors));
    if (configuredRanges.isNotEmpty) {
      await prefs.setString(
          'natConfiguredRangeOffsetsV1', jsonEncode(_natConfiguredRangeOffsets));
      await prefs.setInt('natConfiguredRangeCursor', _natConfiguredRangeCursor);
    }
  } catch (e, stk) {
    logError(e, stk);
  }

  return hits.map((hit) => '${hit.ip}|$port').toList(growable: false);
}

List<String> userListUrls = [];

Future<void> userListsLoad() async {
  try {
    final p = await SharedPreferences.getInstance();
    userListUrls = (p.getString('userListUrls') ?? '')
        .split(RegExp(r'[\r\n\s]+'))
        .where((x) => x.startsWith('http'))
        .toList();
  } catch (e, stk) {
    logError(e, stk);
  }
}

Future<void> userListsSave(String text) async {
  userListUrls = text
      .split(RegExp(r'[\r\n\s]+'))
      .where((x) => x.startsWith('http'))
      .toList();
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString('userListUrls', userListUrls.join('\n'));
  } catch (e, stk) {
    logError(e, stk);
  }
}

// Source inventory is traversed without a fixed total-record ceiling.
const int natHotMin = 30000;
// Sparse index stores one byte offset per 256 records, not one per record.
const int _hotIndexStride = 256;
List<Server> Function()? natExtraSource;
const Duration natHotTtl = Duration(hours: 72);
bool _hotBusy = false;
DateTime? _hotFailAt;
int _hotCursor = 0;
Map<String, double> natSrcRates = {};

class _HotIdx {
  final String file;
  final int lineCount;
  final int byteLength;
  final String signature;
  final List<int> sparseOffsets;
  _HotIdx(this.file, this.lineCount, this.byteLength, this.signature,
      this.sparseOffsets);
}

_HotIdx? _hot;

const String hotVisibleDir = '/storage/emulated/0/Download/King-VPN';
String _hotPath() {
  const dir = '/data/data/com.kingvpn.king_vpn/files';
  try {
    final d = Directory(dir);
    if (!d.existsSync()) d.createSync(recursive: true);
    return '$dir/hot_cache.txt';
  } catch (_) {
    return '${Directory.systemTemp.path}/hot_cache.txt';
  }
}
// فیکس ۳: ماسک UUID/رمز در نسخه‌ای که به Download export می‌شود (فایل اصلی دست‌نخورده)
String _maskUuidsForExport(String txt) {
  var out = txt;
  out = out.replaceAllMapped(
    RegExp(r'(vless://)([0-9a-fA-F\-]{20,})@'),
    (m) => '${m[1]}***@',
  );
  out = out.replaceAllMapped(
    RegExp(r'(trojan://)([^@\s]{6,})@'),
    (m) => '${m[1]}***@',
  );
  out = out.replaceAllMapped(
    RegExp(r'(ss://)([A-Za-z0-9+/=_\-]{8,})@'),
    (m) => '${m[1]}***@',
  );
  out = out.replaceAllMapped(RegExp(r'vmess://([A-Za-z0-9+/=_\-]+)'), (m) {
    try {
      final b64 = m[1]!;
      final norm = base64.normalize(b64);
      final j = jsonDecode(utf8.decode(base64.decode(norm)));
      if (j is Map && j['id'] is String) {
        j['id'] = '***';
        return 'vmess://${base64.encode(utf8.encode(jsonEncode(j)))}';
      }
      return m[0]!;
    } catch (_) {
      return m[0]!;
    }
  });
  return out;
}

Future<void> hotExportToDownload() async {
  try {
    final src = File(_hotPath());
    if (!src.existsSync()) return;
    // Broad storage access is requested only for this explicit public Download export.
    if (!await hotStorageAllow()) return;
    final v = Directory(hotVisibleDir);
    if (!v.existsSync()) v.createSync(recursive: true);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final dst = File('$hotVisibleDir/hot_configs_$ts.txt');
    final exportSink = dst.openWrite();
    var exportFailed = false;
    try {
      await for (final line in src
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        exportSink.writeln(_maskUuidsForExport(line));
      }
      await exportSink.flush();
    } catch (e) {
      // If masking or streaming fails, do not fall back to an unmasked export.
      exportFailed = true;
      dbg('hotExport: ماسک ناموفق؛ خروجی نوشته نشد: $e');
    } finally {
      await exportSink.close();
    }
    if (exportFailed) {
      try {
        await dst.delete();
      } catch (cleanupError) {
        errJournalAdd(cleanupError, kind: 'SILENT-FILE');
      }
      return;
    }
    try {
      final all = v.listSync()
          .whereType<File>()
          .where((f) => f.path.contains('hot_configs_'))
          .toList()
        ..sort((a, b) {
          try { return b.statSync().modified.compareTo(a.statSync().modified); }
          catch (_) { return 0; }
        });
      for (var i = 3; i < all.length; i++) {
        try { all[i].deleteSync(); } catch (e, st) { logError(e, st); }
      }
    } catch (e, st) { logError(e, st); }
  } catch (e) {
    dbg('hotExport ignored: $e');
  }
}

List<String> natHotUrls() {
  final seen = <String>{};
  return [
    for (final u in [...userListUrls, ...listUrls])
      if (u.startsWith('http') && seen.add(u)) u
  ];
}

// Stream ordinary text responses to disk instead of retaining the full body.
Future<int> _hotFetchOne(String u, String path) async {
  final spool = File('$path.download');
  try {
    final response = await getListMirrorStream(u);
    if (response.statusCode != 200) return 0;
    final sink = spool.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    final size = await spool.length();
    if (size == 0) return 0;
    final prefix = await spool.openRead(0, size < 4096 ? size : 4096)
        .transform(utf8.decoder)
        .join();
    if (prefix.contains('<html') || prefix.contains('<!DOCTYPE')) {
      // Preserve HTML-link extraction; this compatibility path is disk-spooled.
      final html = (await spool.readAsString()).replaceAll('&amp;', '&');
      return await _hotWriteSourceLines(
          u, path, _linkRe.allMatches(html).map((m) => m.group(0)!));
    }
    if (prefix.contains('://')) {
      return await _hotWriteSourceLines(
        u,
        path,
        spool.openRead().transform(utf8.decoder).transform(const LineSplitter()),
      );
    }
    // Keep base64 compatibility isolated; the common plain-text path above
    // remains streaming from the network spool into the per-source file.
    final body = (await spool.readAsString()).trim();
    if (!RegExp(r'^[A-Za-z0-9+/=_\-\s]+$').hasMatch(body)) return 0;
    final decoded = utf8.decode(
      base64.decode(base64.normalize(body.replaceAll(RegExp(r'\s'), ''))),
      allowMalformed: true,
    );
    return await _hotWriteSourceLines(
        u, path, const LineSplitter().convert(decoded));
  } catch (e, stk) {
    logError(e, stk);
    return 0;
  } finally {
    try {
      if (await spool.exists()) await spool.delete();
    } catch (e, st) {
      errJournalAdd(e, st: st, kind: 'SILENT-FILE');
    }
  }
}

Future<int> _hotWriteSourceLines(
    String source, String path, Iterable<String> lines) async {
  final sink = File(path).openWrite();
  var count = 0;
  try {
    for (final line in lines) {
      final value = line.trim();
      if (!value.contains('://') ||
          value.contains('[email') ||
          value.contains('protected]')) {
        continue;
      }
      sink.writeln('$source\t$value');
      count++;
    }
    await sink.flush();
  } finally {
    await sink.close();
  }
  return count;
}

Future<void>? _hotEnsureFuture;

Future<void> natHotEnsure({bool force = false}) async {
  final active = _hotEnsureFuture;
  if (active != null) {
    await active;
    return;
  }
  final task = _natHotEnsureImpl(force: force);
  _hotEnsureFuture = task;
  try {
    await task;
  } finally {
    if (identical(_hotEnsureFuture, task)) _hotEnsureFuture = null;
  }
}

Future<void> _natHotEnsureImpl({bool force = false}) async {
  final f = File(_hotPath());
  try {
    final exists = f.existsSync() && f.lengthSync() > 0;
    final age = f.existsSync()
        ? DateTime.now().difference(f.lastModifiedSync())
        : const Duration(days: 365);
    if (!force && exists && age < natHotTtl) return;
    if (!force && _hotFailAt != null &&
        DateTime.now().difference(_hotFailAt!) < const Duration(minutes: 30)) return;
    _hotBusy = true;
    final urls = natHotUrls();
    final dir = '/data/data/com.kingvpn.king_vpn/files';
    final parts = [for (var i = 0; i < urls.length; i++) '$dir/hot_part_$i.txt'];
    final extraPath = '$dir/hot_part_extra.txt';
    try {
      await pool<int>([for (var i = 0; i < urls.length; i++) i], fetchWorkers,
          (i) async {
        await _hotFetchOne(urls[i], parts[i]);
      });
      final extraSrc = natExtraSource?.call() ?? const <Server>[];
      if (extraSrc.isNotEmpty) {
        final ex = [
          for (final sv in extraSrc)
            if (sv.link.contains('://')) 'online\t${sv.link}'
        ];
        await File(extraPath).writeAsString(ex.join('\n'), flush: true);
      }
      final order = natStableSorted<int>(
          [for (var i = 0; i < urls.length; i++) i],
          (a, b) => (natSrcRates[urls[b]] ?? 0.3)
              .compareTo(natSrcRates[urls[a]] ?? 0.3));
      final mixed = order;
      final newPath = '${_hotPath()}.new';
      var freshTotal = 0;
      final oldCachePath = _hotPath();
      final sink = File(newPath).openWrite();
      try {
        final mergeFrom = <String>[
          if (File(extraPath).existsSync()) extraPath,
          for (final i in mixed) parts[i],
          if (File(oldCachePath).existsSync()) oldCachePath,
        ];
        for (final pth in mergeFrom) {
          final isOldCache = pth == oldCachePath;
          final pf = File(pth);
          if (!pf.existsSync()) continue;
          await for (final line in pf
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
            if (line.isEmpty) continue;
            final b = utf8.encode(line);
            sink.add(b);
            sink.add(const [10]);
            if (!isOldCache) freshTotal++;
          }
        }
      } finally {
        await sink.close();
      }
      final sparseIndex = await _hotBuildSparseIndex(newPath);
      final total = sparseIndex.first;
      if (freshTotal > 0 && total > 0) {
        _hotFailAt = null;
        await File(newPath).rename(_hotPath());
        final cacheStat = await File(_hotPath()).stat();
        final cacheSignature =
            '${cacheStat.size}:${cacheStat.modified.microsecondsSinceEpoch}';
        // Persist the freshly-built index at cache commit time; otherwise the
        // next process restart would have to scan the complete cache again.
        await _hotWriteSparseIndex(_hotPath(), cacheSignature, sparseIndex);
        _hot = _HotIdx(_hotPath(), sparseIndex[0], sparseIndex[1],
            cacheSignature, sparseIndex.skip(2).toList(growable: false));
        _hotCursor = 0;
        if (total < natHotMin) {
          dbg('پوشه‌ی منابع تازه: $total کانفیگ (کمتر از $natHotMin)');
        }
      } else {
        _hotFailAt = DateTime.now();
        try {
          await File(newPath).delete();
        } catch (e) { errJournalAdd(e, kind: 'SILENT-FILE'); }
      }
    } finally {
      for (final p in [...parts, extraPath]) {
        try {
          await File(p).delete();
        } catch (e) { errJournalAdd(e, kind: 'SILENT-FILE'); }
      }
    }
  } catch (e) {
    _hotFailAt = DateTime.now();
    logError(e);
  } finally {
    _hotBusy = false;
  }
}

bool natHotReady() {
  try {
    final f = File(_hotPath());
    return f.existsSync() && f.lengthSync() > 0;
  } catch (jex, jstk) { errJournalAdd(jex, st: jstk);
    return false;
  }
}

// Build a sparse index: one byte offset per stride-sized block.
// Packed result: [lineCount, byteLength, offset0, offset1, ...].
Future<List<int>> _hotBuildSparseIndex(String path) =>
    compute(_hotSparseOffsetsIso, path);

String _hotIndexPath(String cachePath) => '$cachePath.sparse.idx';

Future<List<int>?> _hotReadSparseIndex(
    String cachePath, String signature) async {
  try {
    final indexFile = File(_hotIndexPath(cachePath));
    if (!await indexFile.exists()) return null;
    final rows = await indexFile.readAsLines();
    if (rows.isEmpty) return null;
    final header = rows.first.split('|');
    if (header.length != 4 || header[0] != 'v1' || header[1] != signature) {
      return null;
    }
    final lineCount = int.tryParse(header[2]);
    final byteLength = int.tryParse(header[3]);
    if (lineCount == null || byteLength == null ||
        lineCount <= 0 || byteLength <= 0) return null;
    final packed = <int>[lineCount, byteLength];
    var previous = -1;
    for (final row in rows.skip(1)) {
      final offset = int.tryParse(row);
      if (offset == null || offset < 0 || offset > byteLength ||
          offset <= previous) return null;
      packed.add(offset);
      previous = offset;
    }
    // The first sparse block always starts at byte zero.
    if (packed.length < 3 || packed[2] != 0) return null;
    final expected = lineCount ~/ _hotIndexStride + 1;
    if (packed.length - 2 != expected) return null;
    return packed;
  } catch (e, st) {
    logError(e, st);
    return null;
  }
}

Future<void> _hotWriteSparseIndex(
    String cachePath, String signature, List<int> packed) async {
  if (packed.length < 3) return;
  final target = File(_hotIndexPath(cachePath));
  final temporary = File('${target.path}.new');
  final sink = temporary.openWrite();
  try {
    sink.writeln('v1|$signature|${packed[0]}|${packed[1]}');
    for (final offset in packed.skip(2)) {
      sink.writeln(offset);
    }
    await sink.flush();
  } finally {
    await sink.close();
  }
  if (await target.exists()) await target.delete();
  await temporary.rename(target.path);
}

List<int> _hotSparseOffsetsIso(String path) {
  final packed = <int>[0, 0, 0];
  var lineCount = 0;
  var pos = 0;
  var lastByte = -1;
  final raf = File(path).openSync();
  try {
    while (true) {
      final chunk = raf.readSync(64 * 1024);
      if (chunk.isEmpty) break;
      for (var i = 0; i < chunk.length; i++) {
        if (chunk[i] == 10) {
          lineCount++;
          if (lineCount % _hotIndexStride == 0) {
            packed.add(pos + i + 1);
          }
        }
      }
      lastByte = chunk.last;
      pos += chunk.length;
    }
  } finally {
    raf.closeSync();
  }
  if (pos > 0 && lastByte != 10) lineCount++;
  packed[0] = lineCount;
  packed[1] = pos;
  return packed;
}

Future<int> _hotOffsetAtLine(
    RandomAccessFile raf, _HotIdx index, int line) async {
  if (line <= 0) return 0;
  if (line >= index.lineCount) return await raf.length();
  final block = line ~/ _hotIndexStride;
  final baseLine = block * _hotIndexStride;
  var position = index.sparseOffsets[block];
  var separators = line - baseLine;
  await raf.setPosition(position);
  while (separators > 0) {
    final chunk = await raf.read(64 * 1024);
    if (chunk.isEmpty) return await raf.length();
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] == 10) {
        separators--;
        if (separators == 0) return position + i + 1;
      }
    }
    position += chunk.length;
  }
  return position;
}

Future<_HotIdx?> _hotLoad() async {
  final cur = _hot;
  if (cur != null) return cur;
  final f = File(_hotPath());
  try {
    if (!await f.exists()) return null;
    final cacheStat = await f.stat();
    if (cacheStat.size <= 0) return null;
    final cacheSignature =
        '${cacheStat.size}:${cacheStat.modified.microsecondsSinceEpoch}';
    // Reuse the on-disk sparse index after restart. A size/mtime mismatch
    // invalidates it and triggers a complete rebuild from the authoritative cache.
    var sparseIndex = await _hotReadSparseIndex(f.path, cacheSignature);
    if (sparseIndex == null) {
      sparseIndex = await _hotBuildSparseIndex(f.path);
      if (sparseIndex.first <= 0) return null;
      if (sparseIndex[1] != cacheStat.size) return null;
      await _hotWriteSparseIndex(f.path, cacheSignature, sparseIndex);
    }
    _hot = _HotIdx(
      f.path,
      sparseIndex[0],
      sparseIndex[1],
      cacheSignature,
      sparseIndex.skip(2).toList(growable: false),
    );
    _hotCursor = 0;
    return _hot;
  } catch (e, stk) {
    logError(e, stk);
    return null;
  }
}

bool _hotNextBusy = false;
Completer<void>? _hotNextIdle;
const String _hotCursorKey = 'nat_hot_cursor_v1';
const String _hotCursorSignatureKey = 'nat_hot_cursor_signature_v1';

Future<List<Server>> natHotNext(int n,
    {bool fetch = true, bool retried = false}) async {
  // Serialize page reads: concurrent callers must never consume the same
  // persisted cursor position or overwrite each other's progress.
  while (_hotNextBusy) {
    final waiting = _hotNextIdle;
    if (waiting != null) await waiting.future;
  }
  _hotNextBusy = true;
  _hotNextIdle = Completer<void>();
  try {
    return await _natHotNextUnlocked(n, fetch: fetch, retried: retried);
  } finally {
    _hotNextBusy = false;
    _hotNextIdle?.complete();
    _hotNextIdle = null;
  }
}

Future<List<Server>> _natHotNextUnlocked(int n,
    {required bool fetch, required bool retried}) async {
  try {
    if (n <= 0) return const [];
    if (fetch) unawaited(natHotEnsure());
    final h = await _hotLoad();
    if (h == null) return const [];
    final lines = h.lineCount;
    if (lines <= 0) return const [];
    final cacheFile = File(h.file);
    final stat = await cacheFile.stat();
    final signature = '${stat.size}:${stat.modified.microsecondsSinceEpoch}';
    if (signature != h.signature) {
      _hot = null;
      if (retried) return const [];
      return _natHotNextUnlocked(n, fetch: false, retried: true);
    }
    final prefs = await SharedPreferences.getInstance();
    final savedSignature = prefs.getString(_hotCursorSignatureKey);
    final savedCursor = prefs.getInt(_hotCursorKey);
    var cursor = savedSignature == signature && savedCursor != null
        ? savedCursor
        : 0;
    if (cursor < 0 || cursor >= lines) cursor = 0;
    final out = <Server>[];
    final raf = await cacheFile.open();
    try {
      // The open handle is tied to one inode. If its length disagrees with
      // the index, rebuild once rather than pairing offsets with another file.
      if (await raf.length() != h.byteLength) {
        _hot = null;
        if (retried) return const [];
        return _natHotNextUnlocked(n, fetch: false, retried: true);
      }
      var read = 0;
      while (out.length < n && read < lines) {
        var start = cursor;
        if (start >= lines) start = 0;
        final take = min(min(n - out.length, lines - start), lines - read);
        final from = await _hotOffsetAtLine(raf, h, start);
        final endLine = start + take;
        final to = await _hotOffsetAtLine(raf, h, endLine);
        await raf.setPosition(from);
        final bytes = await raf.read(to - from);
        final pageText = utf8.decode(bytes, allowMalformed: true);
        for (final entry in pageText.split('\n')) {
          final tab = entry.indexOf('\t');
          if (tab < 0) continue;
          final server = Server.parse(entry.substring(tab + 1));
          if (server != null) {
            server.src = entry.substring(0, tab);
            out.add(server);
          }
        }
        read += take;
        cursor = (start + take) % lines;
      }
    } finally {
      await raf.close();
    }
    // Save cursor and its cache identity together. A rebuilt cache starts at
    // zero; an app restart against the same cache resumes at the next page.
    final cursorSaved = await prefs.setInt(_hotCursorKey, cursor);
    final signatureSaved =
        await prefs.setString(_hotCursorSignatureKey, signature);
    if (!cursorSaved || !signatureSaved) {
      dbg('natHotNext: ذخیرهٔ Cursor منابع انجام نشد؛ صفحه در اجرای بعد ممکن است تکرار شود');
    }
    _hotCursor = cursor;
    return out;
  } catch (e, stk) {
    logError(e, stk);
    return const [];
  }
}

const String kNatMemKey = 'nat_last_success';

Future<void> natRememberSuccess(Server s) async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        kNatMemKey,
        jsonEncode({
          'link': s.link,
          'natLevel': natLevel,
          'offlineOnly': offlineOnly,
          'indestructibleMode': indestructibleMode,
        }));
  } catch (e, st) {
    logError(e, st);
  }
}

Future<void> natMemLoad() async {
  try {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(kNatMemKey);
    if (raw == null) return null;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    natLevel = (m['natLevel'] as int?) ?? natLevel;
    offlineOnly = (m['offlineOnly'] as bool?) ?? offlineOnly;
  } catch (e, st) {
    logError(e, st);
  }
}


Future<bool> hotStorageAllow() async {
  try {
    final st = Permission.manageExternalStorage;
    if (await st.isGranted) return true;
    return (await st.request()).isGranted;
  } catch (e) {
    logError(e);
    return false;
  }
}

// Internal cache is app-private; building it must not request all-files access.
Future<void> hotAutoFill() async {
  await natHotEnsure();
}
Future<void> hotAutoStart() async {
  try {
    WidgetsBinding.instance.addObserver(HotResumeWatcher());
  } catch (e) {
    logError(e);
  }
  await hotAutoFill();
}
class HotResumeWatcher extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(hotAutoFill());
  }
}

// SNICF: آیا این host یک IP متعلق به کلودفلر است؟
// بازه‌های اصلی کلودفلر: 104.16.0.0/12، 104.24.0.0/14، 162.158.0.0/15، 172.64.0.0/13
bool _isCfIp(String host) {
  final ip = InternetAddress.tryParse(host);
  if (ip == null) return false;
  if (ip.type == InternetAddressType.IPv4) {
    final b = ip.rawAddress;
    int v(int i) => b[i];
    bool inRange(int a, int bb, int prefix) {
      final mask = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
      final x = (v(0) << 24) | (v(1) << 16) | (v(2) << 8) | v(3);
      final y = (a << 24) | (bb << 16);
      return (x & mask) == (y & mask);
    }
    return inRange(104, 16, 12) || inRange(104, 24, 14) ||
        inRange(162, 158, 15) || inRange(172, 64, 13);
  }
  if (ip.type != InternetAddressType.IPv6) return false;
  final value = _natIpv6ToBigInt(ip);
  for (final cidr in _cfRangesV6) {
    final parts = cidr.split('/');
    if (parts.length != 2) continue;
    final networkAddress = InternetAddress.tryParse(parts[0]);
    final prefix = int.tryParse(parts[1]);
    if (networkAddress == null || prefix == null || prefix < 0 || prefix > 128) continue;
    final hostBits = 128 - prefix;
    final mask = prefix == 0 ? BigInt.zero :
        ((BigInt.one << 128) - BigInt.one) ^ ((BigInt.one << hostBits) - BigInt.one);
    if ((value & mask) == (_natIpv6ToBigInt(networkAddress) & mask)) return true;
  }
  return false;
}

// MUXWORKER: Worker کلودفلر فقط VLESS با دستور TCP (1) را می‌پذیرد؛ mux (دستور 3) را رد می‌کند.
// برای آدرس‌های workers.dev/pages.dev mux باید خاموش باشد.
bool _isWorkerOutbound(Map o) {
  try {
    final st = o['settings'];
    if (st is! Map) return false;
    final vn = st['vnext'];
    if (vn is! List || vn.isEmpty) return false;
    final addr = ((vn.first as Map)['address'] ?? '').toString().toLowerCase();
    return addr.endsWith('workers.dev') || addr.endsWith('pages.dev');
  } catch (_) {
    return false;
  }
}
