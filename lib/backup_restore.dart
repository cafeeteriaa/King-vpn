part of 'main.dart';

// BKPRESTORE: پشتیبان‌گیری و بازیابی تنظیمات و کانفیگ‌ها.
// همه‌ی مقادیر ذخیره‌ی برنامه (از جمله لیست‌ها) به یک متن JSON تبدیل می‌شوند.
// کلیدهای امنیتی در flutter_secure_storage هستند و عمداً در پشتیبان نمی‌آیند.
const String kBkpMagic = 'king_backup_v1';

Future<String> bkpExportJson() async {
  final p = await SharedPreferences.getInstance();
  final data = <String, Map<String, dynamic>>{};
  for (final k in p.getKeys()) {
    final v = p.get(k);
    if (v is String) {
      data[k] = {'t': 's', 'v': v};
    } else if (v is bool) {
      data[k] = {'t': 'b', 'v': v};
    } else if (v is int) {
      data[k] = {'t': 'i', 'v': v};
    } else if (v is double) {
      data[k] = {'t': 'd', 'v': v};
    } else if (v is List) {
      data[k] = {'t': 'l', 'v': v.map((e) => e.toString()).toList()};
    }
  }
  return JsonEncoder.withIndent('  ').convert({
    'magic': kBkpMagic,
    'at': DateTime.now().toIso8601String(),
    'count': data.length,
    'data': data,
  });
}

/// متن پشتیبان را می‌خواند و مقادیر را در ذخیره‌ی برنامه می‌نویسد. تعداد موارد را برمی‌گرداند.
Future<int> bkpImportJson(String text) async {
  final root = jsonDecode(text.trim());
  if (root is! Map || root['magic'] != kBkpMagic || root['data'] is! Map) {
    throw const FormatException('این متن پشتیبان معتبر نیست');
  }
  final p = await SharedPreferences.getInstance();
  var n = 0;
  final data = root['data'] as Map;
  for (final e in data.entries) {
    final item = e.value;
    if (item is! Map) continue;
    final k = e.key.toString();
    final t = item['t'];
    final v = item['v'];
    if (t == 's' && v is String) {
      await p.setString(k, v);
    } else if (t == 'b' && v is bool) {
      await p.setBool(k, v);
    } else if (t == 'i' && v is int) {
      await p.setInt(k, v);
    } else if (t == 'd' && v is num) {
      await p.setDouble(k, v.toDouble());
    } else if (t == 'l' && v is List) {
      await p.setStringList(k, v.map((x) => x.toString()).toList());
    } else {
      continue;
    }
    n++;
  }
  return n;
}

extension BkpExt on _HomePageState {
  void bkpSheet(BuildContext ctx0) {
    final restoreC = TextEditingController();
    showModalBottomSheet(
      context: ctx0,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('پشتیبان‌گیری و بازیابی',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              const Text(
                  'پشتیبان شامل تنظیمات، لینک‌ها و اطلاعات اتصال سرورها، پوشه‌ی سرورهای شخصی و اشتراک‌هاست. کلیدهای جداگانه‌ی flutter_secure_storage (مثل کلید AI) در آن نیست. فایل پشتیبان را فقط در محل امن نگه دارید و برای دیگران نفرستید.'),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('کپی پشتیبان'),
                onPressed: () async {
                  final s = await bkpExportJson();
                  await Clipboard.setData(ClipboardData(text: s));
                  if (!mounted) return;
                  ScaffoldMessenger.maybeOf(ctx0)?.showSnackBar(
                      SnackBar(content: Text('پشتیبان کپی شد (${s.length} کاراکتر)')));
                },
              ),
              const Divider(height: 24),
              TextField(
                controller: restoreC,
                maxLines: 4,
                decoration: const InputDecoration(
                    hintText: 'متن پشتیبان را اینجا بچسبانید',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.restore),
                label: const Text('بازیابی از متن'),
                onPressed: () async {
                  try {
                    final n = await bkpImportJson(restoreC.text);
                    if (!mounted) return;
                    ScaffoldMessenger.maybeOf(ctx0)?.showSnackBar(SnackBar(
                        content: Text(
                            '$n مورد بازیابی شد. برای اعمال کامل، برنامه را ببندید و دوباره باز کنید.')));
                    Navigator.pop(ctx);
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.maybeOf(ctx0)?.showSnackBar(
                        SnackBar(content: Text('بازیابی انجام نشد: $e')));
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
