part of 'main.dart';

// NPVAMPATCH ===============================================================
// بخش‌های مشترک V2Ray برای King-vpn: خواندن لینک، IP تمیز، Fragment / Mux / DNS
//
// 1) خواندن «کانفیگ‌های غیراستاندارد» (سازگار با NPV): لینک‌های دارای کاراکتر
//    نامرئی / اسکیپ‌شده / درصدی، لینک‌های بسته‌بندی‌شده با یک اسکیم ناشناخته
//    (npv://، npvt:// ...) که داخلشان base64 یک لینک استاندارد است، متن base64
//    خالی، و کانفیگ JSON کامل v2ray/xray (vmess/vless/trojan/ss) -> لینک استاندارد.
//    پورت و بقیه‌ی پارامترها هرگز دست نمی‌خورند.
// 2) IP تمیز: فهرست IP ها از چند منبع + نمونه از رنج‌های Cloudflare،
//    تست TCP روی 443، نگه‌داشتن سریع‌ترین‌ها؛ برای سرورهای پشت Cloudflare
//    به‌جای آدرس دامنه از این IP ها استفاده می‌شود (SNI/Host همان دامنه می‌ماند).
// 3) Fragment / Mux / DNS امن: تغییر واقعی روی JSON هسته (فقط اتصال واقعی،
//    تست‌ها دست‌نخورده می‌مانند).
// ===========================================================================

// ---------------------------- تنظیمات (ذخیره در settings) ----------------------------
bool npvParse = true; // خواندن کانفیگ‌های غیراستاندارد
bool cleanIpMode = true; // IP تمیز برای سرورهای Cloudflare
bool fragEnabled = false; // OFF by default = much higher post-connect speed
bool muxEnabled = true; // ON: توربو سرعت بعد از اتصال — Mux فعال
bool secureDns = true; // DNS از طریق DoH + IP fallback
bool blockQuic = true; // مسدود کردن QUIC (UDP 443) تا مرورگرها به TCP/TLS برگردند
bool lanDirect = true; // شبکه‌ی محلی (LAN) از تونل رد نشود
bool routeOnly = false; // دامنه‌ی sniff شده فقط برای مسیریابی، مقصد IP دست‌نخورده
String fragLen = '100-200'; // طول تکه‌های Fragment
String fragInt = '10-20'; // فاصله‌ی تکه‌ها (میلی‌ثانیه)
int muxConc = 32; // concurrency بالا برای سرعت بیشتر
String dnsProv = 'auto'; // auto | cloudflare | google | quad9 | opendns | adguard | shecan | electro | radar
/// آخرین ارائه‌دهندهٔ برنده‌شده وقتی dnsProv=auto است
String dnsProvActive = 'cloudflare';
DateTime? _dnsPickAt;
const _fragLenOpts = <String>['100-200', '50-100', '10-30'];
const _fragIntOpts = <String>['10-20', '1-5', '20-40'];
const _muxOpts = <int>[4, 8, 16, 32];
const _dnsOpts = <String>[
  'auto',
  'cloudflare',
  'google',
  'quad9',
  'opendns',
  'adguard',
  'shecan',
  'electro',
  'radar',
];
const _dnsUrls = <String, List<String>>{
  'cloudflare': [
    'https://1.1.1.1/dns-query',
    '1.1.1.1',
    '1.0.0.1',
    '2606:4700:4700::1111',
  ],
  'google': [
    'https://8.8.8.8/dns-query',
    '8.8.8.8',
    '8.8.4.4',
    '2001:4860:4860::8888',
  ],
  'quad9': [
    'https://9.9.9.9/dns-query',
    '9.9.9.9',
    '149.112.112.112',
    '2620:fe::fe',
  ],
  'opendns': [
    '208.67.222.222',
    '208.67.220.220',
    '2620:119:35::35',
  ],
  'adguard': [
    'https://dns.adguard-dns.com/dns-query',
    '94.140.14.14',
    '94.140.15.15',
    '2a10:50c0::ad1:ff',
  ],
  'shecan': [
    '178.22.122.100',
    '185.51.200.2',
  ],
  'electro': [
    '78.157.42.100',
    '78.157.42.101',
  ],
  'radar': [
    '10.202.10.10',
    '10.202.10.11',
  ],
};

/// ارائه‌دهندهٔ واقعی برای ساخت کانفیگ (auto → برنده‌شده)
String effectiveDnsProv() =>
    dnsProv == 'auto' ? dnsProvActive : dnsProv;

/// تست DoH با HTTP
Future<int?> _probeDoh(String url) async {
  final sw = Stopwatch()..start();
  final cl = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final req =
        await cl.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 2));
    req.headers.set('accept', 'application/dns-json');
    final res = await req.close().timeout(const Duration(seconds: 2));
    await res.drain().timeout(const Duration(seconds: 2));
    if (res.statusCode >= 200 && res.statusCode < 400) {
      return sw.elapsedMilliseconds;
    }
  } catch (e, stk) {
    logError(e, stk);
  } finally {
    cl.close(force: true);
  }
  return null;
}

/// تست DNS فقط با IP (پورت ۵۳)
Future<int?> _probeDnsIp(String ip) async {
  final sw = Stopwatch()..start();
  try {
    final s = await Socket.connect(ip, 53,
            timeout: const Duration(seconds: 2))
        .timeout(const Duration(seconds: 2));
    final ms = sw.elapsedMilliseconds;
    s.destroy();
    return ms;
  } catch (e, stk) {
    logError(e, stk);
    return null;
  }
}

/// تست همهٔ ارائه‌دهنده‌ها و انتخاب کم‌تأخیرترین.
/// نتیجه حدود ۱۰ دقیقه کش می‌شود.
Future<String> pickBestDns({bool force = false}) async {
  if (dnsProv != 'auto') {
    dnsProvActive = dnsProv;
    return dnsProv;
  }
  if (!force &&
      _dnsPickAt != null &&
      DateTime.now().difference(_dnsPickAt!) < const Duration(minutes: 10)) {
    return dnsProvActive;
  }

  // DoH-capable providers
  const dohProbes = <String, String>{
    'cloudflare': 'https://1.1.1.1/dns-query?name=google.com&type=A',
    'google': 'https://8.8.8.8/resolve?name=google.com&type=A',
    'quad9': 'https://9.9.9.9:5053/dns-query?name=google.com&type=A',
    'adguard':
        'https://94.140.14.14/dns-query?name=google.com&type=A',
  };
  // Plain-IP providers (TCP :53)
  const ipProbes = <String, String>{
    'opendns': '208.67.222.222',
    'shecan': '178.22.122.100',
    'electro': '78.157.42.100',
    'radar': '10.202.10.10',
  };

  String best = 'cloudflare';
  var bestMs = 1 << 30;

  await Future.wait([
    ...dohProbes.entries.map((e) async {
      final ms = await _probeDoh(e.value);
      if (ms != null && ms < bestMs) {
        bestMs = ms;
        best = e.key;
      }
    }),
    ...ipProbes.entries.map((e) async {
      final ms = await _probeDnsIp(e.value);
      if (ms != null && ms < bestMs) {
        bestMs = ms;
        best = e.key;
      }
    }),
  ]);

  dnsProvActive = best;
  _dnsPickAt = DateTime.now();
  return best;
}
// رنج‌های خصوصی؛ بدون نیاز به فایل geoip
const _lanCidrs = <String>[
  '10.0.0.0/8',
  '172.16.0.0/12',
  '192.168.0.0/16',
  '127.0.0.0/8',
  '169.254.0.0/16',
];
bool iranMore = true; // دامنه‌های ایرانیِ غیر .ir هم مستقیم بروند (به‌جز iranRoute)

// منابع اضافه‌ی لیست. فایل vless_configs.txt در تست زنده باز شد (لینک خام، سطر به سطر؛
// پر از &amp; و userinfo درصدی که پارسر NPV درستشان می‌کند). مسیر vmess/trojan از README خود ریپو.
// لینک مرده خودکار رد می‌شود.
final List<String> _npvUrls = [
  // ebrasha — updated every ~15 min, includes escaped/messy links NPV parser handles
  'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/vless_configs.txt',
  'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/vmess_configs.txt',
  'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/trojan_configs.txt',
  'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/ss_configs.txt',
  'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/all_extracted_configs.txt',
  'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/V2Ray-Config-By-EbraSha-All-Type.txt',
  // frequent updaters (good for npv:// / percent-encoded / messy lines)
  'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/verified/configs.txt',
  'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/all/configs.txt',
  'https://raw.githubusercontent.com/Alirewa/V2ray-Configs/main/config.txt',
  'https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/all_sub.txt',
  'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/All_Configs_Sub.txt',
  'https://raw.githubusercontent.com/barry-far/V2ray-Config/main/All_Configs_Sub.txt',
  'https://raw.githubusercontent.com/hamedcode/port-based-v2ray-configs/main/sub/vless.txt',
  'https://raw.githubusercontent.com/hamedcode/port-based-v2ray-configs/main/sub/vmess.txt',
  'https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/subs/bundles/iran.txt',
  'https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/subs/bundles/best.txt',
  'https://raw.githubusercontent.com/HosseinKoofi/GO_V2rayCollector/main/mixed_iran.txt',
  'https://raw.githubusercontent.com/youfoundamin/V2rayCollector/main/mixed_iran.txt',
  'https://raw.githubusercontent.com/soroushmirzaei/telegram-configs-collector/main/protocols/vless',
  'https://raw.githubusercontent.com/soroushmirzaei/telegram-configs-collector/main/protocols/vmess',
  // verified live 2026-10-16
  'https://raw.githubusercontent.com/3inker/v2ray-subscription/main/subs/all_not_ru.txt',
  'https://raw.githubusercontent.com/3inker/v2ray-subscription/main/subs/all_ru.txt',
  'https://raw.githubusercontent.com/free-nodes/v2rayfree/main/sub',
  'https://raw.githubusercontent.com/ermaozi/get_subscribe/main/subscribe/v2ray.txt',
  'https://raw.githubusercontent.com/Au1rxx/free-vpn-subscriptions/main/output/v2ray-base64.txt',
];

// =========================== 1) پارسر سازگار با NPV ===========================
final RegExp _zeroWidth =
    RegExp('[\u200B-\u200F\u202A-\u202E\u2060\uFEFF]');
final RegExp _pctScheme =
    RegExp(r'^(vmess|vless|trojan|ss)%3a%2f%2f', caseSensitive: false);
final RegExp _anyScheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]{1,12})://(.+)$');
final RegExp _b64Body = RegExp(r'^[A-Za-z0-9+/_\-=\s]+$');

// پاک‌سازی سبک یک خط (روی هر Server.parse اجرا می‌شود، پس باید ارزان باشد)
String npvClean(String s) {
  if (!npvParse) return s;
  var t = s.replaceAll(_zeroWidth, '').trim();
  if (t.contains('&amp;')) t = t.replaceAll('&amp;', '&');
  if (t.contains(r'\/')) t = t.replaceAll(r'\/', '/');
  if (t.contains('%3') || t.contains('%3A')) {
    final m = _pctScheme.firstMatch(t);
    if (m != null) t = '${m.group(1)}://${t.substring(m.end)}';
  }
  // ویرگول / نقطه‌ویرگول / کوتیشن انتهای خط (از CSV و JSON)
  while (t.isNotEmpty && (t.endsWith(',') || t.endsWith(';') || t.endsWith("'"))) {
    t = t.substring(0, t.length - 1);
  }
  return t;
}

String? _b64Text(String raw) {
  try {
    final c = raw.replaceAll(RegExp(r'\s'), '').replaceAll('-', '+').replaceAll('_', '/');
    if (c.length < 16) return null;
    return utf8.decode(base64.decode(base64.normalize(c)), allowMalformed: true);
  } catch (e, stk) {
    logError(e, stk);
    return null;
  }
}

// خطی که اسکیم استاندارد ندارد: npv://<base64>، یا هر اسکیم ناشناخته که
// داخلش یک لینک استاندارد (یا JSON) پنهان است. اگر چیزی پیدا نشد null.
String? npvNormalizeLink(String line) {
  if (!npvParse) return null;
  final t = npvClean(line);
  String payload;
  final m = _anyScheme.firstMatch(t);
  if (m != null) {
    payload = m.group(2)!;
    final h = payload.indexOf('#');
    if (h >= 0) payload = payload.substring(0, h);
    try {
      payload = Uri.decodeComponent(payload);
    } catch (e, stk) { logError(e, stk); }
  } else {
    payload = t;
  }
  if (!_b64Body.hasMatch(payload)) return null;
  final txt = _b64Text(payload);
  if (txt == null) return null;
  final lm = _linkRe.firstMatch(txt);
  if (lm != null) return lm.group(0);
  final tt = txt.trimLeft();
  if (tt.startsWith('{') || tt.startsWith('[')) {
    try {
      final l = npvJsonToLinks(jsonDecode(tt));
      if (l.isNotEmpty) return l.first;
    } catch (e, stk) { logError(e, stk); }
  }
  return null;
}

// یک متن چندخطی (فایل، لینک اشتراک، متن چسبانده‌شده) -> فهرست لینک‌های تک‌خطی
List<String> npvSplit(String text) {
  final plain = text.split(RegExp(r'[\r\n]+'));
  if (!npvParse) return plain;
  final out = <String>[];
  final t = text.replaceAll(_zeroWidth, '').trim();
  if (t.isEmpty) return out;
  // 1) JSON کامل
  if (t.startsWith('{') || t.startsWith('[')) {
    try {
      out.addAll(npvJsonToLinks(jsonDecode(t)));
      if (out.isNotEmpty) return out;
    } catch (e, stk) { logError(e, stk); }
  }
  // 2) کل متن یک بلوک base64 است
  if (!t.contains('://') && _b64Body.hasMatch(t)) {
    final d = _b64Text(t);
    if (d != null && d.contains('://')) return npvSplit(d);
  }
  // 3) خط به خط؛ چند لینک در یک خط هم جدا می‌شود
  for (final raw in plain) {
    final line = npvClean(raw);
    if (line.isEmpty) continue;
    final ms = _linkRe.allMatches(line).toList();
    if (ms.isNotEmpty) {
      for (final m in ms) {
        out.add(npvClean(m.group(0)!));
      }
      continue;
    }
    final alt = npvNormalizeLink(line);
    if (alt != null) out.add(alt);
  }
  return out;
}

// ---- JSON کامل v2ray/xray -> لینک ----
List<String> npvJsonToLinks(dynamic j, {int depth = 0}) {
  final out = <String>[];
  if (depth > 3) return out;
  if (j is List) {
    for (final e in j) {
      out.addAll(npvJsonToLinks(e, depth: depth + 1));
    }
    return out;
  }
  if (j is! Map) return out;
  final remark = (j['remarks'] ?? j['ps'] ?? j['remark'] ?? '').toString();
  if (j['outbounds'] is List) {
    for (final o in (j['outbounds'] as List)) {
      final l = _npvOutboundLink(o, remark);
      if (l != null) out.add(l);
    }
    return out;
  }
  final l = _npvOutboundLink(j, remark);
  if (l != null) out.add(l);
  return out;
}

String? _npvOutboundLink(dynamic o, String remark) {
  try {
    if (o is! Map) return null;
    final proto = (o['protocol'] ?? '').toString().toLowerCase();
    if (!const {'vmess', 'vless', 'trojan', 'shadowsocks'}.contains(proto)) {
      return null;
    }
    final st = (o['streamSettings'] is Map) ? o['streamSettings'] as Map : const {};
    final net = (st['network'] ?? 'tcp').toString();
    final sec = (st['security'] ?? 'none').toString();
    final tag = (o['tag'] ?? '').toString();
    final name = remark.isNotEmpty
        ? remark
        : ((tag.isEmpty || tag == 'proxy') ? 'V2Ray' : tag);
    final settings = (o['settings'] is Map) ? o['settings'] as Map : const {};

    final q = <String, String>{'type': net, 'security': sec};
    if (net == 'ws' && st['wsSettings'] is Map) {
      final w = st['wsSettings'] as Map;
      if (w['path'] != null) q['path'] = w['path'].toString();
      final h = (w['headers'] is Map ? (w['headers'] as Map)['Host'] : null) ?? w['host'];
      if (h != null) q['host'] = h.toString();
    } else if (net == 'grpc' && st['grpcSettings'] is Map) {
      final g = st['grpcSettings'] as Map;
      if (g['serviceName'] != null) q['serviceName'] = g['serviceName'].toString();
    } else if ((net == 'httpupgrade' || net == 'xhttp' || net == 'splithttp') &&
        st['${net}Settings'] is Map) {
      final w = st['${net}Settings'] as Map;
      if (w['path'] != null) q['path'] = w['path'].toString();
      if (w['host'] != null) q['host'] = w['host'].toString();
    }
    if (sec == 'tls' && st['tlsSettings'] is Map) {
      final t = st['tlsSettings'] as Map;
      if (t['serverName'] != null) q['sni'] = t['serverName'].toString();
      if (t['fingerprint'] != null) q['fp'] = t['fingerprint'].toString();
      if (t['alpn'] is List) q['alpn'] = (t['alpn'] as List).join(',');
    } else if (sec == 'reality' && st['realitySettings'] is Map) {
      final r = st['realitySettings'] as Map;
      if (r['serverName'] != null) q['sni'] = r['serverName'].toString();
      if (r['fingerprint'] != null) q['fp'] = r['fingerprint'].toString();
      if (r['publicKey'] != null) q['pbk'] = r['publicKey'].toString();
      if (r['shortId'] != null) q['sid'] = r['shortId'].toString();
      if (r['spiderX'] != null) q['spx'] = r['spiderX'].toString();
    }

    if (proto == 'vmess' || proto == 'vless') {
      final vn = (settings['vnext'] as List?)?.first as Map?;
      if (vn == null) return null;
      final users = vn['users'];
      if (users is! List || users.isEmpty) return null;
      final u = users.first;
      if (u is! Map) return null;
      final addr = vn['address']?.toString() ?? '';
      if (addr.isEmpty) return null;
      final port = int.tryParse('${vn['port']}') ?? 0;
      if (port <= 0 || port > 65535) return null;
      if (proto == 'vless') {
        q['encryption'] = (u['encryption'] ?? 'none').toString();
        if ((u['flow'] ?? '').toString().isNotEmpty) q['flow'] = u['flow'].toString();
        return Uri(
                scheme: 'vless',
                userInfo: u['id'].toString(),
                host: addr,
                port: port,
                queryParameters: q,
                fragment: name)
            .toString();
      }
      final m = <String, dynamic>{
        'v': '2',
        'ps': name,
        'add': addr,
        'port': port.toString(),
        'id': u['id'].toString(),
        'aid': (u['alterId'] ?? 0).toString(),
        'scy': (u['security'] ?? 'auto').toString(),
        'net': net,
        'type': 'none',
        'host': q['host'] ?? '',
        'path': net == 'grpc' ? (q['serviceName'] ?? '') : (q['path'] ?? ''),
        'tls': sec == 'tls' ? 'tls' : '',
        'sni': q['sni'] ?? '',
        'alpn': q['alpn'] ?? '',
        'fp': q['fp'] ?? '',
      };
      return 'vmess://${base64.encode(utf8.encode(jsonEncode(m)))}';
    }
    final sv = (settings['servers'] as List?)?.first as Map?;
    if (sv == null) return null;
    final addr = sv['address']?.toString() ?? '';
    if (addr.isEmpty) return null;
    final port = int.tryParse('${sv['port']}') ?? 0;
    if (port <= 0 || port > 65535) return null;
    if (proto == 'trojan') {
      return Uri(
              scheme: 'trojan',
              userInfo: sv['password'].toString(),
              host: addr,
              port: port,
              queryParameters: q,
              fragment: name)
          .toString();
    }
    // shadowsocks (SIP002)
    final ui = base64
        .encode(utf8.encode('${sv['method']}:${sv['password']}'))
        .replaceAll('=', '');
    return 'ss://$ui@$addr:$port#${Uri.encodeComponent(name)}';
  } catch (e, stk) {
    logError(e, stk);
    return null;
  }
}

// =========================== 2) IP تمیز ===========================
class CleanIp {
  final String ip;
  final int ms;
  CleanIp(this.ip, this.ms);
}

List<CleanIp> cleanIps = [];
DateTime? cleanIpsAt;
String cleanIpStatus = '';
Future<void>? _cleanBusy;
bool _cleanLoaded = false;
String _cleanOp = '';
int _cleanRot = 0;

// رنج‌های IPv4 منتشرشده‌ی Cloudflare. لیست‌های ثابتِ «IP تمیز» زود کهنه می‌شوند و
// ابزارهای معروف (مثل cfray) هم به‌جای دانلود لیست، همین رنج‌ها را اسکن می‌کنند.
const _cfRanges = <String>[
  '104.16.0.0/13',
  '172.64.0.0/13',
  '162.158.0.0/15',
  '188.114.96.0/20',
  '141.101.64.0/18',
  '108.162.192.0/18',
  '190.93.240.0/20',
  '198.41.128.0/17',
  '173.245.48.0/20',
  '103.21.244.0/22',
  '103.22.200.0/22',
  '103.31.4.0/22',
  '131.0.72.0/22',
];

bool _cleanOk(String ip) {
  final a = InternetAddress.tryParse(ip);
  return a != null && a.type == InternetAddressType.IPv4 && !_privateIp(a);
}

List<String> _cidrSample(String cidr, int n, Random r) {
  final p = cidr.split('/');
  if (p.length != 2) return const [];
  final a = InternetAddress.tryParse(p[0]);
  final bits = int.tryParse(p[1]);
  if (a == null ||
      a.type != InternetAddressType.IPv4 ||
      bits == null ||
      bits < 8 ||
      bits > 32) {
    return const [];
  }
  final b = a.rawAddress;
  final base = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
  final span = 1 << (32 - bits);
  final mask = (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF;
  final net = base & mask;
  final out = <String>[];
  for (var i = 0; i < n; i++) {
    final off = span <= 2 ? 0 : 1 + r.nextInt(span - 2);
    final v = net + off;
    out.add('${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}');
  }
  return out;
}

Future<List<String>> _cleanCandidates() async {
  final r = Random();
  final set = <String>{};
  // built-in Cloudflare ranges
  var ranges = List<String>.of(_cfRanges);
  // try official live list (updated by Cloudflare) — if it fails we keep fallback
  try {
    final res = await http
        .get(Uri.parse('https://www.cloudflare.com/ips-v4'))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final live = res.body
          .split(RegExp(r'[\r\n]+'))
          .map((e) => e.trim())
          .where((e) => e.contains('/'))
          .toList();
      if (live.length >= 5) ranges = live;
    }
  } catch (e, stk) { logError(e, stk); }
  for (final c in ranges) {
    set.addAll(_cidrSample(c, 28, r).where(_cleanOk));
  }
  final l = set.toList()..shuffle(r);
  return l.take(240).toList();
}

// CLEANIPFIX: the old probe connected with SecureSocket.connect(ip) which sends
// NO SNI, and Cloudflare drops such handshakes -> every IP failed (0 of 100).
// Now: TCP connect to the IP, TLS with SNI cloudflare.com, then
// /cdn-cgi/trace. If TLS fails the plain HTTP (port 80) answer of Cloudflare is
// used as a second chance.
Future<String> _cfRead(Socket k, Duration t) async {
  final data = <int>[];
  try {
    await for (final c in k.timeout(t, onTimeout: (sink) => sink.close())) {
      data.addAll(c);
      if (data.length > 1500) break;
    }
  } catch (e, stk) { logError(e, stk); }
  return utf8.decode(data, allowMalformed: true).toLowerCase();
}

Future<int?> _cfProbeMs(String ip, Duration t) async {
  final sw = Stopwatch()..start();
  Socket? raw;
  Socket? k;
  try {
    raw = await Socket.connect(ip, 443, timeout: t);
    k = await SecureSocket.secure(raw,
            host: 'cloudflare.com',
            onBadCertificate: (_) => true,
            supportedProtocols: const ['http/1.1'])
        .timeout(t);
    k.write(
        'GET /cdn-cgi/trace HTTP/1.1\r\nHost: cloudflare.com\r\nConnection: close\r\n\r\n');
    await k.flush();
    final txt = await _cfRead(k, t);
    sw.stop();
    if (txt.contains('cloudflare')) return sw.elapsedMilliseconds;
  } catch (e, stk) {
    logError(e, stk);
  } finally {
    k?.destroy();
    raw?.destroy();
  }
  // second chance: plain HTTP on port 80
  Socket? h;
  try {
    final sw2 = Stopwatch()..start();
    h = await Socket.connect(ip, 80, timeout: t);
    h.write(
        'GET /cdn-cgi/trace HTTP/1.1\r\nHost: cloudflare.com\r\nConnection: close\r\n\r\n');
    await h.flush();
    final txt = await _cfRead(h, t);
    sw2.stop();
    if (txt.contains('cloudflare')) return sw2.elapsedMilliseconds + 40;
  } catch (e, stk) {
    logError(e, stk);
  } finally {
    h?.destroy();
  }
  return null;
}

final ValueNotifier<int> cleanTick = ValueNotifier<int>(0);

Future<void> _doRefreshClean() async {
  try {
    cleanIpStatus = 'در حال جمع‌آوری IP...';
    cleanTick.value++;
    final c = await _cleanCandidates();
    final res = <CleanIp>[];
    var done = 0;
    // ANR-safe: async sockets only, a short pause after each probe
    await pool<String>(c, 20, (ip) async {
      if (res.length >= 20) return;
      final ms = await _cfProbeMs(ip, const Duration(milliseconds: 3500));
      done++;
      if (ms != null) res.add(CleanIp(ip, ms));
      if (done % 5 == 0) {
        cleanIpStatus = 'در حال تست... $done از ${c.length} • ${res.length} سالم';
        cleanTick.value++;
      }
      await Future.delayed(const Duration(milliseconds: 20));
    }).timeout(const Duration(seconds: 40), onTimeout: () {});
    res.sort((a, b) => a.ms.compareTo(b.ms));
    cleanIps = res.take(20).toList();
    cleanIpsAt = DateTime.now();
    cleanIpStatus = '${cleanIps.length} IP سالم از ${c.length} تست';
    await _saveCleanIps();
  } catch (e, stk) {
    logError(e, stk);
    cleanIpStatus = 'خطا در دریافت IP';
  }
  cleanTick.value++;
}

Future<void> refreshCleanIps() {
  final cur = _cleanBusy;
  if (cur != null) return cur;
  final f = _doRefreshClean().whenComplete(() {
    _cleanBusy = null;
    cleanTick.value++;
  });
  _cleanBusy = f;
  return f;
}

Future<void> _saveCleanIps() async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        'cip_list_$natOpKey', jsonEncode(cleanIps.map((e) => [e.ip, e.ms]).toList()));
    await p.setInt('cip_at_$natOpKey', DateTime.now().millisecondsSinceEpoch);
  } catch (e, stk) {
    logError(e, stk);
  }
}

Future<void> _loadCleanIps() async {
  try {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('cip_list_$natOpKey');
    if (s == null) return;
    cleanIps = (jsonDecode(s) as List).map<CleanIp>((e) {
      final x = e as List;
      return CleanIp(x[0].toString(), (x[1] as num).toInt());
    }).toList();
    final at = p.getInt('cip_at_$natOpKey');
    if (at != null) cleanIpsAt = DateTime.fromMillisecondsSinceEpoch(at);
  } catch (e, stk) {
    logError(e, stk);
  }
}

// یک IP تمیز برای یک سرور Cloudflare (بین ۵ تای سریع می‌چرخد)
Future<String?> pickCleanIp() async {
  if (!_cleanLoaded || _cleanOp != natOpKey) {
    _cleanLoaded = true;
    if (_cleanOp != natOpKey) {
      cleanIps = [];
      cleanIpsAt = null;
    }
    _cleanOp = natOpKey;
    await _loadCleanIps();
  }
  final stale = cleanIpsAt == null ||
      DateTime.now().difference(cleanIpsAt!) > const Duration(hours: 6);
  if (cleanIps.isEmpty) {
    await refreshCleanIps();
  } else if (stale) {
    refreshCleanIps(); // در پس‌زمینه
  }
  if (cleanIps.isEmpty) return null;
  final n = min(5, cleanIps.length);
  return cleanIps[_cleanRot++ % n].ip;
}

// سایت‌های ایرانی با دامنه‌ی غیر .ir (دامنه‌های .ir و چند سایت بزرگ از قبل در iranDomains هستند).
// این‌ها با IP خارجی یا باز نمی‌شوند یا ترافیک نیم‌بها نمی‌گیرند، پس مستقیم می‌روند.
const _iranMoreDomains = <String>[
  'domain:sheypoor.com',
  'domain:ninisite.com',
  'domain:zoodfood.com',
  'domain:bamilo.com',
  'domain:okala.com',
  'domain:varzesh3.com',
  'domain:tgju.org',
];

// =========================== 3) Fragment / Mux / DNS ===========================
// فقط روی اتصال واقعی (بعد از withIranRouting). تست‌ها بدون این تغییرات می‌مانند.
String withNpvAmCore(String cfg) {
  final moreIr = iranRoute && iranMore;
  if (!fragEnabled &&
      !muxEnabled &&
      !secureDns &&
      !moreIr &&
      !blockQuic &&
      !lanDirect &&
      !routeOnly) {
    return cfg;
  }
  try {
    final j = jsonDecode(cfg);
    if (j is! Map<String, dynamic>) return cfg;
    final outs = (j['outbounds'] as List?) ?? <dynamic>[];

    // خروجی freedom (مستقیم) موجود را پیدا می‌کند؛ اگر نبود می‌سازد
    String directTag() {
      for (final o in outs) {
        if (o is Map &&
            o['protocol'] == 'freedom' &&
            o['tag'] != null &&
            o['tag'] != 'frag-out') {
          return o['tag'].toString();
        }
      }
      outs.add({'tag': 'npv-direct', 'protocol': 'freedom', 'settings': {}});
      return 'npv-direct';
    }

    String blockTag() {
      for (final o in outs) {
        if (o is Map && o['protocol'] == 'blackhole' && o['tag'] != null) {
          return o['tag'].toString();
        }
      }
      outs.add({'tag': 'npv-block', 'protocol': 'blackhole', 'settings': {}});
      return 'npv-block';
    }

    // قوانین مسیریابی جدید؛ همه‌شان در ابتدای لیست قوانین قرار می‌گیرند
    final pre = <dynamic>[];
    if (blockQuic) {
      pre.add({
        'type': 'field',
        'network': 'udp',
        'port': '443',
        'outboundTag': blockTag(),
      });
    }
    if (lanDirect) {
      pre.add({'type': 'field', 'ip': _lanCidrs, 'outboundTag': directTag()});
    }
    if (moreIr) {
      pre.add({
        'type': 'field',
        'domain': _iranMoreDomains,
        'outboundTag': directTag(),
      });
    }
    if (pre.isNotEmpty) {
      final rt = j['routing'] is Map ? j['routing'] as Map : <String, dynamic>{};
      rt['rules'] = [...pre, ...((rt['rules'] as List?) ?? <dynamic>[])];
      j['routing'] = rt;
    }

    if (routeOnly) {
      for (final ib in (j['inbounds'] as List?) ?? <dynamic>[]) {
        if (ib is Map && ib['sniffing'] is Map) {
          (ib['sniffing'] as Map)['routeOnly'] = true;
        }
      }
    }

    dynamic proxy;
    for (final o in outs) {
      if (o is Map &&
          const {'vmess', 'vless', 'trojan', 'shadowsocks'}
              .contains(o['protocol'])) {
        proxy = o;
        break;
      }
    }
    if (proxy != null) {
      final st = proxy['streamSettings'];
      final sec = st is Map ? (st['security'] ?? 'none').toString() : 'none';
      final net = st is Map ? (st['network'] ?? 'tcp').toString() : 'tcp';
      if (fragEnabled && st is Map && (sec == 'tls' || sec == 'reality')) {
        if (!outs.any((o) => o is Map && o['tag'] == 'frag-out')) {
          outs.add({
            'tag': 'frag-out',
            'protocol': 'freedom',
            'settings': {
              'fragment': {
                'packets': 'tlshello',
                'length': fragLen,
                'interval': fragInt,
              }
            },
          });
        }
        final so = st['sockopt'] is Map ? st['sockopt'] as Map : <String, dynamic>{};
        so['dialerProxy'] = 'frag-out';
        st['sockopt'] = so;
      }
      if (muxEnabled && (net == 'tcp' || net == 'ws')) {
        var flow = '';
        try {
          final s = proxy['settings'] as Map;
          flow = ((s['vnext'] as List).first['users'] as List).first['flow']
                  ?.toString() ??
              '';
        } catch (e, stk) { logError(e, stk); }
        // Mux با flow (xtls-rprx-vision) کار نمی‌کند
        if (flow.isEmpty) {
          proxy['mux'] = {'enabled': true, 'concurrency': muxConc};
        }
      }
    }
    j['outbounds'] = outs;
    if (secureDns) {
      final d = j['dns'] is Map ? j['dns'] as Map : <String, dynamic>{};
      // Plain IP DNS FIRST (fast, reliable for apps), then DoH.
      // DoH-only often makes Telegram/apps hang when the tunnel is weak.
      final first =
          _dnsUrls[effectiveDnsProv()] ?? _dnsUrls['cloudflare']!;
      final ips = <dynamic>[];
      final doh = <dynamic>[];
      for (final u in first) {
        if (u.toString().startsWith('https://')) {
          doh.add(u);
        } else {
          ips.add(u);
        }
      }
      for (final e in _dnsUrls.entries) {
        for (final u in e.value) {
          if (u.startsWith('https://')) {
            if (!doh.contains(u)) doh.add(u);
          } else if (!ips.contains(u)) {
            ips.add(u);
          }
        }
      }
      // Always include common public + Iranian DNS as fallback chain
      for (final ip in [
        '1.1.1.1',
        '8.8.8.8',
        '9.9.9.9',
        '208.67.222.222',
        '94.140.14.14',
        '178.22.122.100',
        '185.51.200.2',
        '78.157.42.100',
        '10.202.10.10',
        '2606:4700:4700::1111',
        '2001:4860:4860::8888',
      ]) {
        if (!ips.contains(ip)) ips.add(ip);
      }
      d['servers'] = [...ips, ...doh];
      // UseIP = هم IPv4 و هم IPv6
      d['queryStrategy'] = 'UseIP';
      j['dns'] = d;
      // Help domain-based routing resolve correctly for apps
      final rt = j['routing'] is Map ? j['routing'] as Map : <String, dynamic>{};
      rt['domainStrategy'] = rt['domainStrategy'] ?? 'AsIs';
      j['routing'] = rt;
    }
    return jsonEncode(j);
  } catch (e, stk) {
    logError(e, stk);
    return cfg;
  }
}

// =========================== رابط: بخش تنظیمات + دیالوگ ===========================
List<Widget> npvAmSettingsItems(
  Widget Function(String) head,
  Widget Function(String, bool, void Function(bool), {String? sub}) sw,
  void Function() forceIpMode,
) =>
    [
      head('🧩 تنظیمات V2Ray'),
      sw('خواندن کانفیگ‌های غیراستاندارد', npvParse,
          (v) => npvParse = v,
          sub:
              'لینک‌های اسکیپ‌شده، npv://، base64 خالی و JSON کامل v2ray در «افزودن کانفیگ» و لیست‌ها خوانده می‌شوند'),
      sw('ترافیک داخلی بیشتر مستقیم (سایت‌های ایرانی غیر .ir)', iranMore,
          (v) => iranMore = v,
          sub:
              'بعد از «سایت‌های ایرانی مستقیم بروند» کار می‌کند؛ چند سایت ایرانی دیگر هم بدون VPN باز می‌شوند'),
      sw('مسدود کردن QUIC (UDP 443)', blockQuic, (v) => blockQuic = v,
          sub:
              'مرورگرها و برنامه‌ها به TCP/TLS برمی‌گردند و روی VPN پایدارترند'),
      sw('شبکه‌ی محلی (LAN) مستقیم', lanDirect, (v) => lanDirect = v,
          sub: 'آدرس‌های ۱۰.x و ۱۷۲.۱۶.x و ۱۹۲.۱۶۸.x از تونل رد نمی‌شوند'),
      sw('RouteOnly برای تشخیص دامنه', routeOnly, (v) => routeOnly = v,
          sub:
              'دامنه‌ی تشخیص‌داده‌شده فقط برای مسیریابی است و مقصد IP تغییر نمی‌کند؛ اگر برنامه‌ای خراب شد خاموشش کن'),
      sw('IP تمیز برای سرورهای Cloudflare', cleanIpMode, (v) {
        cleanIpMode = v;
        if (v) forceIpMode(); // به «اتصال با IP» وابسته است
      },
          sub:
              'اپ خودش رنج‌های Cloudflare را اسکن می‌کند (TLS واقعی) و برای سرورهای پشت Cloudflare سریع‌ترین IP را به‌جای دامنه می‌گذارد (اتصال با IP خودکار روشن می‌شود). منوی ⋮ ← IP تمیز'),
      sw('Fragment (تکه‌کردن TLS Hello)', fragEnabled, (v) => fragEnabled = v,
          sub:
              'برای عبور از DPI؛ فقط روی اتصال واقعی و فقط سرورهای TLS/Reality. اگر اتصال برقرار نشد خاموشش کن'),
      sw('Mux (چند اتصال روی یک کانال)', muxEnabled, (v) => muxEnabled = v,
          sub: 'روی سرورهای tcp/ws بدون flow؛ گاهی ثبات را بهتر و گاهی بدتر می‌کند'),
      sw('DNS امن (DoH)', secureDns, (v) => secureDns = v,
          sub: 'پرسش DNS از طریق https://1.1.1.1 و 8.8.8.8 انجام می‌شود'),
      ListTile(
        leading: const Icon(Icons.shield_outlined),
        title: const Text('Kill switch (قطع نت اگر VPN افتاد)'),
        subtitle: const Text(
            'تنظیمات VPN اندروید باز می‌شود؛ برای این اپ «Always-on VPN» و «Block connections without VPN» را روشن کن'),
        onTap: () {
          try {
            bgChannel.invokeMethod('vpnSettings');
          } catch (e, stk) { logError(e, stk); }
        },
      ),
    ];

extension NpvAmExtras on _HomePageState {
  // مقدارهای Fragment / Mux / DNS
  void npvAdvDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setD) {
            Widget row<T>(
                String title, T value, List<T> opts, void Function(T) on) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(title)),
                    DropdownButton<T>(
                      value: opts.contains(value) ? value : opts.first,
                      items: [
                        for (final o in opts)
                          DropdownMenuItem<T>(value: o, child: Text('$o')),
                      ],
                      onChanged: (v) {
                        if (v != null) setD(() => on(v));
                      },
                    ),
                  ],
                ),
              );
            }

            return AlertDialog(
              title: const Text('⚙️ تنظیمات پیشرفته V2Ray'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    row<String>('طول تکه‌های Fragment', fragLen, _fragLenOpts,
                        (v) => fragLen = v),
                    row<String>('فاصله‌ی تکه‌ها (ms)', fragInt, _fragIntOpts,
                        (v) => fragInt = v),
                    row<int>('اتصال همزمان Mux', muxConc, _muxOpts,
                        (v) => muxConc = v),
                    row<String>('DNS امن (DoH)', dnsProv, _dnsOpts,
                        (v) => dnsProv = v),
                    const SizedBox(height: 8),
                    const Text(
                        'این مقدارها فقط وقتی اثر دارند که سوئیچ مربوطه در تنظیمات روشن باشد.',
                        style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              actions: [
                FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('تأیید')),
              ],
            );
          },
        ),
      ),
    ).then((_) => _saveSettings());
  }

  void cleanIpDialog() {
    // CLEANIPFIX: the scan starts by itself when the window opens and the
    // window updates live (it used to show a frozen "collecting..." text)
    if (_cleanBusy == null &&
        (cleanIps.isEmpty ||
            cleanIpsAt == null ||
            DateTime.now().difference(cleanIpsAt!) >
                const Duration(minutes: 30))) {
      cleanIpStatus = 'در حال جمع‌آوری IP...';
      unawaited(() async {
        await _loadCleanIps();
        final fresh = cleanIps.isNotEmpty &&
            cleanIpsAt != null &&
            DateTime.now().difference(cleanIpsAt!) < const Duration(minutes: 30);
        if (fresh) {
          cleanIpStatus = '${cleanIps.length} IP ذخیره‌شده';
          cleanTick.value++;
        } else {
          await refreshCleanIps();
        }
      }());
    }
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: ValueListenableBuilder<int>(
          valueListenable: cleanTick,
          builder: (ctx, _, __) => AlertDialog(
            title: const Text('🌐 IP تمیز'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cleanIpStatus.isNotEmpty
                        ? cleanIpStatus
                        : (cleanIps.isEmpty
                            ? 'هنوز تست نشده'
                            : '${cleanIps.length} IP ذخیره‌شده'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (_cleanBusy != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: LinearProgressIndicator(),
                    ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final e in cleanIps.take(10))
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text('${e.ip}    ${e.ms} ms'),
                          ),
                      ],
                    ),
                  ),
                  if (cleanIps.isEmpty && _cleanBusy == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                          'اگر چیزی پیدا نشد، VPN را قطع کن و دوباره «تست دوباره» را بزن (تست با اینترنت مستقیم دقیق‌تر است).',
                          style: TextStyle(fontSize: 12)),
                    ),
                  if (!cleanIpMode)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                          'برای استفاده، در تنظیمات «IP تمیز» را روشن کن.',
                          style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
              if (cleanIps.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(
                        text: cleanIps.map((e) => e.ip).join('\n')));
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text('IPها کپی شد'),
                          duration: Duration(seconds: 2)));
                    }
                  },
                  child: const Text('کپی'),
                ),
              FilledButton(
                onPressed: _cleanBusy != null
                    ? null
                    : () {
                        cleanIpStatus = 'در حال تست...';
                        cleanTick.value++;
                        unawaited(refreshCleanIps());
                      },
                child: const Text('تست دوباره'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
