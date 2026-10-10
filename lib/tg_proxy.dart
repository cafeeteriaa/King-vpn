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
    return
