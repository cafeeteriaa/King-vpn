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
  final ipOk = parsedIp != null &&
      (parsedIp.type == InternetAddressType.IPv4 ||
          parsedIp.type == InternetAddressType.IPv6);
  if (a.startsWith('https://') || ipOk) return [a];
  return null;
}

Future<int?> _probeDoh(String url, {String expectedDomain = 'google.com'}) async {
  final sw = Stopwatch()..start();
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final base = Uri.parse(url);
    for (final recordType in const [1, 28]) {
      final query = Map<String, String>.of(base.queryParameters)
        ..['name'] = expectedDomain
        ..['type'] = recordType == 1 ? 'A' : 'AAAA';
      final request = await client.getUrl(base.replace(queryParameters: query))
          .timeout(const Duration(seconds: 2));
      request.headers.set('accept', 'application/dns-json');
      final response = await request.close().timeout(const Duration(seconds: 2));
      if (response.statusCode != 200) {
        await response.drain().timeout(const Duration(seconds: 2));
        continue;
      }
      final body = await utf8.decoder.bind(response).join()
          .timeout(const Duration(seconds: 2));
      final decoded = jsonDecode(body);
      if (decoded is! Map || (decoded['Status'] as num?)?.toInt() != 0) continue;
      final question = decoded['Question'];
      if (question is! List || !question.any((q) => q is Map &&
          (q['name']?.toString().toLowerCase() == expectedDomain.toLowerCase() ||
           q['name']?.toString().toLowerCase() == '${expectedDomain.toLowerCase()}.') &&
          (q['type'] as num?)?.toInt() == recordType)) continue;
      final answers = decoded['Answer'];
      if (answers is! List) continue;
      final valid = answers.any((answer) {
        if (answer is! Map ||
            (answer['type'] as num?)?.toInt() != recordType) return false;
        final address = InternetAddress.tryParse(answer['data']?.toString() ?? '');
        if (address == null) return false;
        if (recordType == 1) {
          return address.type == InternetAddressType.IPv4 &&
              NatDnsWireProbe.publicV4(address.rawAddress, 0);
        }
        return address.type == InternetAddressType.IPv6 &&
            NatDnsWireProbe.publicV6(address.rawAddress, 0);
      });
      if (valid) return sw.elapsedMilliseconds;
    }
    return null;
  } catch (e, stk) {
    logError(e, stk);
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<int?> _probeDnsIp(String ip) async {
  final domain = nationalMode ? 'nic.ir' : 'google.com';
  final results = await Future.wait([
    NatDnsWireProbe.probe(ip, domain,
        timeout: const Duration(seconds: 2), recordType: 1),
    NatDnsWireProbe.probe(ip, domain,
        timeout: const Duration(seconds: 2), recordType: 28),
  ]);
  final successful = results.where((result) => result.ok).toList();
  if (successful.isEmpty) return null;
  return successful.map((result) => result.elapsedMs!).reduce(min);
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

// Cloudflare's published IPv6 anycast ranges (refreshed live below).
const _cfRangesV6 = <String>[
  '2400:cb00::/32', '2606:4700::/32', '2803:f800::/32',
  '2405:b500::/32', '2405:8100::/32', '2a06:98c0::/29',
  '2c0f:f248::/32',
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
  ..._cfRangesV6,
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
    Future<void> pull(String label, List<String> fallback,
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
      // Keep the complete live prefix inventory for both address families.
      // Batch sizing belongs to the cursor-based scanner, not source ingestion.
      merged.addAll(fallback);
      merged.addAll(got);
      liveOk++;
    }

    await pull('cloudflare', [..._cfRanges, ..._cfRangesV6], () async {
      final responses = await Future.wait([
        http.get(Uri.parse('https://www.cloudflare.com/ips-v4')),
        http.get(Uri.parse('https://www.cloudflare.com/ips-v6')),
      ]);
      return responses
          .where((response) => response.statusCode == 200)
          .expand((response) => response.body
              .split(RegExp(r'[\r\n]+'))
              .map((entry) => entry.trim())
              .where((entry) => entry.contains('/')))
          .toList();
    });

    await pull('fastly', _fastlyRanges, () async {
      final res = await http.get(Uri.parse('https://api.fastly.com/public-ip-list'));
      if (res.statusCode != 200) return const <String>[];
      final j = await compute(cdnJsonDecodeBg, res.body);
      if (j is! Map) return const <String>[];
      final ipv4 = j['addresses'];
      final ipv6 = j['ipv6_addresses'];
      return <String>[
        if (ipv4 is List) ...ipv4.whereType<String>(),
        if (ipv6 is List) ...ipv6.whereType<String>(),
      ];
    });

    await pull('aws-cloudfront', _awsCfRanges, () async {
      final res = await http.get(Uri.parse('https://ip-ranges.amazonaws.com/ip-ranges.json'));
      if (res.statusCode != 200) return const <String>[];
      final decoded = await compute(cdnJsonDecodeBg, res.body);
      if (decoded is! Map) return const <String>[];
      final ipv4 = decoded['prefixes'];
      final ipv6 = decoded['ipv6_prefixes'];
      return <String>[
        if (ipv4 is List)
          ...ipv4
              .whereType<Map>()
              .where((entry) => entry['service'] == 'CLOUDFRONT')
              .map((entry) => (entry['ip_prefix'] ?? '').toString())
              .where((range) => range.contains('/')),
        if (ipv6 is List)
          ...ipv6
              .whereType<Map>()
              .where((entry) => entry['service'] == 'CLOUDFRONT')
              .map((entry) => (entry['ipv6_prefix'] ?? '').toString())
              .where((range) => range.contains('/')),
      ];
    });

    await pull('google', _gcpCdnRanges, () async {
      final res = await http.get(Uri.parse('https://www.gstatic.com/ipranges/goog.json'));
      if (res.statusCode != 200) return const <String>[];
      final j = await compute(cdnJsonDecodeBg, res.body);
      final list = j is Map ? j['prefixes'] : null;
      if (list is! List) return const <String>[];
      return list
          .whereType<Map>()
          .expand((p) => [
            (p['ipv4Prefix'] ?? '').toString(),
            (p['ipv6Prefix'] ?? '').toString(),
          ])
          .where((s) => s.contains('/'))
          .toList();
    });

    if (merged.length >= 10) {
      // Stable ordering is required because the outer range cursor is an index.
      _liveCdnRanges = merged.toList()..sort();
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
  final address = InternetAddress.tryParse(ip);
  if (address == null) return false;
  if (address.type == InternetAddressType.IPv4) {
    return !_privateIp(address) &&
        NatDnsWireProbe.publicV4(address.rawAddress, 0);
  }
  return address.type == InternetAddressType.IPv6 &&
      NatDnsWireProbe.publicV6(address.rawAddress, 0);
}

List<String> _cidrSample(String cidr, int n, Random random) {
  if (n <= 0) return const [];
  final parts = cidr.split('/');
  if (parts.length != 2) return const [];
  final address = InternetAddress.tryParse(parts[0].trim());
  final prefix = int.tryParse(parts[1]);
  if (address == null || prefix == null) return const [];
  final width = address.type == InternetAddressType.IPv4 ? 32 :
      (address.type == InternetAddressType.IPv6 ? 128 : 0);
  if (width == 0 || prefix < 0 || prefix > width) return const [];
  final bytes = address.rawAddress;
  var base = BigInt.zero;
  for (final byte in bytes) {
    base = (base << 8) | BigInt.from(byte);
  }
  final hostBits = width - prefix;
  final size = BigInt.one << hostBits;
  final mask = prefix == 0 ? BigInt.zero :
      ((BigInt.one << width) - BigInt.one) ^ (size - BigInt.one);
  base &= mask;
  final out = <String>{};
  for (var i = 0; i < n * 3 && out.length < n; i++) {
    var randomValue = BigInt.zero;
    for (var j = 0; j < bytes.length; j++) {
      randomValue = (randomValue << 8) |
          BigInt.from(random.nextInt(256));
    }
    final value = base + (randomValue % size);
    final raw = List<int>.filled(bytes.length, 0);
    var remaining = value;
    for (var j = raw.length - 1; j >= 0; j--) {
      raw[j] = (remaining & BigInt.from(255)).toInt();
      remaining >>= 8;
    }
    final candidate = InternetAddress.fromRawAddress(Uint8List.fromList(raw)).address;
    if (_cleanOk(candidate)) out.add(candidate);
  }
  return out.toList(growable: false);
}

const String _cleanRangeCursorKey = 'clean_ip_range_cursors_v1';
Map<String, dynamic> _cleanStagedRangeCursors = <String, dynamic>{};

Future<List<String>> _cleanCandidates() async {
  final ranges = <String>{..._cfRanges, ..._cfRangesV6};
  try {
    final responses = await Future.wait([
      http.get(Uri.parse('https://www.cloudflare.com/ips-v4'))
          .timeout(const Duration(seconds: 8)),
      http.get(Uri.parse('https://www.cloudflare.com/ips-v6'))
          .timeout(const Duration(seconds: 8)),
    ]);
    for (final response in responses) {
      if (response.statusCode == 200) {
        ranges.addAll(response.body
            .split(RegExp(r'[\r\n]+'))
            .map((entry) => entry.trim())
            .where((entry) => entry.contains('/')));
      }
    }
  } catch (e, stk) {
    logError(e, stk);
  }

  final orderedRanges = ranges.toList()..sort();
  final prefs = await SharedPreferences.getInstance();
  final cursors = <String, dynamic>{};
  final raw = prefs.getString(_cleanRangeCursorKey);
  if (raw != null && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          if (entry.value is String || entry.value is num) {
            cursors['${entry.key}'] = entry.value;
          }
        }
      }
    } catch (e, stk) {
      logError(e, stk);
    }
  }

  // The per-run batch is a resource slice, not a total candidate ceiling.
  // Every IPv4/IPv6 prefix keeps its 128-bit offset for the next refresh.
  const batchSize = 160;
  final out = <String>{};
  if (orderedRanges.isNotEmpty) {
    final start = natCursorIndex(cursors['__clean_range_cursor'], orderedRanges.length);
    var visited = 0;
    for (; visited < orderedRanges.length && out.length < batchSize; visited++) {
      final index = (start + visited) % orderedRanges.length;
      final range = orderedRanges[index];
      final remaining = batchSize - out.length;
      final rangesLeft = orderedRanges.length - visited;
      final quota = max(1, (remaining + rangesLeft - 1) ~/ rangesLeft);
      final expanded = natExpandIpRangeCursor(
        range,
        cursors[range]?.toString() ?? '0',
        maxPerBlock: quota,
      );
      if (expanded.addresses.isEmpty) continue;
      out.addAll(expanded.addresses);
      cursors[range] = expanded.nextCursor;
    }
    if (visited > 0) {
      cursors['__clean_range_cursor'] = (start + visited) % orderedRanges.length;
    }
  }
  if (out.isEmpty && orderedRanges.isNotEmpty) {
    // Single-address /32 and /128 entries are one-shot; begin a fresh sweep
    // after every entry is exhausted so they can be revalidated on later runs.
    for (final range in orderedRanges) {
      cursors[range] = '0';
    }
    cursors['__clean_range_cursor'] = '0';
    final first = orderedRanges.first;
    final expanded = natExpandIpRangeCursor(
      first,
      '0',
      maxPerBlock: batchSize,
    );
    out.addAll(expanded.addresses);
    cursors[first] = expanded.nextCursor;
  }
  _cleanStagedRangeCursors = cursors;
  final result = out.toList()..shuffle(Random());
  return result;
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

Future<int?> _cfProbeMs(String ip, Duration t) async {
  final sw = Stopwatch()..start();
  Socket? raw;
  Socket? k;
  try {
    raw = await Socket.connect(ip, 443, timeout: t);
    k = await SecureSocket.secure(raw,
            host: 'cloudflare.com',
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
    final candidates = await _cleanCandidates();
    final results = <CleanIp>[];
    final clock = Stopwatch()..start();
    const budget = Duration(seconds: 90);
    var next = 0;
    var done = 0;

    Future<void> worker() async {
      while (true) {
        if (clock.elapsed >= budget || next >= candidates.length) return;
        final ip = candidates[next++];
        final latency = await _cfProbeMs(
          ip,
          const Duration(milliseconds: 3500),
        );
        done++;
        if (latency != null) results.add(CleanIp(ip, latency));
        if (done % 5 == 0 || done == candidates.length) {
          cleanIpStatus =
              'در حال تست... $done از ${candidates.length} • ${results.length} سالم';
          cleanTick.value++;
        }
      }
    }

    final workers = min(20, candidates.length);
    await Future.wait(List.generate(workers, (_) => worker()));
    results.sort((a, b) => a.ms.compareTo(b.ms));
    cleanIps = results.toList();
    cleanIpsAt = DateTime.now();
    final complete = done >= candidates.length;
    cleanIpStatus = complete
        ? '${cleanIps.length} IP سالم از ${candidates.length} تست'
        : 'بسته ناقص: $done از ${candidates.length}؛ Cursor برای ادامه حفظ شد';
    await _saveCleanIps();
    await goldMergeIps(results);
    if (complete) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cleanRangeCursorKey,
        jsonEncode(_cleanStagedRangeCursors),
      );
    }
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
  if (!_cleanLoaded || _cleanOp != natOpKey) {
    _cleanLoaded = true;
    if (_cleanOp != natOpKey) {
      cleanIps = [];
      cleanIpsAt = null;
    }
    _cleanOp = natOpKey;
    await _loadCleanIps();
  }
  await goldLoad();
  if (nationalMode) {
    final g = goldIpList();
    if (g.isNotEmpty) {
      cleanIps = g;
      final n = min(5, cleanIps.length);
      return cleanIps[_cleanRot++ % n].ip;
    }
  }
  final stale = cleanIpsAt == null ||
      DateTime.now().difference(cleanIpsAt!) > const Duration(hours: 6);
  if (cleanIps.isEmpty) {
    await refreshCleanIps();
  } else if (stale) {
    refreshCleanIps();
  }
  if (cleanIps.isEmpty) return null;
  final n = min(5, cleanIps.length);
  return cleanIps[_cleanRot++ % n].ip;
}

const _iranMoreDomains = <String>[
  'domain:sheypoor.com',
  'domain:ninisite.com',
  'domain:zoodfood.com',
  'domain:bamilo.com',
  'domain:okala.com',
  'domain:varzesh3.com',
  'domain:tgju.org',
];

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
        if (ib is! Map) continue;
        final sniffing = ib['sniffing'] is Map
            ? Map<String, dynamic>.from(ib['sniffing'] as Map)
            : <String, dynamic>{};
        sniffing['enabled'] = true;
        sniffing['destOverride'] = sniffing['destOverride'] is List
            ? sniffing['destOverride']
            : <String>['http', 'tls'];
        sniffing['routeOnly'] = true;
        ib['sniffing'] = sniffing;
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
      // MUXWORKER: کلودفلر (workers.dev) mux را نمی‌پذیرد؛ برای آن mux خاموش است
      if (muxEnabled && (net == 'tcp' || net == 'ws') && !_isWorkerOutbound(proxy)) {
        var flow = '';
        try {
          final s = proxy['settings'] as Map;
          flow = ((s['vnext'] as List).first['users'] as List).first['flow']
                  ?.toString() ??
              '';
        } catch (e, stk) { logError(e, stk); }
        if (flow.isEmpty) {
          proxy['mux'] = {'enabled': true, 'concurrency': muxConc};
        }
      }
    }
    j['outbounds'] = outs;
    if (secureDns) {
      final d = j['dns'] is Map ? j['dns'] as Map : <String, dynamic>{};
      final first = nationalMode
          ? (_dnsUrls['shecan'] ?? _dnsUrls['electro']!)
          : (customDnsList() ?? _dnsUrls[effectiveDnsProv()] ?? _dnsUrls['cloudflare']!);
      final ips = <dynamic>[];
      final doh = <dynamic>[];
      void addResolver(String value) {
        if (value.startsWith('https://')) {
          if (!doh.contains(value)) doh.add(value);
        } else if (!ips.contains(value)) {
          ips.add(value);
        }
      }
      // National: Iranian resolvers first, imported/custom and global fallback later.
      for (final value in first) { addResolver(value.toString()); }
      final existingServers = d['servers'];
      if (existingServers is List) {
        for (final value in existingServers) { addResolver(value.toString()); }
      }
      for (final entry in _dnsUrls.entries) {
        for (final value in entry.value) { addResolver(value); }
      }
      d['servers'] = [...ips, ...doh];
      d['queryStrategy'] = 'UseIP';
      j['dns'] = d;
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
      sw('شبکه‌ی محلی (LAN) مستقیم', lanDirect, (v) { _markUserTouched(const ['lanDirect']); lanDirect = v; },
          sub: 'آدرس‌های ۱۰.x و ۱۷۲.۱۶.x و ۱۹۲.۱۶۸.x از تونل رد نمی‌شوند'),
      sw('RouteOnly برای تشخیص دامنه', routeOnly, (v) { _markUserTouched(const ['routeOnly']); routeOnly = v; },
          sub:
              'دامنه‌ی تشخیص‌داده‌شده فقط برای مسیریابی است و مقصد IP تغییر نمی‌کند؛ اگر برنامه‌ای خراب شد خاموشش کن'),
      sw('IP تمیز برای سرورهای Cloudflare', cleanIpMode, (v) {
        _markUserTouched(const ['cleanIpMode']);
        cleanIpMode = v;
        if (v) forceIpMode();
      },
          sub:
              'اپ خودش رنج‌های Cloudflare را اسکن می‌کند (TLS واقعی) و برای سرورهای پشت Cloudflare سریع‌ترین IP را به‌جای دامنه می‌گذارد (اتصال با IP خودکار روشن می‌شود). منوی ⋮ ← IP تمیز'),
      sw('Fragment (تکه‌کردن TLS Hello)', fragEnabled, (v) { _markUserTouched(const ['fragEnabled']); fragEnabled = v; },
          sub:
              'برای عبور از DPI؛ فقط روی اتصال واقعی و فقط سرورهای TLS/Reality. اگر اتصال برقرار نشد خاموشش کن'),
      sw('Mux (چند اتصال روی یک کانال)', muxEnabled, (v) { _markUserTouched(const ['muxEnabled']); muxEnabled = v; },
          sub: 'روی سرورهای tcp/ws بدون flow؛ گاهی ثبات را بهتر و گاهی بدتر می‌کند'),
      sw('DNS امن (DoH)', secureDns, (v) => secureDns = v,
          sub: 'پرسش DNS از طریق https://1.1.1.1 و 8.8.8.8 انجام می‌شود'),
      ListTile(
        leading: const Icon(Icons.shield_outlined),
        title: const Text('Kill switch (قطع نت اگر VPN افتاد)'),
        subtitle: const Text(
            'تنظیمات VPN اندروید باز می‌شود؛ برای این اپ «Always-on VPN» و «Block connections without VPN» را روشن کن'),
        onTap: () async {
          try {
            await bgChannel.invokeMethod<void>('vpnSettings');
          } catch (e, stk) {
            logError(e, stk);
          }
        },
      ),
    ];

extension NpvAmExtras on _HomePageState {
  void npvAdvDialog() {
    final customDnsC = TextEditingController(text: customDnsAddr);
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
                    if (dnsProv == 'custom')
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: TextField(
                          controller: customDnsC,
                          decoration: const InputDecoration(
                              hintText: 'مثلاً 1.1.1.1 یا https://dns.example/dns-query',
                              isDense: true),
                          onChanged: (v) => customDnsAddr = v,
                        ),
                      ),
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
    ).then((_) async {
      customDnsC.dispose();
      await _saveSettings();
    });
  }

  // RELAY: UI dialog for the relay server (Multi-hop)
  void showRelayDialog(BuildContext context) {
    final c = TextEditingController(text: relayServerUrl);
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('🔗 سرور واسط (دور زدن نت ملی)'),
          content: TextField(
            controller: c,
            maxLines: 4,
            minLines: 1,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              hintText: 'vless://... یا vmess://...',
              helperText: 'خالی بگذارید تا واسط به‌صورت خودکار از سرورهای سالم شما انتخاب شود. '
                  'اگر لینک بگذارید، در نت ملی اتصال از پشت همین سرور رد می‌شود.',
              helperMaxLines: 2,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () async {
                relayServerUrl = c.text.trim();
                await _saveSettings();
                if (!mounted || !ctx.mounted) return;
                Navigator.pop(ctx);
                _set(relayServerUrl.isEmpty ? 'سرور واسط پاک شد' : 'سرور واسط ذخیره شد');
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    ).whenComplete(c.dispose);
  }

  void cleanIpDialog() {
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
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: cleanIps.length,
                      itemBuilder: (context, index) {
                        final e = cleanIps[index];
                        return Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text('${e.ip}    ${e.ms} ms'),
                        );
                      },
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

const int kGoldRetestBatch = 500; // resumable work slice; not a daily inventory quota
const int kGoldEveryMin = 5;
const int kGoldRetestHours = 24;

class _GoldIp {
  final String ip;
  int ms, port, okAt, testAt;
  _GoldIp(this.ip, this.ms, this.port, this.okAt, this.testAt);
}

class _GoldSrv {
  final String link;
  int ping, okAt, testAt;
  _GoldSrv(this.link, this.ping, this.okAt, this.testAt);
}

final Map<String, _GoldIp> _goldIps = {};
final Map<String, _GoldSrv> _goldSrv = {};
// GOLDDNS: DNS سالم (ip -> میانگین ms) از اسکن DNS؛ جدا از IP تمیز چون پورت VPN ندارد
final Map<String, int> _goldDns = {};
// AUTOSCAN: نتیجه‌ی اسکنرهای خودکار (کلید: 'sni' یا 'port')
final Map<String, List<String>> _goldScan = {};
bool _goldRunning = false;
Timer? _goldTimer;
String _goldDay = '';
int _goldCnt = 0;

String _goldToday() {
  final n = DateTime.now();
  return '${n.year}-${n.month}-${n.day}';
}


Future<void>? _goldLoadF;

Future<void> goldLoad() => _goldLoadF ??= _goldLoadOnce();

Future<void> _goldLoadOnce() async {
  try {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('gold_v1');
    if (s == null) return;
    final m = jsonDecode(s) as Map;
    for (final e in (m['ips'] as List? ?? const [])) {
      final x = e as List;
      final ip = x[0].toString();
      _goldIps[ip] = _GoldIp(ip, (x[1] as num).toInt(), (x[2] as num).toInt(),
          (x[3] as num).toInt(), (x[4] as num).toInt());
    }
    for (final e in (m['srv'] as List? ?? const [])) {
      final x = e as List;
      final link = x[0].toString();
      _goldSrv[link] = _GoldSrv(link, (x[1] as num).toInt(),
          (x[2] as num).toInt(), (x[3] as num).toInt());
    }
    for (final e in (m['dns'] as List? ?? const [])) {
      final x = e as List;
      _goldDns[x[0].toString()] = (x[1] as num).toInt();
    }
    for (final e in (m['scan'] as Map? ?? const {}).entries) {
      _goldScan[e.key.toString()] = [for (final x in (e.value as List)) x.toString()];
    }
    _goldDay = (m['day'] ?? '').toString();
    _goldCnt = (m['cnt'] as num? ?? 0).toInt();
  } catch (e, stk) {
    logError(e, stk);
    // GOLDRETRY: cache را پاک کن تا فراخوانی بعدی دوباره تلاش کند
    _goldLoadF = null;
  }
}

String _goldEncode() => jsonEncode({
      'ips': [
        for (final v in (_goldIps.values.toList()..sort((a, b) => a.ms.compareTo(b.ms))))
          [v.ip, v.ms, v.port, v.okAt, v.testAt]
      ],
      'srv': [
        for (final v in (_goldSrv.values.toList()..sort((a, b) => a.ping.compareTo(b.ping))))
          [v.link, v.ping, v.okAt, v.testAt]
      ],
      'dns': [for (final e in _goldDns.entries) [e.key, e.value]],
      'scan': _goldScan,
      'day': _goldDay,
      'cnt': _goldCnt,
    });

Future<bool> _goldWrite(SharedPreferences p) =>
    p.setString('gold_v1', _goldEncode());

Future<void> goldSave() async {
  await goldLoad();
  try {
    final p = await SharedPreferences.getInstance();
    await _goldWrite(p);
  } catch (e, stk) {
    logError(e, stk);
  }
}

List<CleanIp>? _goldTop;
List<CleanIp> goldIpList() {
  if (_goldTop != null) return _goldTop!;
  // Return the complete saved inventory in quality order. Ranking determines
  // order only; it must never truncate the global pool to a fixed top-N slice.
  final all = _goldIps.values.toList()
    ..sort((a, b) => a.ms.compareTo(b.ms));
  return _goldTop = [for (final v in all) CleanIp(v.ip, v.ms, v.port)];
}

// NATHELP: نت ملی از IPهای تمیز پوشه‌ی جهانی کمک می‌گیرد (فقط خواندن). اسکنر دستی در نت ملی اجرا نمی‌شود، پس چیزی را خراب نمی‌کند.
void goldPrepareNational() {
  if (!nationalMode) return;
  final g = goldIpList();
  if (g.isNotEmpty) cleanIps = g;
}

// NATQUOTA: سهمیه‌ی اسکنرهای دستی در نت ملی. همزمانی کم، و هر بار قبل از شروع صبر می‌کنند
// تا جستجوی بازه‌ی نت ملی تمام شود، تا نت ملی همیشه اولویت داشته باشد.
const int kNatManualConc = 3;
// NATQUOTA-2: جستجوی عادی/آماده‌باش (busy/searching) هم اولویت دارد. _natKeep عمداً گوش داده نمی‌شود
// چون در نت ملی ساعت‌ها اجرا می‌شود و اسکن دستی را گرسنه نگه می‌دارد.
bool Function()? natSearchBusyProbe; // توسط State در initState تنظیم می‌شود
const Duration kNatYieldCap = Duration(minutes: 3); // هیچ اسکن دستی بیش از این صبر نمی‌کند
Future<void> natManualYield({bool Function()? shouldAbort}) async {
  final sw = Stopwatch()..start();
  while (!(shouldAbort?.call() ?? false) &&
      nationalMode &&
      (_natRangeScanBusy || (natSearchBusyProbe?.call() ?? false))) {
    if (sw.elapsed > kNatYieldCap) break;
    await Future.delayed(const Duration(milliseconds: 500));
  }
}

// FOLDERALL: همه‌ی اسکنرها (DNS، SNI/پورت، بازه، IP) در هر حالتی در پوشه‌ی جهانی ذخیره می‌شوند.
// DNS های پوشه برای اسکن DNS هر دو حالت استفاده می‌شوند.
Future<List<String>> goldDnsList() async {
  await goldLoad();
  return _goldDns.keys.toList();
}

Future<bool> goldAddScans(
  Map<String, List<String>> updates, {
  bool Function()? shouldAbort,
}) async {
  if (updates.isEmpty || (shouldAbort?.call() ?? false)) return false;
  await goldLoad();
  if (shouldAbort?.call() ?? false) return false;
  try {
    final p = await SharedPreferences.getInstance();
    // Last cancellation boundary: no shared state is changed before this check.
    if (shouldAbort?.call() ?? false) return false;
    for (final entry in updates.entries) {
      final merged = {...(_goldScan[entry.key] ?? const <String>[]), ...entry.value};
      _goldScan[entry.key] = merged.toList();
    }
    // Start persistence immediately after the synchronous cache update.
    final write = _goldWrite(p);
    return await write;
  } catch (e, stk) {
    logError(e, stk);
    return false;
  }
}

Future<void> goldAddScan(String kind, List<String> items) async {
  await goldLoad();
  final merged = {...(_goldScan[kind] ?? const <String>[]), ...items};
  _goldScan[kind] = merged.toList();
  await goldSave();
}

Future<bool> goldAddDns(List<DnsxHit> hits, {bool Function()? shouldAbort}) async {
  if (hits.isEmpty || (shouldAbort?.call() ?? false)) return false;
  await goldLoad();
  if (shouldAbort?.call() ?? false) return false;
  try {
    final p = await SharedPreferences.getInstance();
    // Last cancellation check before mutating shared DNS state.
    if (shouldAbort?.call() ?? false) return false;
    var changed = false;
    for (final h in hits) {
      if (h.okCount <= 0) continue;
      _goldDns[h.ip] = h.avgMs;
      changed = true;
    }
    if (!changed) return true;
    return await _goldWrite(p);
  } catch (e, stk) {
    logError(e, stk);
    return false;
  }
}

Future<void> goldMergeIps(
  List<CleanIp> res, {
  bool Function()? shouldAbort,
}) async {
  if (res.isEmpty || (shouldAbort?.call() ?? false)) return;
  await goldLoad();
  if (shouldAbort?.call() ?? false) return;
  final p = await SharedPreferences.getInstance();
  // Check again after the asynchronous preferences lookup, immediately before
  // mutating the shared cache so a closed dialog cannot persist stale results.
  if (shouldAbort?.call() ?? false) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  for (final c in res) {
    _goldIps[c.ip] = _GoldIp(c.ip, c.ms, c.port, now, now);
  }
  _goldTop = null;
  await _goldWrite(p);
}

Future<Map<String, int?>> _goldProbe(List<String> ips) async {
  final out = <String, int?>{};
  if (ips.isEmpty) return out;
  await pool<String>(ips, 20, (ip) async {
    out[ip] = await _cfProbeMs(ip, const Duration(milliseconds: 3500));
    await Future.delayed(const Duration(milliseconds: 20));
  }).timeout(const Duration(minutes: 2), onTimeout: () {});
  return out;
}

Future<void> _goldIpStep() async {
  if (nationalMode) return;
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final day = _goldToday();
  if (_goldDay != day) {
    _goldDay = day;
    _goldCnt = 0;
  }
  final retestMs = kGoldRetestHours * 3600 * 1000;

  final due = _goldIps.values
      .where((v) => nowMs - v.testAt >= retestMs)
      .take(kGoldRetestBatch)
      .map((v) => v.ip)
      .toList();
  if (due.isNotEmpty) {
    final r = await _goldProbe(due);
    for (final ip in due) {
      final v = _goldIps[ip];
      if (v == null || !r.containsKey(ip)) continue;
      // A probe omitted by a timed-out partial batch is untested, not dead.
      final ms = r[ip];
      if (ms == null) {
        _goldIps.remove(ip);
      } else {
        v.ms = ms;
        v.okAt = nowMs;
        v.testAt = nowMs;
      }
    }
    _goldCnt += due.length;
    _goldTop = null;
  }

  final cands = await _cleanCandidates();
  final batch = cands
      .where((ip) => !_goldIps.containsKey(ip))
      .take(240)
      .toList();
  if (batch.isEmpty) return;
  final r = await _goldProbe(batch);
  var found = 0;
  for (final ip in batch) {
    final ms = r[ip];
    if (ms != null) {
      _goldIps[ip] = _GoldIp(ip, ms, 443, nowMs, nowMs);
      found++;
    }
  }
  _goldCnt += batch.length;
  _goldTop = null;
  // _cleanCandidates stages a resumable dual-stack cursor. Gold background
  // discovery must commit it too, but only after every candidate in this slice
  // has completed; a timed-out/partial probe leaves the prior cursor intact.
  if (r.length >= batch.length) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cleanRangeCursorKey,
      jsonEncode(_cleanStagedRangeCursors),
    );
  }
  dbg('گلد: IP تازه $found از ${batch.length} • پوشه ${_goldIps.length} • امروز $_goldCnt');
}

Future<void> _goldSrvStep(_HomePageState h) async {
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  var changed = false;

  for (final s in h.good) {
    final p = s.ping;
    if (p == null || h._bad(s)) continue;
    final link = s.useLink;
    final ex = _goldSrv[link];
    if (ex == null) {
      _goldSrv[link] = _GoldSrv(link, p, nowMs, nowMs);
    } else {
      ex.ping = p;
      ex.okAt = nowMs;
      ex.testAt = nowMs;
    }
    changed = true;
  }

  if (!nationalMode) {
    final retestMs = kGoldRetestHours * 3600 * 1000;
    final due = _goldSrv.values
        .where((v) => nowMs - v.testAt >= retestMs)
        .toList();
    // GATEMAX: سقف گیت تست قبل از حلقه‌ی due
    // DSGETTER: از مقدار مؤثر
    _delayGate.max = nationalMode ? kNatDelayConcurrency : max(effFastWorkers, 8);
    for (final v in due) {
      if (!h.mounted || !h.connected || h.busy || h.switching) break;
      final sv = Server.parse(v.link);
      if (sv == null) {
        _goldSrv.remove(v.link);
        changed = true;
        continue;
      }
      final ms = await h._delayOf(sv);
      if (ms == null || ms <= 0) {
        _goldSrv.remove(v.link);
      } else {
        v.ping = ms;
        v.okAt = nowMs;
        v.testAt = nowMs;
      }
      changed = true;
    }
  }

  await _goldMergeGood(h);
  if (changed) await goldSave();
}

Future<void> _goldMergeGood(_HomePageState h) async {
  final keys = {for (final g in h.good) g.key};
  for (final v in _goldSrv.values) {
    if (v.ping <= 0) continue;
    final sv = Server.parse(v.link);
    if (sv == null || keys.contains(sv.key)) continue;
    sv.ping = v.ping;
    h.good.add(sv);
    keys.add(sv.key);
  }
}

Future<void> _goldTick(_HomePageState h) async {
  if (_goldRunning || !h.mounted || !h.connected || h.busy || h.switching) return;
  _goldRunning = true;
  try {
    await goldLoad();
    await _goldIpStep();
    await _goldSrvStep(h);
    await goldSave();
  } catch (e, stk) {
    logError(e, stk);
  } finally {
    _goldRunning = false;
  }
}

void startGoldLoop(_HomePageState h) {
  if (_goldTimer != null) return;
  _goldTimer = Timer.periodic(
      const Duration(minutes: kGoldEveryMin), (_) => _goldTick(h));
  unawaited(goldLoad().then((_) => _goldMergeGood(h)));
  unawaited(_goldTick(h));
}

String goldInfo() {
  var lastMs = 0;
  for (final v in _goldIps.values) {
    if (v.testAt > lastMs) lastMs = v.testAt;
  }
  final when = lastMs == 0
      ? 'هنوز تست نشده'
      : 'آخرین تست: ${DateTime.fromMillisecondsSinceEpoch(lastMs).toString().substring(0, 16)}';
  return 'IP تمیز: ${_goldIps.length} • سرور سالم: ${_goldSrv.length} • DNS: ${_goldDns.length} • $when';
}

Future<void> goldShowList(BuildContext context) async {
  await goldLoad();
  var open = true;
  var cancelled = false;
  var dnsBusy = false;
  var dnsStatus = '';
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      StateSetter? setD;
      void upd(VoidCallback f) {
        if (open && setD != null) setD!(f);
      }
      return StatefulBuilder(builder: (ctx2, ss) {
        setD = ss;
        final ipL = _goldIps.values.toList()..sort((a, b) => a.ms.compareTo(b.ms));
        final srvL = _goldSrv.values.toList()..sort((a, b) => a.ping.compareTo(b.ping));
        final dnsL = _goldDns.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
        return AlertDialog(
          title: const Text('پوشه‌ی جهانی'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(goldInfo(), style: const TextStyle(fontSize: 12)),
                if (dnsStatus.isNotEmpty)
                  Text(dnsStatus,
                      style: const TextStyle(fontSize: 12, color: Color(0xFFD9AE55))),
                const Divider(),
                const Text('سرورهای سالم (سریع → کند):',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                for (final v in srvL)
                  Text('${v.ping} ms  •  ${Server.parse(v.link)?.name ?? v.link}',
                      style: const TextStyle(fontSize: 12)),
                const Divider(),
                const Text('IP تمیز (سریع → کند):',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                for (final v in ipL)
                  Text('${v.ms} ms  •  ${v.ip}:${v.port}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                const Divider(),
                const Text('DNS سالم (سریع → کند):',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                for (final e in dnsL)
                  Text('${e.value} ms  •  ${e.key}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                for (final k in const ['sni_candidates', 'ip_candidates', 'sni', 'port', 'tls']) ...[
                  const Divider(),
                  Text(
                      {
                        'sni_candidates': 'دامنه‌های SNI کشف‌شده (تأییدنشده)',
                        'ip_candidates': 'IPهای کشف‌شده (تأییدنشده)',
                        'sni': 'SNI دارای پاسخ HTTPS در محدودهٔ تنظیم‌شده',
                        'port': 'پورت دارای پاسخ TCP در محدودهٔ تنظیم‌شده',
                        'tls': 'پروتکل TLS مشاهده‌شده',
                      }[k]! + ' (${(_goldScan[k] ?? const []).length}):',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  for (final x in (_goldScan[k] ?? const <String>[]))
                    Text(x, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: dnsBusy
                  ? null
                  : () async {
                      upd(() {
                        dnsBusy = true;
                        dnsStatus = 'اسکن DNS شروع شد...';
                      });
                      try {
                        final list = nationalMode ? kDnsxNationalDefaults : kDnsxDefaults;
                        final r = await dnsxScan(
                          list,
                          domains: dnsxFullDomains(),
                          gap: const Duration(milliseconds: 150),
                          manual: true,
                          onProgress: (d, t) => upd(() => dnsStatus = 'اسکن DNS: $d/$t'),
                          stop: () => cancelled || !open,
                        );
                        if (cancelled || !open) {
                          upd(() => dnsStatus = 'اسکن متوقف شد؛ نتایج ناقص ذخیره نشد');
                        } else {
                          final saved = await goldAddDns(
                            r,
                            shouldAbort: () => cancelled || !open,
                          );
                          if (!saved && (cancelled || !open)) {
                            upd(() => dnsStatus = 'اسکن متوقف شد؛ نتایج ناقص ذخیره نشد');
                          } else {
                            upd(() => dnsStatus =
                                '${r.where((h) => h.okCount > 0).length} DNS سالم پیدا و ذخیره شد');
                          }
                        }
                      } catch (e, stk) {
                        logError(e, stk);
                        upd(() => dnsStatus = 'خطا در اسکن DNS');
                      }
                      upd(() => dnsBusy = false);
                    },
              child: Text(dnsBusy ? 'در حال اسکن DNS...' : 'اسکن DNS الان'),
            ),
            TextButton(
              onPressed: () async {
                final t = ipL.map((v) => '${v.ip}:${v.port}').join('\n');
                await Clipboard.setData(ClipboardData(text: t));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${ipL.length} IP کپی شد')));
                }
              },
              child: const Text('کپی IPها'),
            ),
            TextButton(
              onPressed: () async {
                final t = dnsL.map((e) => e.key).join('\n');
                await Clipboard.setData(ClipboardData(text: t));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${dnsL.length} DNS کپی شد')));
                }
              },
              child: const Text('کپی DNSها'),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: (_goldScan['sni_candidates'] ?? const <String>[]).join('\n')));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('دامنه‌های کاندیدای SNI کپی شد')));
                }
              },
              child: const Text('کپی دامنه‌های کاندیدا'),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: (_goldScan['ip_candidates'] ?? const <String>[]).join('\n')));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('IPهای کاندیدا کپی شد')));
                }
              },
              child: const Text('کپی IPهای کاندیدا'),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: (_goldScan['sni'] ?? const <String>[]).join('\n')));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SNI کپی شد')));
                }
              },
              child: const Text('کپی SNI'),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: (_goldScan['port'] ?? const <String>[]).join('\n')));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پورت‌ها کپی شد')));
                }
              },
              child: const Text('کپی پورت‌ها'),
            ),
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
          ],
        );
      });
    },
  );
  open = false;
  cancelled = true;
}

Timer? _goldSaveT;

void goldNoteServer(Server srv) {
  unawaited(goldLoad());
  final p = srv.ping;
  if (p == null || p <= 0 || srv.personal) return;
  final link = srv.useLink;
  final now = DateTime.now().millisecondsSinceEpoch;
  final ex = _goldSrv[link];
  if (ex == null) {
    _goldSrv[link] = _GoldSrv(link, p, now, now);
  } else {
    ex.ping = p;
    ex.okAt = now;
    ex.testAt = now;
  }
  _goldSaveT ??= Timer(const Duration(seconds: 20), () {
    _goldSaveT = null;
    unawaited(goldSave());
  });
}

const String _manualRangeCursorKey = 'manual_range_scan_cursors_v2';
const String _manualRangeSignatureKey = 'manual_range_scan_signature_v2';

({List<String> addresses, Map<String, dynamic> cursors}) _manualRangeNextBatch(
  List<String> ranges,
  Map<String, dynamic> saved, {
  int batchSize = 2048,
}) {
  final cursors = Map<String, dynamic>.of(saved);
  if (ranges.isEmpty || batchSize <= 0) {
    return (addresses: const <String>[], cursors: cursors);
  }
  final start = natCursorIndex(cursors['__manual_range_cursor'], ranges.length);
  final addresses = <String>{};
  var visited = 0;
  for (; visited < ranges.length && addresses.length < batchSize; visited++) {
    final index = (start + visited) % ranges.length;
    final range = ranges[index];
    final remaining = batchSize - addresses.length;
    final rangesLeft = ranges.length - visited;
    final quota = max(1, (remaining + rangesLeft - 1) ~/ rangesLeft);
    final expanded = natExpandIpRangeCursor(
      range,
      cursors[range]?.toString() ?? '0',
      maxPerBlock: quota,
      wrap: false,
    );
    if (expanded.addresses.isEmpty) {
      cursors[range] = 'done';
      continue;
    }
    addresses.addAll(expanded.addresses);
    cursors[range] = expanded.nextCursor;
  }
  if (visited > 0) {
    cursors['__manual_range_cursor'] = (start + visited) % ranges.length;
  }
  return (addresses: addresses.toList(growable: false), cursors: cursors);
}

// MANUALSCAN: اسکن دستی بازه‌ها با پیشرفت و نتیجه داخل خود دیالوگ (نه پیام پشت دیالوگ)
Future<void> manualRangeScan(BuildContext context, List<String> userRanges) async {
  await goldLoad();
  final ranges = <String>{
    ...userRanges.map((value) => value.trim()).where((value) => value.isNotEmpty),
    for (final clean in goldIpList()) clean.ip,
  }.toList()..sort();
  if (ranges.isEmpty) return;

  final prefs = await SharedPreferences.getInstance();
  final signature = jsonEncode(ranges);
  final previousSignature = prefs.getString(_manualRangeSignatureKey);
  final cursors = <String, dynamic>{};
  if (previousSignature == signature) {
    final raw = prefs.getString(_manualRangeCursorKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.value is String || entry.value is num) {
              cursors['${entry.key}'] = entry.value;
            }
          }
        }
      } catch (e, stk) {
        logError(e, stk);
      }
    }
  } else {
    await prefs.setString(_manualRangeSignatureKey, signature);
    await prefs.setString(_manualRangeCursorKey, '{}');
  }

  final workers =
      nationalMode ? natAdaptiveConcurrency(kNatManualConc) : natAdaptiveWorkers();
  final batchSize = min(
    6000,
    max(
      1,
      (const Duration(minutes: 2).inMilliseconds / 1500 * workers * 0.65).floor(),
    ),
  ).toInt();
  var cancelled = false;
  var finished = false;
  var complete = false;
  var done = 0;
  var hitsCount = 0;
  var batchNumber = 0;
  final hitsByIp = <String, NatIpHit>{};
  var open = true;
  StateSetter? setS;

  void upd(VoidCallback f) {
    if (open && setS != null) setS!(f);
  }

  void showResult() {
    upd(() {
      hitsCount = hitsByIp.length;
    });
  }

  // ignore: unawaited_futures
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx2, ss) {
      setS = ss;
      final result = hitsByIp.values.toList()
        ..sort((a, b) => a.ms.compareTo(b.ms));
      return AlertDialog(
        title: Text(finished ? 'نتیجه‌ی اسکن بازه' : 'در حال اسکن بازه...'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('آدرس‌های بررسی‌شده: $done   •   IP سالم: $hitsCount'),
              Text('دسته: $batchNumber   •   ${complete ? 'همه‌ی بازه‌ها تمام شد' : 'ادامه از Cursor ذخیره می‌شود'}'),
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
                      text: result.map((hit) => '${hit.ip}:443').join('\n'))),
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text('کپی ${result.length} IP'),
                ),
              if (finished && result.isNotEmpty)
                SizedBox(
                  height: 260,
                  child: ListView(
                    children: [
                      for (final hit in result)
                        Text('${hit.ms} ms  •  ${hit.ip}:443',
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
                final text = result.map((hit) => '${hit.ip}:443').join('\n');
                await Clipboard.setData(ClipboardData(text: text));
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
    while (!cancelled && open) {
      final generated = _manualRangeNextBatch(
        ranges,
        cursors,
        batchSize: batchSize,
      );
      final addresses = generated.addresses;
      if (addresses.isEmpty) {
        complete = true;
        break;
      }
      batchNumber++;
      final batchBase = done;
      var completed = 0;
      final batchHits = await natScanIps(
        addresses,
        want: addresses.length,
        concurrency: workers,
        budget: const Duration(minutes: 2),
        timeout: const Duration(milliseconds: 1500),
        cancelled: () => cancelled || !open,
        onProgress: (scanned, total, found) {
          upd(() {
            done = batchBase + scanned;
            completed = scanned;
            hitsCount = hitsByIp.length + found;
          });
        },
      );
      if (cancelled || !open) break;
      for (final hit in batchHits) {
        final previous = hitsByIp[hit.ip];
        if (previous == null || hit.ms < previous.ms) hitsByIp[hit.ip] = hit;
      }
      done = batchBase + completed;
      showResult();

      if (completed < addresses.length) {
        // Do not advance a partial batch; the next opening retries this exact slice.
        break;
      }
      await goldMergeIps(
        [for (final hit in batchHits) CleanIp(hit.ip, hit.ms, 443)],
        shouldAbort: () => cancelled || !open,
      );
      if (cancelled || !open) break;
      cursors
        ..clear()
        ..addAll(generated.cursors);
      await prefs.setString(_manualRangeCursorKey, jsonEncode(cursors));
      if (nationalMode && !cancelled && open) {
        await natManualYield(shouldAbort: () => cancelled || !open);
      }
    }
  } catch (e, stk) {
    logError(e, stk);
  }
  upd(() {
    finished = true;
    hitsCount = hitsByIp.length;
  });
}
