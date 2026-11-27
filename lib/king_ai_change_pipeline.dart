import 'dart:collection';
import 'dart:convert';

/// A dependency-ordered unit in one owner-requested engineering change.
/// A plan is deliberately bounded so the small on-device model can reason
/// about one coherent subsystem at a time instead of truncating a whole project.
class KingAiWorkStage {
  const KingAiWorkStage({required this.id, required this.task});

  final String id;
  final String task;
}

class KingAiWorkPlan {
  const KingAiWorkPlan({required this.summary, required this.stages});

  final String summary;
  final List<KingAiWorkStage> stages;

  static const int maxStages = 6;

  factory KingAiWorkPlan.parse(String raw) {
    var value = raw.trim()
        .replaceFirst(RegExp(r'^\s*```(?:json)?\s*'), '')
        .replaceFirst(RegExp(r'\s*```\s*$'), '');
    final start = value.indexOf('{');
    final end = value.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('King AI work plan is not a JSON object');
    }
    value = value.substring(start, end + 1);
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic> ||
        decoded['summary'] is! String ||
        decoded['stages'] is! List) {
      throw const FormatException('King AI work plan schema is invalid');
    }
    final summary = (decoded['summary'] as String).trim();
    if (summary.isEmpty || summary.length > 1200) {
      throw const FormatException('King AI plan summary is empty or too long');
    }
    final rawStages = decoded['stages'] as List;
    if (rawStages.isEmpty || rawStages.length > maxStages) {
      throw const FormatException('King AI plan must contain 1 to 6 stages');
    }
    final ids = <String>{};
    final stages = <KingAiWorkStage>[];
    for (final item in rawStages) {
      if (item is! Map || item['id'] is! String || item['task'] is! String) {
        throw const FormatException('King AI plan contains a malformed stage');
      }
      final id = (item['id'] as String).trim().toLowerCase();
      final task = (item['task'] as String).trim();
      if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,39}$').hasMatch(id) ||
          !ids.add(id) ||
          task.length < 20 ||
          task.length > 1200) {
        throw const FormatException('King AI stage identity or task is invalid');
      }
      stages.add(KingAiWorkStage(id: id, task: task));
    }
    return KingAiWorkPlan(
      summary: summary,
      stages: List<KingAiWorkStage>.unmodifiable(stages),
    );
  }
}

/// Aggregates several small model passes into one cohesive, atomic PR.
///
/// Each inference pass still receives a bounded context and may change at most
/// three existing files. The aggregate is larger, but no partial PR is created:
/// all stages must finish and pass path, conflict, and size validation first.
class KingAiPatchBundle {
  static const int maxStages = KingAiWorkPlan.maxStages;
  static const int maxFilesPerStage = 3;
  static const int maxChangedFiles = maxStages * maxFilesPerStage;
  static const int maxTotalContentChars = 180000;

  final Map<String, String> _changes = <String, String>{};
  int _completedStages = 0;

  int get completedStages => _completedStages;
  int get changedFileCount => _changes.length;
  bool get isEmpty => _changes.isEmpty;
  Map<String, String> get changes =>
      UnmodifiableMapView<String, String>(_changes);

  void addStage({
    required int stageIndex,
    required Map<String, String> sourceFiles,
    required Map<String, String> changes,
  }) {
    if (_completedStages >= maxStages || stageIndex != _completedStages) {
      throw StateError('King AI stages must be added once, in dependency order');
    }
    if (sourceFiles.isEmpty || sourceFiles.length > 6) {
      throw ArgumentError('Each stage must use 1 to 6 source files');
    }
    if (changes.length > maxFilesPerStage) {
      throw ArgumentError('Each inference stage may change at most 3 files');
    }

    final next = Map<String, String>.of(_changes);
    for (final entry in changes.entries) {
      _validatePath(entry.key);
      if (!sourceFiles.containsKey(entry.key)) {
        throw FormatException('Stage changed a file outside its supplied context: ${entry.key}');
      }
      final suppliedSource = sourceFiles[entry.key]!;
      final hasPreviousStageOutput = next.containsKey(entry.key);
      final previousStageOutput = next[entry.key];
      if (hasPreviousStageOutput && suppliedSource != previousStageOutput) {
        throw StateError('Conflicting stage input for ${entry.key}; later stage did not use the prior output');
      }
      if (!hasPreviousStageOutput && suppliedSource == entry.value) {
        continue;
      }
      next[entry.key] = entry.value;
    }

    if (next.length > maxChangedFiles) {
      throw StateError('Combined King AI change exceeds the 18-file review budget');
    }
    final totalChars = next.values.fold<int>(0, (sum, value) => sum + value.length);
    if (totalChars > maxTotalContentChars) {
      throw StateError('Combined King AI change exceeds the content budget');
    }
    _changes
      ..clear()
      ..addAll(next);
    _completedStages++;
  }

  void _validatePath(String path) {
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.contains('\\') ||
        path.split('/').any((part) => part.isEmpty || part == '.' || part == '..') ||
        !(path.startsWith('lib/') ||
          path.startsWith('test/') ||
          path.startsWith('tools/'))) {
      throw FormatException('Unsafe or unsupported King AI source path: $path');
    }
  }
}
