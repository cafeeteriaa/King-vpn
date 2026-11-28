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
  final int? sniSwap; // V13: swap SNI to natFrontSnis[idx] (CDN-only)
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
  _NatSpec('SNI>cdnjs', sniSwap: 0),
  _NatSpec('SNI>cloudflare', sniSwap: 2),
  _NatSpec('SNI>speed', sniSwap: 3),
  _NatSpec('SNI>divar.ir', sniSwap: 7),
];

final List<_NatSpec> _natSpecs = [..._natBase, ..._natGenerate(), ..._natExtra];

final int _natInitialSpecCount = _natSpecs.length;
int _natDynamicPersistedCount = 0;

Map<String, Object?> _natSpecToJson(_NatSpec s) => <String, Object?>{
  'name': s.name, 'other': s.other, 'fp': s.fp, 'alpn': s.alpn,
  'frag': s.frag, 'port': s.port, 'clean': s.clean, 'mux': s.mux,
  'sniHost': s.sniHost, 'v4': s.v4, 'tfo': s.tfo, 'ed': s.ed,
  'noise': s.noise, 'doh': s.doh, 'muxN': s.muxN, 'noiseK': s.noiseK,
  'nodelay': s.nodelay, 'mode': s.mode, 'edN': s.edN,
  'portIdx': s.portIdx, 'cleanIdx': s.cleanIdx, 'keep': s.keep,
  'mss': s.mss, 'sniSwap': s.sniSwap,
};

_NatSpec _natSpecFromJson(Object? raw) {
  if (raw is! Map) throw const FormatException('Invalid NAT strategy record');
  String? stringValue(Object? value) => value is String ? value : null;
  int? intValue(Object? value) => value is num ? value.toInt() : null;
  bool boolValue(Object? value) => value is bool ? value : false;
  return _NatSpec(
    stringValue(raw['name']) ?? 'Recovered strategy',
    other: boolValue(raw['other']),
    fp: stringValue(raw['fp']),
    alpn: stringValue(raw['alpn']),
    frag: intValue(raw['frag']),
    port: boolValue(raw['port']),
    clean: boolValue(raw['clean']),
    mux: boolValue(raw['mux']),
    sniHost: boolValue(raw['sniHost']),
    v4: boolValue(raw['v4']),
    tfo: boolValue(raw['tfo']),
    ed: boolValue(raw['ed']),
    noise: boolValue(raw['noise']),
    doh: stringValue(raw['doh']),
    muxN: intValue(raw['muxN']) ?? 0,
    noiseK: intValue(raw['noiseK']) ?? 0,
    nodelay: boolValue(raw['nodelay']),
    mode: stringValue(raw['mode']),
    edN: intValue(raw['edN']),
    portIdx: intValue(raw['portIdx']),
    cleanIdx: intValue(raw['cleanIdx']),
    keep: intValue(raw['keep']),
    mss: intValue(raw['mss']),
    sniSwap: intValue(raw['sniSwap']),
  );
}

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
    int? sniSwap}) {
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
  if (sniSwap != null) n.add('SNI>CF#${sniSwap + 1}');
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

  // V13: SNI-swap x fragment combos (bypass SNI + DPI in one shot).
  for (var sniIdx = 0; sniIdx < 4; sniIdx++) {
    final realIdx = const [0, 2, 3, 10][sniIdx];
    for (var fi = 0; fi < _natFragBase.length; fi++) {
      add(_natMk(frag: fi, sniSwap: realIdx));
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
int natGrow(int n) {
  final rnd = Random(DateTime.now().millisecondsSinceEpoch + _natGrowCounter++);
  var added = 0;
  const fps = ['chrome', 'firefox', 'randomized', 'ios', 'android', 'safari', 'edge', 'random', 'qq', '360', 'hellogolang', 'hellochrome', 'hellofirefox', 'hellosafari', 'helloios', 'helloandroid', 'helloedge', 'hello360', 'helloqq', 'hellorandomized', 'hellorandomizedalpn', 'hellorandomizednoalpn'];
  const alpns = <String?>[null, 'h2', 'http/1.1', 'h2,http/1.1'];
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
    final sniSwap = rnd.nextBool() ? rnd.nextInt(natFrontSnis.length) : null;
    _natSpecs.add(_natMk(
      fp: fp, alpn: alpn, frag: frag, port: port, portIdx: portIdx,
      clean: clean, cleanIdx: cleanIdx, v4: v4, tfo: tfo, keep: keep, doh: doh,
      sniSwap: sniSwap,
    ));
    added++;
  }
  if (added > 0) {
    _natNamesC = null;
    _natGenRankKey = '';
    natSaveSoon();
  }
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
  if (_natPick.length > 3000) _natPick.remove(_natPick.keys.first);
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

void natVariantResult(int v, bool ok, {String? profile, int? latencyMs}) {
  if (v < 0) return;
  // KNS: this hook is called only after the real tunnel data-plane probe.
  KingNationalScannerEngine.recordVariantOutcome(v, ok, profile: profile, latencyMs: latencyMs);
  if (v == 0) return;
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
  if (x.sniSwap != null) {
    final index = x.sniSwap!;
    if (index < 0 || index >= natFrontSnis.length ||
        InternetAddress.tryParse(natFrontSnis[index]) != null) return false;
  }
  if (x.other && !f.hasOther) return false;
  if ((x.fp != null || x.alpn != null || x.frag != null || x.noise) &&
      !f.sec) {
    return false;
  }
  if (x.sniHost && !(f.sec && !f.reality && !f.isIp)) return false;
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
  // V13: SNI swap only makes sense for CDN configs with TLS (not reality).
  if (x.sniSwap != null && !(f.sec && f.cdnLike && !f.reality)) return false;
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
    _topWinCache = [for (final r in rows.take(30)) r.key];
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
  natSaveSoon();
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

  final preferLight = !nationalMode && !scannerMode;
  final skipHeavy = !nationalMode && !scannerMode;

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
  final query = Uri.https(host, path, <String, String>{
    'name': nationalMode ? 'nic.ir' : 'google.com',
    'type': 'A',
  }).toString();
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
String _natApplySniSwap(String cfg, int sniIdx) {
  try {
    if (sniIdx < 0 || sniIdx >= natFrontSnis.length) return cfg;
    final sni = natFrontSnis[sniIdx];
    final j = jsonDecode(cfg);
    if (j is! Map<String, dynamic>) return cfg;
    final outs = (j['outbounds'] as List?) ?? <dynamic>[];
    for (final o in outs) {
      if (o is! Map) continue;
      final st = o['streamSettings'];
      if (st is! Map) continue;
      if (st['security'] != 'tls') continue;
      final tls = st['tlsSettings'];
      if (tls is! Map) continue;
      if (tlsHasEch(tls)) continue; // ECH: SNI را عوض نکن
      tls['serverName'] = sni; // keep certificate validation enabled
    }
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
      tls['allowInsecure'] = false;
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
];

String natOpKey = 'x';
final Map<String, String> _natAsnByType = {};
final Map<String, DateTime> _natAsnTry = {};

Future<String> _natNetType() async {
  try {
    final l = await NetworkInterface.list(
        includeLoopback: false, type: InternetAddressType.IPv4);
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
    await _natAppendDynamicSpecs();
    await _natWriteJsonSnapshot('king_nat_learning_state.json', <String, Object?>{
      'v': natVar,
      'w': natWins,
      'd': natDimWins,
      'g': _natGenVer,
      'n': natVarNormal,
      'c': _natCursor,
    });
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
    await _natDynamicSpecsLoad();
    final p = await SharedPreferences.getInstance();
    final file = await _natMemoryFile('king_nat_learning_state.json');
    final hasDiskStore = await file.exists();
    final s = hasDiskStore ? await file.readAsString() : p.getString('natvar2');
    if (s == null) return;
    final j = jsonDecode(s);
    (j['v'] as Map).forEach((k, v) => natVar['$k'] = (v as num).toInt());
    (j['w'] as Map).forEach((k, v) => natWins['$k'] = (v as num).toInt());
    _natWinsVer++; // TOPWIN
    final cursorMap = j['c'];
    if (cursorMap is Map) {
      _natCursor
        ..clear()
        ..addAll({
          for (final entry in cursorMap.entries)
            if (entry.value is num) '${entry.key}': (entry.value as num).toInt(),
        });
    }
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
    }
    if (((j['g'] ?? 0) as num).toInt() != _natGenVer) {
      natVar.removeWhere((k, v) => v >= _natBaseCount);
      _natWinsVer++; // TOPWIN
      natWins.removeWhere((k, v) {
        final n = int.tryParse(k.substring(k.lastIndexOf('#') + 1));
        return n != null && n >= _natBaseCount;
      });
    }
    if (!hasDiskStore) {
      await _natWriteJsonSnapshot('king_nat_learning_state.json', j);
    }
    _natLearnVer++;
  } catch (e, stk) {
    logError(e, stk);
  }
}

const String _ipMemKey = 'natIpMem';
const String _rangeKey = 'natRanges';

final List<Map<String, dynamic>> natIpMem = [];
final Set<String> natIpDeadRun = {};
List<String> natRanges = [];
List<String> natIranIpv6Prefixes = [];
int natRangeCursor = 0; // legacy generic range cursor
int _natConfiguredRangeCursor = 0; // next configured-range entry
final Map<String, int> _natConfiguredRangeCursors = <String, int>{};
bool natRangeInventoryPassComplete = false;
int natRangeScanBatchSequence = 0;
DateTime natRangeLast = DateTime.fromMillisecondsSinceEpoch(0);

Future<File> _natMemoryFile(String name) async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}/$name');
}

Future<KingDiskInventory>? _natIpInventoryFuture;
Future<KingDiskInventory>? _natDomainInventoryFuture;

Future<KingDiskInventory> _natIpInventory() async {
  try {
    return await (_natIpInventoryFuture ??=
        KingDiskInventory.open(name: 'nat-ip-endpoints'));
  } catch (_) {
    _natIpInventoryFuture = null;
    rethrow;
  }
}

Future<KingDiskInventory> _natDomainInventory() async {
  try {
    return await (_natDomainInventoryFuture ??=
        KingDiskInventory.open(name: 'nat-domain-endpoints'));
  } catch (_) {
    _natDomainInventoryFuture = null;
    rethrow;
  }
}


Future<void> _natFileWriteQueue = Future<void>.value();

Future<void> _natWriteJsonSnapshot(String name, Object value) {
  final next = _natFileWriteQueue.then((_) async {
    final file = await _natMemoryFile(name);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(file.path);
  });
  _natFileWriteQueue = next.catchError((Object error, StackTrace stack) {
    logError(error, stack);
  });
  return next;
}


const String _natDynamicSpecsFileName = 'king_nat_dynamic_specs.jsonl';
bool _natDynamicSpecsLoaded = false;

Future<void> _natDynamicSpecsLoad() async {
  if (_natDynamicSpecsLoaded) return;
  _natDynamicSpecsLoaded = true;
  try {
    final file = await _natMemoryFile(_natDynamicSpecsFileName);
    if (!await file.exists()) return;
    final lines = await file.readAsLines();
    if (lines.isEmpty) return;
    Object? header;
    try {
      header = jsonDecode(lines.first);
    } catch (_) {
      header = null;
    }
    if (header is! Map ||
        header['kind'] != 'king-nat-dynamic-specs' ||
        header['version'] != 1 ||
        header['baseCount'] != _natInitialSpecCount) {
      final legacy = File('${file.path}.incompatible');
      if (await legacy.exists()) await legacy.delete();
      await file.rename(legacy.path);
      return;
    }
    final validLines = <String>[lines.first];
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      try {
        _natSpecs.add(_natSpecFromJson(jsonDecode(line)));
        validLines.add(line);
        _natDynamicPersistedCount++;
      } catch (e, stk) {
        logError(e, stk);
        break;
      }
    }
    if (validLines.length != lines.length) {
      await file.writeAsString('${validLines.join('\n')}\n', flush: true);
    }
    _natNamesC = null;
    _natGenRankKey = '';
  } catch (e, stk) {
    logError(e, stk);
  }
}

Future<void> _natAppendDynamicSpecs() {
  final next = _natFileWriteQueue.then((_) async {
    final pendingStart = _natInitialSpecCount + _natDynamicPersistedCount;
    final targetLength = _natSpecs.length;
    if (targetLength <= pendingStart) return;
    final file = await _natMemoryFile(_natDynamicSpecsFileName);
    if (!await file.exists() || await file.length() == 0) {
      final header = <String, Object?>{
        'kind': 'king-nat-dynamic-specs',
        'version': 1,
        'baseCount': _natInitialSpecCount,
      };
      await file.writeAsString('${jsonEncode(header)}\n', flush: true);
    }
    final sink = file.openWrite(mode: FileMode.append);
    for (var index = pendingStart; index < targetLength; index++) {
      sink.writeln(jsonEncode(_natSpecToJson(_natSpecs[index])));
    }
    await sink.flush();
    await sink.close();
    _natDynamicPersistedCount = targetLength - _natInitialSpecCount;
  });
  _natFileWriteQueue = next.catchError((Object error, StackTrace stack) {
    logError(error, stack);
  });
  return next;
}

Future<void> _natWriteMemorySnapshot(
    String name, List<Map<String, dynamic>> values) =>
    _natWriteJsonSnapshot(name, values);

Future<void> _natRangeStateLoad(SharedPreferences prefs) async {
  const name = 'king_nat_range_state.json';
  final file = await _natMemoryFile(name);
  Map<dynamic, dynamic>? state;
  if (await file.exists()) {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is Map) state = decoded;
  } else {
    final configuredRaw = prefs.getString('natConfiguredRangeCursorsV1');
    final endpointRaw = prefs.getString('natCfRangeCursorsV1');
    Object? configured = <String, int>{};
    Object? endpoints = <String, int>{};
    try {
      if (configuredRaw != null && configuredRaw.isNotEmpty) {
        configured = jsonDecode(configuredRaw);
      }
      if (endpointRaw != null && endpointRaw.isNotEmpty) {
        endpoints = jsonDecode(endpointRaw);
      }
    } catch (e, stk) {
      logError(e, stk);
    }
    state = <String, Object?>{
      'configuredCursor': prefs.getInt('natConfiguredRangeCursor') ?? 0,
      'configuredCursors': configured,
      'endpointCursors': endpoints,
    };
    await _natWriteJsonSnapshot(name, state);
  }
  final loaded = state ?? <String, Object?>{};
  final configuredCursor = loaded['configuredCursor'];
  _natConfiguredRangeCursor =
      configuredCursor is num ? configuredCursor.toInt() : 0;
  Map<String, int> decodeCursors(Object? raw) {
    final result = <String, int>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.value is num) {
          result['${entry.key}'] = (entry.value as num).toInt();
        }
      }
    }
    return result;
  }
  _natConfiguredRangeCursors
    ..clear()
    ..addAll(decodeCursors(loaded['configuredCursors']));
  _cfRangeCursors
    ..clear()
    ..addAll(decodeCursors(loaded['endpointCursors']));
}

Future<void> _natRangeStateSave({
  int? configuredCursor,
  Map<String, int>? configuredCursors,
  Map<String, int>? endpointCursors,
}) => _natWriteJsonSnapshot(
  'king_nat_range_state.json',
  <String, Object?>{
    'configuredCursor': configuredCursor ?? _natConfiguredRangeCursor,
    'configuredCursors': configuredCursors ?? _natConfiguredRangeCursors,
    'endpointCursors': endpointCursors ?? _cfRangeCursors,
  },
);

Set<String> natIpMemHosts() => {for (final e in natIpMem) '${e['ip']}'};

Future<void> natIpMemLoad() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final inventory = await _natIpInventory();
    if (await inventory.records().isEmpty) {
      final legacyFile = await _natMemoryFile('king_nat_ip_inventory.json');
      var legacy = await legacyFile.exists()
          ? await legacyFile.readAsString()
          : null;
      if (legacy == null || legacy.isEmpty) legacy = prefs.getString(_ipMemKey);
      if (legacy != null && legacy.isNotEmpty) {
        final decoded = jsonDecode(legacy);
        if (decoded is List) {
          final migrated = <Map<String, Object?>>[];
          for (final raw in decoded) {
            if (raw is! Map) continue;
            final ip = raw['ip']?.toString() ?? '';
            final port = raw['port'];
            if (InternetAddress.tryParse(ip) == null || port is! num ||
                port.toInt() < 1 || port.toInt() > 65535) continue;
            migrated.add(<String, Object?>{
              'key': '$ip|${port.toInt()}',
              'ip': ip,
              'port': port.toInt(),
              't': raw['t'] is num ? (raw['t'] as num).toInt() : 0,
            });
          }
          if (migrated.isNotEmpty) await inventory.upsertBatch(migrated);
        }
      }
    }
    natIpMem.clear();
    await for (final record in inventory.records()) {
      final ip = record['ip'];
      final port = record['port'];
      if (ip is String && port is num) {
        natIpMem.add(<String, dynamic>{
          'ip': ip,
          'port': port.toInt(),
          't': record['t'] is num ? (record['t'] as num).toInt() : 0,
        });
      }
    }
    final rangesFile = await _natMemoryFile('king_nat_configured_ranges.json');
    final hasRangeFile = await rangesFile.exists();
    final savedRanges = hasRangeFile
        ? jsonDecode(await rangesFile.readAsString())
        : (prefs.getString(_rangeKey) ?? '')
            .split(RegExp(r'[\r\n,; ]+'))
            .where((raw) {
              final value = raw.trim();
              if (value.contains('/')) {
                final parts = value.split('/');
                if (parts.length != 2) return false;
                final address = InternetAddress.tryParse(parts[0].trim());
                final prefix = int.tryParse(parts[1].trim());
                if (address == null || prefix == null) return false;
                return address.type == InternetAddressType.IPv4
                    ? prefix >= 0 && prefix <= 32
                    : prefix == 128;
              }
              if (value.contains('-')) {
                final parts = value.split('-');
                if (parts.length != 2) return false;
                return InternetAddress.tryParse(parts[0].trim())?.type == InternetAddressType.IPv4 &&
                    InternetAddress.tryParse(parts[1].trim())?.type == InternetAddressType.IPv4;
              }
              return InternetAddress.tryParse(value) != null;
            })
            .toList();
    natRanges = savedRanges is List
        ? savedRanges.map((value) => value.toString()).toList()
        : <String>[];
    if (!hasRangeFile && natRanges.isNotEmpty) {
      await _natWriteJsonSnapshot('king_nat_configured_ranges.json', natRanges);
    }
    await _natRangeStateLoad(prefs);
    final countrySourcesFile =
        await _natMemoryFile('king_nat_country_prefix_sources.json');
    if (await countrySourcesFile.exists()) {
      try {
        final sourceState = jsonDecode(await countrySourcesFile.readAsString());
        if (sourceState is Map) {
          natIranIpv6Prefixes = NatCountryPrefixSnapshot.parseIpv6PrefixList(
            sourceState['ipv6Prefixes'],
          );
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
const int natDelaySecs = 14;
final List<Map<String, dynamic>> natDomMem = [];

Set<String> natDomMemHosts() => {for (final e in natDomMem) '${e['h']}:${e['port']}'};

Future<void> natDomMemLoad() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final inventory = await _natDomainInventory();
    if (await inventory.records().isEmpty) {
      final legacyFile = await _natMemoryFile('king_nat_domain_inventory.json');
      var legacy = await legacyFile.exists()
          ? await legacyFile.readAsString()
          : null;
      if (legacy == null || legacy.isEmpty) legacy = prefs.getString(_domMemKey);
      if (legacy != null && legacy.isNotEmpty) {
        final decoded = jsonDecode(legacy);
        if (decoded is List) {
          final migrated = <Map<String, Object?>>[];
          for (final raw in decoded) {
            if (raw is! Map) continue;
            final host = raw['h']?.toString() ?? '';
            final port = raw['port'];
            if (host.isEmpty || port is! num ||
                port.toInt() < 1 || port.toInt() > 65535) continue;
            migrated.add(<String, Object?>{
              'key': '$host|${port.toInt()}',
              'h': host,
              'port': port.toInt(),
              't': raw['t'] is num ? (raw['t'] as num).toInt() : 0,
            });
          }
          if (migrated.isNotEmpty) await inventory.upsertBatch(migrated);
        }
      }
    }
    natDomMem.clear();
    await for (final record in inventory.records()) {
      final host = record['h'];
      final port = record['port'];
      if (host is String && port is num) {
        natDomMem.add(<String, dynamic>{
          'h': host,
          'port': port.toInt(),
          't': record['t'] is num ? (record['t'] as num).toInt() : 0,
        });
      }
    }
  } catch (e, stk) {
    logError(e, stk);
  }
}

Future<void> natDomMemSave(String host, int port) async {
  if (host.trim().isEmpty || port < 1 || port > 65535) return;
  final normalizedHost = host.trim();
  final now = DateTime.now().millisecondsSinceEpoch;
  try {
    final inventory = await _natDomainInventory();
    await inventory.upsertBatch(<Map<String, Object?>>[
      <String, Object?>{
        'key': '$normalizedHost|$port',
        'h': normalizedHost,
        'port': port,
        't': now,
      },
    ]);
    natDomMem.removeWhere((e) => e['h'] == normalizedHost && e['port'] == port);
    natDomMem.insert(0, {'h': normalizedHost, 'port': port, 't': now});
  } catch (e, stk) {
    logError(e, stk);
  }
}

Future<void> natIpMemMergeHits(List<String> hits) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final updates = <String, Map<String, Object?>>{};
  for (final item in hits) {
    final parts = item.split('|');
    if (parts.length < 2) continue;
    final ip = parts[0].trim();
    final port = int.tryParse(parts[1].trim());
    if (InternetAddress.tryParse(ip) == null ||
        port == null || port < 1 || port > 65535) continue;
    updates['$ip|$port'] = <String, Object?>{
      'key': '$ip|$port', 'ip': ip, 'port': port, 't': now,
    };
  }
  if (updates.isEmpty) return;
  final inventory = await _natIpInventory();
  await inventory.upsertBatch(updates.values);
  final updatedKeys = updates.keys.toSet();
  natIpMem.removeWhere((entry) =>
      updatedKeys.contains('${entry['ip']}|${entry['port']}'));
  natIpMem.insertAll(0, <Map<String, dynamic>>[
    for (final record in updates.values)
      <String, dynamic>{
        'ip': record['ip'], 'port': record['port'], 't': now,
      },
  ]);
}

Future<void> natIpMemSave(String ip, int port) async {
  if (InternetAddress.tryParse(ip) == null || port < 1 || port > 65535) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  try {
    final inventory = await _natIpInventory();
    await inventory.upsertBatch(<Map<String, Object?>>[
      <String, Object?>{'key': '$ip|$port', 'ip': ip, 'port': port, 't': now},
    ]);
    natIpMem.removeWhere((e) => e['ip'] == ip && e['port'] == port);
    natIpMem.insert(0, {'ip': ip, 'port': port, 't': now});
  } catch (e, stk) {
    logError(e, stk);
  }
}



/// Stream every configured address in bounded batches. Each range has its own
/// durable offset; -1 marks that range complete for the current full pass.
({List<String> addresses, int nextCursor, Map<String, int> nextRangeCursors, bool passCompleted})
    _natConfiguredRangeBatch(int limit) {
  final staged = Map<String, int>.of(_natConfiguredRangeCursors);
  if (limit <= 0 || natRanges.isEmpty) {
    return (addresses: const <String>[], nextCursor: _natConfiguredRangeCursor,
      nextRangeCursors: staged, passCompleted: true);
  }
  if (natRanges.every((range) => (staged[range] ?? 0) < 0)) {
    return (addresses: const <String>[], nextCursor: _natConfiguredRangeCursor,
      nextRangeCursors: staged, passCompleted: true);
  }
  final out = <String>[];
  var index = _natConfiguredRangeCursor % natRanges.length;
  var visited = 0;
  while (out.length < limit && visited < natRanges.length) {
    final range = natRanges[index];
    final cursor = staged[range] ?? 0;
    if (cursor < 0) {
      index = (index + 1) % natRanges.length;
      visited++;
      continue;
    }
    final generated = _natExpandAnyCursor(range, cursor, limit - out.length);
    out.addAll(generated.$1);
    if (generated.$1.isEmpty || generated.$2 <= cursor) {
      staged[range] = -1;
      index = (index + 1) % natRanges.length;
      visited++;
    } else {
      staged[range] = generated.$2;
      break;
    }
  }
  final complete = natRanges.every((range) => (staged[range] ?? 0) < 0);
  return (
    addresses: out,
    nextCursor: complete ? 0 : index,
    nextRangeCursors: staged,
    passCompleted: complete,
  );
}

Future<void> natRangesSave(String text) async {
  natRanges = <String>{
    ...text.split(RegExp(r'[\r\n,; ]+'))
        .where((x) => x.contains('/') || x.contains('-') ||
            InternetAddress.tryParse(x) != null),
  }.toList(growable: false);
  _natConfiguredRangeCursor = 0;
  _natConfiguredRangeCursors.clear();
  natRangeInventoryPassComplete = false;
  try {
    await _natWriteJsonSnapshot('king_nat_configured_ranges.json', natRanges);
    await _natRangeStateSave();
  } catch (e, stk) {
    logError(e, stk);
  }
}

bool _natIranRangeRefreshBusy = false;

/// Refresh the national scanner's durable range inventory from authoritative
/// country registry data, the existing Iranian ISP inventory, and the active
/// network ASN's currently announced BGP prefixes. Failed refreshes never
/// replace or clear the last known-good inventory.
Future<bool> natRefreshIranRangeInventory({bool force = false}) async {
  if (_natIranRangeRefreshBusy) return false;
  _natIranRangeRefreshBusy = true;
  try {
    final prefs = await SharedPreferences.getInstance();

    // Seed Net Melli from the maintained Iranian ISP inventory even when
    // external registry services are unreachable. This is a one-way additive
    // migration: no previously saved range or cursor is discarded.
    final seedRanges = <String>{...natRanges, ...kIrIspRanges}
        .toList(growable: false);
    if (seedRanges.length != natRanges.length) {
      final seedSet = seedRanges.toSet();
      final seedCursors = Map<String, int>.of(_natConfiguredRangeCursors)
        ..removeWhere((range, _) => !seedSet.contains(range));
      for (final range in seedRanges) {
        seedCursors.putIfAbsent(range, () => 0);
      }
      await _natWriteJsonSnapshot(
        'king_nat_configured_ranges.json',
        seedRanges,
      );
      natRanges = seedRanges;
      _natConfiguredRangeCursors
        ..clear()
        ..addAll(seedCursors);
      _natConfiguredRangeCursor = seedRanges.isEmpty
          ? 0
          : _natConfiguredRangeCursor.clamp(0, seedRanges.length - 1).toInt();
      await _natRangeStateSave();
    }

    final now = DateTime.now();
    final lastSuccess = DateTime.fromMillisecondsSinceEpoch(
      prefs.getInt('natIranRangeRefreshSuccessMs') ?? 0,
    );
    final lastAttempt = DateTime.fromMillisecondsSinceEpoch(
      prefs.getInt('natIranRangeRefreshAttemptMs') ?? 0,
    );
    if (!force &&
        natRanges.isNotEmpty &&
        now.difference(lastSuccess) < const Duration(hours: 24)) {
      return false;
    }
    if (!force &&
        now.difference(lastAttempt) < const Duration(hours: 6)) {
      return false;
    }
    await prefs.setInt('natIranRangeRefreshAttemptMs', now.millisecondsSinceEpoch);

    final countryUri = Uri.https(
      'stat.ripe.net',
      '/data/country-resource-list/data.json',
      <String, String>{
        'resource': 'ir',
        'v4_format': 'prefix',
        'sourceapp': 'kingvpn',
      },
    );
    final countryResponse = await http.get(countryUri)
        .timeout(const Duration(seconds: 15));
    if (countryResponse.statusCode != 200) return false;
    final countryJson = jsonDecode(countryResponse.body);
    final country = NatCountryPrefixSnapshot.parseCountryResources(countryJson);
    if (country == null || country.ipv4.isEmpty) return false;

    final networkType = await _natNetType();
    var activeAsn = _natAsnByType[networkType] ?? '';
    if (activeAsn.isEmpty) {
      await natDetectOperator();
      activeAsn = _natAsnByType[networkType] ?? '';
    }
    // Never mix a foreign roaming/current ISP into Iran's inventory. The
    // detected ASN must also appear in RIPE's country-IR registry snapshot.
    if (activeAsn.isNotEmpty && !country.asns.contains('AS$activeAsn')) {
      activeAsn = '';
    }
    final announced = <String>[];
    final announcedIpv6 = <String>[];
    if (RegExp(r'^[0-9]{1,10}
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

List<int>? _ipTriple(String host) {
  final p = host.split('.');
  if (p.length != 4 || InternetAddress.tryParse(host) == null) return null;
  return [for (final x in p.take(3)) int.parse(x)];
}

List<String> natAutoBlocks(List<Server> known) {
  String blk(int a, int b, int c) => '$a.$b.$c.0/24';
  final hitBlocks = <String>[];
  final near = <String>[];
  final rest = <String>[];
  final hitTriples = <List<int>>[];
  for (final e in natIpMem) {
    final t = _ipTriple('${e['ip']}');
    if (t != null) {
      hitTriples.add(t);
      final b = blk(t[0], t[1], t[2]);
      if (!hitBlocks.contains(b)) hitBlocks.add(b);
    }
  }
  for (final t in hitTriples) {
    for (final d in const [-1, 1]) {
      final c = t[2] + d;
      if (c < 0 || c > 255) continue;
      final b = blk(t[0], t[1], c);
      if (!hitBlocks.contains(b) && !near.contains(b)) near.add(b);
    }
  }
  for (final s in known) {
    final t = _ipTriple(s.host);
    if (t == null) continue;
    final b = blk(t[0], t[1], t[2]);
    if (!hitBlocks.contains(b) && !near.contains(b) && !rest.contains(b)) {
      rest.add(b);
    }
  }
  return [...hitBlocks, ...near, ...rest];
}

int _ipToInt(String ip) {
  final p = ip.split('.').map(int.parse).toList();
  return (p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3];
}

String _intToIp(int v) =>
    '${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}';

List<String> natExpandAny(String item, {int maxPerBlock = 65536}) {
  if (maxPerBlock <= 0) return const [];
  if (!item.contains('-')) return natExpandCidr(item, maxPerBlock: maxPerBlock);
  final parts = item.split('-');
  if (parts.length != 2) return const [];
  final a = InternetAddress.tryParse(parts[0].trim());
  final b = InternetAddress.tryParse(parts[1].trim());
  if (a == null || b == null ||
      a.type != InternetAddressType.IPv4 ||
      b.type != InternetAddressType.IPv4) {
    return const [];
  }
  var start = _ipToInt(a.address);
  var end = _ipToInt(b.address);
  if (end < start) {
    final t = start;
    start = end;
    end = t;
  }
  final out = <String>[];
  final count = end - start + 1;
  final step = count > maxPerBlock
      ? (count + maxPerBlock - 1) ~/ maxPerBlock
      : 1;
  for (var v = start; v <= end && out.length < maxPerBlock; v += step) {
    out.add(_intToIp(v));
  }
  return out;
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
  bool cancelled() => stop != null && stop();
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
      final addresses = parsed == null ? await safeLookup(entry.key) : <InternetAddress>[parsed];
      if (cancelled()) return const <String>[];
      for (final address in addresses) {
        // Both address families are valid endpoint results; the socket scanner
        // performs family-aware connects and preserves IPv6 evidence.
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
        want: entry.value.length,
        budget: null,
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
    final l = await NetworkInterface.list(
        includeLoopback: false, type: InternetAddressType.IPv4);
    for (final i in l) {
      for (final a in i.addresses) {
        final h = a.address;
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
  // A discovered/configured endpoint is an exact target only. IPv6 is stored
  // as /128; no neighboring IPv6 subnet is inferred from one address.
  final out = <String>[];
  final seen = <String>{};
  for (final host in hosts) {
    final parsed = InternetAddress.tryParse(host.trim());
    if (parsed == null) continue;
    final cidr = parsed.type == InternetAddressType.IPv4
        ? '${parsed.address}/32'
        : '${parsed.address}/128';
    if (seen.add(cidr)) out.add(cidr);
  }
  return out;
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

final Map<String, int> _cfRangeCursors = {};
List<String> _getCfIps({
  int batchSize = 160000,
  // فیکس ۳: داخل isolate مقدار سراسری‌ها (بازه‌های زنده و cursorها) وجود ندارد؛ از
  // این دو پارامتر پاس داده می‌شوند. در حالت عادی (null) رفتار قبلی دقیقاً حفظ است.
  List<String>? liveRanges,
  Map<String, int>? cursors,
}) {
  // CDNDIV: fire-and-forget; uses the cached/static list below until this
  // (rate-limited, 6h cache) refresh lands, never blocks the scan.
  if (cursors == null) unawaited(refreshCdnRanges());
  final out = <String>[];
  final ranges = liveRanges ?? _liveCdnRanges;
  final curMap = cursors ?? _cfRangeCursors;
  // Cloudflare همچنان اصلی‌ترین استخر است (کانفیگ‌های CDN-fronted معمولاً روی
  // Cloudflare هستند): نیمی از بودجه برای آن، نیم دیگر بین بقیه‌ی CDNها.
  final cfSet = _cfRanges.toSet();
  final cfN = ranges.where(cfSet.contains).length;
  final otherN = ranges.length - cfN;
  final cfShare = (cfN == 0 || otherN == 0) ? 1.0 : 0.5;
  final perCf = cfN == 0 ? 0 : (batchSize * cfShare / cfN).ceil();
  final perOther =
      otherN == 0 ? 0 : (batchSize * (1.0 - (cfN == 0 ? 0.0 : cfShare)) / otherN).ceil();
  for (final cidr in ranges) {
    final perRange = cfSet.contains(cidr) ? perCf : perOther;
    final parts = cidr.split('/');
    if (parts.length != 2) continue;
    final octets = parts[0].split('.');
    if (octets.length != 4) continue;
    final a = int.tryParse(octets[0]);
    final b = int.tryParse(octets[1]);
    final c = int.tryParse(octets[2]);
    final d = int.tryParse(octets[3]);
    final prefix = int.tryParse(parts[1]);
    if (a == null || b == null || c == null || d == null || prefix == null) continue;
    if (prefix < 0 || prefix > 32) continue;
    final base = (a << 24) | (b << 16) | (c << 8) | d;
    final span = 1 << (32 - prefix);
    var cursor = curMap[cidr] ?? 0;
    for (var i = 0; i < perRange; i++) {
      final offset = (cursor + i) % span;
      final v = base + offset;
      out.add('${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}');
    }
    curMap[cidr] = (cursor + perRange) % span;
  }
  return out;
}

// Cursor-aware exact endpoint and configured IPv4 range expansion.
Map<String, dynamic> _genAddrsIso(Map<String, dynamic> args) {
  final int cfIpsBatch = args['cfIpsBatch'] as int;
  final List<String> blocks = List<String>.from(args['blocks'] as List);
  final bool nationalMode = args['nationalMode'] as bool;
  final List<String> liveRanges = List<String>.from(args['liveRanges'] as List);
  final Map<String, int> cursors = Map<String, int>.from(args['cursors'] as Map);
  final addrs = <String>[];
  // A bounded batch limits transient memory only; durable cursors cover every
  // address in each explicitly configured range over subsequent invocations.
  final cap = max(0, (args['outputLimit'] as int?) ?? max(cfIpsBatch * 4, 20000));
  void addBlocks() {
    if (blocks.isEmpty || cap <= 0) return;
    final start = (cursors['__block_cursor'] ?? 0) % blocks.length;
    var processed = 0;
    while (processed < blocks.length && addrs.length < cap) {
      final index = (start + processed) % blocks.length;
      final range = blocks[index];
      final key = 'block:$range';
      final cursor = cursors[key] ?? 0;
      final generated = _natExpandAnyCursor(
          range, cursor, min(256, cap - addrs.length).toInt());
      if (generated.$1.isNotEmpty) {
        addrs.addAll(generated.$1);
        cursors[key] = generated.$2;
      } else {
        cursors[key] = -1;
      }
      processed++;
    }
    if (processed > 0) {
      cursors['__block_cursor'] = (start + processed) % blocks.length;
    }
  }
  if (nationalMode) {
    addrs.addAll(_getCfIps(batchSize: cfIpsBatch, liveRanges: liveRanges, cursors: cursors));
    addBlocks();
  } else {
    addBlocks();
    addrs.addAll(_getCfIps(batchSize: cfIpsBatch, liveRanges: liveRanges, cursors: cursors));
  }
  return {'addrs': addrs, 'cursors': cursors};
}

/// The per-call limit bounds transient memory only; each valid configured IPv4
/// range is traversed completely by its durable offset. No sampling stride or
/// per-range address ceiling is applied to the runtime inventory.
(List<String>, int) _natExpandAnyCursor(String item, int cursor, int maxPerBlock) {
  final range = NatAddressRangeCursor.parse(item);
  if (range == null) return (<String>[], -1);
  return range.read(cursor, maxPerBlock);
}

// Begin another complete pass only after the previous inventory pass finished.
// Interrupted passes retain their durable cursors and are never reset here.
Future<void> natRangeStartNextPass() async {
  final configuredPassDone = natRanges.isEmpty ||
      natRanges.every((range) => (_natConfiguredRangeCursors[range] ?? 0) < 0);
  final endpointPassDone = _cfRangeCursors['__block_pass_done'] == 1;
  if (!natRangeInventoryPassComplete &&
      !(configuredPassDone && endpointPassDone)) return;
  _natConfiguredRangeCursor = 0;
  _natConfiguredRangeCursors.clear();
  _cfRangeCursors.removeWhere((key, value) =>
      key.startsWith('block:') || key.startsWith('__block_'));
  natRangeInventoryPassComplete = false;
  try {
    await _natRangeStateSave();
  } catch (e, stk) {
    logError(e, stk);
  }
}

// RANGEGUARD: یک اسکن بازه در هر لحظه؛ _natKeep و _natEscalate روی cursors مشترک نمی‌نویسند
bool _natRangeScanBusy = false;

Future<List<String>> natRangeScanStep({
  required List<Server> known,
  int maxAddrs = 256,
  int conc = 4,
  bool Function()? stop,
  bool coordinatorOwned = false,
}) async {
  if ((dnsxManualBusy && !coordinatorOwned) || _natRangeScanBusy) return const <String>[];
  _natRangeScanBusy = true;
  try {
    return await _natRangeScanStepBody(
        known: known, maxAddrs: maxAddrs, conc: conc, stop: stop);
  } finally {
    _natRangeScanBusy = false;
  }
}

Future<List<String>> _natRangeScanStepBody({
  required List<Server> known,
  int maxAddrs = 256,
  int conc = 4,
  bool Function()? stop,
}) async {
  // A stop request or a network-mode switch invalidates the whole scan batch.
  // Keep all shared cursors and discoveries unchanged until every phase completes.
  final modeSnapshot = nationalMode;
  bool shouldAbort() =>
      (stop?.call() ?? false) || nationalMode != modeSnapshot;
  if (!kNatIpScanOn || shouldAbort()) return const <String>[];

  var seeds = known;
  if (seeds.length < 50) {
    try {
      final hotSeeds = await natHotNext(800, fetch: false);
      if (shouldAbort()) return const <String>[];
      seeds = [...known, ...hotSeeds];
    } catch (e, stk) {
      logError(e, stk);
      if (shouldAbort()) return const <String>[];
    }
  }
  if (shouldAbort()) return const <String>[];

  // Build endpoint inventory from saved scan hits and IP-literal config hosts.
  // Configured CIDR and dash ranges are expanded by the independent range cursor.
  final hosts = <String>{
    ...natIpMemHosts(),
    for (final server in seeds) if (server.isIp) server.host,
  }.toList(growable: false);
  final blocks = natSeedBlocks(hosts);
  // A changed endpoint inventory starts a fresh traversal generation. This
  // prevents a completed old pass from hiding newly discovered endpoints.
  final inventoryTag = int.parse(
      sha256.convert(utf8.encode(blocks.join('\\n'))).toString().substring(0, 12),
      radix: 16);
  if (_cfRangeCursors['__block_inventory_tag'] != inventoryTag) {
    // Preserve each completed/in-progress block cursor. Only reset the
    // collection-level walk so newly discovered blocks are appended to work.
    _cfRangeCursors.removeWhere((key, value) => key.startsWith('__block_'));
    _cfRangeCursors.removeWhere((key, value) =>
        key.startsWith('block:') && !blocks.contains(key.substring(6)));
    _cfRangeCursors['__block_cursor'] = 0;
    _cfRangeCursors['__block_pass_start'] = 0;
    _cfRangeCursors['__block_pass_done'] = 0;
    _cfRangeCursors['__block_inventory_tag'] = inventoryTag;
  }
  // Every call is one bounded memory batch. The coordinator repeats batches
  // until both configured ranges and exact known endpoints complete a full pass.
  final configuredBatch = modeSnapshot
      ? _natConfiguredRangeBatch(maxAddrs)
      : (
          addresses: const <String>[],
          nextCursor: _natConfiguredRangeCursor,
          nextRangeCursors: Map<String, int>.of(_natConfiguredRangeCursors),
          passCompleted: true,
        );
  final configuredNatRanges = configuredBatch.addresses;
  final blockStart = (_cfRangeCursors['__block_cursor'] ?? 0);
  final blockPassStart = (_cfRangeCursors['__block_pass_start'] ?? blockStart);
  final blockPassDone = _cfRangeCursors['__block_pass_done'] == 1;
  final outputLimit = max(0, maxAddrs - configuredNatRanges.length).toInt();
  final batchBlocks = blockPassDone ? const <String>[] : blocks;
  final args = <String, dynamic>{
    'cfIpsBatch': 0,
    'blocks': batchBlocks,
    'nationalMode': modeSnapshot,
    'liveRanges': <String>[],
    'outputLimit': outputLimit,
    'cursors': Map<String, int>.of(_cfRangeCursors),
  };
  final gen = await compute(_genAddrsIso, args);
  if (shouldAbort()) return const <String>[];

  final generatedCursors = Map<String, int>.from(gen['cursors'] as Map);
  final nextBlockCursor = (generatedCursors['__block_cursor'] ?? blockStart);
  final endpointPassComplete = batchBlocks.isEmpty ||
      (outputLimit > 0 && nextBlockCursor == blockPassStart);
  generatedCursors['__block_pass_start'] =
      endpointPassComplete ? nextBlockCursor : blockPassStart;
  if (endpointPassComplete) {
    generatedCursors['__block_pass_done'] = 1;
  }
  final addrs = <String>{
    ...configuredNatRanges,
    ...(gen['addrs'] as List).cast<String>(),
  }.toList(growable: false);
  final slice = addrs;
  final out = <String>[];
  final portList = natAutoPorts(seeds);

  // The batch is bounded in address count and worker concurrency, not by a
  // wall-clock deadline. Each socket probe has its own timeout; cancellation
  // and network-mode changes still abort immediately.
  for (final port in portList) {
    if (shouldAbort()) return const <String>[];
    final hits = await natScanIps(
      slice,
      port: port,
      concurrency: conc,
      want: slice.length,
      budget: null,
      timeout: const Duration(milliseconds: 1500),
      cancelled: shouldAbort,
    );
    if (shouldAbort()) return const <String>[];
    for (final hit in hits) {
      out.add('${hit.ip}|$port');
    }
  }
  if (shouldAbort()) return const <String>[];
  // Persist every responsive IP:port before advancing its range cursor. If the
  // app is killed before _natRangeAdd builds configs, the endpoint is still in
  // the durable inventory and can be resumed/retested on the next pass.
  await natIpMemMergeHits(out);
  if (shouldAbort()) return const <String>[];

  final nextConfiguredCursor =
      modeSnapshot ? configuredBatch.nextCursor : _natConfiguredRangeCursor;
  final nextConfiguredCursors = modeSnapshot
      ? configuredBatch.nextRangeCursors
      : Map<String, int>.of(_natConfiguredRangeCursors);
  final passComplete = configuredBatch.passCompleted && endpointPassComplete;
  if (shouldAbort()) return const <String>[];
  // Persist the staged cursors before publishing them in memory. A failed
  // durable write therefore cannot silently skip an uncommitted batch.
  await _natRangeStateSave(
    configuredCursor: nextConfiguredCursor,
    configuredCursors: nextConfiguredCursors,
    endpointCursors: generatedCursors,
  );
  if (shouldAbort()) return const <String>[];
  _cfRangeCursors
    ..clear()
    ..addAll(generatedCursors);
  if (modeSnapshot) {
    _natConfiguredRangeCursor = nextConfiguredCursor;
    _natConfiguredRangeCursors
      ..clear()
      ..addAll(nextConfiguredCursors);
  }
  natRangeInventoryPassComplete = passComplete;
  natTemplateSeeds = List<Server>.of(seeds);
  natRandomLast = 0;
  natIpScanned += slice.length;
  natRangeScanBatchSequence++;
  return out;
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

// HOTCAP: کاهش از ۲ میلیون برای جلوگیری از OOM روی گوشی ضعیف
const int natHotPerSource = 80000;
const int natHotMin = 30000;
const int natHotMax = 400000;
List<Server> Function()? natExtraSource;
const Duration natHotTtl = Duration(hours: 72);
const Duration natHotFetchDeadline = Duration(seconds: 900);
bool _hotBusy = false;
DateTime? _hotFailAt;
int _hotCursor = 0;
Map<String, double> natSrcRates = {};

class _HotIdx {
  final String file;
  final List<int> offs;
  _HotIdx(this.file, this.offs);
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
    try {
      final raw = await src.readAsString();
      final masked = _maskUuidsForExport(raw);
      await dst.writeAsString(masked, flush: true);
    } catch (e) {
      // فیکس ۳: اگر ماسک شکست خورد، نسخه‌ی بدون ماسک نوشته نمی‌شود (نشت UUID ممنوع)
      dbg('hotExport: ماسک ناموفق؛ خروجی نوشته نشد: $e');
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

// فیکس ۱۱: split خط‌ها برای بدنه‌ی بزرگ لیست (top-level تا با compute کار کند)
List<String> _hotSplitIso(String body) => body.split(RegExp(r'[\r\n]+'));

Future<List<String>> _hotFetchOne(String u) async {
  final out = <String>[];
  try {
    final r = await getListMirror(u);
    if (r.statusCode != 200) return out;
    var body = r.body.trim();
    if (body.contains('<html') || body.contains('<!DOCTYPE')) {
      body = _linkRe
          .allMatches(body.replaceAll('&amp;', '&'))
          .map((m) => m.group(0)!)
          .join('\n');
    }
    if (!body.contains('://')) {
      if (!RegExp(r'^[A-Za-z0-9+/=_\-\s]+$').hasMatch(body)) return out;
      try {
        body = utf8.decode(
            base64.decode(base64.normalize(body.replaceAll(RegExp(r'\s'), ''))),
            allowMalformed: true);
      } catch (jex, jstk) { errJournalAdd(jex, st: jstk);
        return out;
      }
    }
    // فیکس ۱۱: split روی رشته‌ی چند مگابایتی در isolate انجام می‌شود
    final lines = await compute(_hotSplitIso, body);
    for (final l in lines) {
      if (out.length >= natHotPerSource) break;
      final t = l.trim();
      if (!t.contains('://') || t.contains('[email') || t.contains('protected]')) {
        continue;
      }
      out.add('$u\t$t');
    }
  } catch (e, stk) {
    logError(e, stk);
  }
  return out;
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
    final sw = Stopwatch()..start();
    try {
      await pool<int>([for (var i = 0; i < urls.length; i++) i], fetchWorkers,
          (i) async {
        if (sw.elapsed > natHotFetchDeadline) return;
        final lines = await _hotFetchOne(urls[i]);
        if (lines.isEmpty) return;
        await File(parts[i]).writeAsString(lines.join('\n'), flush: true);
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
      final offs = <int>[0];
      var pos = 0;
      final sink = File(newPath).openWrite();
      try {
        var full = false;
        final seenKeys = <String>{};
        final mergeFrom = <String>[
          if (File(extraPath).existsSync()) extraPath,
          for (final i in mixed) parts[i],
        ];
        for (final pth in mergeFrom) {
          if (full) break;
          final pf = File(pth);
          if (!pf.existsSync()) continue;
          await for (final line in pf
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
            if (line.isEmpty) continue;
            final tab = line.indexOf('\t');
            final cfg = tab >= 0 ? line.substring(tab + 1) : line;
            if (!seenKeys.add(cfg)) continue;
            final b = utf8.encode(line);
            sink.add(b);
            sink.add(const [10]);
            pos += b.length + 1;
            offs.add(pos);
            if (offs.length - 1 >= natHotMax) {
              full = true;
              break;
            }
          }
        }
      } finally {
        await sink.close();
      }
      final total = offs.length - 1;
      final oldIdx = await _hotLoad();
      final oldTotal = oldIdx == null ? 0 : oldIdx.offs.length - 1;
      if (total > 0 && oldTotal > 0 && total < oldTotal ~/ 2) {
        dbg('پوشه‌ی منابع تازه: ساخت جدید فقط $total کانفیگ داشت (قبلی $oldTotal)؛ پوشه‌ی قبلی نگه داشته شد');
        _hotFailAt = DateTime.now();
        try {
          await File(newPath).delete();
        } catch (e) { errJournalAdd(e, kind: 'SILENT-FILE'); }
      } else if (total > 0) {
        _hotFailAt = null;
        await File(newPath).rename(_hotPath());
        _hot = _HotIdx(_hotPath(), offs);
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

// فیکس ۴: ساخت جدول offset خط‌ها برای فایل‌های بزرگ (> 512KB) در isolate انجام می‌شود
// تا حلقه‌ی بایت‌به‌بایت روی چند مگابایت ترد UI را نگیرد. منطق offs عیناً همان است.
Future<List<int>> _hotBuildOffsets(String path) =>
    compute(_hotOffsetsIso, path);

Future<List<int>> _hotOffsetsIso(String path) async {
  final offs = <int>[0];
  var pos = 0;
  await for (final chunk in File(path).openRead()) {
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] == 10) offs.add(pos + i + 1);
    }
    pos += chunk.length;
  }
  if (offs.last != pos) offs.add(pos);
  return offs;
}

Future<_HotIdx?> _hotLoad() async {
  final cur = _hot;
  if (cur != null) return cur;
  final f = File(_hotPath());
  try {
    if (!f.existsSync() || f.lengthSync() == 0) return null;
    List<int> offs;
    if (f.lengthSync() > 512 * 1024) {
      offs = await _hotBuildOffsets(f.path);
    } else {
      offs = <int>[0];
      var pos = 0;
      await for (final chunk in f.openRead()) {
        for (var i = 0; i < chunk.length; i++) {
          if (chunk[i] == 10) offs.add(pos + i + 1);
        }
        pos += chunk.length;
      }
      if (offs.last != pos) offs.add(pos);
    }
    _hot = _HotIdx(f.path, offs);
    _hotCursor = 0;
    return _hot;
  } catch (e, stk) {
    logError(e, stk);
    return null;
  }
}

Future<List<Server>> natHotNext(int n,
    {bool fetch = true, bool retried = false}) async {
  try {
    if (fetch) unawaited(natHotEnsure());
    final h = await _hotLoad();
    if (h == null) return const [];
    final lines = h.offs.length - 1;
    if (lines <= 0) return const [];
    final out = <Server>[];
    final raf = await File(h.file).open();
    try {
      // HOTSTALE: طول handle باز را با ایندکس بسنج؛ handle به inode ثابت است، پس
      // اگر فایل وسط rename عوض شده باشد، این مقایسه ناهم‌خوانی را می‌گیرد
      if (await raf.length() != h.offs.last) {
        _hot = null; // ایندکس قدیمی را دور بریز
        if (retried) return const [];
        return natHotNext(n, fetch: false, retried: true);
      }
      var read = 0;
      while (out.length < n && read < lines) {
        var start = _hotCursor;
        if (start >= lines) start = 0;
        final take = min(min(n - out.length, lines - start), lines - read);
        final from = h.offs[start];
        final to = h.offs[start + take];
        await raf.setPosition(from);
        final bytes = await raf.read(to - from);
        final text = utf8.decode(bytes, allowMalformed: true);
        for (final e in text.split('\n')) {
          final i = e.indexOf('\t');
          if (i < 0) continue;
          final s = Server.parse(e.substring(i + 1));
          if (s != null) {
            s.src = e.substring(0, i);
            out.add(s);
          }
        }
        read += take;
        _hotCursor = (start + take) % lines;
      }
    } finally {
      await raf.close();
    }
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
  if (ip == null || ip.type != InternetAddressType.IPv4) return false;
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
).hasMatch(activeAsn)) {
      final announcedUri = Uri.https(
        'stat.ripe.net',
        '/data/announced-prefixes/data.json',
        <String, String>{
          'resource': 'AS$activeAsn',
          'min_peers_seeing': '1',
          'sourceapp': 'kingvpn',
        },
      );
      try {
        final response = await http.get(announcedUri)
            .timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          final announcedPayload = jsonDecode(response.body);
          announced.addAll(
            NatCountryPrefixSnapshot.parseAnnouncedIpv4(announcedPayload),
          );
          announcedIpv6.addAll(
            NatCountryPrefixSnapshot.parseAnnouncedIpv6(announcedPayload),
          );
        }
      } catch (e, stk) {
        // Registry resources remain useful if the live BGP endpoint is
        // temporarily unavailable. Preserve the previous active-ASN cache.
        logError(e, stk);
      }
    }

    final merged = <String>{
      ...natRanges,
      ...kIrIspRanges,
      ...country.ipv4,
      ...announced,
    }.toList(growable: false);
    if (merged.isEmpty) return false;
    final ipv6Merged = <String>{
      ...natIranIpv6Prefixes,
      ...country.ipv6,
      ...announcedIpv6,
    }.toList()..sort();

    final mergedSet = merged.toSet();
    final nextCursors = Map<String, int>.of(_natConfiguredRangeCursors)
      ..removeWhere((range, _) => !mergedSet.contains(range));
    for (final range in merged) {
      nextCursors.putIfAbsent(range, () => 0);
    }
    final nextRangeCursor = merged.isEmpty
        ? 0
        : _natConfiguredRangeCursor.clamp(0, merged.length - 1).toInt();

    // Commit the inventory before its cursors. The previous inventory remains
    // intact if the source fetch or atomic snapshot write fails.
    await _natWriteJsonSnapshot('king_nat_configured_ranges.json', merged);
    natRanges = merged;
    natIranIpv6Prefixes = ipv6Merged;
    _natConfiguredRangeCursors
      ..clear()
      ..addAll(nextCursors);
    _natConfiguredRangeCursor = nextRangeCursor;
    await _natRangeStateSave();

    await _natWriteJsonSnapshot(
      'king_nat_country_prefix_sources.json',
      <String, Object?>{
        'schema': 1,
        'country': 'IR',
        'source': 'RIPEstat country-resource-list + announced-prefixes',
        'fetchedAt': now.toUtc().toIso8601String(),
        'registryAsns': country.asns,
        'registryIpv6Prefixes': country.ipv6,
        'activeAsnAnnouncedIpv6Prefixes': announcedIpv6,
        'ipv6Prefixes': ipv6Merged,
        'activeNetworkType': networkType,
        'activeAsn': activeAsn.isEmpty ? null : 'AS$activeAsn',
        'activeAsnAnnouncedIpv4Count': announced.length,
        'ipv4InventoryCount': merged.length,
      },
    );
    await prefs.setInt(
      'natIranRangeRefreshSuccessMs',
      now.millisecondsSinceEpoch,
    );
    return true;
  } catch (e, stk) {
    logError(e, stk);
    return false;
  } finally {
    _natIranRangeRefreshBusy = false;
  }
}

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

List<int>? _ipTriple(String host) {
  final p = host.split('.');
  if (p.length != 4 || InternetAddress.tryParse(host) == null) return null;
  return [for (final x in p.take(3)) int.parse(x)];
}

List<String> natAutoBlocks(List<Server> known) {
  String blk(int a, int b, int c) => '$a.$b.$c.0/24';
  final hitBlocks = <String>[];
  final near = <String>[];
  final rest = <String>[];
  final hitTriples = <List<int>>[];
  for (final e in natIpMem) {
    final t = _ipTriple('${e['ip']}');
    if (t != null) {
      hitTriples.add(t);
      final b = blk(t[0], t[1], t[2]);
      if (!hitBlocks.contains(b)) hitBlocks.add(b);
    }
  }
  for (final t in hitTriples) {
    for (final d in const [-1, 1]) {
      final c = t[2] + d;
      if (c < 0 || c > 255) continue;
      final b = blk(t[0], t[1], c);
      if (!hitBlocks.contains(b) && !near.contains(b)) near.add(b);
    }
  }
  for (final s in known) {
    final t = _ipTriple(s.host);
    if (t == null) continue;
    final b = blk(t[0], t[1], t[2]);
    if (!hitBlocks.contains(b) && !near.contains(b) && !rest.contains(b)) {
      rest.add(b);
    }
  }
  return [...hitBlocks, ...near, ...rest];
}

int _ipToInt(String ip) {
  final p = ip.split('.').map(int.parse).toList();
  return (p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3];
}

String _intToIp(int v) =>
    '${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}';

List<String> natExpandAny(String item, {int maxPerBlock = 65536}) {
  if (maxPerBlock <= 0) return const [];
  if (!item.contains('-')) return natExpandCidr(item, maxPerBlock: maxPerBlock);
  final parts = item.split('-');
  if (parts.length != 2) return const [];
  final a = InternetAddress.tryParse(parts[0].trim());
  final b = InternetAddress.tryParse(parts[1].trim());
  if (a == null || b == null ||
      a.type != InternetAddressType.IPv4 ||
      b.type != InternetAddressType.IPv4) {
    return const [];
  }
  var start = _ipToInt(a.address);
  var end = _ipToInt(b.address);
  if (end < start) {
    final t = start;
    start = end;
    end = t;
  }
  final out = <String>[];
  final count = end - start + 1;
  final step = count > maxPerBlock
      ? (count + maxPerBlock - 1) ~/ maxPerBlock
      : 1;
  for (var v = start; v <= end && out.length < maxPerBlock; v += step) {
    out.add(_intToIp(v));
  }
  return out;
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
  bool cancelled() => stop != null && stop();
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
      final addresses = parsed == null ? await safeLookup(entry.key) : <InternetAddress>[parsed];
      if (cancelled()) return const <String>[];
      for (final address in addresses) {
        // Both address families are valid endpoint results; the socket scanner
        // performs family-aware connects and preserves IPv6 evidence.
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
        want: entry.value.length,
        budget: null,
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
    final l = await NetworkInterface.list(
        includeLoopback: false, type: InternetAddressType.IPv4);
    for (final i in l) {
      for (final a in i.addresses) {
        final h = a.address;
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
  // A discovered/configured endpoint is an exact target only. IPv6 is stored
  // as /128; no neighboring IPv6 subnet is inferred from one address.
  final out = <String>[];
  final seen = <String>{};
  for (final host in hosts) {
    final parsed = InternetAddress.tryParse(host.trim());
    if (parsed == null) continue;
    final cidr = parsed.type == InternetAddressType.IPv4
        ? '${parsed.address}/32'
        : '${parsed.address}/128';
    if (seen.add(cidr)) out.add(cidr);
  }
  return out;
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

final Map<String, int> _cfRangeCursors = {};
List<String> _getCfIps({
  int batchSize = 160000,
  // فیکس ۳: داخل isolate مقدار سراسری‌ها (بازه‌های زنده و cursorها) وجود ندارد؛ از
  // این دو پارامتر پاس داده می‌شوند. در حالت عادی (null) رفتار قبلی دقیقاً حفظ است.
  List<String>? liveRanges,
  Map<String, int>? cursors,
}) {
  // CDNDIV: fire-and-forget; uses the cached/static list below until this
  // (rate-limited, 6h cache) refresh lands, never blocks the scan.
  if (cursors == null) unawaited(refreshCdnRanges());
  final out = <String>[];
  final ranges = liveRanges ?? _liveCdnRanges;
  final curMap = cursors ?? _cfRangeCursors;
  // Cloudflare همچنان اصلی‌ترین استخر است (کانفیگ‌های CDN-fronted معمولاً روی
  // Cloudflare هستند): نیمی از بودجه برای آن، نیم دیگر بین بقیه‌ی CDNها.
  final cfSet = _cfRanges.toSet();
  final cfN = ranges.where(cfSet.contains).length;
  final otherN = ranges.length - cfN;
  final cfShare = (cfN == 0 || otherN == 0) ? 1.0 : 0.5;
  final perCf = cfN == 0 ? 0 : (batchSize * cfShare / cfN).ceil();
  final perOther =
      otherN == 0 ? 0 : (batchSize * (1.0 - (cfN == 0 ? 0.0 : cfShare)) / otherN).ceil();
  for (final cidr in ranges) {
    final perRange = cfSet.contains(cidr) ? perCf : perOther;
    final parts = cidr.split('/');
    if (parts.length != 2) continue;
    final octets = parts[0].split('.');
    if (octets.length != 4) continue;
    final a = int.tryParse(octets[0]);
    final b = int.tryParse(octets[1]);
    final c = int.tryParse(octets[2]);
    final d = int.tryParse(octets[3]);
    final prefix = int.tryParse(parts[1]);
    if (a == null || b == null || c == null || d == null || prefix == null) continue;
    if (prefix < 0 || prefix > 32) continue;
    final base = (a << 24) | (b << 16) | (c << 8) | d;
    final span = 1 << (32 - prefix);
    var cursor = curMap[cidr] ?? 0;
    for (var i = 0; i < perRange; i++) {
      final offset = (cursor + i) % span;
      final v = base + offset;
      out.add('${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}');
    }
    curMap[cidr] = (cursor + perRange) % span;
  }
  return out;
}

// Cursor-aware exact endpoint and configured IPv4 range expansion.
Map<String, dynamic> _genAddrsIso(Map<String, dynamic> args) {
  final int cfIpsBatch = args['cfIpsBatch'] as int;
  final List<String> blocks = List<String>.from(args['blocks'] as List);
  final bool nationalMode = args['nationalMode'] as bool;
  final List<String> liveRanges = List<String>.from(args['liveRanges'] as List);
  final Map<String, int> cursors = Map<String, int>.from(args['cursors'] as Map);
  final addrs = <String>[];
  // A bounded batch limits transient memory only; durable cursors cover every
  // address in each explicitly configured range over subsequent invocations.
  final cap = max(0, (args['outputLimit'] as int?) ?? max(cfIpsBatch * 4, 20000));
  void addBlocks() {
    if (blocks.isEmpty || cap <= 0) return;
    final start = (cursors['__block_cursor'] ?? 0) % blocks.length;
    var processed = 0;
    while (processed < blocks.length && addrs.length < cap) {
      final index = (start + processed) % blocks.length;
      final range = blocks[index];
      final key = 'block:$range';
      final cursor = cursors[key] ?? 0;
      final generated = _natExpandAnyCursor(
          range, cursor, min(256, cap - addrs.length).toInt());
      if (generated.$1.isNotEmpty) {
        addrs.addAll(generated.$1);
        cursors[key] = generated.$2;
      } else {
        cursors[key] = -1;
      }
      processed++;
    }
    if (processed > 0) {
      cursors['__block_cursor'] = (start + processed) % blocks.length;
    }
  }
  if (nationalMode) {
    addrs.addAll(_getCfIps(batchSize: cfIpsBatch, liveRanges: liveRanges, cursors: cursors));
    addBlocks();
  } else {
    addBlocks();
    addrs.addAll(_getCfIps(batchSize: cfIpsBatch, liveRanges: liveRanges, cursors: cursors));
  }
  return {'addrs': addrs, 'cursors': cursors};
}

/// The per-call limit bounds transient memory only; each valid configured IPv4
/// range is traversed completely by its durable offset. No sampling stride or
/// per-range address ceiling is applied to the runtime inventory.
(List<String>, int) _natExpandAnyCursor(String item, int cursor, int maxPerBlock) {
  final range = NatAddressRangeCursor.parse(item);
  if (range == null) return (<String>[], -1);
  return range.read(cursor, maxPerBlock);
}

// Begin another complete pass only after the previous inventory pass finished.
// Interrupted passes retain their durable cursors and are never reset here.
Future<void> natRangeStartNextPass() async {
  final configuredPassDone = natRanges.isEmpty ||
      natRanges.every((range) => (_natConfiguredRangeCursors[range] ?? 0) < 0);
  final endpointPassDone = _cfRangeCursors['__block_pass_done'] == 1;
  if (!natRangeInventoryPassComplete &&
      !(configuredPassDone && endpointPassDone)) return;
  _natConfiguredRangeCursor = 0;
  _natConfiguredRangeCursors.clear();
  _cfRangeCursors.removeWhere((key, value) =>
      key.startsWith('block:') || key.startsWith('__block_'));
  natRangeInventoryPassComplete = false;
  try {
    await _natRangeStateSave();
  } catch (e, stk) {
    logError(e, stk);
  }
}

// RANGEGUARD: یک اسکن بازه در هر لحظه؛ _natKeep و _natEscalate روی cursors مشترک نمی‌نویسند
bool _natRangeScanBusy = false;

Future<List<String>> natRangeScanStep({
  required List<Server> known,
  int maxAddrs = 256,
  int conc = 4,
  bool Function()? stop,
  bool coordinatorOwned = false,
}) async {
  if ((dnsxManualBusy && !coordinatorOwned) || _natRangeScanBusy) return const <String>[];
  _natRangeScanBusy = true;
  try {
    return await _natRangeScanStepBody(
        known: known, maxAddrs: maxAddrs, conc: conc, stop: stop);
  } finally {
    _natRangeScanBusy = false;
  }
}

Future<List<String>> _natRangeScanStepBody({
  required List<Server> known,
  int maxAddrs = 256,
  int conc = 4,
  bool Function()? stop,
}) async {
  // A stop request or a network-mode switch invalidates the whole scan batch.
  // Keep all shared cursors and discoveries unchanged until every phase completes.
  final modeSnapshot = nationalMode;
  bool shouldAbort() =>
      (stop?.call() ?? false) || nationalMode != modeSnapshot;
  if (!kNatIpScanOn || shouldAbort()) return const <String>[];

  var seeds = known;
  if (seeds.length < 50) {
    try {
      final hotSeeds = await natHotNext(800, fetch: false);
      if (shouldAbort()) return const <String>[];
      seeds = [...known, ...hotSeeds];
    } catch (e, stk) {
      logError(e, stk);
      if (shouldAbort()) return const <String>[];
    }
  }
  if (shouldAbort()) return const <String>[];

  // Build endpoint inventory from saved scan hits and IP-literal config hosts.
  // Configured CIDR and dash ranges are expanded by the independent range cursor.
  final hosts = <String>{
    ...natIpMemHosts(),
    for (final server in seeds) if (server.isIp) server.host,
  }.toList(growable: false);
  final blocks = natSeedBlocks(hosts);
  // A changed endpoint inventory starts a fresh traversal generation. This
  // prevents a completed old pass from hiding newly discovered endpoints.
  final inventoryTag = int.parse(
      sha256.convert(utf8.encode(blocks.join('\\n'))).toString().substring(0, 12),
      radix: 16);
  if (_cfRangeCursors['__block_inventory_tag'] != inventoryTag) {
    // Preserve each completed/in-progress block cursor. Only reset the
    // collection-level walk so newly discovered blocks are appended to work.
    _cfRangeCursors.removeWhere((key, value) => key.startsWith('__block_'));
    _cfRangeCursors.removeWhere((key, value) =>
        key.startsWith('block:') && !blocks.contains(key.substring(6)));
    _cfRangeCursors['__block_cursor'] = 0;
    _cfRangeCursors['__block_pass_start'] = 0;
    _cfRangeCursors['__block_pass_done'] = 0;
    _cfRangeCursors['__block_inventory_tag'] = inventoryTag;
  }
  // Every call is one bounded memory batch. The coordinator repeats batches
  // until both configured ranges and exact known endpoints complete a full pass.
  final configuredBatch = modeSnapshot
      ? _natConfiguredRangeBatch(maxAddrs)
      : (
          addresses: const <String>[],
          nextCursor: _natConfiguredRangeCursor,
          nextRangeCursors: Map<String, int>.of(_natConfiguredRangeCursors),
          passCompleted: true,
        );
  final configuredNatRanges = configuredBatch.addresses;
  final blockStart = (_cfRangeCursors['__block_cursor'] ?? 0);
  final blockPassStart = (_cfRangeCursors['__block_pass_start'] ?? blockStart);
  final blockPassDone = _cfRangeCursors['__block_pass_done'] == 1;
  final outputLimit = max(0, maxAddrs - configuredNatRanges.length).toInt();
  final batchBlocks = blockPassDone ? const <String>[] : blocks;
  final args = <String, dynamic>{
    'cfIpsBatch': 0,
    'blocks': batchBlocks,
    'nationalMode': modeSnapshot,
    'liveRanges': <String>[],
    'outputLimit': outputLimit,
    'cursors': Map<String, int>.of(_cfRangeCursors),
  };
  final gen = await compute(_genAddrsIso, args);
  if (shouldAbort()) return const <String>[];

  final generatedCursors = Map<String, int>.from(gen['cursors'] as Map);
  final nextBlockCursor = (generatedCursors['__block_cursor'] ?? blockStart);
  final endpointPassComplete = batchBlocks.isEmpty ||
      (outputLimit > 0 && nextBlockCursor == blockPassStart);
  generatedCursors['__block_pass_start'] =
      endpointPassComplete ? nextBlockCursor : blockPassStart;
  if (endpointPassComplete) {
    generatedCursors['__block_pass_done'] = 1;
  }
  final addrs = <String>{
    ...configuredNatRanges,
    ...(gen['addrs'] as List).cast<String>(),
  }.toList(growable: false);
  final slice = addrs;
  final out = <String>[];
  final portList = natAutoPorts(seeds);

  // The batch is bounded in address count and worker concurrency, not by a
  // wall-clock deadline. Each socket probe has its own timeout; cancellation
  // and network-mode changes still abort immediately.
  for (final port in portList) {
    if (shouldAbort()) return const <String>[];
    final hits = await natScanIps(
      slice,
      port: port,
      concurrency: conc,
      want: slice.length,
      budget: null,
      timeout: const Duration(milliseconds: 1500),
      cancelled: shouldAbort,
    );
    if (shouldAbort()) return const <String>[];
    for (final hit in hits) {
      out.add('${hit.ip}|$port');
    }
  }
  if (shouldAbort()) return const <String>[];
  // Persist every responsive IP:port before advancing its range cursor. If the
  // app is killed before _natRangeAdd builds configs, the endpoint is still in
  // the durable inventory and can be resumed/retested on the next pass.
  await natIpMemMergeHits(out);
  if (shouldAbort()) return const <String>[];

  final nextConfiguredCursor =
      modeSnapshot ? configuredBatch.nextCursor : _natConfiguredRangeCursor;
  final nextConfiguredCursors = modeSnapshot
      ? configuredBatch.nextRangeCursors
      : Map<String, int>.of(_natConfiguredRangeCursors);
  final passComplete = configuredBatch.passCompleted && endpointPassComplete;
  if (shouldAbort()) return const <String>[];
  // Persist the staged cursors before publishing them in memory. A failed
  // durable write therefore cannot silently skip an uncommitted batch.
  await _natRangeStateSave(
    configuredCursor: nextConfiguredCursor,
    configuredCursors: nextConfiguredCursors,
    endpointCursors: generatedCursors,
  );
  if (shouldAbort()) return const <String>[];
  _cfRangeCursors
    ..clear()
    ..addAll(generatedCursors);
  if (modeSnapshot) {
    _natConfiguredRangeCursor = nextConfiguredCursor;
    _natConfiguredRangeCursors
      ..clear()
      ..addAll(nextConfiguredCursors);
  }
  natRangeInventoryPassComplete = passComplete;
  natTemplateSeeds = List<Server>.of(seeds);
  natRandomLast = 0;
  natIpScanned += slice.length;
  natRangeScanBatchSequence++;
  return out;
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

// HOTCAP: کاهش از ۲ میلیون برای جلوگیری از OOM روی گوشی ضعیف
const int natHotPerSource = 80000;
const int natHotMin = 30000;
const int natHotMax = 400000;
List<Server> Function()? natExtraSource;
const Duration natHotTtl = Duration(hours: 72);
const Duration natHotFetchDeadline = Duration(seconds: 900);
bool _hotBusy = false;
DateTime? _hotFailAt;
int _hotCursor = 0;
Map<String, double> natSrcRates = {};

class _HotIdx {
  final String file;
  final List<int> offs;
  _HotIdx(this.file, this.offs);
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
    try {
      final raw = await src.readAsString();
      final masked = _maskUuidsForExport(raw);
      await dst.writeAsString(masked, flush: true);
    } catch (e) {
      // فیکس ۳: اگر ماسک شکست خورد، نسخه‌ی بدون ماسک نوشته نمی‌شود (نشت UUID ممنوع)
      dbg('hotExport: ماسک ناموفق؛ خروجی نوشته نشد: $e');
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

// فیکس ۱۱: split خط‌ها برای بدنه‌ی بزرگ لیست (top-level تا با compute کار کند)
List<String> _hotSplitIso(String body) => body.split(RegExp(r'[\r\n]+'));

Future<List<String>> _hotFetchOne(String u) async {
  final out = <String>[];
  try {
    final r = await getListMirror(u);
    if (r.statusCode != 200) return out;
    var body = r.body.trim();
    if (body.contains('<html') || body.contains('<!DOCTYPE')) {
      body = _linkRe
          .allMatches(body.replaceAll('&amp;', '&'))
          .map((m) => m.group(0)!)
          .join('\n');
    }
    if (!body.contains('://')) {
      if (!RegExp(r'^[A-Za-z0-9+/=_\-\s]+$').hasMatch(body)) return out;
      try {
        body = utf8.decode(
            base64.decode(base64.normalize(body.replaceAll(RegExp(r'\s'), ''))),
            allowMalformed: true);
      } catch (jex, jstk) { errJournalAdd(jex, st: jstk);
        return out;
      }
    }
    // فیکس ۱۱: split روی رشته‌ی چند مگابایتی در isolate انجام می‌شود
    final lines = await compute(_hotSplitIso, body);
    for (final l in lines) {
      if (out.length >= natHotPerSource) break;
      final t = l.trim();
      if (!t.contains('://') || t.contains('[email') || t.contains('protected]')) {
        continue;
      }
      out.add('$u\t$t');
    }
  } catch (e, stk) {
    logError(e, stk);
  }
  return out;
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
    final sw = Stopwatch()..start();
    try {
      await pool<int>([for (var i = 0; i < urls.length; i++) i], fetchWorkers,
          (i) async {
        if (sw.elapsed > natHotFetchDeadline) return;
        final lines = await _hotFetchOne(urls[i]);
        if (lines.isEmpty) return;
        await File(parts[i]).writeAsString(lines.join('\n'), flush: true);
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
      final offs = <int>[0];
      var pos = 0;
      final sink = File(newPath).openWrite();
      try {
        var full = false;
        final seenKeys = <String>{};
        final mergeFrom = <String>[
          if (File(extraPath).existsSync()) extraPath,
          for (final i in mixed) parts[i],
        ];
        for (final pth in mergeFrom) {
          if (full) break;
          final pf = File(pth);
          if (!pf.existsSync()) continue;
          await for (final line in pf
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
            if (line.isEmpty) continue;
            final tab = line.indexOf('\t');
            final cfg = tab >= 0 ? line.substring(tab + 1) : line;
            if (!seenKeys.add(cfg)) continue;
            final b = utf8.encode(line);
            sink.add(b);
            sink.add(const [10]);
            pos += b.length + 1;
            offs.add(pos);
            if (offs.length - 1 >= natHotMax) {
              full = true;
              break;
            }
          }
        }
      } finally {
        await sink.close();
      }
      final total = offs.length - 1;
      final oldIdx = await _hotLoad();
      final oldTotal = oldIdx == null ? 0 : oldIdx.offs.length - 1;
      if (total > 0 && oldTotal > 0 && total < oldTotal ~/ 2) {
        dbg('پوشه‌ی منابع تازه: ساخت جدید فقط $total کانفیگ داشت (قبلی $oldTotal)؛ پوشه‌ی قبلی نگه داشته شد');
        _hotFailAt = DateTime.now();
        try {
          await File(newPath).delete();
        } catch (e) { errJournalAdd(e, kind: 'SILENT-FILE'); }
      } else if (total > 0) {
        _hotFailAt = null;
        await File(newPath).rename(_hotPath());
        _hot = _HotIdx(_hotPath(), offs);
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

// فیکس ۴: ساخت جدول offset خط‌ها برای فایل‌های بزرگ (> 512KB) در isolate انجام می‌شود
// تا حلقه‌ی بایت‌به‌بایت روی چند مگابایت ترد UI را نگیرد. منطق offs عیناً همان است.
Future<List<int>> _hotBuildOffsets(String path) =>
    compute(_hotOffsetsIso, path);

Future<List<int>> _hotOffsetsIso(String path) async {
  final offs = <int>[0];
  var pos = 0;
  await for (final chunk in File(path).openRead()) {
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] == 10) offs.add(pos + i + 1);
    }
    pos += chunk.length;
  }
  if (offs.last != pos) offs.add(pos);
  return offs;
}

Future<_HotIdx?> _hotLoad() async {
  final cur = _hot;
  if (cur != null) return cur;
  final f = File(_hotPath());
  try {
    if (!f.existsSync() || f.lengthSync() == 0) return null;
    List<int> offs;
    if (f.lengthSync() > 512 * 1024) {
      offs = await _hotBuildOffsets(f.path);
    } else {
      offs = <int>[0];
      var pos = 0;
      await for (final chunk in f.openRead()) {
        for (var i = 0; i < chunk.length; i++) {
          if (chunk[i] == 10) offs.add(pos + i + 1);
        }
        pos += chunk.length;
      }
      if (offs.last != pos) offs.add(pos);
    }
    _hot = _HotIdx(f.path, offs);
    _hotCursor = 0;
    return _hot;
  } catch (e, stk) {
    logError(e, stk);
    return null;
  }
}

Future<List<Server>> natHotNext(int n,
    {bool fetch = true, bool retried = false}) async {
  try {
    if (fetch) unawaited(natHotEnsure());
    final h = await _hotLoad();
    if (h == null) return const [];
    final lines = h.offs.length - 1;
    if (lines <= 0) return const [];
    final out = <Server>[];
    final raf = await File(h.file).open();
    try {
      // HOTSTALE: طول handle باز را با ایندکس بسنج؛ handle به inode ثابت است، پس
      // اگر فایل وسط rename عوض شده باشد، این مقایسه ناهم‌خوانی را می‌گیرد
      if (await raf.length() != h.offs.last) {
        _hot = null; // ایندکس قدیمی را دور بریز
        if (retried) return const [];
        return natHotNext(n, fetch: false, retried: true);
      }
      var read = 0;
      while (out.length < n && read < lines) {
        var start = _hotCursor;
        if (start >= lines) start = 0;
        final take = min(min(n - out.length, lines - start), lines - read);
        final from = h.offs[start];
        final to = h.offs[start + take];
        await raf.setPosition(from);
        final bytes = await raf.read(to - from);
        final text = utf8.decode(bytes, allowMalformed: true);
        for (final e in text.split('\n')) {
          final i = e.indexOf('\t');
          if (i < 0) continue;
          final s = Server.parse(e.substring(i + 1));
          if (s != null) {
            s.src = e.substring(0, i);
            out.add(s);
          }
        }
        read += take;
        _hotCursor = (start + take) % lines;
      }
    } finally {
      await raf.close();
    }
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
  if (ip == null || ip.type != InternetAddressType.IPv4) return false;
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
