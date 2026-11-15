part of 'main.dart';

// SUBGROUP: مدیریت گروهی لینک‌های اشتراک. چند اشتراک با نام، روشن/خاموش،
// به‌روزرسانی جدا یا همه‌ی اشتراک‌های فعال. کانفیگ‌ها مثل «افزودن لینک اشتراک» به صف می‌روند.
const String kSgrpKey = 'sgrp_v1';

class SgrpGroup {
  SgrpGroup({
    required this.name,
    required this.url,
    this.enabled = true,
    this.last = 0,
    this.count = 0,
  });

  String name;
  String url;
  bool enabled;
  int last; // زمان آخرین به‌روزرسانی (ms)
  int count; // تعداد کانفیگ‌های آخرین دریافت

  Map<String, dynamic> toJson() =>
      {'n': name, 'u': url, 'e': enabled, 't': last, 'c': count};

  static SgrpGroup? fromJson(Object? o) {
    if (o is! Map) return null;
    final u = o['u'];
    if (u is! String || u.isEmpty) return null;
    return SgrpGroup(
      name: (o['n'] ?? u).toString(),
      url: u,
      enabled: o['e'] != false,
      last: o['t'] is int ? o['t'] as int : 0,
      count: o['c'] is int ? o['c'] as int : 0,
    );
  }
}

Future<List<SgrpGroup>> sgrpLoad() async {
  final p = await SharedPreferences.getInstance();
  final out = <SgrpGroup>[];
  final raw = p.get(kSgrpKey);
  if (raw is List) {
    for (final s in raw) {
      try {
        final g = SgrpGroup.fromJson(jsonDecode(s.toString()));
        if (g != null) out.add(g);
      } catch (_) {}
    }
  }
  return out;
}

extension SgrpExt on _HomePageState {
  Future<void> sgrpSave(List<SgrpGroup> groups) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
        kSgrpKey, [for (final g in groups) jsonEncode(g.toJson())]);
  }

  /// یک اشتراک را می‌گیرد و کانفیگ‌های تازه را به صف اضافه می‌کند (بدون تکراری)
  Future<int> sgrpFetchOne(SgrpGroup g) async {
    final list = (await fetchSubscription(g.url)).take(300).toList();
    if (list.isEmpty) {
      // خطا یا اشتراک خالی: زمان آخرین به‌روزرسانی را موفق نشان نده
      return 0;
    }
    g.last = DateTime.now().millisecondsSinceEpoch;
    final have = {for (final s in pending) s.key};
    final fresh = list.where((s) => !have.contains(s.key)).toList();
    for (final s in list) {
      favs[s.key] = s.link;
    }
    _saveFavs();
    pending.insertAll(0, fresh);
    g.count = list.length;
    return list.length;
  }

  Future<int> sgrpRefreshAll(List<SgrpGroup> groups) async {
    _set('به‌روزرسانی اشتراک‌ها...');
    var total = 0;
    for (final g in groups) {
      if (!g.enabled) continue;
      total += await sgrpFetchOne(g);
    }
    await sgrpSave(groups);
    _set('$total کانفیگ از اشتراک‌های فعال دریافت شد');
    return total;
  }

  void sgrpAddDialog(
      BuildContext ctx0, List<SgrpGroup> groups, VoidCallback refresh) {
    final nameC = TextEditingController();
    final urlC = TextEditingController();
    showDialog(
      context: ctx0,
      builder: (d) => AlertDialog(
        title: const Text('افزودن اشتراک'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: 'نام گروه')),
            TextField(
                controller: urlC,
                decoration:
                    const InputDecoration(labelText: 'لینک اشتراک (https://...)')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('لغو')),
          TextButton(
            onPressed: () async {
              final u = urlC.text.trim();
              if (!u.startsWith('http://') && !u.startsWith('https://')) return;
              final n = nameC.text.trim();
              groups.add(SgrpGroup(name: n.isEmpty ? u : n, url: u));
              await sgrpSave(groups);
              Navigator.pop(d);
              refresh();
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
  }

  Future<void> sgrpSheet(BuildContext ctx0) async {
    final groups = await sgrpLoad();
    if (!mounted) return;
    showModalBottomSheet(
      context: ctx0,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          void refresh() => setS(() {});
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('تنظیمات گروهی اشتراک',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  if (groups.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('هنوز اشتراکی اضافه نشده است.'),
                    ),
                  for (final g in groups)
                    Card(
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: Text(g.name),
                            subtitle: Text(g.last == 0
                                ? 'هنوز به‌روز نشده'
                                : 'کانفیگ‌ها: ${g.count} • '
                                    '${DateTime.fromMillisecondsSinceEpoch(g.last).toString().substring(0, 16)}'),
                            value: g.enabled,
                            onChanged: (v) async {
                              g.enabled = v;
                              await sgrpSave(groups);
                              refresh();
                            },
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.refresh),
                                label: const Text('به‌روزرسانی'),
                                onPressed: () async {
                                  final n = await sgrpFetchOne(g);
                                  await sgrpSave(groups);
                                  refresh();
                                  ScaffoldMessenger.maybeOf(ctx0)?.showSnackBar(
                                      SnackBar(content: Text('$n کانفیگ دریافت شد')));
                                },
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('حذف'),
                                onPressed: () async {
                                  groups.remove(g);
                                  await sgrpSave(groups);
                                  refresh();
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('افزودن اشتراک'),
                    onPressed: () => sgrpAddDialog(ctx0, groups, refresh),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.sync),
                    label: const Text('به‌روزرسانی همه‌ی فعال‌ها'),
                    onPressed: () async {
                      await sgrpRefreshAll(groups);
                      refresh();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
