// پوشه‌ی «سرورهای شخصی»
// هر سروری که خودت به برنامه می‌دهی، و هر سروری که با «ساخت خودکار کلودفلر»
// ساخته‌ای، به این پوشه اضافه می‌شود. همهٔ ورودی‌های معتبر نگهداری می‌شوند.
// بررسی سلامت و انتخاب اتصال، همهٔ ورودی‌ها را به‌صورت تدریجی پردازش می‌کند.

// از همان لایه‌ی ذخیره‌ی برنامه استفاده می‌کند (پکیج shared_preferences در پروژه نیست)
import 'prefs_store.dart';
import 'errjournal.dart';

const String _kPersonalFolderPref = 'personal_folder_v1';

/// کش درون‌حافظه‌ای لینک‌های پوشه (برای نمایش سریع در صفحه‌ی اصلی)
List<String> personalFolderCache = <String>[];

/// آخرین سروری که با موفقیت وصل شد (اولین انتخاب دفعه‌ی بعد، بدون تست پینگ)
String personalLastGood = '';
const String _kPersonalLastGoodPref = 'personal_last_good_v1';

/// پوشه و آخرین سرور سالم را از حافظه می‌خواند. خطا = پوشه‌ی خالی، برنامه بالا می‌آید.
Future<void> loadPersonalFolder() async {
  try {
    final p = await SharedPreferences.getInstance();
    personalFolderCache =
        List<String>.of(p.getStringList(_kPersonalFolderPref) ?? const <String>[]);
    final lg = p.getStringList(_kPersonalLastGoodPref) ?? const <String>[];
    personalLastGood = lg.isEmpty ? '' : lg.first;
  } catch (e, stk) {
    errJournalAdd(e, kind: 'PERSONAL-FOLDER', st: stk);
  }
}

/// ثبت می‌کند کدام سرور وصل شد
Future<void> setPersonalLastGood(String link) async {
  personalLastGood = link.trim();
  try {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kPersonalLastGoodPref, [personalLastGood]);
  } catch (e, stk) {
    errJournalAdd(e, kind: 'PERSONAL-FOLDER', st: stk);
  }
}

/// یک لینک را از پوشه حذف می‌کند
Future<void> removeFromPersonalFolder(String link) async {
  personalFolderCache.remove(link.trim());
  try {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kPersonalFolderPref, personalFolderCache);
  } catch (e, stk) {
    errJournalAdd(e, kind: 'PERSONAL-FOLDER', st: stk);
  }
}

/// لینک‌ها را به پوشه اضافه می‌کند؛ فقط ورودی خالی و تکراری نادیده گرفته می‌شود.
/// تعداد سرورهای تازه‌اضافه‌شده را برمی‌گرداند.
Future<int> addToPersonalFolder(Iterable<String> links) async {
  var added = 0;
  final set = personalFolderCache.toSet();
  for (final l in links) {
    final t = l.trim();
    if (t.isEmpty || set.contains(t)) continue;
    personalFolderCache.add(t);
    set.add(t);
    added++;
  }
  if (added == 0) return 0;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kPersonalFolderPref, personalFolderCache);
  } catch (e, stk) {
    errJournalAdd(e, kind: 'PERSONAL-FOLDER', st: stk);
  }
  return added;
}
