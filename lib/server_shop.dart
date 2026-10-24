part of 'main.dart';

// SERVER SHOP ===============================================================
// پوشه‌ی «خرید سرور شخصی»: لیست کانال‌های تلگرامی فروش سرور.
// همه‌ی محتوا از یک فایل JSON آنلاین (Gist) خوانده می‌شود؛ برای ویرایش فقط
// همان فایل را در سایت gist.github.com ویرایش کن، نیازی به کد و ساخت دوباره‌ی اپ نیست.

const String shopConfigUrl =
    'https://gist.githubusercontent.com/cafeeteriaa/1515b3b0e7bf966d587c0e822a812323/raw/shop.json';

// داده‌ی پیش‌فرض (تا وقتی اینترنت یا Gist نیست)
const String _shopDefaultJson = '{"title":"خرید سرور شخصی","channels":[]}';

class _ShopServer {
  final String name, specs, price, link;
  _ShopServer(this.name, this.specs, this.price, this.link);
}

class _ShopChannel {
  final String name, desc, link;
  final List<_ShopServer> servers;
  _ShopChannel(this.name, this.desc, this.link, this.servers);
}

String _shopStr(dynamic v) => v is String ? v.trim() : '';

String _shopLink(dynamic v) {
  var t = _shopStr(v);
  if (t.startsWith('@')) t = 'https://t.me/${t.substring(1)}';
  if (t.startsWith('t.me/')) t = 'https://$t';
  return (t.startsWith('https://') || t.startsWith('tg://')) ? t : '';
}

List<_ShopChannel>? _shopParse(String body) {
  try {
    final j = jsonDecode(body);
    if (j is! Map) return null;
    final out = <_ShopChannel>[];
    final cs = j['channels'];
    if (cs is List) {
      for (final c in cs) {
        if (c is! Map) continue;
        final name = _shopStr(c['name']);
        if (name.isEmpty) continue;
        final servers = <_ShopServer>[];
        final ss = c['servers'];
        if (ss is List) {
          for (final s in ss) {
            if (s is! Map) continue;
            final sn = _shopStr(s['name']);
            final sp = _shopStr(s['specs']);
            if (sn.isEmpty && sp.isEmpty) continue;
            servers.add(_ShopServer(
                sn, sp, _shopStr(s['price']), _shopLink(s['link'])));
          }
        }
        out.add(_ShopChannel(
            name, _shopStr(c['desc']), _shopLink(c['link']), servers));
      }
    }
    return out;
  } catch (e, stk) {
    logError(e, stk);
    return null;
  }
}

Future<void> _shopOpen(BuildContext ctx, String url) async {
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
Future<List<_ShopChannel>> _shopLoad({bool force = false}) async {
  SharedPreferences? p;
  List<_ShopChannel>? cached;
  try {
    p = await SharedPreferences.getInstance();
    final c = p.getString('shop_cfg');
    if (c != null) cached = _shopParse(c);
  } catch (e, stk) {
    logError(e, stk);
  }
  if (shopConfigUrl.startsWith('https://')) {
    try {
      final r = await http
          .get(Uri.parse(shopConfigUrl), headers: {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final body = utf8.decode(r.bodyBytes);
        final list = _shopParse(body);
        if (list != null) {
          await p?.setString('shop_cfg', body);
          return list;
        }
      }
    } catch (e, stk) {
      logError(e, stk);
    }
  }
  return cached ?? _shopParse(_shopDefaultJson) ?? <_ShopChannel>[];
}

void serverShopOpen(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const _ShopChannelsPage()));
}

class _ShopChannelsPage extends StatefulWidget {
  const _ShopChannelsPage();
  @override
  State<_ShopChannelsPage> createState() => _ShopChannelsPageState();
}

class _ShopChannelsPageState extends State<_ShopChannelsPage> {
  late Future<List<_ShopChannel>> _f = _shopLoad();

  Future<void> _refresh() async {
    final f = _shopLoad(force: true);
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
          title: const Text('خرید سرور شخصی'),
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'به‌روزرسانی',
                onPressed: _refresh),
          ],
        ),
        body: FutureBuilder<List<_ShopChannel>>(
          future: _f,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final list = snap.data ?? const <_ShopChannel>[];
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
                    child: ListTile(
                      leading: const Icon(Icons.folder_outlined,
                          color: _uiGold, size: 30),
                      title: Text(c.name,
                          style: const TextStyle(
                              color: _uiText, fontWeight: FontWeight.bold)),
                      subtitle: c.desc.isEmpty
                          ? Text('${c.servers.length} سرور',
                              style: const TextStyle(color: _uiSub))
                          : Text(c.desc,
                              style: const TextStyle(color: _uiSub)),
                      trailing: const Icon(Icons.chevron_left, color: _uiGold),
                      onTap: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
                          builder: (_) => _ShopServersPage(c))),
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

class _ShopServersPage extends StatelessWidget {
  final _ShopChannel ch;
  const _ShopServersPage(this.ch);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _uiBg,
        appBar: AppBar(backgroundColor: _uiBar, title: Text(ch.name)),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (ch.link.isNotEmpty)
              FilledButton.icon(
                icon: const Icon(Icons.send),
                label: const Text('ورود به کانال تلگرام'),
                onPressed: () => _shopOpen(context, ch.link),
              ),
            const SizedBox(height: 10),
            if (ch.servers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: Text('مشخصات سروری ثبت نشده است.',
                        style: TextStyle(color: _uiSub))),
              ),
            for (final s in ch.servers)
              Card(
                color: _uiCard,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0x77D9AE55))),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (s.name.isNotEmpty)
                        Text(s.name,
                            style: const TextStyle(
                                color: _uiGold,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                      if (s.specs.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(s.specs,
                            style: const TextStyle(
                                color: _uiText, height: 1.7, fontSize: 14)),
                      ],
                      if (s.price.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('💰 ${s.price}',
                            style: const TextStyle(color: _uiSub)),
                      ],
                      if ((s.link.isNotEmpty ? s.link : ch.link)
                          .isNotEmpty) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.send),
                          label: const Text('خرید / ارتباط در تلگرام'),
                          onPressed: () => _shopOpen(
                              context, s.link.isNotEmpty ? s.link : ch.link),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
