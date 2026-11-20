part of 'main.dart';

// BKPRESTORE: پشتیبان‌گیری و بازیابی تنظیمات و کانفیگ‌ها.
// همه‌ی مقادیر ذخیره‌ی برنامه (از جمله لیست‌ها) به یک متن JSON تبدیل می‌شوند.
// کلیدهای امنیتی در flutter_secure_storage هستند و عمداً در پشتیبان نمی‌آیند.
const String kBkpMagic = 'king_backup_v1';

// Backup input is untrusted. Validate the complete payload before touching preferences.
const int _bkpMaxBytes = 2 * 1024 * 1024;
const int _bkpMaxEntries = 500;
const int _bkpMaxStringLength = 256 * 1024;
const int _bkpMaxListItems = 500;
const int _bkpMaxListItemLength = 16 * 1024;
final RegExp _bkpAllowedKey = RegExp(r'^[A-Za-z0-9_.-]{1,128}$');
final RegExp _bkpSensitiveKey = RegExp(
    r'(token|secret|password|passwd|credential|api.?key|private.?key|auth.?key)',
    caseSensitive: false);

bool _bkpKeyAllowed(String key) =>
    _bkpAllowedKey.hasMatch(key) && !_bkpSensitiveKey.hasMatch(key);

// Each entry is measured once as it is collected. Summing these encoded
// entry sizes is a conservative upper bound for the compact data object;
// reserve space for the envelope and pretty-print whitespace.
void _bkpEnsureExportWithinBudget(int encodedEntryBytes) {
  const formattingReserve = 32 * 1024;
  const envelopeReserve = 512;
  if (encodedEntryBytes >
      _bkpMaxBytes - formattingReserve - envelopeReserve) {
    throw const FormatException('حجم پشتیبان از حد مجاز بیشتر است');
  }
}

Future<String> bkpExportJson() async {
  final p = await SharedPreferences.getInstance();
  final timestamp = DateTime.now().toIso8601String();
  final data = <String, Map<String, dynamic>>{};
  var encodedEntryBytes = 0;
  for (final k in p.getKeys()) {
    if (!_bkpKeyAllowed(k)) continue;
    final v = p.get(k);
    if (v is String && v.length <= _bkpMaxStringLength) {
      data[k] = {'t': 's', 'v': v};
    } else if (v is bool) {
      data[k] = {'t': 'b', 'v': v};
    } else if (v is int) {
      data[k] = {'t': 'i', 'v': v};
    } else if (v is double && v.isFinite) {
      data[k] = {'t': 'd', 'v': v};
    } else if (v is List &&
        v.length <= _bkpMaxListItems &&
        v.every((e) => e is String && e.length <= _bkpMaxListItemLength)) {
      data[k] = {'t': 'l', 'v': v};
    }
    if (data.length > _bkpMaxEntries) {
      throw const FormatException('تعداد تنظیمات برای پشتیبان بیش از حد مجاز است');
    }
    // Measure only the new entry: avoid re-encoding the entire accumulated
    // backup on every iteration (quadratic work for large preference sets).
    final entry = data[k];
    if (entry != null) {
      encodedEntryBytes += utf8.encode(jsonEncode({k: entry})).length;
      _bkpEnsureExportWithinBudget(encodedEntryBytes);
    }
  }
  final encoded = JsonEncoder.withIndent('  ').convert({
    'magic': kBkpMagic,
    'at': timestamp,
    'count': data.length,
    'data': data,
  });
  if (utf8.encode(encoded).length > _bkpMaxBytes) {
    throw const FormatException('حجم پشتیبان از حد مجاز بیشتر است');
  }
  return encoded;
}

Future<bool> _bkpWriteValue(
    SharedPreferences preferences, String key, Object? value) async {
  if (value == null) return preferences.remove(key);
  if (value is String) return preferences.setString(key, value);
  if (value is bool) return preferences.setBool(key, value);
  if (value is int) return preferences.setInt(key, value);
  if (value is double) return preferences.setDouble(key, value);
  if (value is List<String>) return preferences.setStringList(key, value);
  throw StateError('نوع مقدار تنظیم برای بازیابی پشتیبانی نمی‌شود');
}

/// Validate all entries before writing any preference.
Future<int> bkpImportJson(String text) async {
  if (utf8.encode(text).length > _bkpMaxBytes) {
    throw const FormatException('حجم متن پشتیبان بیش از حد مجاز است');
  }
  final decoded = jsonDecode(text);
  if (decoded is! Map ||
      decoded['magic'] != kBkpMagic ||
      decoded['data'] is! Map) {
    throw const FormatException('این متن پشتیبان معتبر نیست');
  }
  final rawData = decoded['data'] as Map;
  if (rawData.isEmpty || rawData.length > _bkpMaxEntries) {
    throw const FormatException('تعداد تنظیمات پشتیبان معتبر نیست');
  }
  final declaredCount = decoded['count'];
  if (declaredCount != null &&
      (declaredCount is! int || declaredCount != rawData.length)) {
    throw const FormatException('تعداد موارد پشتیبان با محتوای آن سازگار نیست');
  }

  final staged = <String, Object>{};
  for (final entry in rawData.entries) {
    if (entry.key is! String || entry.value is! Map) {
      throw const FormatException('ساختار یکی از تنظیمات معتبر نیست');
    }
    final key = entry.key as String;
    if (!_bkpKeyAllowed(key) || staged.containsKey(key)) {
      throw const FormatException('کلید نامعتبر یا غیرمجاز در پشتیبان وجود دارد');
    }
    final item = entry.value as Map;
    if (item.length != 2 || !item.containsKey('t') || !item.containsKey('v')) {
      throw const FormatException('ساختار مقدار پشتیبان معتبر نیست');
    }
    final type = item['t'];
    final value = item['v'];
    if (type == 's' && value is String &&
        value.length <= _bkpMaxStringLength) {
      staged[key] = value;
    } else if (type == 'b' && value is bool) {
      staged[key] = value;
    } else if (type == 'i' && value is int) {
      staged[key] = value;
    } else if (type == 'd' && value is num && value.isFinite) {
      staged[key] = value.toDouble();
    } else if (type == 'l' && value is List &&
        value.length <= _bkpMaxListItems &&
        value.every((x) => x is String && x.length <= _bkpMaxListItemLength)) {
      staged[key] = List<String>.from(value);
    } else {
      throw const FormatException('نوع یا اندازهٔ یکی از مقادیر پشتیبان معتبر نیست');
    }
  }

  // No preferences are changed until every key and value has passed validation.
  // Snapshot every target key before the first write so a failed restore can roll back.
  final p = await SharedPreferences.getInstance();
  final previous = <String, Object?>{
    for (final key in staged.keys) key: p.get(key),
  };
  final attempted = <String>[];
  try {
    for (final entry in staged.entries) {
      attempted.add(entry.key);
      final ok = await _bkpWriteValue(p, entry.key, entry.value);
      if (!ok) throw StateError('ذخیرهٔ تنظیم ناموفق بود');
    }
  } catch (_) {
    var rollbackFailures = 0;
    for (final key in attempted.reversed) {
      try {
        final restored = await _bkpWriteValue(p, key, previous[key]);
        if (!restored) rollbackFailures++;
      } catch (_) {
        rollbackFailures++;
      }
    }
    if (rollbackFailures > 0) {
      throw StateError(
          'بازیابی ناموفق شد و بازگردانی $rollbackFailures مورد نیز کامل نشد');
    }
    rethrow;
  }
  return staged.length;
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
                  if (!mounted || !ctx0.mounted) return;
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
                    if (!mounted || !ctx0.mounted || !ctx.mounted) return;
                    ScaffoldMessenger.maybeOf(ctx0)?.showSnackBar(SnackBar(
                        content: Text(
                            '$n مورد بازیابی شد. برای اعمال کامل، برنامه را ببندید و دوباره باز کنید.')));
                    Navigator.pop(ctx);
                  } catch (e) {
                    if (!mounted || !ctx0.mounted) return;
                    ScaffoldMessenger.maybeOf(ctx0)?.showSnackBar(
                        SnackBar(content: Text('بازیابی انجام نشد: $e')));
                  }
                },
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(restoreC.dispose);
  }
}
