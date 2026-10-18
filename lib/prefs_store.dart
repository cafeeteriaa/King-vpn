import 'dart:convert';
import 'dart:io';

// Replacement for the shared_preferences plugin. On this build the plugin's
// Android side throws NoSuchMethodError on every call, so the plugin is removed
// from the build and the app keeps its settings in one JSON file instead.
// The class keeps the same name and the same method signatures, so the rest of
// the code does not change.
class SharedPreferences {
  SharedPreferences._(this._file, this._data);

  static const String _dirPath = '/data/data/com.kingvpn.king_vpn/files';
  static SharedPreferences? _inst;

  final File _file;
  final Map<String, dynamic> _data;

  static Future<SharedPreferences> getInstance() async {
    final cached = _inst;
    if (cached != null) return cached;
    File f;
    try {
      final dir = Directory(_dirPath);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      f = File('$_dirPath/prefs.json');
    } catch (_) {
      f = File('${Directory.systemTemp.path}/prefs.json');
    }
    Map<String, dynamic> data = <String, dynamic>{};
    try {
      if (f.existsSync()) {
        final m = jsonDecode(f.readAsStringSync());
        if (m is Map) data = Map<String, dynamic>.from(m);
      }
    } catch (_) {
      data = <String, dynamic>{};
    }
    _inst = SharedPreferences._(f, data);
    return _inst!;
  }

  void _save() {
    try {
      _file.writeAsStringSync(jsonEncode(_data));
    } catch (_) {}
  }

  bool containsKey(String key) => _data.containsKey(key);

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
