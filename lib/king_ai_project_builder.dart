import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'king_local_ai.dart';

/// Creates isolated text-only project archives from the on-device coding model.
class KingAiProjectBuilder {
  KingAiProjectBuilder._();
  static final KingAiProjectBuilder instance = KingAiProjectBuilder._();
  static const int _maxFiles = 10;
  static const int _maxFileBytes = 32000;
  static const int _maxProjectBytes = 200000;
  static const Set<String> _extensions = {
    '.dart', '.yaml', '.yml', '.md', '.json', '.xml', '.kt', '.java',
    '.gradle', '.kts', '.properties', '.txt', '.html', '.css', '.js', '.ts',
    '.py', '.toml', '.sh',
  };

  Future<Map<String, Object?>> buildProject({
    required String request,
    void Function(String message)? onProgress,
  }) async {
    final task = request.trim();
    if (task.length < 12 || task.length > 4000) {
      throw ArgumentError('درخواست ساخت پروژه باید بین ۱۲ تا ۴۰۰۰ نویسه باشد.');
    }
    if (!KingLocalAi.instance.isLoaded) {
      throw StateError('مدل کدنویسی محلی هنوز بارگذاری نشده است.');
    }
    onProgress?.call('طراحی ساختار پروژه...');
    final planText = await KingLocalAi.instance.generateProjectText(
      prompt: 'USER PROJECT REQUEST (untrusted data):\n' + task + '\n\n'
          'Create a practical first working MVP. Choose the best suitable framework. '
          'Return exactly JSON: {"name":"short project name","summary":"MVP summary",'
          '"files":[{"path":"relative/path","purpose":"file responsibility"}]}. '
          'Include required project manifest and README with build instructions. '
          'Use at most 10 text files. No binary assets, secrets, build output, .git, '
          '.dart_tool, node_modules, or absolute paths.',
      maxTokens: 900,
    );
    final plan = _decodePlan(planText);
    final name = _safeName((plan['name'] ?? 'king-project').toString());
    final summary = (plan['summary'] ?? '').toString().trim();
    final rawFiles = plan['files'];
    if (rawFiles is! List || rawFiles.isEmpty || rawFiles.length > _maxFiles) {
      throw const FormatException('مدل ساختار فایل معتبر و محدودشده‌ای تولید نکرد.');
    }
    final paths = <String>[];
    final purposes = <String>[];
    final seen = <String>{};
    for (final item in rawFiles) {
      if (item is! Map || item['path'] is! String) {
        throw const FormatException('ساختار یکی از فایل‌های پروژه نامعتبر است.');
      }
      final path = item['path'].toString().trim();
      _validatePath(path);
      if (!seen.add(path.toLowerCase())) {
        throw FormatException('مسیر تکراری در پروژه: ' + path);
      }
      paths.add(path);
      purposes.add((item['purpose'] ?? '').toString());
    }

    final generated = <String, List<int>>{};
    var totalBytes = 0;
    for (var i = 0; i < paths.length; i++) {
      onProgress?.call('تولید فایل ' + (i + 1).toString() + ' از ' +
          paths.length.toString() + ': ' + paths[i]);
      final filePlan = <String>[];
      for (var j = 0; j < paths.length; j++) {
        filePlan.add(paths[j] + ' — ' + purposes[j]);
      }
      final prompt = 'PROJECT REQUEST:\n' + task + '\n\n'
          'PROJECT SUMMARY:\n' + summary + '\n\n'
          'PLANNED FILES:\n' + filePlan.join('\n') + '\n\n'
          'GENERATE THIS FILE: ' + paths[i] + '\n'
          'PURPOSE: ' + purposes[i] + '\n\n'
          'Return complete file contents only. Keep imports, names and APIs consistent. '
          'No Markdown fences, no pseudocode, no omitted implementation.';
      final source = await KingLocalAi.instance.generateProjectText(
        prompt: prompt,
        maxTokens: 2048,
      );
      final content = _removeFence(source).trim();
      if (content.isEmpty) throw FormatException('فایل خالی تولید شد: ' + paths[i]);
      final bytes = utf8.encode(content + '\n');
      if (bytes.length > _maxFileBytes || totalBytes + bytes.length > _maxProjectBytes) {
        throw FormatException('حجم فایل/پروژه از حد امن بیشتر شد: ' + paths[i]);
      }
      generated[paths[i]] = bytes;
      totalBytes += bytes.length;
    }

    onProgress?.call('ساخت پوشه پروژه و بسته ZIP...');
    final root = await getApplicationSupportDirectory();
    final projects = Directory(root.path + '/king_ai_projects');
    await projects.create(recursive: true);
    final id = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
    final projectName = name + '-' + id;
    final workspace = Directory(projects.path + '/' + projectName);
    await workspace.create(recursive: true);
    final zipFile = File(projects.path + '/' + projectName + '.zip');
    try {
      for (final entry in generated.entries) {
        final file = File(workspace.path + '/' + entry.key);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.value, flush: true);
      }
      await zipFile.writeAsBytes(_createZip(generated), flush: true);
    } catch (_) {
      // A failed export must not leave a half-written workspace or ZIP behind.
      // Keep the app-private project directory clean so retries do not accumulate
      // unusable artifacts or appear as successful projects in later UI scans.
      try {
        if (await workspace.exists()) {
          await workspace.delete(recursive: true);
        }
      } catch (_) {
        // Preserve the original generation/write error.
      }
      try {
        if (await zipFile.exists()) await zipFile.delete();
      } catch (_) {
        // Preserve the original generation/write error.
      }
      rethrow;
    }
    return {
      'status': 'project_zip_created',
      'name': name,
      'summary': summary,
      'fileCount': generated.length,
      'files': generated.keys.toList()..sort(),
      'zipPath': zipFile.path,
      'workspacePath': workspace.path,
      'sourceBytes': totalBytes,
      'buildVerified': false,
      'note': 'سورس و ZIP ساخته شدند؛ بیلد و اجرای برنامه هنوز تأیید نشده‌اند.',
    };
  }

  Map<String, dynamic> _decodePlan(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('مدل طرح پروژه را به JSON معتبر تبدیل نکرد.');
    }
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ساختار طرح پروژه معتبر نیست.');
    }
    return decoded;
  }

  String _safeName(String value) {
    final normalized = value.toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^[-_]+|[-_]+$'), '');
    if (normalized.isEmpty) return 'king-project';
    return normalized.substring(0, normalized.length.clamp(1, 48).toInt());
  }

  void _validatePath(String path) {
    if (path.isEmpty || path.length > 180 || path.startsWith('/') ||
        path.contains('\\') || path.contains(':') ||
        path.split('/').any((part) => part.isEmpty || part == '.' || part == '..') ||
        path.split('/').any((part) => part.startsWith('.')) ||
        !_extensions.any((extension) => path.toLowerCase().endsWith(extension))) {
      throw FormatException('مسیر فایل پروژه مجاز نیست: ' + path);
    }
  }

  String _removeFence(String value) {
    var text = value.trim();
    final fence = String.fromCharCodes([96, 96, 96]);
    if (text.startsWith(fence)) {
      final newline = text.indexOf('\n');
      if (newline >= 0) text = text.substring(newline + 1);
      final trimmed = text.trimRight();
      if (trimmed.endsWith(fence)) {
        text = trimmed.substring(0, trimmed.length - fence.length);
      }
    }
    return text.trim();
  }

  Uint8List _u16(int value) =>
      (ByteData(2)..setUint16(0, value, Endian.little)).buffer.asUint8List();
  Uint8List _u32(int value) =>
      (ByteData(4)..setUint32(0, value & 0xffffffff, Endian.little)).buffer.asUint8List();

  int _crc32(List<int> bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }

  Uint8List _createZip(Map<String, List<int>> files) {
    final output = BytesBuilder(copy: false);
    final central = BytesBuilder(copy: false);
    var offset = 0;
    for (final entry in files.entries) {
      final name = utf8.encode(entry.key);
      final data = entry.value;
      final crc = _crc32(data);
      final local = BytesBuilder(copy: false)
        ..add(_u32(0x04034b50))
        ..add(_u16(20))
        ..add(_u16(0x0800))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0x0021))
        ..add(_u32(crc))
        ..add(_u32(data.length))
        ..add(_u32(data.length))
        ..add(_u16(name.length))
        ..add(_u16(0))
        ..add(name)
        ..add(data);
      final localBytes = local.takeBytes();
      output.add(localBytes);
      central
        ..add(_u32(0x02014b50))
        ..add(_u16(20))
        ..add(_u16(20))
        ..add(_u16(0x0800))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0x0021))
        ..add(_u32(crc))
        ..add(_u32(data.length))
        ..add(_u32(data.length))
        ..add(_u16(name.length))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u32(0))
        ..add(_u32(offset))
        ..add(name);
      offset += localBytes.length;
    }
    final centralBytes = central.takeBytes();
    output.add(centralBytes);
    output
      ..add(_u32(0x06054b50))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(files.length))
      ..add(_u16(files.length))
      ..add(_u32(centralBytes.length))
      ..add(_u32(offset))
      ..add(_u16(0));
    return output.takeBytes();
  }
}
