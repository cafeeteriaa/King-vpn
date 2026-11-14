// پوشه‌ی «سرورهای شخصی»
// هر سروری که خودت به برنامه می‌دهی، و هر سروری که با «ساخت خودکار کلودفلر»
// ساخته‌ای، به این پوشه اضافه می‌شود. تا ۱۰۰۰ سرور ذخیره می‌شود.
// اتصال از این پوشه: ۵۰ سرور اول پینگ گرفته می‌شود و به بهترینش وصل می‌شود.

import 'package:shared_preferences/shared_preferences.dart';

import 'errjournal.dart';

const int kPersonalFolderCap = 1000;
const String _kPersonalFolderPref = 'personal_folder_v1';

/// کش درون‌حافظه‌ای لینک‌های پوشه (برای نمایش سریع در صفحه‌ی اصلی)
List<String> personalFolderCache = <String>[];

/// پوشه را از حافظه می‌خواند. خطا = پوشه‌ی خالی، برنامه بالا می‌آید.
Future<void> loadPersonalFolder() async {
  try {
    final p = await SharedPreferences.getInstance();
    personalFolderCache =
        List<String>.of(p.getStringList(_kPersonalFolderPref) ?? const <String>[]);
  } catch (e, stk) {
    errJournalAdd(e, kind: 'PERSONAL-FOLDER', st: stk);
  }
}

/// لینک‌ها را به پوشه اضافه می‌کند (تکراری‌ها نادیده گرفته می‌شوند، تا سقف ۱۰۰۰).
/// تعداد سرورهای تازه‌اضافه‌شده را برمی‌گرداند.
Future<int> addToPersonalFolder(Iterable<String> links) async {
  var added = 0;
  final set = personalFolderCache.toSet();
  for (final l in links) {
    final t = l.trim();
    if (t.isEmpty || set.contains(t)) continue;
    if (personalFolderCache.length >= kPersonalFolderCap) break;
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
