// پوشه‌ی «سرورهای شخصی»
// آرشیو کامل روی دیسک نگهداری می‌شود؛ این کش فقط پنجره‌ی نمایشی اول است.
// عملیات افزودن/حذف به‌صورت جریانی و تراکنشی انجام می‌شوند.

import 'prefs_store.dart';
import 'personal_folder_store.dart';
import 'errjournal.dart';

const String _kPersonalFolderPref = 'personal_folder_v1';

Future<void> _personalMutationQueue = Future<void>.value();

Future<T> _serializePersonalMutation<T>(Future<T> Function() action) {
  final operation = _personalMutationQueue.then<T>((_) => action());
  _personalMutationQueue = operation.then<void>(
    (_) {},
    onError: (Object error, StackTrace stackTrace) {},
  );
  return operation;
}

/// فقط صفحه‌ی اول برای سازگاری رابط‌های قدیمی؛ آرشیو کامل اینجا نگهداری نمی‌شود.
List<String> personalFolderCache = <String>[];
int personalFolderCount = 0;
int personalFolderRevision = 0;
Future<void> Function()? personalFolderIndexRefresh;

/// آخرین سروری که با موفقیت وصل شد.
String personalLastGood = '';
const String _kPersonalLastGoodPref = 'personal_last_good_v1';

Future<void> _refreshPersonalFolderView() async {
  final page = await PersonalFolderStore.readPage(limit: 50);
  personalFolderCount = page.totalCount;
  personalFolderCache = List<String>.of(page.items);
  personalFolderRevision++;
  await personalFolderIndexRefresh?.call();
}

/// مهاجرت legacy فقط یک بار انجام می‌شود؛ پس از آن بارگذاری فقط count و یک صفحه است.
Future<void> loadPersonalFolder() {
  return _serializePersonalMutation(() async {
    try {
      final p = await SharedPreferences.getInstance();
      final hasLegacy = p.containsKey(_kPersonalFolderPref);
      if (!await PersonalFolderStore.hasValidSnapshot()) {
        final legacy = p.getStringList(_kPersonalFolderPref) ?? const <String>[];
        await PersonalFolderStore.writeSnapshot(legacy);
      }
      await _refreshPersonalFolderView();
      if (hasLegacy) {
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

/// ثبت می‌کند کدام سرور وصل شد.
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

/// حذف مستقیم از آرشیو دیسکی؛ هیچ کپی کامل از پوشه ساخته نمی‌شود.
Future<void> removeFromPersonalFolder(String link) {
  return _serializePersonalMutation(() async {
    try {
      final removed = await PersonalFolderStore.removeLink(link);
      if (removed) await _refreshPersonalFolderView();
    } catch (e, stk) {
      errJournalAdd(e, kind: 'PERSONAL-FOLDER', st: stk);
    }
  });
}

/// افزودن مستقیم و تراکنشی؛ فقط ورودی تازه در حافظه نگهداری می‌شود.
Future<int> addToPersonalFolder(Iterable<String> links) {
  final input = List<String>.of(links);
  return _serializePersonalMutation(() async {
    try {
      final added = await PersonalFolderStore.appendAll(input);
      if (added > 0) await _refreshPersonalFolderView();
      return added;
    } catch (e, stk) {
      errJournalAdd(e, kind: 'PERSONAL-FOLDER', st: stk);
      return 0;
    }
  });
}
