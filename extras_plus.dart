part of 'main.dart';

// EXTRASPLUS ================================================================
// ابزارهای اضافه: آمار و کنترل حالت‌های نت ملی، تاریخچه‌ی اتصال، اطلاعات IP
// خروجی، تست سرعت دستی، پشتیبان‌گیری / بازگردانی، افزودن از کلیپ‌بورد ...

// حالت‌های نت ملی که کاربر خاموش کرده (حالت 0 «عادی» همیشه روشن است)
final Set<int> natDisabled = {};
// تاریخچه‌ی اتصال: 'زمان|نام|کلید|حالت|نت ملی'
final List<String> connHist = [];
bool _plusLoaded = false;

Future<void> plusLoad() async {
  if (_plusLoaded) return;
  _plusLoaded = true;
  try {
    final p = await SharedPreferences.getInstance();
    natDisabled
      ..clear()
      ..addAll((p.getStringList('plus_dis') ?? const <String>[])
          .map((e) => int.tryParse(e))
          .whereType<int>());
    connHist
      ..clear()
      ..addAll(p.getStringList('plus_hist') ?? const <String>[]);
  } catch (e) {
    logError(e);
  }
}

Future<void> plusSave() async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
        'plus_dis', natDisabled.map((e) => '$e').toList());
    await p.setStringList('plus_hist', connHist);
  } catch (e) {
    logError(e);
  }
}

// called when a connection is up
void plusHistAdd(Server s) {
  try {
    connHist.add('${DateTime.now().toIso8601String()}|'
        '${s.name.replaceAll('|', ' ')}|${s.key}|'
        '${natVar[_nk(s)] ?? 0}|${nationalMode ? 1 : 0}');
    while (connHist.length > 60) {
      connHist.removeAt(0);
    }
    plusSave();
  } catch (e) {
    logError(e);
  }
}

Future<String> _plusIpInfo() async {
  final c = HttpClient()
    ..findProxy = ((_) => proxyMode ? 'PROXY 127.0.0.1:$httpProxyPort' : 'DIRECT')
    ..connectionTimeout = const Duration(seconds: 6);
  try {
    final req = await c
        .getUrl(Uri.parse(
            'https://ipapi.co/json/'))
        .timeout(const Duration(seconds: 8));
    final res = await req.close().timeout(const Duration(seconds: 8));
    final body =
        await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 8));
    final j = jsonDecode(body);
    if (j is! Map || j['error'] == true || j['ip'] == null) return 'جوابی نیامد';
    return 'IP: ${j['ip']}\nکشور: ${j['country_name']}\nمنطقه: ${j['region']}\n'
        'شهر: ${j['city']}\nاپراتور: ${j['org']}\n${j['asn']}';
  } catch (e) {
    return 'خطا: $e';
  } finally {
    c.close(force: true);
  }
}

Future<String> _plusBackupText() async {
  final p = await SharedPreferences.getInstance();
  final out = <String, dynamic>{};
  for (final k in p.getKeys()) {
    final v = p.get(k);
    Map<String, dynamic>? e;
    if (v is String) {
      e = {'t': 's', 'v': v};
    } else if (v is int) {
      e = {'t': 'i', 'v': v};
    } else if (v is double) {
      e = {'t': 'd', 'v': v};
    } else if (v is bool) {
      e = {'t': 'b', 'v': v};
    } else if (v is List) {
      e = {'t': 'l', 'v': v.map((x) => '$x').toList()};
    }
    if (e == null) continue;
    if (jsonEncode(e).length > 150000) continue; // big caches are skipped
    out[k] = e;
  }
  return 'KINGVPN-BACKUP\n${base64.encode(utf8.encode(jsonEncode(out)))}';
}

Future<int> _plusRestoreText(String t) async {
  final lines = t.trim().split(RegExp(r'\s+'));
  if (lines.length < 2 || lines.first != 'KINGVPN-BACKUP') return -1;
  final j = jsonDecode(utf8.decode(base64.decode(base64.normalize(lines[1]))));
  if (j is! Map) return -1;
  final p = await SharedPreferences.getInstance();
  var n = 0;
  for (final k in j.keys) {
    final e = j[k];
    if (e is! Map) continue;
    final v = e['v'];
    switch (e['t']) {
      case 's':
        await p.setString('$k', '$v');
        break;
      case 'i':
        await p.setInt('$k', (v as num).toInt());
        break;
      case 'd':
        await p.setDouble('$k', (v as num).toDouble());
        break;
      case 'b':
        await p.setBool('$k', v == true);
        break;
      case 'l':
        await p.setStringList('$k', (v as List).map((x) => '$x').toList());
        break;
      default:
        continue;
    }
    n++;
  }
  return n;
}

extension PlusExt on _HomePageState {
  Future<void> _plusText(String title, String text) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: SelectableText(text)),
          actions: [
            TextButton(
                onPressed: () => Clipboard.setData(ClipboardData(text: text)),
                child: const Text('کپی')),
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
          ],
        ),
      ),
    );
  }

  Future<void> _plusAddFromText(String text) async {
    final added = <Server>[];
    for (final l in npvSplit(text)) {
      final s = Server.parse(l);
      if (s != null) added.add(s);
    }
    for (final s in added) {
      favs[s.key] = s.link;
      favObj.remove(s.key);
      if (!good.any((g) => g.key == s.key) &&
          !pending.any((p) => p.key == s.key)) {
        pending.insert(0, s);
      }
    }
    _saveFavs();
    // ignore: invalid_use_of_protected_member
    setState(() {});
    _set(added.isEmpty
        ? 'کانفیگ معتبر پیدا نشد'
        : '${added.length} کانفیگ اضافه شد • در بخش «📌 کانفیگ‌های من» است');
  }

  String _plusStats() {
    final pre = '$natOpKey#';
    final rows = <MapEntry<int, int>>[];
    natWins.forEach((k, n) {
      if (!k.startsWith(pre)) return;
      final v = int.tryParse(k.substring(pre.length));
      if (v != null && v >= 0 && v < _natSpecs.length) rows.add(MapEntry(v, n));
    });
    rows.sort((a, b) => b.value.compareTo(a.value));
    final b = StringBuffer('شبکه / اپراتور: $natOpKey\n');
    b.writeln('Ultra: ${ultraMode ? 'روشن' : 'خاموش'} • '
        'توربو: ${turboSpeed ? 'روشن' : 'خاموش'} • '
        'نت ملی: ${nationalMode ? 'بله' : 'خیر'}');
    b.writeln('سطح ماتریس: $natLevel • کل حالت‌ها: ${_natSpecs.length}');
    final cur = current;
    if (cur != null) {
      final v = natVarFor(cur);
      final vn = (v >= 0 && v < _natVarNames.length) ? _natVarNames[v] : '#$v';
      b.writeln('سرور فعلی: ${cur.name}');
      b.writeln('حالت فعال: $vn');
      if (v > 0 && v < _natSpecs.length) {
        final ds = _natDims(_natSpecs[v]);
        if (ds.isNotEmpty) b.writeln('ابعاد: ${ds.join(' · ')}');
      }
    }
    b.writeln('');
    if (rows.isEmpty) {
      b.write('هنوز حالتی روی این شبکه جواب نداده است.');
    } else {
      b.writeln('جدول برندگان حالت (این اپراتور):');
      for (final r in rows.take(25)) {
        b.writeln('• ${_natSpecs[r.key].name}: ${r.value} بار');
      }
      if (rows.length > 25) b.writeln('… و ${rows.length - 25} مورد دیگر');
    }
    b.writeln('\nسرورهای یادگرفته‌شده: ${natVar.length}');
    final dims = natDimWins.entries
        .where((e) => e.key.startsWith(pre))
        .toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    if (dims.isNotEmpty) {
      b.writeln('\nویژگی‌های برنده (ابعاد DNA اپراتور):');
      for (final e in dims.take(20)) {
        b.writeln('• ${e.key.substring(pre.length)}: ${e.value} بار');
      }
    }
    return b.toString();
  }

  // rich scrollable DNA board (winners table + dimensions)
  Future<void> _plusDnaBoard() async {
    await plusLoad();
    if (!mounted) return;
    final pre = '$natOpKey#';
    final rows = <MapEntry<int, int>>[];
    natWins.forEach((k, n) {
      if (!k.startsWith(pre)) return;
      final v = int.tryParse(k.substring(pre.length));
      if (v != null && v >= 0 && v < _natSpecs.length) {
        rows.add(MapEntry(v, n));
      }
    });
    rows.sort((a, b) => b.value.compareTo(a.value));
    final dims = natDimWins.entries
        .where((e) => e.key.startsWith(pre))
        .toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.85,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text('DNA اپراتور: $natOpKey',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 6),
                Text(
                    'Ultra ${ultraMode ? '✓' : '✗'} • توربو ${turboSpeed ? '✓' : '✗'} • '
                    'سطح $natLevel • ${_natSpecs.length} حالت',
                    style: const TextStyle(fontSize: 13)),
                if (current != null) ...[
                  const SizedBox(height: 8),
                  Builder(builder: (_) {
                    final v = natVarFor(current!);
                    final vn = v < _natVarNames.length ? _natVarNames[v] : '$v';
                    return Text('الان: ${current!.name} • حالت $vn',
                        style: const TextStyle(fontSize: 13));
                  }),
                ],
                const Divider(height: 24),
                const Text('برندگان حالت',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                if (rows.isEmpty)
                  const ListTile(
                      dense: true,
                      title: Text('هنوز چیزی یاد گرفته نشده'))
                else
                  ...rows.take(40).map((r) => ListTile(
                        dense: true,
                        title: Text(_natSpecs[r.key].name),
                        trailing: Text('${r.value}×',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        subtitle: Text(_natDims(_natSpecs[r.key])
                            .take(4)
                            .join(' · ')),
                      )),
                const Divider(height: 24),
                const Text('ابعاد برنده (ویژگی‌ها)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                if (dims.isEmpty)
                  const ListTile(
                      dense: true, title: Text('هنوز بُعدی ثبت نشده'))
                else
                  ...dims.take(30).map((e) => ListTile(
                        dense: true,
                        title: Text(e.key.substring(pre.length)),
                        trailing: Text('${e.value}×'),
                      )),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _plusStats()));
                    _set('جدول DNA کپی شد');
                  },
                  child: const Text('کپی متن کامل'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _plusVariants() async {
    await plusLoad();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.8,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                      'حالت‌های پایه‌ی نت ملی (حالت «عادی» همیشه روشن است) • '
                      '${_natSpecs.length - _natBaseCount} حالت ترکیبی دیگر خودکار و با یادگیری هر اپراتور مرتب می‌شود',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _natBaseCount - 1,
                    itemBuilder: (_, i) {
                      final v = i + 1;
                      return CheckboxListTile(
                        dense: true,
                        title: Text(_natSpecs[v].name),
                        value: !natDisabled.contains(v),
                        onChanged: (on) {
                          setS(() {
                            if (on == true) {
                              natDisabled.remove(v);
                            } else {
                              natDisabled.add(v);
                            }
                          });
                          plusSave();
                        },
                      );
                    },
                  ),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }

  String _plusHistText() {
    if (connHist.isEmpty) return 'هنوز اتصالی ثبت نشده است.';
    final b = StringBuffer();
    for (final l in connHist.reversed) {
      final p = l.split('|');
      if (p.length < 5) continue;
      final t = DateTime.tryParse(p[0]);
      final when = t == null ? p[0] : _dbgHms(t);
      final v = int.tryParse(p[3]) ?? 0;
      final vn = (v > 0 && v < _natSpecs.length) ? ' • ${_natSpecs[v].name}' : '';
      b.writeln('$when  ${p[1]}${p[4] == '1' ? ' (نت ملی)' : ''}$vn');
    }
    return b.toString();
  }

  Future<void> plusSheet() async {
    await plusLoad();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        Widget tile(IconData ic, String t, Future<void> Function() f,
            {String? sub}) {
          return ListTile(
            dense: true,
            leading: Icon(ic),
            title: Text(t),
            subtitle: sub == null ? null : Text(sub),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await f();
              } catch (e) {
                logError(e);
                _set('خطا: $e');
              }
            },
          );
        }

        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.85,
              child: ListView(children: [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('ابزارهای بیشتر',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                tile(Icons.insights, 'جدول DNA اپراتور (برندگان حالت)',
                    _plusDnaBoard,
                    sub: 'حالت‌ها و ویژگی‌هایی که روی این شبکه جواب داده‌اند'),
                tile(Icons.text_snippet_outlined, 'آمار متنی کامل',
                    () => _plusText('آمار حالت‌ها', _plusStats())),
                tile(Icons.tune, 'روشن / خاموش کردن حالت‌های نت ملی',
                    _plusVariants,
                    sub: 'حالتی که روی اپراتورت بی‌فایده است را خاموش کن'),
                tile(Icons.public, 'اطلاعات IP خروجی', () async {
                  _set('در حال گرفتن اطلاعات IP...');
                  await _plusText('IP خروجی', await _plusIpInfo());
                }, sub: 'با VPN روشن، IP و کشور سرور را نشان می‌دهد'),
                tile(Icons.speed, 'تست سرعت دستی', () async {
                  _set('تست سرعت...');
                  final mb = await measure(
                      win: const Duration(seconds: 5),
                      total: const Duration(seconds: 20),
                      direct: true);
                  _set(mb == null
                      ? 'تست سرعت جواب نداد'
                      : 'سرعت: ${(mb * 8).toStringAsFixed(1)} Mbit/s '
                          '(${(mb * 1024).round()} KB/s)');
                }),
                tile(Icons.paste, 'چسباندن کانفیگ از کلیپ‌بورد', () async {
                  final d = await Clipboard.getData('text/plain');
                  final t = d?.text ?? '';
                  if (t.trim().isEmpty) {
                    _set('کلیپ‌بورد خالی است');
                    return;
                  }
                  await _plusAddFromText(t);
                }),
                tile(Icons.copy_all, 'کپی سرورهای پوشه (نت ملی)', () async {
                  final l = _resMap.values.map((e) => e.link).toList();
                  await Clipboard.setData(ClipboardData(text: l.join('\n')));
                  _set('${l.length} سرور پوشه کپی شد');
                }),
                tile(Icons.link, 'کپی لینک سرور فعلی', () async {
                  final c = current;
                  if (c == null) {
                    _set('الان به سروری وصل نیستی');
                    return;
                  }
                  await Clipboard.setData(ClipboardData(text: c.link));
                  _set('لینک سرور کپی شد');
                }),
                tile(Icons.history, 'تاریخچه‌ی اتصال',
                    () => _plusText('تاریخچه‌ی اتصال', _plusHistText())),
                tile(Icons.backup, 'پشتیبان‌گیری از تنظیمات و سرورها (کپی)',
                    () async {
                  final t = await _plusBackupText();
                  await Clipboard.setData(ClipboardData(text: t));
                  _set('پشتیبان کپی شد؛ جایی مثل «پیام‌های ذخیره‌شده» نگهش دار');
                }),
                tile(Icons.restore, 'بازگردانی از پشتیبان (کلیپ‌بورد)',
                    () async {
                  final d = await Clipboard.getData('text/plain');
                  final n = await _plusRestoreText(d?.text ?? '');
                  _set(n < 0
                      ? 'متن پشتیبان داخل کلیپ‌بورد نیست'
                      : '$n مورد بازگردانی شد • برنامه را کامل ببند و دوباره باز کن');
                }),
                tile(Icons.delete_sweep, 'پاک کردن یادگیری نت ملی', () async {
                  natVar.clear();
                  natWins.clear();
                  natDimWins.clear();
                  _natPick.clear();
                  await natSavePersisted();
                  _set('یادگیری نت ملی پاک شد');
                }, sub: 'اگر اپراتور یا شهرت عوض شده مفید است'),
              ]),
            ),
          ),
        );
      },
    );
  }
}
