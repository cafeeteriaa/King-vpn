// پوشه‌ی «سرورهای شخصی»
// ورودی‌ها در ژورنال دیسکی نگهداری می‌شوند؛ سقف ثابت تعداد/نمایش/پینگ نداریم.
// این مسیر مستقل از موجودی‌های Online و Offline باقی می‌ماند.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'prefs_store.dart';
import 'errjournal.dart';

const String _kPersonalFolderPref = 'personal_folder_v1';
const String _kPersonalLastGoodPref = 'personal_last_good_v1';
const String _kPersonalJournalName = 'personal_folder.jsonl';

/// Cache compatibility for existing UI and connection code. The durable
/// source of truth is the append-only disk journal, not SharedPreferences.
List<String> personalFolderCache = <String>[];
String personalLastGood = '';

Future<void>? _personalLoadTask;
Future<void> _personalWriteQueue = Future<void>.value();

Future<File> _personalJournal() async {
  final dir = await getApplicationSupportDirectory();
  if (!await dir.exists()) await dir.create(recursive: true);
  return File('${dir.path}/$_kPersonalJournalName');
}

Future<void> _enqueuePersonalWrite(Future<void> Function() action) {
  final previous = _personalWriteQueue;
  final release = Completer<void>();
  _personalWriteQueue = release.future;
  return () async {
    await previous;
    try {
      await action();
    } finally {
      release.complete();
    }
  }();
}

/// Load journal incrementally, recovering from malformed/torn individual rows.
/// Legacy SharedPreferences data is migrated once and then its old key is removed.
Future<void> loadPersonalFolder() => _personalLoadTask ??= _loadPersonalFolder();

Future<void> _loadPersonalFolder() async {
  try {
    final journal = await _personalJournal();
    final loaded = <String>[];
    final seen = <String>{};
    if (await journal.exists()) {
      await for (final line in journal
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        try {
          final row = jsonDecode(line);
          if (row is! Map || row['v'] != 1 || row['link'] is! String) continue;
          final link = (row['link'] as String).trim();
          if (link.isEmpty) continue;
          if (row['op'] == 'add') {
            if (seen.add(link)) loaded.add(link);
          } else if (row['op'] == 'remove') {
            if (seen.remove(link)) loaded.remove(link);
          }
        } catch (_) {
          // Skip a damaged record; later journal entries remain readable.
        }
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getStringList(_kPersonalFolderPref) ?? const <String>[];
      if (legacy.isNotEmpty) {
        final unique = <String>{};
        final rows = <String>[];
        for (final raw in legacy) {
          final link = raw.trim();
          if (link.isNotEmpty && unique.add(link)) {
            loaded.add(link);
            rows.add(jsonEncode(<String, Object>{'v': 1, 'op': 'add', 'link': link}));
          }
        }
        if (rows.isNotEmpty) {
          await journal.writeAsString('${rows.join('\n')}\n', flush: true);
          await prefs.remove(_kPersonalFolderPref);
        }
      }
    }
    personalFolderCache = loaded;
    final prefs = await SharedPreferences.getInstance();
    personalLastGood = prefs.getString(_kPersonalLastGoodPref) ?? '';
  } catch (e, stk) {
    errJournalAdd(e, kind: 'PERSONAL-FOLDER', st: stk);
  }
}

/// Record which personal server connected successfully.
Future<void> setPersonalLastGood(String link) async {
  personalLastGood = link.trim();
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPersonalLastGoodPref, personalLastGood);
  } catch (e, stk) {
    errJournalAdd(e, kind: 'PERSONAL-FOLDER', st: stk);
  }
}

/// Remove one exact link without rewriting the entire inventory.
Future<void> removeFromPersonalFolder(String link) async {
  await loadPersonalFolder();
  final normalized = link.trim();
  if (normalized.isEmpty || !personalFolderCache.contains(normalized)) return;
  try {
    final journal = await _personalJournal();
    await _enqueuePersonalWrite(() => journal.writeAsString(
      jsonEncode(<String, Object>{'v': 1, 'op': 'remove', 'link': normalized}) + '\n',
      mode: FileMode.append,
      flush: true,
    ));
  } catch (e, stk) {
    errJournalAdd(e, kind: 'PERSONAL-FOLDER', st: stk);
  }
  personalFolderCache.remove(normalized);
}

/// Add every distinct non-empty link. No fixed inventory cap or silent truncation.
Future<int> addToPersonalFolder(Iterable<String> links) async {
  await loadPersonalFolder();
  final seen = personalFolderCache.toSet();
  final addedLinks = <String>[];
  for (final raw in links) {
    final link = raw.trim();
    if (link.isNotEmpty && seen.add(link)) addedLinks.add(link);
  }
  if (addedLinks.isEmpty) return 0;
  try {
    final journal = await _personalJournal();
    final payload = '${addedLinks.map((link) => jsonEncode(
      <String, Object>{'v': 1, 'op': 'add', 'link': link},
    )).join('\n')}\n';
    await _enqueuePersonalWrite(() => journal.writeAsString(
      payload,
      mode: FileMode.append,
      flush: true,
    ));
  } catch (e, stk) {
    errJournalAdd(e, kind: 'PERSONAL-FOLDER', st: stk);
  }
  personalFolderCache.addAll(addedLinks);
  return addedLinks.length;
}
