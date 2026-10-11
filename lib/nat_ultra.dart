part of 'main.dart';

// NATULTRA ==================================================================
// نت ملی / اینترنت کند: هر سرور فقط با «یک» حالت تست نمی‌شود؛ حالت‌های مختلف
// (آدرس دامنه/IP، Fragment با اندازه‌های مختلف، fingerprint های مختلف، ALPN)
// پشت‌سرهم امتحان می‌شوند. حالتی که جواب داد برای اتصال واقعی هم همان
// استفاده می‌شود (قبلاً تست بدون Fragment بود ولی اتصال با Fragment).
//
// natLevel 1 = حالت عادی + آدرس دیگر + Fragment ریز
// natLevel 2 = همه‌ی حالت‌ها + آدرس تست دوم (دکمه‌ی «جستجوی سرور با نت ملی»
//              و هر مرحله‌ی «گسترده»)
int natLevel = 1;

// کلید سرور -> شماره‌ی حالتی که جواب داد
final Map<String, int> natVar = {};

const List<String> _natVarNames = [
  'عادی',
  'آدرس دیگر',
  'Fragment ریز',
  'Fragment متوسط',
  'fp=firefox',
  'fp=randomized + Fragment',
  'fp=ios',
  'alpn=http/1.1',
];

const String _natAltTestUrl = 'http://cp.cloudflare.com/generate_204';

bool _natIsSecure(Server s) {
  if (s.ovpn) return false;
  final l = s.link.toLowerCase();
  if (l.startsWith('ss://')) return false;
  return s.tls || s.reality || l.contains('security=tls') || l.contains('"tls":"tls"');
}

bool _natApplies(Server s, int v) {
  if (s.ovpn) return false;
  if (v == 0) return true;
  if (v == 1) return s.ipLink != null && s.ipLink != s.link;
  return _natIsSecure(s);
}

// ترتیب امتحان حالت‌ها برای یک سرور (کد ≥100 = همان حالت با آدرس تست دوم)
List<int> _natOrder(Server s, {bool full = false}) {
  final known = natVar[_nk(s)];
  final out = <int>[];
  if (known != null && _natApplies(s, known)) out.add(known);
  // حالت‌هایی که روی این اپراتور بیشتر جواب داده‌اند اول امتحان می‌شوند
  final cand = (natLevel >= 2 || full ? [0, 1, 2, 3, 4, 5, 6, 7] : [0, 1, 2])
    ..sort((a, b) {
      final d = (natWins['$natOpKey#$b'] ?? 0) - (natWins['$natOpKey#$a'] ?? 0);
      return d != 0 ? d : a - b;
    });
  for (final v in cand) {
    if (v != known && _natApplies(s, v)) out.add(v);
  }
  if (natLevel >= 2 || full) out.add(100);
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
  } catch (_) {
    return link;
  }
}

String _natLinkFor(Server s, int v) {
  if (s.ovpn) return s.useLink;
  final base = (v == 1 && s.ipLink != null) ? s.link : s.useLink;
  switch (v) {
    case 4:
      return _natSetParam(base, 'fp', 'firefox');
    case 5:
      return _natSetParam(base, 'fp', 'randomized');
    case 6:
      return _natSetParam(base, 'fp', 'ios');
    case 7:
      return _natSetParam(base, 'alpn', 'http/1.1');
  }
  return base;
}

// Fragment روی TLS Hello با اندازه‌ی مخصوص هر حالت
String _natFrag(String cfg, int v) {
  const fr = <int, List<String>>{
    2: ['10-30', '5-10'],
    3: ['100-200', '10-20'],
    5: ['50-100', '5-10'],
  };
  final p = fr[v];
  if (p == null) return cfg;
  try {
    final j = jsonDecode(cfg);
    if (j is! Map<String, dynamic>) return cfg;
    final outs = (j['outbounds'] as List?) ?? <dynamic>[];
    dynamic proxy;
    for (final o in outs) {
      if (o is Map &&
          const {'vmess', 'vless', 'trojan', 'shadowsocks'}
              .contains(o['protocol'])) {
        proxy = o;
        break;
      }
    }
    if (proxy == null) return cfg;
    final st = proxy['streamSettings'];
    if (st is! Map) return cfg;
    final sec = (st['security'] ?? 'none').toString();
    if (sec != 'tls' && sec != 'reality') return cfg;
    outs.removeWhere((o) => o is Map && o['tag'] == 'frag-out');
    outs.add({
      'tag': 'frag-out',
      'protocol': 'freedom',
      'settings': {
        'fragment': {'packets': 'tlshello', 'length': p[0], 'interval': p[1]}
      },
    });
    final so = st['sockopt'] is Map ? st['sockopt'] as Map : <String, dynamic>{};
    so['dialerProxy'] = 'frag-out';
    st['sockopt'] = so;
    j['outbounds'] = outs;
    return jsonEncode(j);
  } catch (_) {
    return cfg;
  }
}

// کانفیگ نهایی یک سرور با حالت v (v=0 دقیقاً مثل قبل است)
String natCfg(Server s, int v) {
  final cfg = V2ray.parseFromURL(_natLinkFor(s, v)).getFullConfiguration();
  return _natFrag(cfg, v);
}

// حالتی که برای اتصال واقعی استفاده می‌شود
int natVarFor(Server s) => nationalMode ? (natVar[_nk(s)] ?? 0) : 0;

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
  } catch (_) {
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
    final j = jsonDecode(body);
    final raw = '${j[field] ?? ''}';
    final m = RegExp(r'(\d{3,7})').firstMatch(raw);
    return m?.group(1);
  } catch (_) {
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
  } catch (_) {}
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
    await p.setString('natvar2', jsonEncode({'v': natVar, 'w': natWins}));
  } catch (e) {
    logError(e);
  }
}

Future<void> natLoadPersisted() async {
  try {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('natvar2');
    if (s == null) return;
    final j = jsonDecode(s);
    (j['v'] as Map).forEach((k, v) => natVar['$k'] = (v as num).toInt());
    (j['w'] as Map).forEach((k, v) => natWins['$k'] = (v as num).toInt());
  } catch (e) {
    logError(e);
  }
}
