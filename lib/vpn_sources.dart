import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Server finders for 4 other VPN apps (COPY ONLY, nothing connects inside
// this app):
//   Hiddify        -> v2ray style links (vless / vmess / trojan / ss /
//                     hysteria2 / tuic) from public GitHub lists
//   SlipNet        -> slipnet:// links from public Telegram channel previews
//   VPN Client Pro -> OpenVPN profiles from the public VPN Gate API
//   HTTP Injector  -> v2ray style links (vless / vmess / trojan / ss)
//
// Every press on "جستجو" brings NEW servers first (already shown ones are
// remembered). Dead servers are dropped by a real TCP connect test where the
// protocol allows it (UDP based ones can not be tested this way).
// ---------------------------------------------------------------------------

enum VsKind { hiddify, slipnet, vpnclient, injector }

const _ghRaw = 'https://raw.githubusercontent.com/';

class VsSpec {
  final VsKind kind;
  final String id, title, emoji, howTo, honest;
  final List<String> urls;
  final List<String> schemes; // accepted link schemes (v2ray style kinds)
  const VsSpec({
    required this.kind,
    required this.id,
    required this.title,
    required this.emoji,
    required this.howTo,
    required this.honest,
    required this.urls,
    this.schemes = const [],
  });
}

// v2ray style public lists (auto updated by their owners); a dead link is
// simply skipped
const List<String> _v2rayLists = [
  '${_ghRaw}kasesm/Free-Config/refs/heads/main/all_raw.txt',
  '${_ghRaw}kasesm/Free-Config/refs/heads/main/vless_raw.txt',
  '${_ghRaw}ebrasha/free-v2ray-public-list/refs/heads/main/vless_configs.txt',
  '${_ghRaw}ebrasha/free-v2ray-public-list/refs/heads/main/vmess_configs.txt',
  '${_ghRaw}ebrasha/free-v2ray-public-list/refs/heads/main/trojan_configs.txt',
  '${_ghRaw}Epodonios/v2ray-configs/main/All_Configs_Sub.txt',
  '${_ghRaw}barry-far/V2ray-Config/main/All_Configs_Sub.txt',
  '${_ghRaw}MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/super-sub.txt',
];

const List<VsSpec> vsSpecs = [
  VsSpec(
    kind: VsKind.hiddify,
    id: 'hiddify',
    title: 'Hiddify',
    emoji: '🦊',
    howTo:
        'کپی کن، بعد در Hiddify: «+» ← «افزودن از کلیپ‌بورد». کپی همه هم یک‌جا وارد می‌شود.',
    honest:
        'تست = باز بودن پورت سرور. پروتکل‌های UDP (hysteria2 و tuic) قابل تست پورت نیستند و آخر لیست با برچسب «بدون تست» می‌آیند.',
    urls: _v2rayLists,
    schemes: ['vless', 'vmess', 'trojan', 'ss', 'hysteria2', 'hy2', 'tuic'],
  ),
  VsSpec(
    kind: VsKind.slipnet,
    id: 'slipnet',
    title: 'SlipNet',
    emoji: '🕳️',
    howTo:
        'کپی کن، بعد در SlipNet روی لینک slipnet:// بزن یا از «Import» کلیپ‌بورد را بچسبان.',
    honest:
        'SlipNet تونل DNS است و با تست پورت سالم بودنش معلوم نمی‌شود. تازه‌ترین کانفیگ‌های پست‌شده در کانال‌ها آورده می‌شوند؛ سالم بودن را خود SlipNet با «Test Server Reachability» نشان می‌دهد.',
    urls: [
      'https://t.me/s/SlipNet_app',
      'https://t.me/s/FreakConfig',
    ],
  ),
  VsSpec(
    kind: VsKind.vpnclient,
    id: 'vpnclient',
    title: 'VPN Client Pro',
    emoji: '🛡️',
    howTo:
        'متن .ovpn را کپی کن، در یادداشت‌ها یا مدیر فایل با پسوند .ovpn ذخیره کن و در VPN Client Pro با «Import» بازش کن.',
    honest:
        'منبع: لیست زنده‌ی VPN Gate (دانشگاه تسوکوبا). سرورهای TCP با تست پورت واقعی بررسی می‌شوند؛ سرورهای UDP را فقط می‌توان با امتیاز و پینگ خود VPN Gate مرتب کرد. بعضی IPها در ایران بسته‌اند.',
    urls: [
      'https://www.vpngate.net/api/iphone/',
      'http://www.vpngate.net/api/iphone/',
    ],
  ),
  VsSpec(
    kind: VsKind.injector,
    id: 'injector',
    title: 'HTTP Injector',
    emoji: '💉',
    howTo:
        'کپی کن و در HTTP Injector نوع V2Ray را انتخاب کن و لینک را وارد کن.',
    honest:
        'برای حساب‌های SSH و فایل‌های .hc منبع عمومی قابل‌اعتماد و خودکار وجود ندارد (سایت‌های ساخت اکانت کپچا دارند و هر چند روز منقضی می‌شوند)؛ پس اینجا لینک‌های V2Ray که HTTP Injector می‌خواند آورده می‌شود. تست = باز بودن پورت.',
    urls: _v2rayLists,
    schemes: ['vless', 'vmess', 'trojan', 'ss'],
  ),
];

// ---- one found server
class VsItem {
  final String text; // what is copied
  final String title;
  final String subtitle;
  final String key; // for "already shown"
  final String source;
  final String proto;
  int? ping;
  bool tested;
  int rank; // lower = better (used for sorting)
  VsItem({
    required this.text,
    required this.title,
    required this.subtitle,
    required this.key,
    required this.source,
    required this.proto,
    this.ping,
    this.tested = false,
    this.rank = 0,
  });
}

class _VsState {
  final ValueNotifier<int> tick = ValueNotifier<int>(0);
  List<VsItem> items = [];
  bool running = false;
  String status = '';
  double? progress;
}

final Map<String, _VsState> _vsStates = {
  for (final s in vsSpecs) s.id: _VsState(),
};

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

class _Hp {
  final String host;
  final int port;
  final String name;
  _Hp(this.host, this.port, this.name);
}

final RegExp _vsLinkRe = RegExp(
    r'(?:vless|vmess|trojan|ss|hysteria2|hy2|tuic)://[^\s"<>\x27]+',
    caseSensitive: false);

String _vsClean(String l) {
  var t = l.replaceAll('&amp;', '&');
  t = t.replaceAll(RegExp(r'[)\],.;]+$'), '');
  return t;
}

// many lists are one base64 block
String _vsExpand(String body) {
  final t = body.trim();
  if (t.isEmpty || t.contains('://')) return t;
  try {
    final c = t.replaceAll(RegExp(r'\s'), '');
    return utf8.decode(base64.decode(base64.normalize(c)), allowMalformed: true);
  } catch (_) {
    return t;
  }
}

String _vsDec(String s) {
  try {
    return Uri.decodeComponent(s);
  } catch (_) {
    return s;
  }
}

_Hp? _vsSplitHp(String hp, String name) {
  var h = hp.trim();
  if (h.isEmpty) return null;
  String host;
  String portStr;
  if (h.startsWith('[')) {
    final e = h.indexOf(']');
    if (e < 0) return null;
    host = h.substring(1, e);
    portStr = e + 2 <= h.length ? h.substring(e + 2) : '';
  } else {
    final c = h.lastIndexOf(':');
    if (c < 0) return null;
    host = h.substring(0, c);
    portStr = h.substring(c + 1);
  }
  final m = RegExp(r'^\d+').firstMatch(portStr);
  final port = m == null ? null : int.tryParse(m.group(0)!);
  if (host.isEmpty || port == null || port <= 0 || port > 65535) return null;
  return _Hp(host, port, name);
}

_Hp? _vsHostPort(String link) {
  try {
    final i = link.indexOf('://');
    if (i < 0) return null;
    final scheme = link.substring(0, i).toLowerCase();
    var rest = link.substring(i + 3);
    var name = '';
    final hash = rest.indexOf('#');
    if (hash >= 0) {
      name = _vsDec(rest.substring(hash + 1));
      rest = rest.substring(0, hash);
    }
    if (scheme == 'vmess') {
      final j = jsonDecode(
          utf8.decode(base64.decode(base64.normalize(rest.trim()))));
      if (j is! Map) return null;
      final port = int.tryParse(j['port'].toString());
      final host = (j['add'] ?? '').toString();
      if (host.isEmpty || port == null || port <= 0 || port > 65535) {
        return null;
      }
      return _Hp(host, port, (j['ps'] ?? name).toString());
    }
    final q = rest.indexOf('?');
    if (q >= 0) rest = rest.substring(0, q);
    if (scheme == 'ss' && !rest.contains('@')) {
      rest = utf8.decode(
          base64.decode(base64.normalize(_vsDec(rest).replaceAll('=', ''))));
    }
    final slash = rest.indexOf('/');
    if (slash >= 0) rest = rest.substring(0, slash);
    final at = rest.lastIndexOf('@');
    return _vsSplitHp(at >= 0 ? rest.substring(at + 1) : rest, name);
  } catch (_) {
    return null;
  }
}

Future<int?> _vsProbe(String host, int port) async {
  final sw = Stopwatch()..start();
  try {
    final s = await Socket.connect(host, port,
        timeout: const Duration(milliseconds: 3000));
    s.destroy();
    return sw.elapsedMilliseconds;
  } catch (_) {
    return null;
  }
}

Future<void> _vsPool<T>(
    List<T> items, int workers, Future<void> Function(T) fn) async {
  final it = items.iterator;
  Future<void> worker() async {
    while (it.moveNext()) {
      try {
        await fn(it.current);
      } catch (_) {}
    }
  }

  final n = items.length < workers ? items.length : workers;
  await Future.wait(List.generate(n, (_) => worker()));
}

int _vsNetFail = 0; // how many downloads failed in the current search

Future<String?> _vsGetOnce(String url, int sec) async {
  try {
    final r = await http.get(Uri.parse(url), headers: const {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
    }).timeout(Duration(seconds: sec));
    if (r.statusCode != 200) return null;
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  } catch (_) {
    return null;
  }
}

// SOURCEFIX: one retry, and t.me is also tried as telegram.me (some networks
// block only one of the two names)
Future<String?> _vsGet(String url, {int sec = 15}) async {
  final alts = <String>[url];
  if (url.startsWith('https://t.me/')) {
    alts.add(url.replaceFirst('https://t.me/', 'https://telegram.me/'));
  }
  for (var round = 0; round < 2; round++) {
    for (final u in alts) {
      final b = await _vsGetOnce(u, sec);
      if (b != null) return b;
    }
  }
  _vsNetFail++;
  return null;
}

Future<Set<String>> _vsLoadSeen(String id) async {
  try {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList('vsrc_seen_$id') ?? <String>[]).toSet();
  } catch (_) {
    return <String>{};
  }
}

Future<void> _vsSaveSeen(String id, Set<String> seen) async {
  try {
    final p = await SharedPreferences.getInstance();
    final l = seen.toList();
    await p.setStringList(
        'vsrc_seen_$id', l.length > 600 ? l.sublist(l.length - 600) : l);
  } catch (_) {}
}

String _vsFlag(String cc) {
  final c = cc.trim().toUpperCase();
  if (c.length != 2 || !RegExp(r'^[A-Z]{2}$').hasMatch(c)) return '🌐';
  return String.fromCharCodes(c.codeUnits.map((x) => 0x1F1E6 + x - 65));
}

// ---------------------------------------------------------------------------
// finders
// ---------------------------------------------------------------------------

// Hiddify + HTTP Injector: v2ray style links
Future<List<VsItem>> _findV2ray(VsSpec spec, _VsState st, Set<String> seen) async {
  final all = <String, VsItem>{};
  final udpOnly = <VsItem>[];
  var fetched = 0;
  await Future.wait(spec.urls.map((u) async {
    final body = await _vsGet(u);
    fetched++;
    st.status = 'منبع $fetched از ${spec.urls.length} دریافت شد...';
    st.progress = 0.4 * fetched / spec.urls.length;
    st.tick.value++;
    if (body == null) return;
    final src = Uri.parse(u).pathSegments.length > 1
        ? Uri.parse(u).pathSegments[1]
        : Uri.parse(u).host;
    for (final m in _vsLinkRe.allMatches(_vsExpand(body))) {
      final link = _vsClean(m.group(0)!);
      final scheme = link.substring(0, link.indexOf('://')).toLowerCase();
      if (!spec.schemes.contains(scheme)) continue;
      final hp = _vsHostPort(link);
      if (hp == null) continue;
      final key = '${hp.host.toLowerCase()}:${hp.port}';
      if (all.containsKey(key)) continue;
      all[key] = VsItem(
        text: link,
        title: hp.name.isEmpty ? '${hp.host}:${hp.port}' : hp.name,
        subtitle: '$scheme • ${hp.host}:${hp.port}',
        key: key,
        source: src,
        proto: scheme,
      );
    }
  }));
  if (all.isEmpty) return [];
  final tcp = <VsItem>[];
  for (final it in all.values) {
    if (it.proto == 'hysteria2' || it.proto == 'hy2' || it.proto == 'tuic') {
      udpOnly.add(it);
    } else {
      tcp.add(it);
    }
  }
  tcp.shuffle();
  // never-shown first
  final fresh = tcp.where((e) => !seen.contains(e.key)).toList();
  final old = tcp.where((e) => seen.contains(e.key)).toList();
  final cand = [...fresh, ...old].take(160).toList();
  final alive = <VsItem>[];
  var done = 0;
  st.status = 'تست ${cand.length} سرور از ${all.length}...';
  st.tick.value++;
  await _vsPool<VsItem>(cand, 16, (it) async {
    final p = it.key.lastIndexOf(':');
    final ms = await _vsProbe(it.key.substring(0, p),
        int.parse(it.key.substring(p + 1)));
    done++;
    if (done % 8 == 0) {
      st.progress = 0.4 + 0.6 * done / cand.length;
      st.tick.value++;
    }
    if (ms != null) {
      it.ping = ms;
      it.tested = true;
      alive.add(it);
    }
  });
  alive.sort((a, b) => a.ping!.compareTo(b.ping!));
  // new ones first among the alive, then the old ones
  final out = <VsItem>[
    ...alive.where((e) => !seen.contains(e.key)),
    ...alive.where((e) => seen.contains(e.key)),
  ].take(20).toList();
  if (spec.kind == VsKind.hiddify) {
    udpOnly.shuffle();
    out.addAll(udpOnly
        .where((e) => !seen.contains(e.key))
        .take(6)
        .toList());
  }
  return out;
}

// SlipNet: slipnet:// links from public Telegram channel previews
final RegExp _slipRe = RegExp(r'slipnet://[A-Za-z0-9+/=_\-%]{16,}');

Future<List<VsItem>> _findSlipnet(VsSpec spec, _VsState st, Set<String> seen) async {
  final found = <String, VsItem>{};
  var fetched = 0;
  await Future.wait(spec.urls.map((u) async {
    final body = await _vsGet(u);
    fetched++;
    st.status = 'کانال $fetched از ${spec.urls.length} خوانده شد...';
    st.progress = fetched / spec.urls.length;
    st.tick.value++;
    if (body == null) return;
    final src = Uri.parse(u).pathSegments.isNotEmpty
        ? Uri.parse(u).pathSegments.last
        : u;
    // newest posts are at the END of the preview page
    final ms = _slipRe.allMatches(body).toList().reversed;
    for (final m in ms) {
      final link = m.group(0)!;
      if (found.containsKey(link)) continue;
      var title = 'SlipNet config';
      var sub = '@$src';
      try {
        final b = link.substring('slipnet://'.length);
        final txt = utf8.decode(base64.decode(base64.normalize(_vsDec(b))),
            allowMalformed: true);
        final f = txt.split('|');
        if (f.length >= 4) {
          final name = f[2].trim();
          if (name.isNotEmpty && name.length < 60) title = name;
          sub = '${f[1].trim()} • ${f[3].trim()} • @$src';
        }
      } catch (_) {}
      found[link] = VsItem(
        text: link,
        title: title,
        subtitle: sub,
        key: link,
        source: src,
        proto: 'slipnet',
        rank: found.length,
      );
    }
  }));
  final l = found.values.toList();
  final fresh = l.where((e) => !seen.contains(e.key)).toList();
  final old = l.where((e) => seen.contains(e.key)).toList();
  return [...fresh, ...old].take(20).toList();
}

// VPN Client Pro: OpenVPN profiles from VPN Gate
Future<List<VsItem>> _findVpnGate(VsSpec spec, _VsState st, Set<String> seen) async {
  String? body;
  for (var i = 0; i < spec.urls.length; i++) {
    st.status = 'دریافت لیست VPN Gate...';
    st.progress = null;
    st.tick.value++;
    body = await _vsGet(spec.urls[i], sec: 25);
    if (body != null && body.contains(',')) break;
    body = null;
  }
  if (body == null) return [];
  final cands = <VsItem>[];
  final udp = <VsItem>[];
  final scoreOf = <String, int>{};
  for (final raw in body.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('*') || line.startsWith('#')) continue;
    final f = line.split(',');
    if (f.length < 15) continue;
    String ovpn;
    try {
      ovpn = utf8.decode(base64.decode(base64.normalize(f[14].trim())),
          allowMalformed: true);
    } catch (_) {
      continue;
    }
    if (!ovpn.contains('remote')) continue;
    final pm = RegExp(r'^proto\s+(\w+)', multiLine: true).firstMatch(ovpn);
    final rm = RegExp(r'^remote\s+(\S+)\s+(\d+)', multiLine: true)
        .firstMatch(ovpn);
    if (rm == null) continue;
    final proto = (pm?.group(1) ?? 'udp').toLowerCase();
    final host = rm.group(1)!;
    final port = int.tryParse(rm.group(2)!) ?? 0;
    if (port <= 0) continue;
    final score = int.tryParse(f[2]) ?? 0;
    final ping = int.tryParse(f[3]) ?? 0;
    final speed = (int.tryParse(f[4]) ?? 0) / 1000000.0;
    final sessions = f[7].trim();
    final key = '$host:$port/$proto';
    final it = VsItem(
      text: ovpn.replaceAll('\r', ''),
      title: '${_vsFlag(f[6])} ${f[5].trim()} • $host:$port',
      subtitle:
          '${proto.toUpperCase()} • پینگ VPN Gate: $ping ms • ${speed.toStringAsFixed(1)} Mbps • $sessions نشست',
      key: key,
      source: 'vpngate',
      proto: proto,
      ping: ping,
      rank: -score,
    );
    scoreOf[key] = score;
    if (proto.startsWith('tcp')) {
      cands.add(it);
    } else {
      udp.add(it);
    }
  }
  if (cands.isEmpty && udp.isEmpty) return [];
  // best VPN Gate score first, then test the TCP ones for real
  cands.sort((a, b) => a.rank.compareTo(b.rank));
  final toTest = cands.take(60).toList();
  var done = 0;
  final alive = <VsItem>[];
  st.status = 'تست ${toTest.length} سرور TCP...';
  st.tick.value++;
  await _vsPool<VsItem>(toTest, 12, (it) async {
    final k = it.key.split('/').first;
    final p = k.lastIndexOf(':');
    final ms = await _vsProbe(k.substring(0, p), int.parse(k.substring(p + 1)));
    done++;
    st.progress = done / toTest.length;
    if (done % 6 == 0) st.tick.value++;
    if (ms != null) {
      it.tested = true;
      it.ping = ms;
      alive.add(it);
    }
  });
  alive.sort((a, b) => a.rank.compareTo(b.rank));
  udp.sort((a, b) => a.rank.compareTo(b.rank));
  final tcpOut = [
    ...alive.where((e) => !seen.contains(e.key)),
    ...alive.where((e) => seen.contains(e.key)),
  ].take(12).toList();
  final udpOut = [
    ...udp.where((e) => !seen.contains(e.key)),
    ...udp.where((e) => seen.contains(e.key)),
  ].take(8).toList();
  return [...tcpOut, ...udpOut];
}

Future<void> vsRefresh(VsSpec spec) async {
  final st = _vsStates[spec.id]!;
  if (st.running) return;
  st.running = true;
  st.items = [];
  st.progress = null;
  _vsNetFail = 0;
  st.status = 'در حال شروع...';
  st.tick.value++;
  try {
    final seen = await _vsLoadSeen(spec.id);
    List<VsItem> r;
    switch (spec.kind) {
      case VsKind.slipnet:
        r = await _findSlipnet(spec, st, seen);
        break;
      case VsKind.vpnclient:
        r = await _findVpnGate(spec, st, seen);
        break;
      case VsKind.hiddify:
      case VsKind.injector:
        r = await _findV2ray(spec, st, seen);
        break;
    }
    st.items = r;
    for (final e in r) {
      seen.add(e.key);
    }
    await _vsSaveSeen(spec.id, seen);
    final tested = r.where((e) => e.tested).length;
    st.status = r.isEmpty
        ? (_vsNetFail > 0
            ? 'سایت منبع از این شبکه باز نشد (t.me و VPN Gate در ایران فیلتر هستند). اول با دکمه‌ی «اتصال» اصلی به یک سرور وصل شو، بعد دوباره «جستجو» را بزن.'
            : 'منبع باز شد ولی کانفیگ جدیدی در آن نبود؛ کمی بعد دوباره «جستجو» را بزن')
        : '${r.length} مورد پیدا شد'
            '${tested > 0 ? ' • $tested مورد با تست پورت تأیید شد' : ''}'
            ' • با هر بار جستجو، موارد جدیدتر می‌آید';
  } catch (e) {
    st.status = 'خطا: $e';
  } finally {
    st.running = false;
    st.progress = null;
    st.tick.value++;
  }
}

// ---------------------------------------------------------------------------
// UI
// ---------------------------------------------------------------------------

VsSpec vsSpecOf(VsKind k) => vsSpecs.firstWhere((s) => s.kind == k);

void vsOpen(BuildContext context, VsKind k,
    {Future<void> Function(String link)? onConnect}) {
  Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => VsPage(spec: vsSpecOf(k), onConnect: onConnect)));
}

class VsPage extends StatefulWidget {
  final VsSpec spec;
  // connects the app itself to a link (only Hiddify / HTTP Injector pages)
  final Future<void> Function(String link)? onConnect;
  const VsPage({super.key, required this.spec, this.onConnect});
  @override
  State<VsPage> createState() => _VsPageState();
}

class _VsPageState extends State<VsPage> {
  VsSpec get spec => widget.spec;
  _VsState get st => _vsStates[spec.id]!;

  @override
  void initState() {
    super.initState();
    // every time the page opens a fresh search starts
    if (!st.running) {
      Future.microtask(() => vsRefresh(spec));
    }
  }

  Future<void> _copy(String t, String msg) async {
    await Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Widget _tile(VsItem it) {
    final isOvpn = spec.kind == VsKind.vpnclient;
    // the app core reads these four; hysteria2 / tuic have no connect button
    // COPYONLY: no connect button in any of these pages
    const canConnect = false;
    final badge = it.tested
        ? '✅ ${it.ping} ms'
        : (it.proto == 'slipnet' ? '🆕' : '⚪ بدون تست');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        title: Text(it.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${it.subtitle}\n$badge',
            maxLines: 3,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 12)),
        isThreeLine: true,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (canConnect)
            IconButton(
              tooltip: 'اتصال',
              icon: const Icon(Icons.power_settings_new),
              onPressed: () {
                final cb = widget.onConnect!;
                Navigator.pop(context);
                cb(it.text);
              },
            ),
          IconButton(
            tooltip: 'کپی',
            icon: const Icon(Icons.copy),
            onPressed: () => _copy(
                it.text, isOvpn ? 'متن .ovpn کپی شد' : 'کانفیگ کپی شد'),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text('${spec.emoji} سرور برای ${spec.title}')),
        body: ValueListenableBuilder<int>(
          valueListenable: st.tick,
          builder: (ctx, _, __) {
            final items = st.items;
            final canCopyAll = items.isNotEmpty && spec.kind != VsKind.vpnclient;
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: st.running ? null : () => vsRefresh(spec),
                      icon: Icon(items.isEmpty ? Icons.search : Icons.refresh),
                      label: Text(st.running
                          ? 'در حال جستجو...'
                          : (items.isEmpty
                              ? 'جستجوی سرور سالم'
                              : '🔄 جستجوی تازه (سرور جدید)')),
                    ),
                  ),
                  if (spec.kind != VsKind.vpnclient) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: canCopyAll
                          ? () => _copy(
                              items.map((e) => e.text).join('\n'),
                              '${items.length} کانفیگ کپی شد')
                          : null,
                      child: const Text('کپی همه'),
                    ),
                  ],
                ]),
              ),
              if (st.running) LinearProgressIndicator(value: st.progress),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(st.status,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFFCDD1D8))),
              ),
              Expanded(
                child: ListView(children: [
                  for (final it in items) _tile(it),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text('📋 ${spec.howTo}',
                        style: const TextStyle(fontSize: 12.5, height: 1.6)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    child: Text('ℹ️ ${spec.honest}',
                        style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.6,
                            color: Color(0xFFCDD1D8))),
                  ),
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }
}
