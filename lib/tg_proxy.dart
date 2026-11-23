import 'dart:convert';
import 'errjournal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

// =============================================================================
// پروکسی تلگرام — لیست پروکسی‌های عمومی (MTProto / SOCKS) برای کپی یا باز کردن
// این فایل عمداً جدا نگه داشته شده است.
// =============================================================================

class _TgPx {
  final String title, link, kind;
  _TgPx(this.title, this.link, this.kind);
}

const _tgPxSources = <String>[
  'https://raw.githubusercontent.com/hookzof/socks5_list/master/tg/mtproto.json',
  'https://raw.githubusercontent.com/hookzof/socks5_list/master/tg/socks.json',
  'https://raw.githubusercontent.com/ALIILAPRO/MTProtoProxy/main/mtproto.txt',
];

bool _tgPxValidHost(String value) {
  final host = value.trim().toLowerCase();
  if (host.isEmpty || host.length > 253 || host.contains('..')) return false;
  final labels = host.split('.');
  if (labels.length < 2) return false;
  return labels.every((label) => label.isNotEmpty && label.length <= 63 &&
      RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label));
}
int? _tgPxValidPort(String value) {
  final port = int.tryParse(value.trim());
  return port != null && port >= 1 && port <= 65535 ? port : null;
}
String? _tgPxBuildLink({required String host, required String port, String? secret, String? user, String? pass}) {
  final cleanHost = host.trim().toLowerCase();
  final cleanPort = _tgPxValidPort(port);
  if (!_tgPxValidHost(cleanHost) || cleanPort == null) return null;
  final params = <String, String>{'server': cleanHost, 'port': cleanPort.toString()};
  final isMtproto = secret != null && secret.isNotEmpty;
  if (isMtproto) {
    final cleanSecret = secret.trim();
    if (!RegExp(r'^(?:[a-fA-F0-9]{32,128}|[a-zA-Z0-9_-]{22,128})$').hasMatch(cleanSecret)) return null;
    params['secret'] = cleanSecret;
  } else {
    final cleanUser = user?.trim() ?? '';
    final cleanPass = pass?.trim() ?? '';
    if (cleanUser.length > 128 || cleanPass.length > 256) return null;
    if (cleanUser.isNotEmpty) params['user'] = cleanUser;
    if (cleanPass.isNotEmpty) params['pass'] = cleanPass;
  }
  return Uri.https('t.me', isMtproto ? '/proxy' : '/socks', params).toString();
}
String? _tgPxNormalizeLink(String raw) {
  try {
    final uri = Uri.parse(raw.trim());
    final isHttps = uri.scheme == 'https' && uri.host.toLowerCase() == 't.me';
    final isTelegramScheme = uri.scheme == 'tg' && (uri.host == 'proxy' || uri.host == 'socks');
    if (!isHttps && !isTelegramScheme) return null;
    final kind = isTelegramScheme ? uri.host : (uri.pathSegments.isEmpty ? '' : uri.pathSegments.first);
    if (kind != 'proxy' && kind != 'socks') return null;
    final q = uri.queryParameters;
    return _tgPxBuildLink(host: q['server'] ?? '', port: q['port'] ?? '', secret: kind == 'proxy' ? q['secret'] : null, user: q['user'], pass: q['pass']);
  } catch (_) { return null; }
}
const String _tgPxCacheKey = 'tg_proxy_cache_v1';
bool _tgPxUsedCache = false;

Future<List<_TgPx>> _tgPxReadCache() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tgPxCacheKey);
    if (raw == null || raw.isEmpty) return <_TgPx>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <_TgPx>[];
    final out = <_TgPx>[];
    final seen = <String>{};
    for (final item in decoded.take(200)) {
      if (item is! Map) continue;
      final link = _tgPxNormalizeLink('${item['link'] ?? ''}');
      if (link == null || !seen.add(link)) continue;
      final uri = Uri.parse(link);
      final kind = uri.pathSegments.first == 'socks' ? 'SOCKS5' : 'MTProto';
      final title = '${item['title'] ?? 'پروکسی'}';
      out.add(_TgPx('ذخیره‌شده • ${title.substring(0, title.length.clamp(0, 100).toInt())}', link, kind));
    }
    return out;
  } catch (e, st) {
    errJournalAdd(e, st: st);
    return <_TgPx>[];
  }
}

Future<void> _tgPxWriteCache(List<_TgPx> items) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final snapshot = items.take(200).map((item) => <String, String>{
      'title': item.title,
      'link': item.link,
    }).toList(growable: false);
    await prefs.setString(_tgPxCacheKey, jsonEncode(snapshot));
  } catch (e, st) {
    errJournalAdd(e, st: st);
  }
}

Future<List<_TgPx>> _tgPxLoad() async {
  final cached = await _tgPxReadCache();
  _tgPxUsedCache = false;
  final out = <_TgPx>[];
  final seen = <String>{};
  for (final url in _tgPxSources) {
    if (out.length >= 200) break;
    try {
      final r = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      if (r.statusCode != 200) continue;
      final body = r.body.trim();
      if (body.length > 2 * 1024 * 1024) continue;
      if (body.startsWith('[') || body.startsWith('{')) {
        try {
          final j = jsonDecode(body);
          if (j is List) {
            for (final e in j) {
              if (out.length >= 200) break;
              if (e is! Map) continue;
              final host = '${e['host'] ?? e['server'] ?? ''}'.trim();
              final port = '${e['port'] ?? ''}'.trim();
              final secret = '${e['secret'] ?? ''}'.trim();
              final user = '${e['user'] ?? e['username'] ?? ''}'.trim();
              final pass = '${e['pass'] ?? e['password'] ?? ''}'.trim();
              final link = _tgPxBuildLink(host: host, port: port, secret: secret.isEmpty ? null : secret, user: user, pass: pass);
              if (link == null) continue;
              final kind = secret.isNotEmpty ? 'MTProto' : 'SOCKS5';
              if (seen.add(link)) out.add(_TgPx('$kind • $host:$port', link, kind));
            }
          }
        } catch (e, jstk) { errJournalAdd(e, st: jstk); debugPrint("catch: $e"); }
      } else {
        for (final raw in body.split(RegExp(r'[\r\n]+'))) {
          if (out.length >= 200) break;
          final line = raw.trim();
          if (line.isEmpty) continue;
          final m = RegExp(
                  r'(https://t\.me/(?:proxy|socks)\?[^\s<>"]+|tg://(?:proxy|socks)\?[^\s<>"]+)',
                  caseSensitive: false)
              .firstMatch(line);
          if (m == null) continue;
          final link = _tgPxNormalizeLink(m.group(0)!);
          if (link == null) continue;
          if (seen.add(link)) {
            final kind = Uri.parse(link).pathSegments.first == 'socks' ? 'SOCKS5' : 'MTProto';
            out.add(_TgPx('$kind • پروکسی', link, kind));
          }
        }
      }
    } catch (e, jstk) { errJournalAdd(e, st: jstk); debugPrint("catch: $e"); }
  }
  if (out.isNotEmpty) {
    await _tgPxWriteCache(out);
    return out;
  }
  _tgPxUsedCache = cached.isNotEmpty;
  return cached;
}

/// ویجت پروکسی تلگرام برای صفحه اصلی / شیت
Widget tgProxyRow(BuildContext context) {
  return const _TgProxyPanel();
}

class _TgProxyPanel extends StatefulWidget {
  const _TgProxyPanel();
  @override
  State<_TgProxyPanel> createState() => _TgProxyPanelState();
}

class _TgProxyPanelState extends State<_TgProxyPanel> {
  List<_TgPx>? _items;
  bool _loading = false;
  String _status = 'برای دریافت لیست، «جستجو» را بزن';

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _status = 'در حال دریافت پروکسی‌ها…';
    });
    final list = await _tgPxLoad();
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
      _status = list.isEmpty
          ? 'پروکسی پیدا نشد (شبکه یا منبع فیلتر است)'
          : (_tgPxUsedCache
              ? '${list.length} پروکسی از حافظهٔ ذخیره‌شده؛ منابع آنلاین در دسترس نیستند'
              : '${list.length} پروکسی از منابع آنلاین دریافت شد');
    });
  }

  Future<void> _copy(String t) async {
    await Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('کپی شد'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _open(String link) async {
    // USER: مستقیم وارد تلگرام شود نه سایت.
    // اول با اسکیم خود تلگرام (tg://) باز می‌شود تا مرورگر دخالت نکند.
    // اگر تلگرام نصب نبود یا باز نشد، لینک https را امتحان می‌کنیم.
    final tgLink = link
        .replaceFirst('https://t.me/proxy', 'tg://proxy')
        .replaceFirst('https://t.me/socks', 'tg://socks');
    for (final candidate in [tgLink, link]) {
      try {
        final ok = await launchUrl(Uri.parse(candidate),
            mode: LaunchMode.externalNonBrowserApplication);
        if (ok) return;
      } catch (e, jstk) { errJournalAdd(e, st: jstk); debugPrint("catch: $e"); }
    }
    await _copy(link);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items ?? const <_TgPx>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'پروکسی تلگرام',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            _status,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _loading ? null : _refresh,
            icon: Icon(_loading ? Icons.hourglass_top : Icons.search),
            label: Text(_loading ? 'در حال جستجو…' : 'جستجوی پروکسی'),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty && !_loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'پروکسی‌های MTProto و SOCKS عمومی برای باز کردن در تلگرام.\n'
                'بعد از پیدا شدن می‌توانی کپی کنی یا مستقیم باز کنی.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
          for (final it in items.take(40))
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(it.kind, style: const TextStyle(fontSize: 11)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'باز کردن در تلگرام',
                      icon: const Icon(Icons.open_in_new, size: 20),
                      onPressed: () => _open(it.link),
                    ),
                    IconButton(
                      tooltip: 'کپی',
                      icon: const Icon(Icons.copy, size: 20),
                      onPressed: () => _copy(it.link),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
