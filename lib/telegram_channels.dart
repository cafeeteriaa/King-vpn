part of 'main.dart';

// TELEGRAM CHANNELS =========================================================
// پوشه‌ی «کانال‌های تلگرامی»: لیست کانال‌های تلگرامی.
// همه‌ی محتوا از یک فایل JSON آنلاین (Gist) خوانده می‌شود؛ برای ویرایش فقط
// همان فایل را در سایت gist.github.com ویرایش کن، نیازی به کد و ساخت دوباره‌ی اپ نیست.
//
// نمونه‌ی فایل JSON (اسم فایل در Gist: channels.json):
// {
//   "title": "کانال‌های تلگرامی",
//   "channels": [
//     {
//       "name": "اسم کانال",
//       "desc": "توضیح کوتاه",
//       "link": "@channel_id"
//     }
//   ]
// }

// آدرس فایل Gist (بدون کد طولانی نسخه، تا با هر ویرایش خودکار به‌روز شود).
// تا وقتی خالی یا اشتباه باشد، لیست خالی نشان داده می‌شود.
const String tgChannelsConfigUrl =
    'https://gist.githubusercontent.com/cafeeteriaa/c8ff6626deee9550466da99e32ec9e73/raw/channels.json';

// داده‌ی پیش‌فرض (تا وقتی اینترنت یا Gist نیست)
const String _tgcDefaultJson = '{"title":"کانال‌های تلگرامی","channels":[]}';

class _TgcChannel {
  final String name, desc, link;
  _TgcChannel(this.name, this.desc, this.link);
}

String _tgcStr(dynamic v) => v is String ? v.trim() : '';

String _tgcLink(dynamic v) {
  var t = _tgcStr(v);
  if (t.startsWith('@')) t = 'https://t.me/${t.substring(1)}';
  if (t.startsWith('t.me/')) t = 'https://$t';
  return (t.startsWith('https://') || t.startsWith('tg://')) ? t : '';
}

List<_TgcChannel>? _tgcParse(String body) {
  try {
    final j = jsonDecode(body);
    if (j is! Map) return null;
    final out = <_TgcChannel>[];
    final cs = j['channels'];
    if (cs is List) {
      for (final c in cs) {
        if (c is! Map) continue;
        final name = _tgcStr(c['name']);
        if (name.isEmpty) continue;
        out.add(_TgcChannel(name, _tgcStr(c['desc']), _tgcLink(c['link'])));
      }
    }
    return out;
  } catch (e, stk) {
    logError(e, stk);
    return null;
  }
}

Future<void> _tgcOpen(BuildContext ctx, String url) async {
  if (url.isEmpty) return;
  try {
    if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      return;
    }
  } catch (e, stk) {
    logError(e, stk);
  }
  await Clipboard.setData(ClipboardData(text: url));
  if (ctx.mounted) {
    ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('تلگرام باز نشد؛ لینک کپی شد.')));
  }
}

// اول نسخه‌ی ذخیره‌شده (سریع)، بعد از اینترنت به‌روز می‌شود.
Future<List<_TgcChannel>> _tgcLoad({bool force = false}) async {
  SharedPreferences? p;
  List<_TgcChannel>? cached;
  try {
    p = await SharedPreferences.getInstance();
    final c = p.getString('tgc_cfg');
    if (c != null) cached = _tgcParse(c);
  } catch (e, stk) {
    logError(e, stk);
  }
  if (tgChannelsConfigUrl.startsWith('https://')) {
    try {
      final r = await http
          .get(Uri.parse(tgChannelsConfigUrl),
              headers: {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final body = utf8.decode(r.bodyBytes);
        final list = _tgcParse(body);
        if (list != null) {
          await p?.setString('tgc_cfg', body);
          return list;
        }
      }
    } catch (e, stk) {
      logError(e, stk);
    }
  }
  return cached ?? _tgcParse(_tgcDefaultJson) ?? <_TgcChannel>[];
}

void telegramChannelsOpen(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const _TgcChannelsPage()));
}

class _TgcChannelsPage extends StatefulWidget {
  const _TgcChannelsPage();
  @override
  State<_TgcChannelsPage> createState() => _TgcChannelsPageState();
}

class _TgcChannelsPageState extends State<_TgcChannelsPage> {
  late Future<List<_TgcChannel>> _f = _tgcLoad();

  Future<void> _refresh() async {
    final f = _tgcLoad(force: true);
    setState(() => _f = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _uiBg,
        appBar: AppBar(
          backgroundColor: _uiBar,
          title: const Text('کانال‌های تلگرامی'),
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'به‌روزرسانی',
                onPressed: _refresh),
          ],
        ),
        body: FutureBuilder<List<_TgcChannel>>(
          future: _f,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final list = snap.data ?? const <_TgcChannel>[];
            if (list.isEmpty) {
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(children: const [
                  SizedBox(height: 120),
                  Center(
                      child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('فعلاً کانالی ثبت نشده است.',
                        style: TextStyle(color: _uiSub)),
                  )),
                ]),
              );
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final c = list[i];
                  return Card(
                    color: _uiCard,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0x77D9AE55))),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.send,
                                  color: _uiGold, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(c.name,
                                    style: const TextStyle(
                                        color: _uiGold,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          if (c.desc.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(c.desc,
                                style: const TextStyle(
                                    color: _uiText, height: 1.7, fontSize: 14)),
                          ],
                          if (c.link.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.send),
                              label: const Text('ورود به کانال تلگرام'),
                              onPressed: () => _tgcOpen(ctx, c.link),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
