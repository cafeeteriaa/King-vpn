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
const int natMaxVariants = 2000000;
int natFloor = 0;
List<Server> natRestPending = [];

const int _natCodeBase = 100000;
const int _natBaseCount = 50;
// V7: bumped to 3 because the meaning of the port-hopping index changed
// (port 80 added to the CF port list), so old saved generated variants
// no longer point at the same meaning.
const int _natGenVer = 3;

final Map<String, int> natVar = {};

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
    '1-3', '2-8', '5-15', '10-30', '20-50', '30-60', '50-100', '100-200',
    '200-400', '400-800'
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
      this.mss});
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
    '${x.edN}|${x.noise}|${x.noiseK}|${x.nodelay}|${x.doh}|${x.mode}|${x.keep}';

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
    int? keep}) {
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
      keep: keep);
}

List<_NatSpec> _natGenerate() {
  final out = <_NatSpec>[];
  final seen = <String>{for (final b in _natBase) _natSig(b)};
  void add(_NatSpec x) {
    if (seen.add(_natSig(x))) out.add(x);
  }

  const fps = [
    'chrome', 'firefox', 'randomized', 'ios', 'android', 'safari', 'edge',
    'random', 'qq', '360'
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

int natGrow(int n) => 0;

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
  return i == 0 ? url : _natTestUrls[(i - 1) % _natTestUrls.length];
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

bool _natAppliesF(_NatFacts f, int v) {
  if (v < 0 || v >= _natSpecs.length) return false;
  if (v == 0) return true;
  if (natDisabled.contains(v)) return false;
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
  return true;
}

bool _natChangesAddr(int v) {
  if (v <= 0 || v >= _natSpecs.length) return false;
  final x = _natSpecs[v];
  return x.other || x.port || x.clean || x.doh != null;
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
  return d;
}

List<int> _natGenRank = [];
String _natGenRankKey = '';

List<int> _natGenRanked() {
  final key = '$natOpKey|$_natLearnVer|${_natSpecs.length}';
  if (key == _natGenRankKey) return _natGenRank;
  final idx = <int>[for (var i = _natBaseCount; i < _natSpecs.length; i++) i];
  final sc = <int, int>{};
  for (final i in idx) {
    var s = 0;
    for (final d in _natDims(_natSpecs[i])) {
      s += natDimWins['$natOpKey#$d'] ?? 0;
    }
    sc[i] = s;
  }
  idx.sort((a, b) {
    final d = (sc[b] ?? 0) - (sc[a] ?? 0);
    return d != 0 ? d : a - b;
  });
  _natGenRank = idx;
  _natGenRankKey = key;
  return idx;
}

List<int> _natTopWinners(int n) {
  final pre = '$natOpKey#';
  final rows = <MapEntry<int, int>>[];
  natWins.forEach((k, c) {
    if (!k.startsWith(pre)) return;
    final v = int.tryParse(k.substring(pre.length));
    if (v != null && v > 0 && v < _natSpecs.length) rows.add(MapEntry(v, c));
  });
  rows.sort((a, b) => b.value.compareTo(a.value));
  return [for (final r in rows.take(n)) r.key];
}

final Map<String, int> _natCursor = {};
String _natCk(Server s) => '$natOpKey#${s.key}';

void natCursorAdvance(Server s, int n) {
  if (n <= 0) return;
  final k = _natCk(s);
  if (_natCursor.length > 4000) _natCursor.remove(_natCursor.keys.first);
  _natCursor[k] = (_natCursor[k] ?? 0) + n;
}

Duration natBudget({bool full = false}) {
  final l = full ? 3 : natLevel;
  if (l <= 1) return const Duration(seconds: 40);
  if (l == 2) return const Duration(seconds: 75);
  if (l == 3) return const Duration(seconds: 150);
  return const Duration(seconds: 260);
}

const List<int> _natGenCap = [
  0, 0, 200, 1200, 6000, 15000, 30000, 60000, 100000, 150000, 200000
];

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
  if (knownOk && (!skipHeavy || !natIsHeavy(known!))) put(known!);

  if (preferLight) {
    final lightFirst = <int>[0, 1, 4, 13, 7, 20, 12, 33, 38, 40, 44];
    for (final w in _natTopWinners(8)) {
      if (!natIsHeavy(w) && !lightFirst.contains(w)) lightFirst.add(w);
    }
    for (final v in lightFirst) {
      if (_natAppliesF(f, v)) put(v);
    }
  }

  // KCP is registered after _natGenerate(), so it has no rank on fresh installs.
  // Test it early at level >= 2, only in national mode (where heavy variants run).
  if (lvl >= 2 && nationalMode) {
    final kcpIdx = _natSpecs.indexWhere((x) => x.mode == 'kcp:none');
    if (kcpIdx > 0 && _natAppliesF(f, kcpIdx)) put(kcpIdx);
  }

  if (lvl >= 2) {
    for (final w in _natTopWinners(6)) {
      if (skipHeavy && natIsHeavy(w)) continue;
      if (_natAppliesF(f, w)) put(w);
    }
  }

  final cand = (lvl >= 2
      ? <int>[for (var i = 0; i < _natBaseCount; i++) i]
      : <int>[0, 1, 2, 8])
    ..sort((a, b) {
      if (preferLight) {
        final ha = natIsHeavy(a) ? 1 : 0;
        final hb = natIsHeavy(b) ? 1 : 0;
        if (ha != hb) return ha - hb;
      }
      final d = (natWins['$natOpKey#$b'] ?? 0) - (natWins['$natOpKey#$a'] ?? 0);
      return d != 0 ? d : a - b;
    });
  if (!again) {
    if (!knownOk || (preferLight && knownOk && natIsHeavy(known!))) {
      for (final v in cand) {
        if (skipHeavy && natIsHeavy(v)) continue;
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
      if (skipHeavy && natIsHeavy(v)) continue;
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
    if (app.isNotEmpty && cursor < app.length) {
      final end = min(app.length, cursor + cap);
      for (var k = cursor; k < end; k++) {
        final gv = app[k];
        if (skipHeavy && natIsHeavy(gv)) continue;
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
      var b = link.substring(8);
      b = b.padRight(b.length + (4 - b.length % 4) % 4, '=');
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
      var b = link.substring(8);
      b = b.padRight(b.length + (4 - b.length % 4) % 4, '=');
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
      var b = link.substring(8);
      b = b.padRight(b.length + (4 - b.length % 4) % 4, '=');
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
      var b = link.substring(8);
      b = b.padRight(b.length + (4 - b.length % 4) % 4, '=');
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
Future<bool> natDohUsable(int v) async {
  if (v < 0 || v >= _natSpecs.length) return false;
  final doh = _natSpecs[v].doh;
  if (doh == null) return true;
  final cached = dohPreOk[v];
  if (cached != null) return cached;
  var host = doh;
  final u = Uri.tryParse(doh);
  if (u != null && u.hasAuthority) host = u.host;
  final ms = await natTcpProbe(host, 443, const Duration(seconds: 4));
  final ok = ms != null;
  dohPreOk[v] = ok;
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
  if (x.sniHost) {
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
    if (RegExp(r'"flow"\s*:\s*"xtls').hasMatch(cfg)) return cfg;
    o['mux'] = {'enabled': true, 'concurrency': n > 0 ? n : 8};
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
    sanitizeCfg(_natCfgRaw(s, v, reuse: reuse));

String _natCfgRaw(Server s, int v, {bool reuse = false}) {
  var cfg = buildCoreConfig(_natLinkFor(s, v, reuse: reuse));
  if (v <= 0 || v >= _natSpecs.length) return cfg;
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
  return cfg;
}

int natSafeVariant(int v) {
  if (v < 0) return 0;
  if (v >= _natSpecs.length) return 0;
  return v;
}
int natVarFor(Server s) {
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
    var asn = _natAsnByType[type] ?? '';
    final tried = _natAsnTry[type];
    if (asn.isEmpty &&
        (tried == null ||
            DateTime.now().difference(tried) > const Duration(minutes: 10))) {
      _natAsnTry[type] = DateTime.now();
      final r = await Future.wait([
        _natAsnFrom('http://ip-api.com/json/?fields=as', 'as'),
        _natAsnFrom('https://ipinfo.io/json', 'org'),
        _natAsnFrom('https://api.ip.sb/geoip', 'asn'),
      ]);
      for (final x in r) {
        if (x != null && x.isNotEmpty) {
          asn = x;
          break;
        }
      }
      if (asn.isNotEmpty) _natAsnByType[type] = asn;
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
  if (v > 0 && v < _natSpecs.length) {
    for (final d in _natDims(_natSpecs[v])) {
      final dk = '$natOpKey#$d';
      natDimWins[dk] = (natDimWins[dk] ?? 0) + 1;
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

Future<void> natSavePersisted() async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString('natvar2',
        jsonEncode({'v': natVar, 'w': natWins, 'd': natDimWins, 'g': _natGenVer}));
  } catch (e, stk) {
    logError(e, stk);
  }
}

Future<void> natLoadPersisted() async {
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
    final d = j['d'];
    if (d is Map) {
      d.forEach((k, v) => natDimWins['$k'] = (v as num).toInt());
    }
    if (((j['g'] ?? 0) as num).toInt() != _natGenVer) {
      natVar.removeWhere((k, v) => v >= _natBaseCount);
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
int natRangeCursor = 0;
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
        .where((x) => x.contains('/') || x.contains('-'))
        .toList();
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

Future<void> natRangesSave(String text) async {
  natRanges = text
      .split(RegExp(r'[\r\n,; ]+'))
      .where((x) => x.contains('/') || x.contains('-'))
      .toList();
  natRangeCursor = 0;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(_rangeKey, natRanges.join('\n'));
  } catch (e, stk) {
    logError(e, stk);
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
  final ports = cnt.keys.toList()
    ..sort((x, y) => cnt[y]! - cnt[x]!);
  final out = <int>[...ports.take(10)];
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

List<String> natExpandAny(String item) {
  if (!item.contains('-')) return natExpandCidr(item, maxPerBlock: 65536);
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
  for (var v = start; v <= end && out.length < 65536; v++) {
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
  if (!kNatIpScanOn) return out;
  try {
    final hosts = <String>{
      for (final s in known) if (!s.isIp && s.host.isNotEmpty) s.host,
      ...natIrDomains,
    }.take(3000).toList();
    final ips = <String>{};
    for (var i = 0; i < hosts.length; i += 50) {
      if (stop != null && stop()) break;
      final chunk = hosts.skip(i).take(50);
      final res = await Future.wait(chunk.map((h) => safeLookup(h)));
      for (final list in res) {
        for (final a in list) {
          if (a.type == InternetAddressType.IPv4) ips.add(a.address);
        }
      }
    }
    natDomainHosts = hosts.length;
    natDomainIps = ips.length;
    dbg('دامنه‌ها: ${hosts.length} دامنه • ${ips.length} IP یکتا');
    if (ips.isEmpty) return out;
    final tw = Stopwatch()..start();
    final portOrder = <int>[
      ...natCommonPorts,
      for (var p = 1; p < 65536; p++) if (!natCommonPorts.contains(p)) p,
    ];
    for (final p in portOrder) {
      if (tw.elapsed > const Duration(minutes: 3)) break;
      if (stop != null && stop()) break;
      final hits = await natScanIps(
        ips.toList(),
        port: p,
        concurrency: conc,
        want: 50,
        budget: const Duration(seconds: 5),
        timeout: const Duration(milliseconds: 1500),
        cancelled: stop,
      );
      for (final h in hits) {
        out.add('${h.ip}|$p');
        natDomainOpen = out.length;
      }
    }
  } catch (e, stk) {
    logError(e, stk);
  }
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
  final out = <String>[];
  void add(String b) {
    if (!out.contains(b)) out.add(b);
  }
  for (final h in hosts) {
    final t = _ipTriple(h);
    if (t == null) continue;
    add('${t[0]}.${t[1]}.${t[2]}.0/24');
    for (final d in const [-1, 1]) {
      final c = t[2] + d;
      if (c >= 0 && c <= 255) add('${t[0]}.${t[1]}.$c.0/24');
    }
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

Future<List<String>> natRangeScanStep({
  required List<Server> known,
  int maxAddrs = 256,
  int conc = 4,
  bool Function()? stop,
  Duration budget = const Duration(minutes: 2),
}) async {
  if (!kNatIpScanOn) return <String>[];
  final domOut = <String>[];
  var seeds = known;
  if (seeds.length < 50) {
    try {
      seeds = [...known, ...await natHotNext(800, fetch: false)];
    } catch (e, stk) {
      logError(e, stk);
    }
  }
  natTemplateSeeds = seeds.take(2).toList();
  final hosts = <String>[
    ...natIpMemHosts(),
    ...await natDeviceHosts(),
    ...natIranDnsHosts,
  ];
  final blocks = natRanges.isNotEmpty ? natRanges : natSeedBlocks(hosts);
  final addrs = <String>[];
  for (final r in blocks) {
    addrs.addAll(natExpandAny(r));
  }
  if (addrs.isEmpty) return const <String>[];
  final from = natRangeCursor % addrs.length;
  final slice = addrs.skip(from).take(maxAddrs).toList();
  natRangeCursor = from + slice.length;
  natRandomLast = 0;
  natIpScanned += slice.length;
  final out = <String>[...domOut];
  final portList = natAutoPorts(seeds);
  final perPort = Duration(
      milliseconds: max(20000, budget.inMilliseconds ~/ max(1, portList.length)));
  for (final port in portList) {
    if (stop != null && stop()) break;
    final hits = await natScanIps(
      slice,
      port: port,
      concurrency: conc,
      want: 50,
      budget: perPort,
      timeout: const Duration(milliseconds: 1500),
      cancelled: stop,
    );
    for (final h in hits) {
      out.add('${h.ip}|$port');
    }
  }
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

const int natHotPerSource = 2000000;
const int natHotMin = 30000;
const int natHotMax = 2000000;
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

String _hotPath() {
  const dir = '/data/data/com.kingvpn.king_vpn/files';
  try {
    final d = Directory(dir);
    if (!d.existsSync()) d.createSync(recursive: true);
    return '$dir/hot_cache.txt';
  } catch (jex, jstk) { errJournalAdd(jex, st: jstk);
    return '${Directory.systemTemp.path}/hot_cache.txt';
  }
}

List<String> natHotUrls() {
  final seen = <String>{};
  return [
    for (final u in [...userListUrls, ...listUrls])
      if (u.startsWith('http') && seen.add(u)) u
  ];
}

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
    for (final l in body.split(RegExp(r'[\r\n]+'))) {
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

Future<void> natHotEnsure({bool force = false}) async {
  if (_hotBusy) return;
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
      final order = [for (var i = 0; i < urls.length; i++) i]
        ..sort((a, b) => (natSrcRates[urls[b]] ?? 0.3)
            .compareTo(natSrcRates[urls[a]] ?? 0.3));
      final newPath = '${_hotPath()}.new';
      final offs = <int>[0];
      var pos = 0;
      final sink = File(newPath).openWrite();
      try {
        var full = false;
        final seenKeys = <int>{};
        final mergeFrom = <String>[
          if (File(extraPath).existsSync()) extraPath,
          for (final i in order) parts[i],
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
            if (!seenKeys.add(cfg.hashCode)) continue;
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

Future<_HotIdx?> _hotLoad() async {
  final cur = _hot;
  if (cur != null) return cur;
  final f = File(_hotPath());
  try {
    if (!f.existsSync() || f.lengthSync() == 0) return null;
    final offs = <int>[0];
    var pos = 0;
    await for (final chunk in f.openRead()) {
      for (var i = 0; i < chunk.length; i++) {
        if (chunk[i] == 10) offs.add(pos + i + 1);
      }
      pos += chunk.length;
    }
    if (offs.last != pos) offs.add(pos);
    _hot = _HotIdx(f.path, offs);
    _hotCursor = 0;
    return _hot;
  } catch (e, stk) {
    logError(e, stk);
    return null;
  }
}

Future<List<Server>> natHotNext(int n, {bool fetch = true}) async {
  try {
    if (fetch) unawaited(natHotEnsure());
    final h = await _hotLoad();
    if (h == null) return const [];
    final lines = h.offs.length - 1;
    if (lines <= 0) return const [];
    final out = <Server>[];
    final raf = await File(h.file).open();
    try {
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
  } catch (_) {}
}

Future<void> natMemLoad() async {
  try {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(kNatMemKey);
    if (raw == null) return null;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    natLevel = (m['natLevel'] as int?) ?? natLevel;
    offlineOnly = (m['offlineOnly'] as bool?) ?? offlineOnly;
  } catch (_) {}
}
