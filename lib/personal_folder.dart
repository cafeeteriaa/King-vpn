// پوشه‌ی «سرورهای شخصی»
// هر سروری که خودت به برنامه می‌دهی، و هر سروری که با «ساخت خودکار کلودفلر»
// ساخته‌ای، به این پوشه اضافه می‌شود. همهٔ ورودی‌های معتبر نگهداری می‌شوند.
// بررسی سلامت و انتخاب اتصال، به کل ورودی‌های معتبر دسترسی دارد.

import 'prefs_store.dart';
import 'personal_folder_store.dart';
import 'errjournal.dart';

const String _kPersonalFolderPref = 'personal_folder_v1';

// Serialize load/add/remove/last-good writes so concurrent operations cannot
// overwrite each other's snapshots or cache state.
Future<void> _personalMutationQueue = Future<void>.value();

Future<T> _serializePersonalMutation<T>(Future<T> Function() action) {
  final operation = _personalMutationQueue.then<T>((_) => action());
  _personalMutationQueue = operation.then<void>(
    (_) {},
    onError: (Object error, StackTrace stackTrace) {},
  );
  return operation;
}

/// کش درون‌حافظه‌ای لینک‌های پوشه (برای نمایش سریع در صفحه‌ی اصلی)
List<String> personalFolderCache = <String>[];

/// آخرین سروری که با موفقیت وصل شد (اولین انتخاب دفعه‌ی بعد، بدون تست پینگ)
String personalLastGood = '';
const String _kPersonalLastGoodPref = 'personal_last_good_v1';

/// پوشه و آخرین سرور سالم را از حافظه می‌خواند. خطا = پوشه‌ی خالی، برنامه بالا می‌آید.
Future<void> loadPersonalFolder() {
  return _serializePersonalMutation(() async {
    try {
      final p = await SharedPreferences.getInstance();
      final hasLegacy = p.containsKey(_kPersonalFolderPref);
      final loaded = await PersonalFolderStore.readOrMigrate(() async {
        return p.getStringList(_kPersonalFolderPref) ?? const <String>[];
      });
      personalFolderCache = loaded;

      if (hasLegacy) {
        // The durable file is already committed. If preference cleanup fails,
        // the file remains authoritative and the legacy copy is harmless.
        await p.remove(_kPersonalFolderPref);
        await p.flush();
      }
      final lg = p.getStringList(_kPersonalLastGoodPref) ?? const <String>[];
      personalLastGood = lg.isEmpty ? '' : lg.first;
    } catch (e, stk) {
      errJournalAdd(e, kind: 'PERSONAL-FOLDER', st: stk);
    }
  });
}

/// ثبت می‌کند کدام سرور وصل شد
Future<void> setPersonalLastGood(String link) {
  return _serializePersonalMutation(() async {
    personalLastGood = link.trim();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kPersonalLastGoodPref, [personalLastGood]);
    } catch (e, stk) {
      errJournalAdd(e, kind: 'PERSONAL-FOLDER', st: stk);
    }
  });
}

/// یک لینک را از پوشه حذف می‌کند. کش فقط پس از commit موفق تغییر می‌کند.
Future<void> removeFromPersonalFolder(String link) {
  return _serializePersonalMutation(() async {
    try {
      final removed = await PersonalFolderStore.removeLinks([link]);
      if (removed == 0) return;
      final normalized = link.trim().toLowerCase();
      personalFolderCache.removeWhere(
        (entry) => entry.trim().toLowerCase() == normalized,
      );
    } catch (e, stk) {
      errJournalAdd(e, kind: 'PERSONAL-FOLDER', st: stk);
    }
  });
}

/// لینک‌ها را اضافه می‌کند؛ فقط ورودی خالی و تکراری نادیده گرفته می‌شود.
/// تعداد سرورهای تازه‌ثبت‌شده را فقط پس از ذخیره‌ی موفق برمی‌گرداند.
Future<int> addToPersonalFolder(Iterable<String> links) {
  final input = List<String>.of(links);
  return _serializePersonalMutation(() async {
    try {
      final committed = await PersonalFolderStore.appendLinks(input);
      if (committed.isEmpty) return 0;
      // Keep the legacy UI cache coherent while the store performs the durable
      // mutation with bounded-memory streaming rather than snapshot rebuilding.
      personalFolderCache.addAll(committed);
      return committed.length;
    } catch (e, stk) {
      errJournalAdd(e, kind: 'PERSONAL-FOLDER', st: stk);
      return 0;
    }
  });
}
