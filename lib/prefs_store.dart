import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'errjournal.dart';
import 'dart:io';

// Replacement for the shared_preferences plugin. On this build the plugin's
// Android side throws NoSuchMethodError on every call, so the plugin is removed
// from the build and the app keeps its settings in one JSON file instead.
// The class keeps the same name and the same method signatures, so the rest of
// the code does not change.
//
// SECURITY-PASS: The stored data (UUIDs, API keys, server configs) is now
// obfuscated/encrypted using a byte-level XOR mask before being written to disk.
class SharedPreferences {
  SharedPreferences._(this._file, this._data);

  static const String _dirPath = '/data/data/com.kingvpn.king_vpn/files';
  static SharedPreferences? _inst;
  
  // SECURITY: single-byte XOR mask to prevent casual reading of plain UUIDs/Keys
  static const int _xorKey = 0x5A;

  final File _file;
  final Map<String, dynamic> _data;

  // فیکس ۲ (پرفورمنس): نوشتن روی دیسک debounce می‌شود (۲ ثانیه) و کلیدهای حجیم در
  // فایل‌های جانبی جدا نگه داشته می‌شوند؛ در حافظه همه‌چیز همان یک Map است.
  bool _dirty = false;
  Timer? _saveT;
  static const int _splitMinBytes = 256 * 1024;
  static const Map<String, List<String>> _sideFiles = {
    'prefs_cache.json': ['cache', 'list_cache'],
    'prefs_logs.json': ['dbgLines', 'dbgProbs3'],
    'prefs_nat.json': ['natvar2'],
  };
  final Map<String, String> _lastWritten = <String, String>{};

  static Future<SharedPreferences> getInstance() async {
    final cached = _inst;
    if (cached != null) return cached;
    File f;
    try {
      final dir = Directory(_dirPath);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      f = File('$_dirPath/prefs.json');
    } catch (jex, jstk) { errJournalAdd(jex, st: jstk);
      f = File('${Directory.systemTemp.path}/prefs.json');
    }
    Map<String, dynamic> data = <String, dynamic>{};
    try {
      if (f.existsSync()) {
        final rawBytes = f.readAsBytesSync();
        if (rawBytes.isNotEmpty) {
          // SECURITY: Decode XOR mask
          final decryptedBytes = rawBytes.map((b) => b ^ _xorKey).toList();
          final m = jsonDecode(utf8.decode(decryptedBytes));
          if (m is Map) data = Map<String, dynamic>.from(m);
        }
      }
    } catch (jex, jstk) { errJournalAdd(jex, st: jstk);
      // Migration fallback: if the old file was plain JSON, try reading it raw once
      try {
        final rawStr = f.readAsStringSync();
        final m = jsonDecode(rawStr);
        if (m is Map) {
          data = Map<String, dynamic>.from(m);
          // We'll save it back encrypted on the next _save() call
        }
      } catch (_) {
        data = <String, dynamic>{};
      }
    }
    // فیکس ۲: لود فایل‌های جانبی و merge در همان Map (جانبی‌ها بر کلید قدیمی در فایل اصلی غلبه دارند)
    bool needSplit = false;
    try {
      final dirPath = f.parent.path;
      for (final e in _sideFiles.entries) {
        final sf = File('$dirPath/${e.key}');
        if (!sf.existsSync()) continue;
        try {
          final b = sf.readAsBytesSync();
          if (b.isEmpty) continue;
          final m = jsonDecode(utf8.decode(b.map((x) => x ^ _xorKey).toList()));
          if (m is Map) {
            for (final k in e.value) {
              if (m.containsKey(k)) data[k] = m[k];
            }
          }
        } catch (jex, jstk) { errJournalAdd(jex, st: jstk); }
      }
      // فایل اصلی بزرگ (>= 256KB) و هنوز تقسیم‌نشده: در اولین ذخیره‌ی debounce شده تقسیم می‌شود
      if (f.existsSync() && f.lengthSync() >= _splitMinBytes) needSplit = true;
    } catch (jex, jstk) { errJournalAdd(jex, st: jstk); }
    _inst = SharedPreferences._(f, data);
    if (needSplit) _inst!._save();
    return _inst!;
  }

  // فیکس ۲: همگام و ارزان؛ فقط علامت می‌گذارد و debounce را آماده می‌کند
  void _save() {
    _dirty = true;
    _saveSoon();
  }

  void _saveSoon() {
    _saveT ??= Timer(const Duration(seconds: 2), () {
      _saveT = null;
      if (!_dirty) return;
      _dirty = false;
      _writeAll();
    });
  }

  // منطق نوشتن (همان بدنه‌ی قبلی callback دیبانس) تا هم تایمر و هم flush() از آن استفاده کنند
  void _writeAll() {
    try {
      // کلیدها به چهار دسته تقسیم می‌شوند: فایل اصلی + سه فایل جانبی
      final Map<String, Map<String, dynamic>> parts = {
        for (final n in _sideFiles.keys) n: <String, dynamic>{},
      };
      final Map<String, dynamic> main = <String, dynamic>{};
      final Map<String, String> owner = {
        for (final e in _sideFiles.entries)
          for (final k in e.value) k: e.key,
      };
      _data.forEach((k, v) {
        final o = owner[k];
        if (o == null) {
          main[k] = v;
        } else {
          parts[o]![k] = v;
        }
      });
      final dirPath = _file.parent.path;
      final Map<String, Map<String, dynamic>> jobs = {
        _file.path: main,
        for (final e in parts.entries) '$dirPath/${e.key}': e.value,
      };
      jobs.forEach((path, map) {
        try {
          final jsonString = jsonEncode(map);
          // فایل جانبی بدون تغییر (و خالی) دوباره نوشته نمی‌شود
          if (_lastWritten[path] == jsonString) return;
          final rawBytes = utf8.encode(jsonString);
          // SECURITY: Encode XOR mask before writing to disk
          final enc = Uint8List(rawBytes.length);
          for (var i = 0; i < rawBytes.length; i++) {
            enc[i] = rawBytes[i] ^ _xorKey;
          }
          // اتمیک: اول فایل موقت با flush، بعد rename (فایل اصلی هیچ‌وقت نیمه‌نوشته نمی‌ماند)
          final tmp = File('$path.tmp');
          tmp.writeAsBytesSync(enc, flush: true);
          tmp.renameSync(path);
          _lastWritten[path] = jsonString;
        } catch (jex, jstk) { errJournalAdd(jex, st: jstk); }
      });
    } catch (jex, jstk) { errJournalAdd(jex, st: jstk);}
  }

  // همگام‌سازی فوری روی دیسک (مثلاً هنگام paused/detached) تا ۲ ثانیه‌ی debounce داده از دست ندهد.
  // همان منطق debounce را (شامل فایل‌های جانبی، XOR و rename اتمیک) صدا می‌زند.
  Future<void> flush() async {
    _saveT?.cancel();
    _saveT = null;
    if (!_dirty) return;
    _dirty = false;
    try {
      _writeAll();
    } catch (e) {
      errJournalAdd(e, kind: 'SILENT-FILE');
    }
  }

  bool containsKey(String key) => _data.containsKey(key);

  Set<String> getKeys() => _data.keys.toSet();

  Object? get(String key) => _data[key];

  bool? getBool(String key) {
    final v = _data[key];
    return v is bool ? v : null;
  }

  int? getInt(String key) {
    final v = _data[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  double? getDouble(String key) {
    final v = _data[key];
    return v is num ? v.toDouble() : null;
  }

  String? getString(String key) {
    final v = _data[key];
    return v is String ? v : null;
  }

  List<String>? getStringList(String key) {
    final v = _data[key];
    if (v is List) return v.map((e) => e.toString()).toList();
    return null;
  }

  Future<bool> setBool(String key, bool value) async {
    _data[key] = value;
    _save();
    return true;
  }

  Future<bool> setInt(String key, int value) async {
    _data[key] = value;
    _save();
    return true;
  }

  Future<bool> setDouble(String key, double value) async {
    _data[key] = value;
    _save();
    return true;
  }

  Future<bool> setString(String key, String value) async {
    _data[key] = value;
    _save();
    return true;
  }

  Future<bool> setStringList(String key, List<String> value) async {
    _data[key] = List<String>.from(value);
    _save();
    return true;
  }

  Future<bool> remove(String key) async {
    _data.remove(key);
    _save();
    return true;
  }
}
