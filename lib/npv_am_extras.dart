part of 'main.dart';

// NPVAMPATCH ===============================================================
// بخش‌های مشترک V2Ray برای King-vpn: خواندن لینک، IP تمیز، Fragment / Mux / DNS
// ===========================================================================

bool npvParse = true;
String relayServerUrl = ''; // RELAY: لینک سرور واسط (Multi-hop)
bool cleanIpMode = true;
bool fragEnabled = false;
bool muxEnabled = false; // off by default: enable only when a server is verified compatible
bool secureDns = true;
bool blockQuic = true;
bool lanDirect = true;
bool routeOnly = false;
String fragLen = '100-200';
String fragInt = '10-20';
int muxConc = 32; // default Mux concurrency = 32 (۱۲۸ باعث HOL blocking می‌شد)
String dnsProv = 'auto';
String dnsProvActive = 'cloudflare';
DateTime? _dnsPickAt;
String? _dnsPickNetworkKey;

Future<String> _dnsNetworkKey() async {
  try {
    final interfaces = await NetworkInterface.list(includeLoopback: false);
    final rows = <String>[];
    for (final iface in interfaces) {
      final ips = iface.addresses.map((a) => a.address).toList()..sort();
      if (ips.isNotEmpty) rows.add('${iface.name}:${ips.join(',')}');
    }
    rows.sort();
    return '${nationalMode ? 'nat' : 'global'}|${rows.join('|')}';
  } catch (_) {
    return '${nationalMode ? 'nat' : 'global'}|unknown';
  }
}
const _fragLenOpts = <String>['100-200', '50-100', '10-30'];
const _fragIntOpts = <String>['10-20', '1-5', '20-40'];
const _muxOpts = <int>[4, 8, 16, 32, 64, 128];
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
  'custom',
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

String effectiveDnsProv() =>
    dnsProv == 'auto' ? dnsProvActive : dnsProv;

String customDnsAddr = '';

List<String>? customDnsList() {
  if (effectiveDnsProv() != 'custom') return null;
  final a = customDnsAddr.trim();
  final parsedIp = InternetAddress.tryParse(a);
  final ipOk = parsedIp != null && parsedIp.type == InternetAddressType.IPv4;
  if (a.startsWith('https://') || ipOk) return [a];
  return null;
}

Future<int?> _probeDoh(String url, {String expectedDomain = 'google.com'}) async {
  final sw = Stopwatch()..start();
  final cl = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final req = await cl.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 2));
    req.headers.set('accept', 'application/dns-json');
    final res = await req.close().timeout(const Duration(seconds: 2));
    if (res.statusCode != 200) {
      await res.drain().timeout(const Duration(seconds: 2));
      return null;
    }
    final body = await utf8.decoder.bind(res).join().timeout(const Duration(seconds: 2));
    final decoded = jsonDecode(body);
    if (decoded is! Map || (decoded['Status'] as num?)?.toInt() != 0) return null;
    final question = decoded['Question'];
    if (question is! List || !question.any((q) => q is Map &&
        (q['name']?.toString().toLowerCase() == expectedDomain.toLowerCase() ||
         q['name']?.toString().toLowerCase() == '${expectedDomain.toLowerCase()}.') &&
        (q['type'] as num?)?.toInt() == 1)) return null;
    final answers = decoded['Answer'];
    if (answers is! List) return null;
    final valid = answers.any((a) {
      if (a is! Map || (a['type'] as num?)?.toInt() != 1) return false;
      final ip = InternetAddress.tryParse(a['data']?.toString() ?? '');
      if (ip == null || ip.type != InternetAddressType.IPv4) return false;
      final octets = ip.rawAddress;
      return NatDnsWireProbe.publicV4(octets, 0);
    });
    return valid ? sw.elapsedMilliseconds : null;
  } catch (e, stk) {
    logError(e, stk);
    return null;
  } finally {
    cl.close(force: true);
  }
}

Future<int?> _probeDnsIp(String ip) async {
  final domain = nationalMode ? 'nic.ir' : 'google.com';
  final result = await NatDnsWireProbe.probe(
    ip,
    domain,
    timeout: const Duration(seconds: 2),
  );
  return result.ok ? result.elapsedMs : null;
}

Future<String> pickBestDns({bool force = false}) async {
  if (dnsProv != 'auto') {
    dnsProvActive = dnsProv;
    return dnsProv;
  }
  final networkKey = await _dnsNetworkKey();
  if (_dnsPickNetworkKey != networkKey) {
    _dnsPickAt = null;
    _dnsPickNetworkKey = networkKey;
  }
  if (!force &&
      _dnsPickAt != null &&
      DateTime.now().difference(_dnsPickAt!) < const Duration(minutes: 10)) {
    return dnsProvActive;
  }

  const dohProbes = <String, String>{
    'cloudflare': 'https://1.1.1.1/dns-query?name=google.com&type=A',
    'google': 'https://8.8.8.8/resolve?name=google.com&type=A',
    'quad9': 'https://9.9.9.9:5053/dns-query?name=google.com&type=A',
    'adguard':
        'https://94.140.14.14/dns-query?name=google.com&type=A',
  };
  const ipProbes = <String, String>{
    'opendns': '208.67.222.222',
    'shecan': '178.22.122.100',
    'electro': '78.157.42.100',
    'radar': '10.202.10.10',
  };

  String best = dnsProvActive.isNotEmpty ? dnsProvActive : 'cloudflare';
  var bestMs = 1 << 30;
  var foundValidResolver = false;
  // During a domestic-only outage do not spend the first DNS-selection window
  // on global DoH endpoints. Probe only domestic resolvers with a real .ir query.
  final selectedDohProbes = nationalMode
      ? const <String, String>{}
      : dohProbes;
  final selectedIpProbes = nationalMode
      ? const <String, String>{
          'shecan': '178.22.122.100',
          'electro': '78.157.42.100',
          'radar': '10.202.10.10',
        }
      : ipProbes;

  await Future.wait([
    ...selectedDohProbes.entries.map((e) async {
      final ms = await _probeDoh(e.value, expectedDomain: 'google.com');
      if (ms != null && ms < bestMs) {
        bestMs = ms;
        best = e.key;
        foundValidResolver = true;
      }
    }),
    ...selectedIpProbes.entries.map((e) async {
      final ms = await _probeDnsIp(e.value);
      if (ms != null && ms < bestMs) {
        bestMs = ms;
        best = e.key;
        foundValidResolver = true;
      }
    }),
  ]);

  if (foundValidResolver) dnsProvActive = best;
  else dbg('DNS auto: no resolver returned a validated answer; keeping previous provider=$dnsProvActive');
  _dnsPickNetworkKey = networkKey;
  _dnsPickAt = DateTime.now();
  return dnsProvActive;
}

const _lanCidrs = <String>[
  '10.0.0.0/8',
  '172.16.0.0/12',
  '192.168.0.0/16',
  '127.0.0.0/8',
  '169.254.0.0/16',
];
bool iranMore = true;

final List<String> _npvUrls = [
  'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/vless_configs.txt',
  'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/vmess_configs.txt',
  'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/trojan_configs.txt',
  'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/ss_configs.txt',
  'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/all_extracted_configs.txt',
  'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/V2Ray-Config-By-EbraSha-All-Type.txt',
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
  'https://raw.githubusercontent.com/3inker/v2ray-subscription/main/subs/all_not_ru.txt',
  'https://raw.githubusercontent.com/3inker/v2ray-subscription/main/subs/all_ru.txt',
  'https://raw.githubusercontent.com/free-nodes/v2rayfree/main/sub',
  'https://raw.githubusercontent.com/ermaozi/get_subscribe/main/subscribe/v2ray.txt',
  'https://raw.githubusercontent.com/Au1rxx/free-vpn-subscriptions/main/output/v2ray-base64.txt',
];

final RegExp _zeroWidth =
    RegExp('[\u200B-\u200F\u202A-\u202E\u2060\uFEFF]');
final RegExp _pctScheme =
    RegExp(r'^(vmess|vless|trojan|ss)%3a%2f%2f', caseSensitive: false);
final RegExp _anyScheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]{1,12})://(.+)$');
final RegExp _b64Body = RegExp(r'^[A-Za-z0-9+/_\-=\s]+$');

String npvClean(String s) {
  if (!npvParse) return s;
  var t = s.replaceAll(_zeroWidth, '').trim();
  if (t.contains('&amp;')) t = t.replaceAll('&amp;', '&');
  if (t.contains(r'\/')) t = t.replaceAll(r'\/', '/');
  if (t.contains('%3') || t.contains('%3A')) {
    final m = _pctScheme.firstMatch(t);
    if (m != null) t = '${m.group(1)}://${t.substring(m.end)}';
  }
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
    } catch (e, st) { logError(e, st); }
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

List<String> npvSplit(String text) {
  final plain = text.split(RegExp(r'[\r\n]+'));
  if (!npvParse) return plain;
  final out = <String>[];
  final t = text.replaceAll(_zeroWidth, '').trim();
  if (t.isEmpty) return out;
  if (t.startsWith('{') || t.startsWith('[')) {
    try {
      out.addAll(npvJsonToLinks(jsonDecode(t)));
      if (out.isNotEmpty) return out;
    } catch (e, stk) { logError(e, stk); }
  }
  if (!t.contains('://') && _b64Body.hasMatch(t)) {
    final d = _b64Text(t);
    if (d != null && d.contains('://')) return npvSplit(d);
  }
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
      final vnl = settings['vnext'];
      // SAFE: آرایه‌ی خالی از یک منبع خارجی نباید با first استثنا بیندازد
      final vn = (vnl is List && vnl.isNotEmpty && vnl.first is Map) ? vnl.first as Map : null;
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
    final svl = settings['servers'];
    final sv = (svl is List && svl.isNotEmpty && svl.first is Map) ? svl.first as Map : null;
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
    final ui = base64
        .encode(utf8.encode('${sv['method']}:${sv['password']}'))
        .replaceAll('=', '');
    return 'ss://$ui@$addr:$port#${Uri.encodeComponent(name)}';
  } catch (e, stk) {
    logError(e, stk);
    return null;
  }
}

class CleanIp {
  final String ip;
  final int ms;
  final int port;
  CleanIp(this.ip, this.ms, [this.port = 443]);
}

List<CleanIp> cleanIps = [];
DateTime? cleanIpsAt;
String cleanIpStatus = '';
Future<void>? _cleanBusy;
bool _cleanLoaded = false;
String _cleanOp = '';
int _cleanRot = 0;

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

// CDNDIV: Fastly's published anycast ranges — a second CDN pool so a
// block of Cloudflare's ranges doesn't take out all CDN-fronted servers.
const _fastlyRanges = <String>[
  '151.101.0.0/16',
  '199.232.0.0/16',
  '23.235.32.0/20',
  '43.249.72.0/22',
  '103.244.50.0/24',
  '104.156.80.0/20',
  '140.248.64.0/18',
  '146.75.0.0/17',
];

// CDNDIV: Amazon CloudFront's published edge ranges (subset of
// ip-ranges.amazonaws.com filtered to the CLOUDFRONT service).
const _awsCfRanges = <String>[
  '13.32.0.0/15',
  '13.224.0.0/14',
  '52.84.0.0/15',
  '54.182.0.0/16',
  '54.192.0.0/16',
  '54.230.0.0/16',
  '54.239.128.0/18',
  '204.246.164.0/22',
  '205.251.192.0/19',
];

// CDNDIV: Google's published edge/anycast ranges used by Google Cloud
// CDN / Google Front (subset of goog.json).
const _gcpCdnRanges = <String>[
  '34.96.0.0/20',
  '34.104.0.0/20',
  '142.250.0.0/15',
  '172.217.0.0/16',
  '172.253.0.0/16',
  '108.177.0.0/17',
];

// CDNDIV: static multi-CDN pool used as the safe fallback (and initial
// value) whenever the live range fetch below has not run yet or fails.
const _allCdnRanges = <String>[
  ..._cfRanges,
  ..._fastlyRanges,
  ..._awsCfRanges,
  ..._gcpCdnRanges,
];

// CDNDIV: the pool actually used for national-mode CDN-IP scanning.
// Starts as the static multi-CDN list above; refreshCdnRanges() below
// swaps it for a live-fetched version when one succeeds, so a change on
// any single CDN's side never has to wait for an app update.
List<String> _liveCdnRanges = List<String>.of(_allCdnRanges);
DateTime? _cdnRangesFetchedAt;
DateTime? _cdnRangesTriedAt;
bool _cdnRangesBusy = false;

// PERFFIX: decoding the multi-MB AWS/Google JSON on the UI isolate froze the app.
// این تابع سراسری است تا compute() بتواند آن را در isolate پس‌زمینه اجرا کند.
dynamic cdnJsonDecodeBg(String body) => jsonDecode(body);

// CDNDIV: pulls each CDN's own published range list and merges whatever
// succeeds into _liveCdnRanges. Safe to call repeatedly (it no-ops while
// already running, and keeps the previous working list on any failure).
Future<void> refreshCdnRanges() async {
  if (_cdnRangesBusy) return;
  final last = _cdnRangesFetchedAt;
  if (last != null && DateTime.now().difference(last) < const Duration(hours: 6)) return;
  // اگر آخرین تلاش ناموفق بود، تا ۱۰ دقیقه دوباره تلاش نکن (نت ملی = endpoint ها بسته)
  final tried = _cdnRangesTriedAt;
  if (tried != null && DateTime.now().difference(tried) < const Duration(minutes: 10)) return;
  _cdnRangesTriedAt = DateTime.now();
  _cdnRangesBusy = true;
  try {
    final merged = <String>{};
    var liveOk = 0;
    // هر CDN جدا: اگر دریافتش شکست خورد، لیست استاتیک خودش جایگزین می‌شود
    // (قبلاً فقط CDNهای موفق می‌ماندند و بقیه از استخر حذف می‌شدند).
    Future<void> pull(String label, List<String> fallback, int cap,
        Future<List<String>> Function() fetch) async {
      var got = const <String>[];
      try {
        got = await fetch().timeout(const Duration(seconds: 8));
      } catch (e, stk) {
        logError(e, stk);
      }
      if (got.length < 3) {
        merged.addAll(fallback);
        return;
      }
      // رنج‌های استاتیک همیشه می‌مانند؛ رنج‌های زنده تا سقف cap اضافه می‌شوند
      merged.addAll(fallback);
      merged.addAll(got.take(cap));
      liveOk++;
    }

    await pull('cloudflare', _cfRanges, 64, () async {
      final res = await http.get(Uri.parse('https://www.cloudflare.com/ips-v4'));
      if (res.statusCode != 200) return const <String>[];
      return res.body
          .split(RegExp(r'[\r\n]+'))
          .map((e) => e.trim())
          .where((e) => e.contains('/'))
          .toList();
    });

    await pull('fastly', _fastlyRanges, 48, () async {
      final res = await http.get(Uri.parse('https://api.fastly.com/public-ip-list'));
      if (res.statusCode != 200) return const <String>[];
      final j = await compute(cdnJsonDecodeBg, res.body);
      final addrs = j is Map ? j['addresses'] : null;
      if (addrs is! List) return const <String>[];
      return addrs.whereType<String>().toList();
    });

    await pull('aws-cloudfront', _awsCfRanges, 96, () async {
      final res = await http.get(Uri.parse('https://ip-ranges.amazonaws.com/ip-ranges.json'));
      if (res.statusCode != 200) return const <String>[];
      final j = await compute(cdnJsonDecodeBg, res.body);
      final list = j is Map ? j['prefixes'] : null;
      if (list is! List) return const <String>[];
      return list
          .whereType<Map>()
          .where((p) => p['service'] == 'CLOUDFRONT')
          .map((p) => (p['ip_prefix'] ?? '').toString())
          .where((s) => s.contains('/'))
          .toList();
    });

    await pull('google', _gcpCdnRanges, 48, () async {
      final res = await http.get(Uri.parse('https://www.gstatic.com/ipranges/goog.json'));
      if (res.statusCode != 200) return const <String>[];
      final j = await compute(cdnJsonDecodeBg, res.body);
      final list = j is Map ? j['prefixes'] : null;
      if (list is! List) return const <String>[];
      return list
          .whereType<Map>()
          .map((p) => (p['ipv4Prefix'] ?? '').toString())
          .where((s) => s.contains('/'))
          .toList();
    });

    if (merged.length >= 10) {
      _liveCdnRanges = merged.toList();
      if (liveOk > 0) _cdnRangesFetchedAt = DateTime.now();
      dbg('CDNDIV: live CDN ranges refreshed (${_liveCdnRanges.length} blocks)');
    }
  } catch (e, stk) {
    logError(e, stk);
  } finally {
    _cdnRangesBusy = false;
  }
}

// ECH: Encrypted Client Hello (اختیاری). فقط وقتی لینک پارامتر `ech=` داشته باشد
// (و security=tls باشد، نه reality) به tlsSettings همان outbound اضافه می‌شود:
//   ech=<ECHConfigList بیس۶۴>  یا  ech=example.com+udp://1.1.1.1  (جستجوی DNS)
// بدون پارامتر ech، کانفیگ دقیقاً همان قبلی برمی‌گردد. هر خطایی => کانفیگ بدون تغییر.
String echFromLink(String link) {
  try {
    final low = link.trim().toLowerCase();
    if (low.startsWith('vless://') ||
        low.startsWith('trojan://') ||
        low.startsWith('ss://')) {
      final u = Uri.tryParse(link.trim());
      return (u?.queryParameters['ech'] ?? '').replaceAll(' ', '+').trim();
    } else if (low.startsWith('vmess://')) {
      var b = link.trim().substring(8).split('#').first;
      b = b.replaceAll('-', '+').replaceAll('_', '/');
      while (b.length % 4 != 0) {
        b += '=';
      }
      final m = jsonDecode(utf8.decode(base64.decode(b)));
      if (m is Map) return (m['ech'] ?? '').toString().trim();
    }
  } catch (e, st) {
    logError(e, st);
  }
  return '';
}

// ECH فعال است ⇒ serverName داخلی (SNI واقعی) است و نباید توسط سوییچ‌های
// SNI نت ملی (cdnjs و ...) عوض شود، وگرنه هندشیک ECH خراب می‌شود.
bool tlsHasEch(Map tls) => (tls['echConfigList'] ?? '').toString().isNotEmpty;

String echApply(String link, String cfg) {
  try {
    final ech = echFromLink(link);
    if (ech.isEmpty) return cfg;
    final j = jsonDecode(cfg);
    if (j is! Map) return cfg;
    final outs = j['outbounds'] ?? j['outbound'];
    if (outs is! List) return cfg;
    var changed = false;
    for (final o in outs) {
      if (o is! Map) continue;
      final st = o['streamSettings'];
      if (st is! Map || st['security'] != 'tls') continue;
      final tls = st['tlsSettings'];
      if (tls is! Map) continue;
      tls['echConfigList'] = ech;
      changed = true;
      break; // فقط outbound اصلی پروکسی (اولین outbound با TLS)
    }
    if (changed) dbg('ECH: echConfigList روی کانفیگ اعمال شد');
    return changed ? jsonEncode(j) : cfg;
  } catch (e, stk) {
    logError(e, stk);
    return cfg;
  }
}

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
  var ranges = List<String>.of(_cfRanges);
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
  return l;
}

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

bool isValidCloudflareTraceResponse(String response) {
  final headerEnd = response.indexOf('\r\n\r\n');
  if (headerEnd < 0) return false;
  final headers = response.substring(0, headerEnd);
  final lines = headers.split('\r\n');
  if (lines.isEmpty ||
      !RegExp(r'^HTTP/1\.[01] 200(?:\s|$)').hasMatch(lines.first)) {
    return false;
  }
  final normalizedHeaders = headers.toLowerCase();
  if (!normalizedHeaders.contains('server: cloudflare') ||
      !normalizedHeaders.contains('cf-ray:')) {
    return false;
  }
  final body = response.substring(headerEnd + 4);
  final bodyLines = body.split(RegExp(r'\r?\n'));
  bool hasField(String name) =>
      bodyLines.any((line) => line.toLowerCase().startsWith('$name='));
  return hasField('ip') && hasField('colo') && hasField('http');
}

Future<int?> _cfProbeMs(String ip, Duration t) async {
  final sw = Stopwatch()..start();
  Socket? raw;
  Socket? secure;
  try {
    raw = await Socket.connect(ip, 443, timeout: t);
    secure = await SecureSocket.secure(
      raw,
      host: 'cloudflare.com',
      supportedProtocols: const ['http/1.1'],
    ).timeout(t);
    secure.write(
        'GET /cdn-cgi/trace HTTP/1.1\r\nHost: cloudflare.com\r\nConnection: close\r\n\r\n');
    await secure.flush();
    final response = await _cfRead(secure, t);
    sw.stop();
    if (isValidCloudflareTraceResponse(response)) {
      return sw.elapsedMilliseconds;
    }
  } catch (e, stk) {
    logError(e, stk);
  } finally {
    secure?.destroy();
    raw?.destroy();
  }
  // Plain HTTP/80 is deliberately not accepted as proof of a Cloudflare IP:
  // an unrelated server can spoof the trace text without a validated TLS peer.
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
    await pool<String>(c, 20, (ip) async {
      final ms = await _cfProbeMs(ip, const Duration(milliseconds: 3500));
      done++;
      if (ms != null) res.add(CleanIp(ip, ms));
      if (done % 5 == 0) {
        cleanIpStatus = 'در حال تست... $done از ${c.length} • ${res.length} سالم';
        cleanTick.value++;
      }
      await Future.delayed(const Duration(milliseconds: 20));
    });
    res.sort((a, b) => a.ms.compareTo(b.ms));
    cleanIps = res.toList(growable: false);
    cleanIpsAt = DateTime.now();
    cleanIpStatus = '${cleanIps.length} IP سالم از ${c.length} تست';
    await _saveCleanIps();
    await goldMergeIps(res);
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
        'cip_list_$natOpKey', jsonEncode(cleanIps.map((e) => [e.ip, e.ms, e.port]).toList()));
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
      return CleanIp(x[0].toString(), (x[1] as num).toInt(),
          x.length > 2 ? (x[2] as num).toInt() : 443);
    }).toList();
    final at = p.getInt('cip_at_$natOpKey');
    if (at != null) cleanIpsAt = DateTime.fromMillisecondsSinceEpoch(at);
  } catch (e, stk) {
    logError(e, stk);
  }
}

Future<String?> pickCleanIp() async {
  if (nationalMode) {
    await natNationalIpMemLoad();
    if (natNationalIpMem.isEmpty) return null;
    final index = _cleanRot++ % natNationalIpMem.length;
    return (natNationalIpMem[index]['ip'] ?? '').toString();
  }
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
      DateTime.now().difference(cleanIpsAt!) > const Duration(hours: 12);
  if (cleanIps.isEmpty || stale) {
    await refreshCleanIps();
  }
  if (cleanIps.isEmpty) return null;
  return cleanIps[_cleanRot++ % cleanIps.length].ip;
}

Future<void> manualRangeScan(BuildContext context, List<String> userAddrs) async {
  // FOLDERHELP: IPهای تمیز پوشه اول تست می‌شوند (کمک پوشه به اسکن بازه، در نت ملی و عادی)
  await goldLoad();
  // RANGEFIX: بازه‌ی کاربر اول می‌آید تا با سقف زمان کوتاه هرگز کنار گذاشته نشود
  // RANGEFIX: بازه‌ی کاربر اول و با ترتیب تصادفی (تا بازه‌ی بزرگ در سقف زمان کل بازه را پوشش دهد)
  final shuffledUser = List<String>.of(userAddrs)..shuffle(Random());
  final addrs = {...shuffledUser, for (final c in goldIpList()) c.ip}.toList();
  var cancelled = false;
  var finished = false;
  var done = 0;
  var hitsCount = 0;
  var total = addrs.length;
  var result = <NatIpHit>[];
  var open = true;
  StateSetter? setS;

  void upd(VoidCallback f) {
    if (open && setS != null) setS!(f);
  }

  // ignore: unawaited_futures
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx2, ss) {
      setS = ss;
      return AlertDialog(
        title: Text(finished ? 'نتیجه‌ی اسکن بازه' : 'در حال اسکن بازه...'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('آدرس‌ها: $done / $total   •   IP سالم: $hitsCount'),
              if (!finished) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(),
              ],
              if (finished && result.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text('هیچ IP سالمی پیدا نشد.'),
                ),
              if (finished && result.isNotEmpty)
                TextButton.icon(
                  onPressed: () => Clipboard.setData(ClipboardData(
                      text: result.map((h) => '${h.ip}:443').join('\n'))),
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text('کپی ${result.length} IP'),
                ),
              if (finished && result.isNotEmpty)
                SizedBox(
                  height: 260,
                  child: ListView(
                    children: [
                      for (final h in result)
                        Text('${h.ms} ms  •  ${h.ip}:443',
                            style: const TextStyle(
                                fontSize: 12, fontFamily: 'monospace')),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (!finished)
            TextButton(
              onPressed: () => cancelled = true,
              child: const Text('توقف'),
            ),
          if (finished && result.isNotEmpty)
            TextButton(
              onPressed: () async {
                final t = result.map((h) => '${h.ip}:443').join('\n');
                await Clipboard.setData(ClipboardData(text: t));
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('${result.length} IP کپی شد')));
                }
              },
              child: const Text('کپی IPها'),
            ),
          TextButton(
            onPressed: () {
              cancelled = true;
              Navigator.pop(ctx);
            },
            child: const Text('بستن'),
          ),
        ],
      );
    }),
  ).then((_) {
    open = false;
    cancelled = true;
  });

  try {
    if (nationalMode) {
      await natManualYield(shouldAbort: () => cancelled || !open);
    }
    // Do not start a scan if the user cancelled while waiting for the national scan.
    if (!cancelled) {
      result = await natScanIps(
        addrs,
        concurrency: nationalMode ? kNatManualConc : natAdaptiveWorkers(),
        // RANGEFIX: بازه‌ی کوچک ۲ دقیقه؛ بازه‌ی بزرگ (بیش از ۴۰۹۶ IP) ۸ دقیقه
        timeout: const Duration(milliseconds: 1500),
        cancelled: () => cancelled || !open,
        onProgress: (d, t, h) => upd(() {
          done = d;
          total = t;
          hitsCount = h;
        }),
      );
      // Partial results remain visible, but a cancelled scan must not enter shared storage.
      if (!cancelled && open) {
        await goldMergeIps(
          [for (final h in result) CleanIp(h.ip, h.ms, 443)],
          shouldAbort: () => cancelled || !open,
        );
      }
    }
  } catch (e, stk) {
    logError(e, stk);
  }
  upd(() {
    finished = true;
    hitsCount = result.length;
  });
}
