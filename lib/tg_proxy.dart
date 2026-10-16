import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// =============================================================================
// پروکسی تلگرام — لیست پروکسی‌های عمومی (MTProto / SOCKS) برای کپی یا باز کردن
// این فایل عمداً جدا از vpn_sources است تا با VsKind تداخل نداشته باشد.
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

Future<List<_TgPx>> _tgPxLoad() async {
  final out = <_TgPx>[];
  final seen = <String>{};
  for (final url in _tgPxSources) {
    try {
      final r = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) continue;
      final body = r.body.trim();
      if (body.startsWith('[') || body.startsWith('{')) {
        try {
          final j = jsonDecode(body);
          if (j is List) {
            for (final e in j) {
              if (e is! Map) continue;
              final host = '${e['host'] ?? e['server'] ?? ''}'.trim();
              final port = '${e['port'] ?? ''}'.trim();
              final secret = '${e['secret'] ?? ''}'.trim();
              if (host.isEmpty || port.isEmpty) continue;
              String link;
              String kind;
              if (secret.isNotEmpty) {
                link = 'https://t.me/proxy?server=$host&port=$port&secret=$secret';
                kind = 'MTProto';
              } else {
                final user = '${e['user'] ?? e['username'] ?? ''}'.trim();
                final pass = '${e['pass'] ?? e['password'] ?? ''}'.trim();
                link = 'https://t.me/socks?server=$host&port=$port'
                    '${user.isEmpty ? '' : '&user=$user'}'
                    '${pass.isEmpty ? '' : '&pass=$pass'}';
                kind = 'SOCKS5';
              }
              if (seen.add(link)) {
                out.add(_TgPx('$kind • $host:$port', link, kind));
              }
            }
          }
        } catch (_) {}
      } else {
        for (final raw in body.split(RegExp(r'[\r\n]+'))) {
          final line = raw.trim();
          if (line.isEmpty) continue;
          final m = RegExp(
                  r'(https://t\.me/(?:proxy|socks)\?[^\s<>"]+|tg://(?:proxy|socks)\?[^\s<>"]+)',
                  caseSensitive: false)
              .firstMatch(line);
          if (m == null) continue;
          var link = m.group(0)!;
          if (link.startsWith('tg://')) {
            link = link
                .replaceFirst('tg://proxy', 'https://t.me/proxy')
                .replaceFirst('tg://socks', 'https://t.me/socks');
          }
          if (seen.add(link)) {
            final kind = link.contains('socks') ? 'SOCKS5' : 'MTProto';
            out.add(_TgPx('$kind • پروکسی', link, kind));
          }
        }
      }
    } catch (_) {}
  }
  return out;
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
          : '${list.length} پروکسی پیدا شد';
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
    try {
      final u = Uri.parse(link);
      if (await canLaunchUrl(u)) {
        await launchUrl(u, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}
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
