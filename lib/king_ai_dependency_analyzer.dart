import 'dart:convert';

/// Static, dependency-free import graph for Dart and Python source supplied
/// to an owner repair task. Unresolved SDK/package imports remain explicit.
class KingAiDependencyAnalyzer {
  KingAiDependencyAnalyzer._();

  static Map<String, Object?> analyze(Map<String, String> sourceFiles) {
    final paths = sourceFiles.keys.toSet();
    final edges = <String, List<String>>{};
    final unresolved = <String, List<String>>{};
    for (final entry in sourceFiles.entries) {
      final path = entry.key;
      final imports = path.endsWith('.dart')
          ? _dartImports(entry.value)
          : path.endsWith('.py')
              ? _pythonImports(entry.value, path)
              : const <String>[];
      final resolved = <String>{};
      final missing = <String>{};
      for (final target in imports) {
        final candidate = _resolve(path, target, paths);
        if (candidate == null) {
          if (!_isExternal(target)) missing.add(target);
        } else if (candidate != path) {
          resolved.add(candidate);
        }
      }
      edges[path] = resolved.toList()..sort();
      if (missing.isNotEmpty) unresolved[path] = missing.toList()..sort();
    }
    return {'files': paths.length, 'edges': edges, 'unresolved': unresolved, 'cycles': _cycles(edges)};
  }

  static List<String> _dartImports(String source) {
    final result = <String>[];
    final pattern = RegExp(r'''(?:import|export|part)\s+['"]([^'"]+)['"]''');
    for (final match in pattern.allMatches(source)) {
      final value = match.group(1);
      if (value != null) result.add(value);
    }
    return result;
  }

  static List<String> _pythonImports(String source, String path) {
    final result = <String>[];
    final package = path.split('/')..removeLast();
    for (final line in const LineSplitter().convert(source)) {
      final from = RegExp(r'^\s*from\s+([.\w]+)\s+import\s+(.+)$').firstMatch(line);
      if (from != null) {
        var module = from.group(1)!;
        var dots = 0;
        while (dots < module.length && module.codeUnitAt(dots) == 46) { dots++; }
        module = module.substring(dots).replaceAll('.', '/');
        final base = List<String>.from(package);
        for (var i = 1; i < dots; i++) {
          if (base.isNotEmpty) base.removeLast();
        }
        final prefix = [...base, if (module.isNotEmpty) module].join('/');
        for (final imported in from.group(2)!.split(',')) {
          final name = imported.trim().split(RegExp(r'\s+')).first;
          if (name.isEmpty || name == '*') continue;
          result.add(prefix.isEmpty ? name : '$prefix/$name');
        }
        if (module.isNotEmpty && prefix.isNotEmpty) result.add(prefix);
        continue;
      }
      for (final match in RegExp(r'^\s*import\s+([.\w]+)').allMatches(line)) {
        result.add(match.group(1)!.replaceAll('.', '/'));
      }
    }
    return result;
  }

  static bool _isExternal(String target) {
    if (target.startsWith('dart:') || target.startsWith('http:') || target.startsWith('https:')) return true;
    if (target.startsWith('package:')) return !target.startsWith('package:king_vpn/');
    return !target.startsWith('.') && !target.contains('/');
  }

  static String? _resolve(String sourcePath, String target, Set<String> paths) {
    String candidate;
    if (target.startsWith('package:')) {
      final packagePath = target.substring('package:'.length);
      final slash = packagePath.indexOf('/');
      if (slash < 0 || packagePath.substring(0, slash) != 'king_vpn') return null;
      candidate = 'lib/' + packagePath.substring(slash + 1);
    } else if (target.startsWith('dart:') || target.startsWith('http:') || target.startsWith('https:')) {
      return null;
    } else if (target.startsWith('/')) {
      candidate = target.substring(1);
    } else {
      final parent = sourcePath.contains('/') ? sourcePath.substring(0, sourcePath.lastIndexOf('/')) : '';
      candidate = parent.isEmpty || target.startsWith(parent + '/') ? target : parent + '/' + target;
    }
    final normalized = _normalize(candidate);
    if (normalized == null) return null;
    for (final option in [normalized, normalized + '.dart', normalized + '.py', normalized + '/__init__.py']) {
      if (paths.contains(option)) return option;
    }
    return null;
  }

  static String? _normalize(String path) {
    final parts = <String>[];
    for (final part in path.replaceAll('\\', '/').split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isEmpty) return null;
        parts.removeLast();
      } else { parts.add(part); }
    }
    return parts.join('/');
  }

  static List<List<String>> _cycles(Map<String, List<String>> edges) {
    final found = <List<String>>[];
    final visited = <String>{};
    final active = <String>[];
    final activeSet = <String>{};
    void visit(String node) {
      if (activeSet.contains(node)) {
        final start = active.indexOf(node);
        if (start >= 0) found.add([...active.sublist(start), node]);
        return;
      }
      if (!visited.add(node)) return;
      active.add(node);
      activeSet.add(node);
      for (final next in edges[node] ?? const <String>[]) { visit(next); }
      active.removeLast();
      activeSet.remove(node);
    }
    for (final node in edges.keys) { visit(node); }
    return found;
  }
}
