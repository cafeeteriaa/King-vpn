import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// ---------------------------------------------------------------------------
// Telegram (MTProto) proxies: from every source the 2 best FRESH proxies are
// picked (alive = TCP connect works, never shown before), so they can be
// copied or opened in Telegram. Every tap on "پروکسی جدید" brings new ones.
// A proxy is never shown twice in one refresh, even if several sources
// (mirrors) contain it.
// ---------------------------------------------------------------------------

const _tgRaw = 'https://raw.githubusercontent.com/';

class TgSource {
  final String name;
  final List<String> urls; // alternatives: the first one that works is used
  const TgSource(this.name, this.urls);
}

const tgSources = <TgSource>[
  TgSource('SoliSpirit', [
    '${_tgRaw}SoliSpirit/mtproto/master/all_proxies.txt',
  ]),
  TgSource('Kudts', [
    '${_tgRaw}Kudts/mtproto/master/all_proxies.txt',
  ]),
  TgSource('anonymouskeys', [
    '${_tgRaw}anonymouskeys/mtproto/main/proxies.txt',
  ]),
  TgSource('kort0881', [
    '${_tgRaw}kort0881/telegram-proxy-collector/main/proxy_all.txt',
    '${_tgRaw}kort0881/telegram-proxy-collector/main/proxies/proxy_all.txt',
  ]),
  TgSource('Grim1313', [
    '${_tgRaw}Grim1313/mtproto-for-telegram/master/all_proxies.txt',
  ]),
  TgSource('neobxod', [
    '${_tgRaw}neobxod/mtproto-for-telegram/master/all_proxies.txt',
  ]),
  TgSource('ALIILAPRO', [
    '${_tgRaw}ALIILAPRO/MTProtoProxy/main/mtproto.txt',
  ]),
  TgSource('Argh94', [
    '${_tgRaw}Argh94/Proxy-List/main/MTProto.txt',
    '${_tgRaw}Argh94/Proxy-List/main/mtproto.txt',
  ]),
];

class TgProxy {
  final String server, secret, source;
  final int port;
  int? ping;
  TgProxy(this.server, this.port, this.secret, this.source);
  String get key => '${server.toLowerCase()}:$port';
  String get link => 'tg://proxy?server=$server&port=$port&secret=$secret';
}

// ---- state (kept while the app is open, so reopening the page is instant)
final ValueNotifier<int> _tgTick = ValueNotifier<int>(0);
final Map<String, List<TgProxy>> _tgShown = {};
bool _tgRunning = false;
int _tgDone = 0;
String _tgStatus = '';

final _tgLinkRe = RegExp(r'(?:tg://proxy|https?://t\.me/proxy)\?[^\s"<>]+',
    caseSensitive: false);

String? _tgQ(String q, String k) {
  for (final p in q.split('&')) {
    final i = p.indexOf('=');
    if (i > 0 && p.substring(0, i).toLowerCase() == k) {
      return p.substring(i + 1);
    }
  }
  return null;
}

// reads tg://proxy / t.me/proxy links, or a JSON list (host/port/secret)
List<TgProxy> tgParse(String body, String src) {
  final out = <TgProxy>[];
  final keys = <String>{};
  void add(String? server, String? port, String? secret) {
    if (server == null || port == null || secret == null) return;
    final s = server.trim();
    final sec = secret.trim();
    final p = int.tryParse(port.trim());
    if (s.isEmpty || sec.isEmpty || p == null || p <= 0 || p > 65535) return;
    if (!keys.add('${s.toLowerCase()}:$p')) return;
    out.add(TgProxy(s, p, sec, src));
  }

  final b = body.replaceAll('&amp;', '&');
  for (final m in _tgLinkRe.allMatches(b)) {
    final l = m.group(0)!.replaceAll(RegExp(r'[)\],.;]+$'), '');
    final qi = l.indexOf('?');
    if (qi < 0) continue;
    final q = l.substring(qi + 1);
    add(_tgQ(q, 'server'), _tgQ(q, 'port'), _tgQ(q, 'secret'));
  }
  if (out.isEmpty) {
    try {
      dynamic j = jsonDecode(body.trim());
      if (j is Map) j = j['proxies'] ?? j['data'] ?? j['result'] ?? [];
      if (j is List) {
        for (final e in j) {
          if (e is Map) {
            add((e['host'] ?? e['server'] ?? e['ip'])?.toString(),
                e['port']?.toString(), e['secret']?.toString());
          }
        }
      }
    } catch (_) {}
  }
  return out;
}

Future<void> _tgPool<T>(
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

Future<int?> _tgProbe(TgProxy p) async {
  final sw = Stopwatch()..start();
  try {
    final s = await Socket.connect(p.server, p.port,
        timeout: const Duration(milliseconds: 3000));
    s.destroy();
    return sw.elapsedMilliseconds;
  } catch (_) {
    return null;
  }
}

Future<Set<String>> _tgLoadSeen() async {
  try {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList('tgp_seen') ?? <String>[]).toSet();
  } catch (_) {
    return <String>{};
  }
}

Future<void> _tgSaveSeen(Set<String> seen) async {
  try {
    final p = await SharedPreferences.getInstance();
    final l = seen.toList();
    final keep = l.length > 800 ? l.sublist(l.length - 800) : l;
    await p.setStringList('tgp_seen', keep);
  } catch (_) {}
}

// the 2 best alive proxies of one source (never-shown ones first).
// [claimed] holds the keys already taken by other sources in this refresh,
// so the same proxy never appears twice (mirrors, shared lists).
Future<List<TgProxy>> _tgPick(
    TgSource src, Set<String> seen, Set<String> claimed) async {
  var all = <TgProxy>[];
  for (final u in src.urls) {
    try {
      final r =
          await http.get(Uri.parse(u)).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) continue;
      all = tgParse(r.body, src.name);
      if (all.isNotEmpty) break;
    } catch (_) {}
  }
  if (all.isEmpty) return [];
  // new entries are added at the start or at the end of these files, so the
  // candidates are taken from both ends
  final cand = <TgProxy>[];
  final ck = <String>{};
  for (final p in [...all.take(25), ...all.reversed.take(25)]) {
    if (ck.add(p.key)) cand.add(p);
  }
  final alive = <TgProxy>[];
  await _tgPool<TgProxy>(cand, 12, (p) async {
    final ms = await _tgProbe(p);
    if (ms != null) {
      p.ping = ms;
      alive.add(p);
    }
  });
  alive.sort((a, b) => a.ping!.compareTo(b.ping!));
  final fresh = alive.where((p) => !seen.contains(p.key)).toList();
  final old = alive.where((p) => seen.contains(p.key)).toList();
  final picked = <TgProxy>[];
  for (final p in [...fresh, ...old]) {
    if (picked.length >= 2) break;
    // no await between check and add, so two sources can never take the same
    if (claimed.add(p.key)) picked.add(p);
  }
  return picked;
}

// "پروکسی جدید": all sources in parallel, results appear one by one
Future<void> tgRefresh() async {
  if (_tgRunning) return;
  _tgRunning = true;
  _tgShown.clear();
  _tgDone = 0;
  _tgStatus = 'در حال دریافت از ${tgSources.length} منبع...';
  _tgTick.value++;
  try {
    final seen = await _tgLoadSeen();
    final claimed = <String>{};
    await Future.wait(tgSources.map((src) async {
      var got = <TgProxy>[];
      try {
        got = await _tgPick(src, seen, claimed);
      } catch (_) {}
      _tgShown[src.name] = got;
      for (final p in got) {
        seen.add(p.key);
      }
      _tgDone++;
      _tgStatus = 'منبع $_tgDone از ${tgSources.length} بررسی شد...';
      _tgTick.value++;
    }));
    await _tgSaveSeen(seen);
    final n = _tgShown.values.fold<int>(0, (a, l) => a + l.length);
    final srcs = _tgShown.values.where((l) => l.isNotEmpty).length;
    _tgStatus = n == 0
        ? 'پروکسی سالمی پیدا نشد؛ دوباره «پروکسی جدید» را بزن'
        : '$n پروکسی تازه از $srcs منبع • با هر بار زدن «پروکسی جدید»، موارد جدیدتر می‌آید';
  } catch (e) {
    _tgStatus = 'خطا: $e';
  } finally {
    _tgRunning = false;
    _tgTick.value++;
  }
}

// ---------------------------------------------------------------------------
// rows shown in the main list
// ---------------------------------------------------------------------------

// above the personal server: search ALL rows together and connect
Widget searchAllRow(VoidCallback onTap) => InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        color: Color(0xFF34373E),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: const Row(children: [
          Expanded(
              child: Text(
                  '🔎 جستجوی همه گزینه‌ها با هم • بزن تا از همه ردیف‌ها بهترین سرور پیدا و وصل شود',
                  maxLines: 3,
                  style: TextStyle(fontWeight: FontWeight.bold))),
          Icon(Icons.play_circle_outline, size: 20),
        ]),
      ),
    );

// under the personal server: Telegram proxies
Widget tgProxyRow(BuildContext context) => InkWell(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const TgProxyPage())),
      child: Container(
        width: double.infinity,
        color: Color(0xFF34373E),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: const Row(children: [
          Expanded(
              child: Text(
                  '✈️ پروکسی تلگرام • از هر منبع ۲ پروکسی تازه • بزن تا لیست و کپی باز شود',
                  maxLines: 3,
                  style: TextStyle(fontWeight: FontWeight.bold))),
          Icon(Icons.send, size: 20),
        ]),
      ),
    );

class TgProxyPage extends StatefulWidget {
  const TgProxyPage({super.key});
  @override
  State<TgProxyPage> createState() => _TgProxyPageState();
}

class _TgProxyPageState extends State<TgProxyPage> {
  @override
  void initState() {
    super.initState();
    if (_tgShown.isEmpty && !_tgRunning) {
      Future.microtask(tgRefresh);
    }
  }

  void _snack(String t) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t), duration: const Duration(seconds: 2)));
  }

  Future<void> _copy(String t, String msg) async {
    await Clipboard.setData(ClipboardData(text: t));
    if (mounted) _snack(msg);
  }

  Future<void> _open(TgProxy p) async {
    try {
      if (await launchUrl(Uri.parse(p.link),
          mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {}
    await _copy(p.link, 'تلگرام باز نشد؛ لینک کپی شد');
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('✈️ پروکسی تلگرام')),
        body: ValueListenableBuilder<int>(
          valueListenable: _tgTick,
          builder: (ctx, _, __) {
            final all = <TgProxy>[];
            final children = <Widget>[];
            for (final s in tgSources) {
              final l = _tgShown[s.name];
              if (l == null || l.isEmpty) continue;
              all.addAll(l);
              children.add(Container(
                width: double.infinity,
                color: Color(0xFF2A2D33),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text('📚 ${s.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ));
              for (final p in l) {
                children.add(Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    title: Text('${p.server}:${p.port}',
                        textDirection: TextDirection.ltr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('پینگ ${p.ping ?? '-'} ms'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'کپی لینک',
                        icon: const Icon(Icons.copy),
                        onPressed: () => _copy(p.link, 'لینک پروکسی کپی شد'),
                      ),
                      IconButton(
                        tooltip: 'باز کردن در تلگرام',
                        icon: const Icon(Icons.send),
                        onPressed: () => _open(p),
                      ),
                    ]),
                  ),
                ));
              }
            }
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _tgRunning ? null : tgRefresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('پروکسی جدید'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: all.isEmpty
                        ? null
                        : () => _copy(all.map((p) => p.link).join('\n'),
                            '${all.length} لینک کپی شد'),
                    child: const Text('کپی همه'),
                  ),
                ]),
              ),
              if (_tgRunning)
                LinearProgressIndicator(
                    value: tgSources.isEmpty
                        ? null
                        : (_tgDone / tgSources.length).clamp(0.0, 1.0)),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(_tgStatus,
                    style: const TextStyle(fontSize: 12, color: Color(0xFFCDD1D8))),
              ),
              Expanded(child: ListView(children: children)),
            ]);
          },
        ),
      ),
    );
  }
}
