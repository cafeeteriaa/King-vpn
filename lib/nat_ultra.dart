part of 'main.dart';

// NATULTRA ==================================================================
// نت ملی / اینترنت کند: هر سرور فقط با «یک» حالت تست نمی‌شود؛ حالت‌های مختلف
// (آدرس دامنه/IP، Fragment با اندازه‌های مختلف، fingerprint ها، ALPN، پورت CDN،
// IP تمیز، Mux، DNS-over-HTTPS، Noise، TCP FastOpen ...) پشت‌سرهم امتحان می‌شوند.
// حالتی که جواب داد برای اتصال واقعی هم همان استفاده می‌شود.
//
// natLevel 1 = حالت‌های سبک (عادی، آدرس دیگر، Fragment ریز)
// natLevel 2 = همه‌ی حالت‌ها + چند آدرس تست (دکمه‌ی «جستجوی سرور با نت ملی»)
// natLevel 3 = هر حالت + هر آدرس تست (مرحله‌های آخر جستجوی گسترده و پوشه)
// natLevel 4 = حالت نهایی: ۵۰ حالت پایه + چند صد حالت ترکیبی از فضای چندهزارحالتی
//              (Fragment / fingerprint / ALPN / DNS / پورت / IP تمیز / Mux / Noise ...)
//              که بر اساس یادگیری همین اپراتور مرتب شده‌اند و هر دور از ادامه‌ی دور قبل
//              شروع می‌شوند (cursor)، پس در چند دور همه‌ی فضا پوشش داده می‌شود.
int natLevel = 1;
// کف سطح: دکمه «جستجوی سرور با نت ملی» = ۴ (بالاترین). جستجو زیر این سطح نمی‌رود
int natFloor = 0;
// سرورهایی که IP/دامنه‌شان در اسکن TCP جواب نداد؛ فقط وقتی صف سالم‌ها تمام شد تست می‌شوند
List<Server> natRestPending = []; // سطح ۱۰ = حالت نهایی با حلقه‌ی بی‌پایان (نت ملی)

// کد حالت = شماره‌ی آدرس تست * _natCodeBase + شماره‌ی حالت
const int _natCodeBase = 100000;
// ۵۰ حالت دست‌نویس اول (شماره‌هایشان ثابت است تا ذخیره‌شده‌های قدیمی خراب نشوند)
const int _natBaseCount = 50;
// اگر ترتیب / ساختار حالت‌های تولیدی عوض شد این عدد را زیاد کن
const int _natGenVer = 1;

// کلید سرور -> شماره‌ی حالتی که جواب داد
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

// همه‌ی پروفایل‌های Fragment = ۹ ردیف پایه + چند صد ترکیب تولیدی
// (طول بسته × فاصله × تعداد بسته‌ها)، بدون تکرار
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

// پروفایل‌های Noise: [packet, delay]
const List<List<String>> _natNoises = [
  ['10-20', '10-16'],
  ['5-10', '5-10'],
  ['30-60', '20-40'],
  ['50-100', '10-30'],
  ['1-5', '1-5'],
];

// DNS هایی که هسته با آن‌ها آدرس سرور را پیدا می‌کند (DoH یا IP ساده)
// اولویت با DNSهای ایرانی و محلی که روی نت ملی معمولاً باز می‌مانند.
const List<String> _natDnsList = [
  // Iranian / national-friendly first
  '178.22.122.100',
  '185.51.200.2',
  '78.157.42.100',
  '78.157.42.101',
  '10.202.10.10',
  '10.202.10.11',
  '10.202.10.202',
  // global DoH
  'https+local://1.1.1.1/dns-query',
  'https+local://8.8.8.8/dns-query',
  'https+local://9.9.9.9/dns-query',
  'https+local://1.0.0.1/dns-query',
  'https+local://8.8.4.4/dns-query',
  'https+local://149.112.112.112/dns-query',
  'https+local://94.140.14.14/dns-query',
  'https+local://208.67.222.222/dns-query',
  'https+local://208.67.220.220/dns-query',
  // plain IPs as fallback
  '1.1.1.1',
  '8.8.8.8',
  '9.9.9.9',
  '94.140.14.14',
  '208.67.222.222',
];

// مشخصات یک حالت. null / false = دست نمی‌زند.
class _NatSpec {
  final String name;
  final bool other; // the other address (domain <-> resolved IP)
  final String? fp, alpn;
  final int? frag; // index in _natFrags
  final bool port, clean, mux, sniHost, v4, tfo, ed, noise;
  final String? doh; // DNS server used by the core (DoH url or plain IP)
  // extras used by the generated variants (defaults = old behaviour)
  final int muxN; // 0 = default (8)
  final int noiseK; // index in _natNoises
  final bool nodelay;
  final String? mode; // 'xhttp:<mode>' | 'grpc:<mode>'
  final int? edN; // early-data size
  final int? portIdx; // fixed index in _natCfPorts (null = rotate)
  final int? cleanIdx; // fixed index in cleanIps (null = rotate)
  final int? keep; // tcp keep-alive interval (seconds)
  final int? mss; // TCP MSS (≈ MTU - 40) for the adaptive MTU tuner
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

// شماره‌ی 0..12 همان معنی قبلی را دارند (ذخیره‌شده‌های قدیمی خراب نمی‌شوند)
const List<_NatSpec> _natBase = [
  _NatSpec('عادی'), // 0
  _NatSpec('آدرس دیگر', other: true), // 1
  _NatSpec('Fragment ریز', frag: 0), // 2
  _NatSpec('Fragment متوسط', frag: 1), // 3
  _NatSpec('fp=firefox', fp: 'firefox'), // 4
  _NatSpec('fp=randomized + Fragment', fp: 'randomized', frag: 2), // 5
  _NatSpec('fp=ios', fp: 'ios'), // 6
  _NatSpec('alpn=http/1.1', alpn: 'http/1.1'), // 7
  _NatSpec('Fragment خیلی ریز', frag: 3), // 8
  _NatSpec('Fragment چندبسته‌ای', frag: 4), // 9
  _NatSpec('پورت دیگر CDN', port: true), // 10
  _NatSpec('IP تمیز Cloudflare', clean: true), // 11
  _NatSpec('Mux', mux: true), // 12
  _NatSpec('fp=chrome', fp: 'chrome'), // 13
  _NatSpec('fp=safari', fp: 'safari'), // 14
  _NatSpec('fp=edge', fp: 'edge'), // 15
  _NatSpec('fp=android', fp: 'android'), // 16
  _NatSpec('fp=random', fp: 'random'), // 17
  _NatSpec('fp=qq', fp: 'qq'), // 18
  _NatSpec('fp=360', fp: '360'), // 19
  _NatSpec('alpn=h2', alpn: 'h2'), // 20
  _NatSpec('alpn=h2,http/1.1', alpn: 'h2,http/1.1'), // 21
  _NatSpec('Fragment 20-50', frag: 5), // 22
  _NatSpec('Fragment ریز و کند', frag: 6), // 23
  _NatSpec('Fragment درشت', frag: 7), // 24
  _NatSpec('Fragment ۱-۲ بسته', frag: 8), // 25
  _NatSpec('fp=chrome + Fragment', fp: 'chrome', frag: 0), // 26
  _NatSpec('fp=firefox + Fragment خیلی ریز', fp: 'firefox', frag: 3), // 27
  _NatSpec('fp=randomized + Fragment متوسط', fp: 'randomized', frag: 1), // 28
  _NatSpec('fp=ios + Fragment', fp: 'ios', frag: 2), // 29
  _NatSpec('Fragment + Mux', frag: 0, mux: true), // 30
  _NatSpec('Fragment + IP تمیز', frag: 0, clean: true), // 31
  _NatSpec('Fragment + پورت دیگر', frag: 0, port: true), // 32
  _NatSpec('SNI = Host', sniHost: true), // 33
  _NatSpec('SNI = Host + Fragment', sniHost: true, frag: 0), // 34
  _NatSpec('DoH کلودفلر', doh: 'https+local://1.1.1.1/dns-query'), // 35
  _NatSpec('DoH گوگل', doh: 'https+local://8.8.8.8/dns-query'), // 36
  _NatSpec('DoH Quad9', doh: 'https+local://9.9.9.9/dns-query'), // 37
  _NatSpec('فقط IPv4', v4: true), // 38
  _NatSpec('Fragment + Noise', frag: 0, noise: true), // 39
  _NatSpec('TCP FastOpen', tfo: true), // 40
  _NatSpec('Fragment + TCP FastOpen', frag: 0, tfo: true), // 41
  _NatSpec('WebSocket early-data', ed: true), // 42
  _NatSpec('alpn=h2 + Fragment', alpn: 'h2', frag: 0), // 43
  _NatSpec('fp=chrome + alpn=h2,http/1.1', fp: 'chrome', alpn: 'h2,http/1.1'), // 44
  _NatSpec('DoH + Fragment', doh: 'https+local://1.1.1.1/dns-query', frag: 0), // 45
  _NatSpec('WebSocket early-data + Fragment', ed: true, frag: 0), // 46
  _NatSpec('آدرس دیگر + Fragment', other: true, frag: 0), // 47
  _NatSpec('آدرس دیگر + fp=chrome', other: true, fp: 'chrome'), // 48
  _NatSpec('آدرس دیگر + Fragment خیلی ریز', other: true, frag: 3), // 49
];

// ===================== فضای حالت‌های تولیدی (چند هزار حالت) =====================
// ترتیب تولید = اولویت پیش‌فرض (ساده و پرکاربرد اول). شماره‌ی حالت‌ها همیشه
// از ۵۰ شروع می‌شود و با _natGenVer نسخه‌بندی می‌شود.
// حالت‌های تازه (MTU تطبیقی و Keep-Alive) در انتها اضافه می‌شوند تا شماره‌ی
// حالت‌های قبلی و یادگیری‌های ذخیره‌شده جابه‌جا نشوند.
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

  // popular Fragment profiles: the base rows + tlshello with 3 intervals
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

  // tier 1: one feature
  for (final p in fps) {
    add(_natMk(fp: p));
  }
  for (final a in alpns) {
    add(_natMk(alpn: a));
  }
  for (final g in top) {
    add(_natMk(frag: g));
  }

  // tier 2: two features
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

  // tier 3: network / socket / DNS / address modifiers x (nothing, Fragment, fp)
  final mods = <_NatSpec Function(int?, String?)>[];
  for (final n in const [4, 8, 16]) {
    mods.add((f, p) => _natMk(frag: f, fp: p, mux: true, muxN: n));
  }
  mods.add((f, p) => _natMk(frag: f, fp: p, v4: true));
  mods.add((f, p) => _natMk(frag: f, fp: p, tfo: true));
  mods.add((f, p) => _natMk(frag: f, fp: p, nodelay: true));
  mods.add((f, p) => _natMk(frag: f, fp: p, keep: 15));
  for (var k = 0; k < _natNoises.length; k++) {
    mods.add((f, p) => _natMk(frag: f ?? 0, fp: p, noise: true, noiseK: k));
  }
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

  // tier 4: transport modes (XHTTP / gRPC)
  for (final m in const ['auto', 'packet-up', 'stream-up', 'stream-one']) {
    add(_natMk(mode: 'xhttp:$m'));
    for (final g in top.take(6)) {
      add(_natMk(mode: 'xhttp:$m', frag: g));
    }
    for (final p in const ['chrome', 'firefox', 'randomized']) {
      add(_natMk(mode: 'xhttp:$m', fp: p));
    }
  }
  for (final m in const ['gun', 'multi']) {
    add(_natMk(mode: 'grpc:$m'));
    for (final g in top.take(6)) {
      add(_natMk(mode: 'grpc:$m', frag: g));
    }
    for (final p in const ['chrome', 'firefox', 'randomized']) {
      add(_natMk(mode: 'grpc:$m', fp: p));
    }
  }

  // tier 5: Fragment x fp x ALPN
  for (final g in top.take(20)) {
    for (final p in fps.take(5)) {
      for (final a in alpns) {
        add(_natMk(frag: g, fp: p, alpn: a));
      }
    }
  }

  // tier 6: every remaining Fragment profile (alone, then with a fingerprint)
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

// NATINF ======= فضای بی‌پایان حالت‌ها =======
// وقتی همه‌ی حالت‌های ثابت برای یک سرور امتحان شد (cursor به انتها رسید)، حالت‌های
// تازه‌ی تصادفی ساخته می‌شوند و به انتهای جدول اضافه می‌شوند؛ پس هیچ‌وقت حالتی
// برای امتحان تمام نمی‌شود. مولد با seed ثابت است: شماره‌ی حالت‌ها بعد از بستن
// برنامه همان می‌ماند و ذخیره‌شده‌ها (natVar / natWins) خراب نمی‌شوند.
final Random _natRnd = Random(20260711);
final Set<String> _natSeen = {for (final x in _natSpecs) _natSig(x)};
const int _natMaxSpecs = 60000;
const List<String> _natFpAll = [
  'chrome', 'firefox', 'randomized', 'ios', 'android', 'safari', 'edge',
  'random', 'qq', '360'
];
const List<String> _natAlpnAll = ['h2', 'http/1.1', 'h2,http/1.1'];
const List<String> _natModeAll = [
  'xhttp:auto', 'xhttp:packet-up', 'xhttp:stream-up', 'xhttp:stream-one',
  'grpc:gun', 'grpc:multi'
];

_NatSpec _natRandSpec() {
  final r = _natRnd;
  bool chance(int pct) => r.nextInt(100) < pct;
  final fp = chance(70) ? _natFpAll[r.nextInt(_natFpAll.length)] : null;
  final alpn = chance(40) ? _natAlpnAll[r.nextInt(_natAlpnAll.length)] : null;
  final noise = chance(15);
  int? frag;
  if (noise || chance(65)) frag = r.nextInt(_natFrags.length);
  const muxNs = [2, 4, 8, 16, 32];
  final mux = chance(20);
  const keeps = [10, 15, 30, 60];
  final keep = chance(15) ? keeps[r.nextInt(keeps.length)] : null;
  const edNs = [256, 512, 1024, 2048, 4096];
  final ed = chance(15);
  final port = chance(25);
  final clean = chance(20);
  return _natMk(
      fp: fp,
      alpn: alpn,
      frag: frag,
      noise: noise,
      noiseK: r.nextInt(_natNoises.length),
      mux: mux,
      muxN: muxNs[r.nextInt(muxNs.length)],
      v4: chance(15),
      tfo: chance(15),
      nodelay: chance(20),
      keep: keep,
      ed: ed,
      edN: edNs[r.nextInt(edNs.length)],
      other: chance(15),
      sniHost: chance(15),
      port: port,
      portIdx: port && chance(60) ? r.nextInt(_natCfPorts.length) : null,
      clean: clean,
      cleanIdx: clean && chance(60) ? r.nextInt(8) : null,
      doh: chance(30) ? _natDnsList[r.nextInt(_natDnsList.length)] : null,
      mode: chance(10) ? _natModeAll[r.nextInt(_natModeAll.length)] : null);
}

// n حالت تازه (بدون تکرار) به انتهای جدول اضافه می‌کند
int natGrow(int n) {
  var made = 0, tries = 0;
  while (made < n && tries < n * 30 && _natSpecs.length < _natMaxSpecs) {
    tries++;
    final x = _natRandSpec();
    if (_natSeen.add(_natSig(x))) {
      _natSpecs.add(x);
      made++;
    }
  }
  if (made > 0) {
    _natNamesC = null;
    _natGenRankKey = '';
  }
  return made;
}

// برای نمایش (main.dart از این استفاده می‌کند)
List<String>? _natNamesC;
List<String> get _natVarNames =>
    _natNamesC ??= [for (final x in _natSpecs) x.name];

// ---------------------------------------------------------------------------
// آدرس‌های تست. کد = شماره‌ی آدرس * _natCodeBase + شماره‌ی حالت (0 = آدرس پیش‌فرض)
const List<String> _natTestUrls = [
  'http://cp.cloudflare.com/generate_204', // 1  (قبلاً آدرس دوم)
  'http://www.msftconnecttest.com/connecttest.txt', // 2
  'http://connectivitycheck.gstatic.com/generate_204', // 3
  'http://clients3.google.com/generate_204', // 4
  'http://www.google.com/generate_204', // 5
  'http://detectportal.firefox.com/success.txt', // 6
  'http://captive.apple.com/hotspot-detect.html', // 7
  'http://www.apple.com/library/test/success.html', // 8
  'http://edge-http.microsoft.com/captiveportal/generate_204', // 9
  'http://play.googleapis.com/generate_204', // 10
  'http://www.gstatic.com/generate_204', // 11
  'http://nmcheck.gnome.org/check_network_status.txt', // 12
  'http://connectivity-check.ubuntu.com/', // 13
  'http://www.cloudflare.com/cdn-cgi/trace', // 14
  'http://neverssl.com/', // 15
  'http://example.com/', // 16
  'https://cp.cloudflare.com/generate_204', // 17
  'https://www.google.com/generate_204', // 18
  'https://www.youtube.com/generate_204', // 19
  'https://one.one.one.one/', // 20
  'https://dns.google/', // 21
  'https://www.bing.com/', // 22
  'https://www.wikipedia.org/', // 23
  'https://www.cloudflare.com/cdn-cgi/trace', // 24
];

String? _natUrlFor(int code, String? url) {
  final i = code ~/ _natCodeBase;
  return i == 0 ? url : _natTestUrls[(i - 1) % _natTestUrls.length];
}

// ports Cloudflare proxies for HTTPS (a CDN server often answers on all)
const List<int> _natCfPorts = [443, 2053, 2083, 2087, 2096, 8443];
const Set<String> _natCdnNets = {
  'ws', 'grpc', 'httpupgrade', 'xhttp', 'splithttp', 'h2'
};
int _natRot = 0;

// the port / clean IP that was chosen for (server, variant) in the last test:
// the real connection reuses exactly the same values (reuse = true)
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
  final i = _natCfPorts.indexOf(s.port);
  final next = _natCfPorts[(i + 1 + (_natRot++ % 5)) % _natCfPorts.length];
  return next == s.port ? 2053 : next;
}

bool _natIsSecure(Server s) {
  final l = s.link.toLowerCase();
  if (l.startsWith('ss://')) return false;
  return s.tls || s.reality || l.contains('security=tls') || l.contains('"tls":"tls"');
}

// facts about a server, computed once per _natOrder call (not once per variant)
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

bool _natAppliesF(_NatFacts f, int v) {
  if (v < 0 || v >= _natSpecs.length) return false;
  if (v == 0) return true;
  if (natDisabled.contains(v)) return false;
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
    return false; // same port as now: no change
  }
  if (x.clean && !(f.sec && !f.reality && f.hasClean && f.cdnLike)) {
    return false;
  }
  if (x.mux && (f.reality || f.ss)) return false;
  if (x.mux && v >= _natBaseCount && (f.grpc || f.xh)) return false;
  if (x.doh != null && f.isIp) return false;
  final md = x.mode;
  if (md != null) {
    if (f.vmess) return false; // vmess links keep the mode elsewhere
    if (md.startsWith('xhttp:') && !f.xh) return false;
    if (md.startsWith('grpc:') && !f.grpc) return false;
  }
  return true;
}

// does this variant change WHERE the core connects (address / port / DNS)?
// (when the plain TCP port is closed, only those can still help)
bool _natChangesAddr(int v) {
  if (v <= 0 || v >= _natSpecs.length) return false;
  final x = _natSpecs[v];
  return x.other || x.port || x.clean || x.doh != null;
}

// ----------------------- یادگیری: ویژگی‌های برنده‌ی هر اپراتور -----------------------
// '<op>#<ویژگی>' -> تعداد موفقیت (fp=chrome, fl=10-30, dns=..., mux ...)
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

// all generated variants, best first for THIS operator (cached until learning changes)
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

// the variants that already worked most on this operator
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

// per server: how far through its (ranked) generated variants the search got.
// The next round continues from there, so many rounds cover the whole space.
final Map<String, int> _natCursor = {};
String _natCk(Server s) => '$natOpKey#${s.key}';

void natCursorAdvance(Server s, int n) {
  if (n <= 0) return;
  final k = _natCk(s);
  if (_natCursor.length > 4000) _natCursor.remove(_natCursor.keys.first);
  _natCursor[k] = (_natCursor[k] ?? 0) + n;
}

// time one server may use for its variants in one pass
Duration natBudget({bool full = false}) {
  final l = full ? 3 : natLevel;
  if (l <= 1) return const Duration(seconds: 40);
  if (l == 2) return const Duration(seconds: 75);
  if (l == 3) return const Duration(seconds: 150);
  return const Duration(seconds: 260);
}

// how many generated variants one pass may queue (by level 1..4)
// سطح ۵ تا ۱۰: تعداد حالت‌های ترکیبی بیشتر در هر دور (تا سقف _natMaxSpecs)
const List<int> _natGenCap = [0, 0, 20, 120, 600, 1500, 3000, 6000, 10000, 15000, 20000];

// ترتیب امتحان حالت‌ها برای یک سرور (کد ≥ _natCodeBase = همان حالت با آدرس تست دیگر)
List<int> _natOrder(Server s, {bool full = false}) {
  var lvl = full ? 3 : natLevel;
  if (lvl < 1) lvl = 1;
  if (lvl > 10) lvl = 10;
  final f = _NatFacts(s);
  final known = natVar[_nk(s)];
  final cursor = _natCursor[_natCk(s)] ?? 0;
  final again = cursor > 0 && lvl >= 2; // a repeat pass: skip what failed before
  final out = <int>[];
  final used = <int>{};
  void put(int c) {
    if (used.add(c)) out.add(c);
  }

  // NORMAL: never use Fragment/Noise variants (they kill post-connect speed).
  // National mode may still try heavy variants when the filter is hard.
  final preferLight = !nationalMode;
  final skipHeavy = !nationalMode;

  final knownOk = known != null && _natAppliesF(f, known);
  // known light winner first; skip known heavy on normal
  if (knownOk && (!skipHeavy || !natIsHeavy(known!))) put(known!);

  if (preferLight) {
    // dedicated light speed candidates before anything heavy
    final lightFirst = <int>[0, 1, 4, 13, 7, 20, 12, 33, 38, 40, 44];
    for (final w in _natTopWinners(8)) {
      if (!natIsHeavy(w) && !lightFirst.contains(w)) lightFirst.add(w);
    }
    for (final v in lightFirst) {
      if (_natAppliesF(f, v)) put(v);
    }
  }

  // variants that worked on OTHER servers of this operator come first
  if (lvl >= 2) {
    for (final w in _natTopWinners(6)) {
      if (skipHeavy && natIsHeavy(w)) continue;
      if (_natAppliesF(f, w)) put(w);
    }
  }

  // the 50 base variants, the ones that won most on this operator first
  final cand = (lvl >= 2
      ? <int>[for (var i = 0; i < _natBaseCount; i++) i]
      : <int>[0, 1, 2, 8])
    ..sort((a, b) {
      if (preferLight) {
        final ha = natIsHeavy(a) ? 1 : 0;
        final hb = natIsHeavy(b) ? 1 : 0;
        if (ha != hb) return ha - hb; // light first
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
          break; // the first (best ranked) variant, then the early URLs
        }
      }
    }
    // if the default test address is blocked every server looks dead,
    // so a few other addresses are tried early
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

  // generated variants (ranked by what works on this operator; resumes at cursor)
  final gens = <int>[];
  final cap = _natGenCap[lvl];
  if (cap > 0) {
    final app = <int>[];
    for (final v in _natGenRanked()) {
      if (_natAppliesF(f, v)) app.add(v);
    }
    // NATINF: the whole (finite) space was tried on this server: make new ones
    if (app.isNotEmpty && cursor >= app.length) {
      if (natGrow(cap * 2) > 0) {
        app.clear();
        for (final v in _natGenRanked()) {
          if (_natAppliesF(f, v)) app.add(v);
        }
      }
    }
    if (app.isNotEmpty) {
      final st = cursor % app.length;
      for (var k = 0; k < app.length && k < cap; k++) {
        final gv = app[(st + k) % app.length];
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
    // best variants of this network x every test address
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
  } catch (e) {
    logError(e);
    return link;
  }
}

// reads one parameter of a link ('' when absent)
String _natGetParam(String link, String key) {
  try {
    if (link.toLowerCase().startsWith('vmess://')) {
      var b = link.substring(8);
      b = b.padRight(b.length + (4 - b.length % 4) % 4, '=');
      final j = jsonDecode(utf8.decode(base64.decode(b)));
      return (j[key] ?? '').toString();
    }
    return Uri.parse(link).queryParameters[key] ?? '';
  } catch (e) {
    logError(e);
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
  } catch (e) {
    logError(e);
    return link;
  }
}

// same config on another address; SNI / Host keep the real domain
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
  } catch (e) {
    logError(e);
    return link;
  }
}

String _natLinkFor(Server s, int v, {bool reuse = false}) {
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
    // the fingerprint / alpn / sni / mode changes above must survive the swap
    link = _natApplyTweaks(link, x, s);
    if (x.port) {
      link = _natSetPort(link, int.tryParse(portPick('p2')) ?? 2053);
    }
  }
  return link;
}

// link-level tweaks (fingerprint, ALPN, transport mode, SNI, early data)
String _natApplyTweaks(String link, _NatSpec x, Server s) {
  if (x.fp != null) link = _natSetParam(link, 'fp', x.fp!);
  if (x.alpn != null) link = _natSetParam(link, 'alpn', x.alpn!);
  final md = x.mode;
  if (md != null) {
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

// the first real proxy outbound of a core config (or null)
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

// Fragment on the TLS Hello (and the first packets) with the sizes of table row [fi]
String _natFrag(String cfg, int fi, {bool noise = false, int noiseK = 0}) {
  if (fi < 0 || fi >= _natFrags.length) return cfg;
  final p = _natFrags[fi];
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
      'fragment': {'packets': p[2], 'length': p[0], 'interval': p[1]}
    };
    // random junk packets before the handshake (cores without support ignore it)
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
  } catch (e) {
    logError(e);
    return cfg;
  }
}

// Mux: many requests share one connection (survives per-connection throttling)
String _natMux(String cfg, [int n = 0]) {
  try {
    final j = jsonDecode(cfg);
    if (j is! Map<String, dynamic>) return cfg;
    final o = _natProxyOut(j);
    if (o == null) return cfg;
    if (RegExp(r'"flow"\s*:\s*"xtls').hasMatch(cfg)) return cfg; // vision can't use mux
    o['mux'] = {'enabled': true, 'concurrency': n > 0 ? n : 8};
    return jsonEncode(j);
  } catch (e) {
    logError(e);
    return cfg;
  }
}

// the core resolves names through DNS-over-HTTPS (poisoned local DNS is skipped)
String _natDns(String cfg, String doh) {
  try {
    final j = jsonDecode(cfg);
    if (j is! Map<String, dynamic>) return cfg;
    final d = j['dns'] is Map ? j['dns'] as Map : <String, dynamic>{};
    d['servers'] = [doh, 'localhost'];
    j['dns'] = d;
    return jsonEncode(j);
  } catch (e) {
    logError(e);
    return cfg;
  }
}

// socket options of the proxy outbound (TCP FastOpen / IPv4 only / NoDelay / KeepAlive)
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
  } catch (e) {
    logError(e);
    return cfg;
  }
}

// کانفیگ نهایی یک سرور با حالت v (v=0 دقیقاً مثل قبل است)
String natCfg(Server s, int v, {bool reuse = false}) {
  var cfg =
      V2ray.parseFromURL(_natLinkFor(s, v, reuse: reuse)).getFullConfiguration();
  if (v <= 0 || v >= _natSpecs.length) return cfg;
  final x = _natSpecs[v];
  if (x.frag != null) {
    cfg = _natFrag(cfg, x.frag!, noise: x.noise, noiseK: x.noiseK);
  }
  if (x.mux) cfg = _natMux(cfg, x.muxN);
  if (x.doh != null) cfg = _natDns(cfg, x.doh!);
  if (x.v4 || x.tfo || x.nodelay || x.keep != null || x.mss != null) {
    cfg = _natSock(cfg,
        v4: x.v4, tfo: x.tfo, nodelay: x.nodelay, keep: x.keep, mss: x.mss);
  }
  return cfg;
}

// حالتی که برای اتصال واقعی استفاده می‌شود.
// ULTRA: وقتی ultraMode روشن است هم حالت یادگرفته‌شده اعمال می‌شود
// (قبلاً فقط nationalMode بود و ماتریس در اتصال عادی بی‌اثر می‌ماند).
int natVarFor(Server s) =>
    (nationalMode || ultraMode || indestructibleMode)
        ? (natVar[_nk(s)] ?? 0)
        : 0;

// TURBO: is this variant a speed-killer (Fragment / Noise)?
bool natIsHeavy(int v) {
  final base = v % _natCodeBase;
  if (base <= 0 || base >= _natSpecs.length) return false;
  final x = _natSpecs[base];
  return x.frag != null || x.noise;
}

// TURBO: pick a light (no Fragment/Noise) variant that still fits this server.
// Prefers: known light winner > base 0 > other non-heavy ranked variants.
int? natSpeedVariant(Server s, {int prefer = 0}) {
  final f = _NatFacts(s);
  final known = natVar[_nk(s)];
  if (known != null &&
      !natIsHeavy(known) &&
      _natAppliesF(f, known % _natCodeBase)) {
    return known % _natCodeBase;
  }
  // candidates that keep address tricks (other/port/clean/doh) but drop frag/noise
  final cand = <int>[0, 1, 4, 13, 7, 20, 12, 33, 38, 40];
  for (final w in _natTopWinners(8)) {
    if (!cand.contains(w)) cand.add(w);
  }
  for (final v in cand) {
    if (v == prefer) continue;
    if (natIsHeavy(v)) continue;
    if (_natAppliesF(f, v)) return v;
  }
  // any non-heavy base that applies
  for (var i = 0; i < _natBaseCount; i++) {
    if (i == prefer) continue;
    if (!natIsHeavy(i) && _natAppliesF(f, i)) return i;
  }
  return null;
}

// DoH با چند آدرس (اگر 1.1.1.1 بسته بود بقیه امتحان می‌شوند)
const List<String> _dohEps = [
  'https://1.1.1.1/dns-query?name=%N&type=A',
  'https://8.8.8.8/resolve?name=%N&type=A',
  'https://1.0.0.1/dns-query?name=%N&type=A',
  'https://9.9.9.9:5053/dns-query?name=%N&type=A',
];

// ====================== یادگیری هر اپراتور / شبکه ======================
// کلید شبکه: نوع اتصال (mob/wifi) + شماره‌ی ASN اپراتور. آمار پروتکل‌ها،
// حالت‌های موفق و IP های تمیز برای هر اپراتور جدا ذخیره و یاد گرفته می‌شود.
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
  } catch (e) {
    logError(e);
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
    if (!t.startsWith('{')) return null; // HTML page from a portal/filter
    final j = jsonDecode(t);
    if (j is! Map) return null;
    final raw = '${j[field] ?? ''}';
    final m = RegExp(r'(\d{3,7})').firstMatch(raw);
    return m?.group(1);
  } catch (e) {
    logError(e);
    return null;
  } finally {
    c.close(force: true);
  }
}

// فقط وقتی VPN وصل نیست صدا زده شود (وگرنه ASN خروجی VPN برمی‌گردد)
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
  } catch (e) { logError(e); }
}

// ====================== حافظه‌ی حالت‌های موفق ======================
final Map<String, int> natWins = {}; // '<op>#<variant>' -> تعداد موفقیت
Timer? _natSaveT;

String _nk(Server s) => '$natOpKey#${s.key}';

void natVarSet(Server s, int v) {
  natVar.remove(_nk(s));
  natVar[_nk(s)] = v;
  final wk = '$natOpKey#$v';
  natWins[wk] = (natWins[wk] ?? 0) + 1;
  if (v > 0 && v < _natSpecs.length) {
    // learn WHICH features worked on this operator: every untested combination
    // that shares them moves up the queue for all the other servers
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
  } catch (e) {
    logError(e);
  }
}

Future<void> natLoadPersisted() async {
  await plusLoad();
  await natIpMemLoad();
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
      // the generated table changed: its saved numbers no longer match
      natVar.removeWhere((k, v) => v >= _natBaseCount);
      natWins.removeWhere((k, v) {
        final n = int.tryParse(k.substring(k.lastIndexOf('#') + 1));
        return n != null && n >= _natBaseCount;
      });
    }
    // NATINF: saved numbers may point at generated (random) variants
    var mx = 0;
    for (final v in natVar.values) {
      if (v > mx) mx = v;
    }
    natWins.forEach((k, c) {
      final q = int.tryParse(k.substring(k.lastIndexOf('#') + 1));
      if (q != null && q > mx) mx = q;
    });
    if (mx >= _natSpecs.length && mx < _natMaxSpecs) {
      natGrow(mx - _natSpecs.length + 1);
    }
    _natLearnVer++;
  } catch (e) {
    logError(e);
  }
}

// ===== حافظه‌ی IPهای کارا + اسکن بازه‌های IP (نت ملی) =========================
// IPهایی که با کانفیگ واقعاً اینترنت جهانی را رد کرده‌اند ذخیره می‌شوند و
// دفعه‌ی بعد اول تست می‌شوند. بازه‌ها (CIDR) را خود کاربر وارد می‌کند.
const String _ipMemKey = 'natIpMem';
const String _rangeKey = 'natRanges';
const int _ipMemMax = 200;

final List<Map<String, dynamic>> natIpMem = [];
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
    }
    natRanges = (p.getString(_rangeKey) ?? '')
        .split(RegExp(r'[\r\n,; ]+'))
        .where((x) => x.contains('/') || x.contains('-'))
        .toList();
  } catch (e) {
    logError(e);
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
  } catch (e) {
    logError(e);
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
  } catch (e) {
    logError(e);
  }
}

// پورت‌ها از خود کانفیگ‌های برنامه گرفته می‌شوند (حداکثر ۵۰ تا). اگر کانفیگ‌ها
// پورت کمتری داشته باشند، همان کمتر اسکن می‌شود. اگر هیچ کانفیگی نبود، ۴۴۳ استفاده می‌شود.
List<int> natAutoPorts(List<Server> known) {
  final cnt = <int, int>{};
  for (final s in known) {
    if (s.port > 0 && s.port < 65536) cnt[s.port] = (cnt[s.port] ?? 0) + 1;
  }
  // پورتی که قبلاً IP باز داشته، وزن بیشتری می‌گیرد
  for (final e in natIpMem) {
    final p = (e['port'] as num?)?.toInt() ?? 0;
    if (p > 0 && p < 65536) cnt[p] = (cnt[p] ?? 0) + 5;
  }
  if (cnt.isEmpty) return const [443];
  final ports = cnt.keys.toList()
    ..sort((x, y) => cnt[y]! - cnt[x]!);
  return ports.take(50).toList();
}

// [a, b, c] از IPv4 یا null
List<int>? _ipTriple(String host) {
  final p = host.split('.');
  if (p.length != 4 || InternetAddress.tryParse(host) == null) return null;
  return [for (final x in p.take(3)) int.parse(x)];
}

// ترتیب بلوک‌ها (هر کدام /24):
// ۱) بلوک‌هایی که قبلاً IP باز داشته‌اند
// ۲) همسایه‌ی آن‌ها (یک بلوک قبل و بعد) چون سرورها معمولاً کنار هم هستند
// ۳) بلوک‌های IP سرورهای کانفیگ‌ها
// بلوک‌هایی که در بازه‌ی دستی کاربر هستند، این مرحله را ندارند.
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

// بازه می‌تواند CIDR باشد (5.160.0.0/16) یا از-تا (5.160.0.0-5.160.3.255).
// هر بازه حداکثر ۶۵ هزار آدرس می‌دهد.
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

// یک مرحله‌ی اسکن. هر بار بلوک بعدی (تغییر خودکار) و پورت‌های کانفیگ بررسی می‌شوند.
// خروجی: لیست «ip|port». بعد از هر مرحله ادامه از همان جای قبلی است.
Future<List<String>> natRangeScanStep({
  required List<Server> known,
  int maxAddrs = 256,
  int conc = 200,
  bool Function()? stop,
}) async {
  final blocks = natRanges.isNotEmpty ? natRanges : natAutoBlocks(known);
  if (blocks.isEmpty) return const [];
  final addrs = <String>[];
  for (final r in blocks) {
    addrs.addAll(natExpandAny(r));
  }
  if (addrs.isEmpty) return const [];
  final from = natRangeCursor % addrs.length;
  final slice = addrs.skip(from).take(maxAddrs).toList();
  natRangeCursor = from + slice.length;
  final out = <String>[];
  for (final port in natAutoPorts(known)) {
    if (stop != null && stop()) break;
    final hits = await natScanIps(
      slice,
      port: port,
      concurrency: conc,
      want: 50,
      budget: const Duration(minutes: 2),
      timeout: const Duration(milliseconds: 1500),
      cancelled: stop,
    );
    for (final h in hits) {
      out.add('${h.ip}|$port');
    }
  }
  return out;
}

// ===== لیست‌های کانفیگ اضافه‌ی کاربر (لینک اشتراک مستقیم) ======================
// کاربر لینک‌های اشتراک (txt یا base64) از کانال‌ها و منابع مورد اعتمادش را وارد می‌کند.
// این لینک‌ها اول دریافت می‌شوند، قبل از لیست‌های عمومی.
List<String> userListUrls = [];

Future<void> userListsLoad() async {
  try {
    final p = await SharedPreferences.getInstance();
    userListUrls = (p.getString('userListUrls') ?? '')
        .split(RegExp(r'[\r\n\s]+'))
        .where((x) => x.startsWith('http'))
        .toList();
  } catch (e) {
    logError(e);
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
  } catch (e) {
    logError(e);
  }
}

// ===== پوشه‌ی منابع تازه (فقط برای نت ملی، هر ۲۴ ساعت بازسازی) ===============
// کانفیگ‌ها از منبع‌های HOT (بالای فهرست، قبل از «SoliSpirit») دریافت و در یک فایل
// جدا ذخیره می‌شوند (نه در prefs؛ چون prefs کل داده را هر بار در حافظه می‌نویسد).
// هر دور جستجوی نت ملی فقط یک تکه (مثلاً ۳۰۰۰ تا) پارس و تست می‌شود و ادامه‌ی دور
// بعد از همان جای قبلی است. این پوشه فقط در حالت نت ملی استفاده می‌شود؛ خلبان هم
// وقتی نت ملی تشخیص داده شود از همین مسیر (connect با نت ملی) از آن استفاده می‌کند.
const int natHotPerSource = 15000;
const int natHotMax = 300000;
const Duration natHotTtl = Duration(hours: 24);
const Duration natHotFetchDeadline = Duration(seconds: 180);
bool _hotBusy = false;
List<String>? _hotLines; // خطوط «src\tlink» در حافظه (فقط یک بار خوانده می‌شود)
int _hotCursor = 0;

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

// منبع‌های HOT: همان‌هایی که قبل از بخش «SoliSpirit» در فهرست اصلی هستند
List<String> natHotUrls() {
  var end = _paths.indexWhere((p) => p.startsWith('SoliSpirit/'));
  if (end < 0) end = min(80, _paths.length);
  return [for (final p in _paths.sublist(0, end)) '$_gh$p'];
}

// دریافت خام خطوط کانفیگ از منبع‌ها (بدون پارس، تا حافظه کم مصرف بماند)
Future<Set<String>> natHotFetch(List<String> urls) async {
  final out = <String>{};
  final sw = Stopwatch()..start();
  await pool<String>(urls, fetchWorkers, (u) async {
    if (sw.elapsed > natHotFetchDeadline) return;
    try {
      final r = await getListMirror(u);
      if (r.statusCode != 200) return;
      var body = r.body.trim();
      if (body.contains('<html') || body.contains('<!DOCTYPE')) {
        body = _linkRe
            .allMatches(body.replaceAll('&amp;', '&'))
            .map((m) => m.group(0)!)
            .join('\n');
      }
      if (!body.contains('://')) {
        if (!RegExp(r'^[A-Za-z0-9+/=_\-\s]+$').hasMatch(body)) return;
        try {
          body = utf8.decode(
              base64.decode(base64.normalize(body.replaceAll(RegExp(r'\s'), ''))));
        } catch (_) {
          return;
        }
      }
      var n = 0;
      for (final l in body.split(RegExp(r'[\r\n]+'))) {
        if (n >= natHotPerSource) break;
        final t = l.trim();
        if (!t.contains('://') || t.contains('[email') || t.contains('protected]')) {
          continue;
        }
        out.add('$u\t$t');
        n++;
      }
    } catch (e) {
      logError(e);
    }
  });
  return out;
}

// اگر ۲۴ ساعت گذشته باشد، فایل از نو ساخته می‌شود. اگر دریافت تازه خالی بود،
// فایل قبلی نگه داشته می‌شود.
Future<void> natHotEnsure() async {
  if (_hotBusy) return;
  final f = File(_hotPath());
  try {
    final age = f.existsSync()
        ? DateTime.now().difference(f.lastModifiedSync())
        : const Duration(days: 365);
    if (age < natHotTtl && (_hotLines != null || f.lengthSync() > 0)) return;
    _hotBusy = true;
    final fresh = await natHotFetch(natHotUrls());
    if (fresh.isNotEmpty) {
      final list = fresh.toList()..shuffle();
      final take = list.length > natHotMax ? list.sublist(0, natHotMax) : list;
      await f.writeAsString(take.join('\n'), flush: true);
      _hotLines = null; // دفعه‌ی بعد از فایل تازه خوانده شود
      _hotCursor = 0;
    }
  } catch (e) {
    logError(e);
  } finally {
    _hotBusy = false;
  }
}

// تکه‌ی بعدی از پوشه (حداکثر n کانفیگ). وقتی به آخر رسید، از اول شروع می‌شود.
Future<List<Server>> natHotNext(int n) async {
  try {
    await natHotEnsure(); // هر ۲۴ ساعت تازه می‌شود (حتی اگر برنامه باز مانده باشد)
    if (_hotLines == null) {
      final f = File(_hotPath());
      _hotLines = f.existsSync()
          ? f.readAsLinesSync().where((x) => x.contains('\t')).toList()
          : <String>[];
      _hotCursor = 0;
    }
    final lines = _hotLines!;
    if (lines.isEmpty) return const [];
    final out = <Server>[];
    var tries = 0;
    while (out.length < n && tries < lines.length) {
      final e = lines[_hotCursor];
      _hotCursor = (_hotCursor + 1) % lines.length;
      tries++;
      final i = e.indexOf('\t');
      final s = Server.parse(e.substring(i + 1));
      if (s != null) {
        s.src = e.substring(0, i);
        out.add(s);
      }
    }
    return out;
  } catch (e) {
    logError(e);
    return const [];
  }
}
