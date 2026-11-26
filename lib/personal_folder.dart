// پوشهٔ سرورهای شخصی — مستقل از Online و Offline
// لینک‌های واردشده، دستی، تولیدشده با Cloudflare و سرورهای شخصی دیگر
// در فایل JSONL اختصاصی نگهداری می‌شوند؛ ظرفیت مصنوعی یا سقف تعداد وجود ندارد.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'prefs_store.dart';
import 'errjournal.dart';

const String _kPersonalFolderPref = 'personal_folder_v1';
const String _kPersonalLastGoodPref = 'personal_last_good_v1';

/// حافظهٔ سریع برای UI و منطق اتصال؛ منبع پایدار، ژورنال دیسکی است.
List<String> personalFolderCache = <String>[];
final Set<String> _personalFolderIndex = <String>{};
String personalLastGood = '';

Future<void> _personalFolderWriteQueue = Future<void>.value();
Future<void>? _personalFolderLoadTask;
bool _personalFolderLoaded = false;

Future<T> _serializePersonalMutation<T>(Future<T> Function() action) {
  final operation = _personalFolderWriteQueue.then<T>((_) => action());
  _personalFolderWriteQueue = operation.then<void>(
    (_) {},
    onError: (Object error, StackTrace stackTrace) {},
  );
  return operation;
}

Future<Directory> _personalFolderDirectory() async {
  final root = await getApplicationSupportDirectory();
  final dir = Directory('${root.path}/KingVPN/PersonalServers');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

Future<File> _personalFolderJournal() async =>
    File('${(await _personalFolderDirectory()).path}/personal_servers.jsonl');

Future<void> _appendPersonalEventsUnlocked(
  Iterable<Map<String, Object?>> events,
) async {
  final file = await _personalFolderJournal();
  final lockFile = await File('${file.path}.lock').open(mode: FileMode.append);
  var locked = false;
  try {
    await lockFile.lock(FileLock.exclusive);
    locked = true;
    final out = await file.open(mode: FileMode.append);
    try {
      for (final event in events) {
        await out.writeString(jsonEncode(<String, Object>{
          'v': 1,
          ...event,
          'at': DateTime.now().toUtc().toIso8601String(),
        }) + '\n');
      }
      await out.flush();
    } finally {
      await out.close();
    }
  } finally {
    try {
      if (locked) await lockFile.unlock();
    } finally {
      await lockFile.close();
    }
  }
}

/// ژورنال را به‌صورت streaming replay می‌کند؛ خط ناقص/خراب فقط همان رکورد را رد می‌کند.
Future<void> _replayPersonalJournal(File file) async {
  await for (final line in file
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map || decoded['v'] != 1) continue;
      final op = decoded['op'];
      final link = decoded['link'];
      if (op is! String || link is! String || link.trim().isEmpty) continue;
      final value = link.trim();
      if (op == 'add') {
        if (_personalFolderIndex.add(value)) personalFolderCache.add(value);
      } else if (op == 'remove') {
        if (_personalFolderIndex.remove(value)) {
          personalFolderCache.remove(value);
        }
      }
    } catch (e, stk) {
      errJournalAdd(e, st: stk, kind: 'PERSONAL-FOLDER-ROW');
    }
  }
}

/// پوشه و آخرین سرور سالم را از ژورنال دیسکی می‌خواند و SharedPreferences قدیمی را مهاجرت می‌دهد.
Future<void> loadPersonalFolder() async {
  if (_personalFolderLoaded) return;
  final active = _personalFolderLoadTask;
  if (active != null) return active;
  final task = _serializePersonalMutation(() async {
    try {
      personalFolderCache = <String>[];
      _personalFolderIndex.clear();
      final file = await _personalFolderJournal();
      if (await file.exists()) await _replayPersonalJournal(file);

      // One-time migration from the previous SharedPreferences string-list store.
      final p = await SharedPreferences.getInstance();
      final legacy = p.getStringList(_kPersonalFolderPref) ?? const <String>[];
      final migrate = <String>[];
      final migrateSeen = <String>{};
      for (final raw in legacy) {
        final value = raw.trim();
        if (value.isNotEmpty && !_personalFolderIndex.contains(value) &&
            migrateSeen.add(value)) {
          migrate.add(value);
        }
      }
      if (migrate.isNotEmpty) {
        await _appendPersonalEventsUnlocked([
          for (final value in migrate) <String, Object?>{'op': 'add', 'link': value},
        ]);
        personalFolderCache.addAll(migrate);
        _personalFolderIndex.addAll(migrate);
      }
      if (legacy.isNotEmpty) await p.remove(_kPersonalFolderPref);

      final lg = p.getStringList(_kPersonalLastGoodPref) ?? const <String>[];
      personalLastGood = lg.isEmpty ? '' : lg.first.trim();
      _personalFolderLoaded = true;
    } catch (e, stk) {
      errJournalAdd(e, st: stk, kind: 'PERSONAL-FOLDER');
      _personalFolderLoaded = false;
      rethrow;
    }
  });
  _personalFolderLoadTask = task;
  try {
    await task;
  } catch (_) {
    _personalFolderLoadTask = null;
    rethrow;
  }
}

/// ثبت می‌کند کدام سرور وصل شد.
Future<void> setPersonalLastGood(String link) async {
  personalLastGood = link.trim();
  try {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kPersonalLastGoodPref, [personalLastGood]);
  } catch (e, stk) {
    errJournalAdd(e, st: stk, kind: 'PERSONAL-FOLDER');
  }
}

/// یک لینک را از پوشه حذف می‌کند؛ حذف نیز به‌صورت رویداد پایدار ثبت می‌شود.
Future<void> removeFromPersonalFolder(String link) async {
  await loadPersonalFolder();
  final value = link.trim();
  if (value.isEmpty) return;
  try {
    await _serializePersonalMutation(() async {
      if (!_personalFolderIndex.contains(value)) return;
      await _appendPersonalEventsUnlocked([
        <String, Object?>{'op': 'remove', 'link': value},
      ]);
      _personalFolderIndex.remove(value);
      personalFolderCache.remove(value);
    });
  } catch (e, stk) {
    errJournalAdd(e, st: stk, kind: 'PERSONAL-FOLDER');
  }
}

/// لینک‌ها را بدون سقف مصنوعی اضافه می‌کند؛ تکراری‌ها فقط یک‌بار ذخیره می‌شوند.
Future<int> addToPersonalFolder(Iterable<String> links) async {
  await loadPersonalFolder();
  return _serializePersonalMutation(() async {
    final added = <String>[];
    final batchSeen = <String>{};
    for (final raw in links) {
      final value = raw.trim();
      if (value.isEmpty || _personalFolderIndex.contains(value) ||
          !batchSeen.add(value)) {
        continue;
      }
      added.add(value);
    }
    if (added.isEmpty) return 0;
    try {
      await _appendPersonalEventsUnlocked([
        for (final value in added) <String, Object?>{'op': 'add', 'link': value},
      ]);
      personalFolderCache.addAll(added);
      _personalFolderIndex.addAll(added);
      return added.length;
    } catch (e, stk) {
      errJournalAdd(e, st: stk, kind: 'PERSONAL-FOLDER');
      return 0;
    }
  });
}
