part of 'main.dart';

// NPVAMPATCH ===============================================================
// پل واقعی NPV / AM برای King-vpn (جایگزین اسکریپت‌های نمایشی Gemini)
//
// 1) خواندن «کانفیگ‌های غیراستاندارد» (سازگار با NPV): لینک‌های دارای کاراکتر
//    نامرئی / اسکیپ‌شده / درصدی، لینک‌های بسته‌بندی‌شده با یک اسکیم ناشناخته
//    (npv://، npvt:// ...) که داخلشان base64 یک لینک استاندارد است، متن base64
//    خالی، و کانفیگ JSON کامل v2ray/xray (vmess/vless/trojan/ss) -> لینک استاندارد.
//    پورت و بقیه‌ی پارامترها هرگز دست نمی‌خورند.
// 2) IP تمیز (سبک AM): فهرست IP ها از چند منبع + نمونه از رنج‌های Cloudflare،
//    تست TCP روی 443، نگه‌داشتن سریع‌ترین‌ها؛ برای سرورهای پشت Cloudflare
//    به‌جای آدرس دامنه از این IP ها استفاده می‌شود (SNI/Host همان دامنه می‌ماند).
// 3) Fragment / Mux / DNS امن: تغییر واقعی روی JSON هسته (فقط اتصال واقعی،
//    تست‌ها دست‌نخورده می‌مانند).
// ===========================================================================

// ---------------------------- تنظیمات (ذخیره در settings) ----------------------------
bool npvParse = true; // خواندن کانفیگ‌های غیراستاندارد
bool cleanIpMode = true; // IP تمیز برای سرورهای Cloudflare
bool fragEnabled = false; // Fragment روی TLS Hello (نیاز به هسته‌ی Xray)
bool muxEnabled = false; // Mux روی خروجی اصلی
bool secureDns = true; // DNS از طریق DoH
bool blockQuic = true; // مسدود کردن QUIC (UDP 443) تا مرورگرها به TCP/TLS برگردند
bool lanDirect = true; // شبکه‌ی محلی (LAN) از تونل رد نشود
bool routeOnly = false; // دامنه‌ی sniff شده فقط برای مسیریابی، مقصد IP دست‌نخورده
String fragLen = '100-200'; // طول تکه‌های Fragment
String fragInt = '10-20'; // فاصله‌ی تکه‌ها (میلی‌ثانیه)
int muxConc = 8; // تعداد اتصال همزمان Mux
String dnsProv = 'cloudflare'; // ارائه‌دهنده‌ی DoH: cloudflare | google | quad9
const _fragLenOpts = <String>['100-200', '50-100', '10-30'];
const _fragIntOpts = <String>['10-20', '1-5', '20-40'];
const _muxOpts = <int>[4, 8, 16];
const _dnsOpts = <String>['cloudflare', 'google', 'quad9'];
const _dnsUrls = <String, List<String>>{
  'cloudflare': ['https://1.1.1.1/dns-query', '1.1.1.1'],
  'google': ['https://8.8.8.8/dns-query', '8.8.8.8'],
  'quad9': ['https://9.9.9.9/dns-query', '9.9.9.9'],
};
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
  'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/vless_configs.txt',
  'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/vmess_configs.txt',
  'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/trojan_configs.txt',
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
  } catch (_) {
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
    } catch (_) {}
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
    } catch (_) {}
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
    } catch (_) {}
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
        : ((tag.isEmpty || tag == 'proxy') ? 'NPV' : tag);
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
      final u = (vn['users'] as List).first as Map;
      final addr = vn['address'].toString();
      final port = int.parse(vn['port'].toString());
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
    final addr = sv['address'].toString();
    final port = int.parse(sv['port'].toString());
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
  } catch (_) {
    return null;
  }
}

// =========================== 2) IP تمیز (سبک AM) ===========================
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
  for (final c in _cfRanges) {
    set.addAll(_cidrSample(c, 14, r).where(_cleanOk));
  }
  final l = set.toList()..shuffle(r);
  return l.take(180).toList();
}

// TLS واقعی روی 443 + بررسی اینکه جواب از Cloudflare است (فقط باز بودن پورت کافی نیست)
Future<int?> _cfProbeMs(String ip, Duration t) async {
  final sw = Stopwatch()..start();
  SecureSocket? k;
  try {
    k = await SecureSocket.connect(ip, 443,
        timeout: t,
        onBadCertificate: (_) => true,
        supportedProtocols: ['http/1.1']);
    k.write(
        'GET /cdn-cgi/trace HTTP/1.1\r\nHost: cloudflare.com\r\nConnection: close\r\n\r\n');
    await k.flush();
    final data = <int>[];
    await for (final c in k.timeout(t, onTimeout: (sink) => sink.close())) {
      data.addAll(c);
      if (data.length > 1500) break;
    }
    sw.stop();
    final txt = utf8.decode(data, allowMalformed: true).toLowerCase();
    return txt.contains('cloudflare') ? sw.elapsedMilliseconds : null;
  } catch (_) {
    return null;
  } finally {
    k?.destroy();
  }
}

Future<void> _doRefreshClean() async {
  try {
    cleanIpStatus = 'در حال جمع‌آوری IP...';
    final c = await _cleanCandidates();
    final res = <CleanIp>[];
    await pool<String>(c, 40, (ip) async {
      final ms = await _cfProbeMs(ip, const Duration(milliseconds: 3000));
      if (ms != null) res.add(CleanIp(ip, ms));
