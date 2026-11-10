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
// VARCAP: حداکثر حالت (ماتریس) برای هر سرور در نت ملی
// MATRIXCAP: سقف حالت‌ها برای هر سرور در هر دور (قبلاً ۱۰). سقف واقعی زمان همان natBudget است
const int natMaxVariants = 2000000;
int natFloor = 0;
// سرورهایی که IP/دامنه‌شان در اسکن TCP جواب نداد؛ فقط وقتی صف سالم‌ها تمام شد تست می‌شوند
List<Server> natRestPending = []; // سطح ۱۰ = حالت نهایی با حلقه‌ی بی‌پایان (نت ملی)

// کد حالت = شماره‌ی آدرس تست * _natCodeBase + شماره‌ی حالت
const int _natCodeBase = 100000;
// ۵۰ حالت دست‌نویس اول (شماره‌هایشان ثابت است تا ذخیره‌شده‌های قدیمی خراب نشوند)
const int _natBaseCount = 50;
// اگر ترتیب / ساختار حالت‌های تولیدی عوض شد این عدد را زیاد کن
// V7: bumped to 3 because the meaning of the port-hopping index changed
// (port 80 added to the CF port list), so old saved generated variants
// no longer point at the same meaning.
const int _natGenVer = 3;

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
  // KCP-UDP: همان هسته‌ی فعلی (Xray) است؛ ترافیک روی UDP می‌رود. فقط وقتی سرور kcp را قبول کند جواب می‌دهد
  _NatSpec('mKCP (UDP)', mode: 'kcp:none'),
  // NEWFP: اثرانگشت‌های TLS دیگری که Xray پشتیبانی می‌کند (فقط سمت کلاینت، بدون تغییر در سرور)
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

  // tier 4: Fragment x fp x ALPN
  for (final g in top.take(20)) {
    for (final p in fps.take(5)) {
      for (final a in alpns) {
        add(_natMk(frag: g, fp: p, alpn: a));
      }
    }
  }

  // tier 5: every remaining Fragment profile (alone, then with a fingerprint)
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
// NATFINITE: no random/infinite variant generation. The curated matrix above
// is finite, reproducible, and each variant has a defined protocol meaning.
int natGrow(int n) => 0;

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

// V7-PORT: priority-ordered list for port hopping, tuned for Iranian operators.
// 443 (default HTTPS), 80 (plain HTTP often passes when 443 is throttled),
// then alternate CDN ports that Cloudflare accepts (8443, 2053, 2083, 2087, 2096).
// Used both for variant generation and for _natNextPort's priority walk.
const List<int> _natCfPorts = [443, 80, 8443, 2053, 2083, 2087, 2096];
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
  // V7-PORT: strict priority walk over _natCfPorts. Starting from the port
  // right after the server's current port, walk the list once and return
  // the first port that is different. This produces the order 443→80→8443
  // →2053→2083→2087→2096 (and wraps around). If every port somehow equals
  // the current one, fall back to 443.
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

// RETIRED: حالت‌هایی که تست واقعی ترافیک نداده‌اند؛ دیگر در ماتریس و تست خودکار استفاده نمی‌شوند
const Set<String> _natRetiredNames = {
  'Fragment ریز و کند', // روی ۵ تلاش با اتصال واقعی ترافیک نداد
  'fp=android', // جدید: روی ۳ تلاش با اتصال واقعی ترافیک نداد (گزارش تست نت ملی)
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
    return false; // same port as now: no change
  }
  if (x.clean && !(f.sec && !f.reality && f.hasClean && f.cdnLike)) {
    return false;
  }
  // Mux is a throughput/concurrency feature, not a reachability workaround;
  // it can make fragile links less stable. Do not use it in the national matrix.
  if (x.mux) return false;
  // Noise packets are not a reliable DPI bypass and can trigger rate limits.
  if (x.noise) return false;
  // A client cannot convert a server's transport by rewriting the URI. XHTTP,
  // gRPC and KCP modes must match the server-side listener, so never mutate them.
  if (x.mode != null) return false;
  if (x.doh != null && f.isIp) return false;
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
// سطح ۵ تا ۱۰: سهم بیشتری از ماتریس محدود و ازپیش‌تعریف‌شده در هر دور
const List<int> _natGenCap = [
  0, 0, 200, 1200, 6000, 15000, 30000, 60000, 100000, 150000, 200000
];

// ترتیب امتحان حالت‌ها برای یک سرور (کد ≥ _natCodeBase = همان حالت با آدرس تست دیگر)
List<int> _natOrder(Server s, {bool full = false}) {
  goldPrepareNational(); // GOLD: قبل از ساختن حالت‌ها، IPهای پوشه‌ی جهانی در نت ملی آماده شوند
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
    // Continue from the next untested curated item; never wrap and repeat
    // failed combinations forever, and never manufacture random variants.
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
  } catch (e, stk) {
    logError(e, stk);
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
  } catch (e, stk) {
    logError(e, stk);
    return link;
  }
}

String _natLinkFor(Server s, int v, {bool reuse = false}) {
  goldPrepareNational(); // GOLD: در نت ملی IPهای پوشه‌ی جهانی استفاده می‌شوند
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
    // IPPORT: همان پورتی که IP روی آن باز بود (اگر پورت ثابت نباشد)
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

// DNSPRE: آدرس DoH این حالت از گوشی باز است؟ (فقط یک بار سنجیده می‌شود)
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

// link-level tweaks (fingerprint, ALPN, transport mode, SNI, early data)
String _natApplyTweaks(String link, _NatSpec x, Server s) {
  if (x.fp != null) link = _natSetParam(link, 'fp', x.fp!);
  if (x.alpn != null) link = _natSetParam(link, 'alpn', x.alpn!);
  final md = x.mode;
  if (md != null && md.startsWith('kcp:')) {
    link = _natSetParam(link, 'type', 'kcp');
    link = _natSetParam(link, 'headerType', md.substring(4));
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

// MULTIHOP: سرور exit (خراب یا ضعیف) از پشت سرور relay (سالم) رد می‌شود.
// هر دو با همان هسته‌ی Xray: outbound سرور relay به‌عنوان hop اضافه می‌شود و
// sockopt.dialerProxy خروجی سرور exit به آن اشاره می‌کند. اگر ساخت نشود null می‌دهد.
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
    if (!keepInbounds) ej.remove('inbounds'); // تست: ورودی لازم نیست؛ اتصال واقعی ورودی‌ها (tun/socks) را نگه می‌دارد
    return jsonEncode(ej);
  } catch (_) {
    return null;
  }
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

// V7-FRAG: Fragment on the TLS Hello (and the first packets) with the sizes of
// table row [fi], PLUS a deterministic jitter seeded by (server key, variant).
// The DPI of Iranian operators can pattern-match a fixed TLS hello fragment
// signature (e.g. "always 120 bytes then 85 bytes"). With this jitter, each
// (server, variant) pair gets a slightly different length/interval within the
// same profile, so the pattern changes from server to server — but the SAME
// pair always gets the SAME jitter, so the test and the real connection use
// identical byte counts (the test that succeeded is the connection that runs).
String _natFrag(String cfg, int fi,
    {bool noise = false, int noiseK = 0, int seed = 0}) {
  if (fi < 0 || fi >= _natFrags.length) return cfg;
  final p = _natFrags[fi];

  // V7-FRAG: seeded jitter. Small shifts (±6 bytes for length, ±3 ms for
  // interval) keep the profile within a safe range while still randomizing
  // the exact fragment boundaries the DPI sees.
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
  } catch (e, stk) {
    logError(e, stk);
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

    // 1) primary DoH (chosen by the caller)
    add(doh);
    // 2) dynamic fallback: Cloudflare, then Google
    add('https+local://1.1.1.1/dns-query');
    add('https+local://8.8.8.8/dns-query');
    // 3) plain-IP DNS as a last resort (works even when all DoH are blocked)
    add('1.1.1.1');
    add('8.8.8.8');
    // 4) local resolver — lets the OS/network handle anything else
    add('localhost');

    d['servers'] = servers;
    j['dns'] = d;
    return jsonEncode(j);
  } catch (e, stk) {
    logError(e, stk);
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
  } catch (e, stk) {
    logError(e, stk);
    return cfg;
  }
}

// کانفیگ نهایی یک سرور با حالت v (v=0 دقیقاً مثل قبل است)
// DIALERFIX: the final pass always drops a dialerProxy whose outbound is gone,
// because fragment/mux/dns/sockopt edits below can leave one behind.
String natCfg(Server s, int v, {bool reuse = false}) =>
    sanitizeCfg(_natCfgRaw(s, v, reuse: reuse));

String _natCfgRaw(Server s, int v, {bool reuse = false}) {
  var cfg = buildCoreConfig(_natLinkFor(s, v, reuse: reuse));
  if (v <= 0 || v >= _natSpecs.length) return cfg;
  final x = _natSpecs[v];
  if (x.frag != null) {
    // V7-FRAG: seed = server key hash XOR variant number. Same (server, variant)
    // pair always gets the same jitter → test and connection use identical
    // fragment sizes. Different servers/variants get different sizes → DPI
    // cannot pattern-match one fixed signature across the fleet.
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

// حالتی که برای اتصال واقعی استفاده می‌شود.
// ULTRA: وقتی ultraMode روشن است هم حالت یادگرفته‌شده اعمال می‌شود
// (قبلاً فقط nationalMode بود و ماتریس در اتصال عادی بی‌اثر می‌ماند).
// NATONLYVAR: حالت‌های نت ملی (IP تمیز، پورت، DNS، SNI) فقط در نت ملی اعمال می‌شوند.
// قبلاً شکست‌ناپذیر (که پیش‌فرض روشن است) هم آن‌ها را روی اتصال عادی می‌گذاشت.
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
  // Ignore legacy saved variants that relied on mux/noise/transport rewriting.
  if (x.mux || x.noise || x.mode != null) return 0;
  return v;
}

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
    if (v == prefer)
