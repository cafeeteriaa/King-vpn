part of 'main.dart';

/// Append-only scanner journal with crash recovery and privacy-safe cursors.
class KingScanJournal {
  KingScanJournal._(this.jobId, this._file);

  final String jobId;
  final File _file;
  Future<void> _writeTail = Future<void>.value();
  Map<String, Object?>? _latest;
  int _sequence = 0;
  bool _needsSeparator = false;

  static const Set<String> _cursorFields = <String>{
    'rangeIndex', 'rangeCount', 'rangeOffsets', 'batch', 'serverIndex',
    'serverKeyHash', 'candidateIndex', 'variantIndex', 'variantCode', 'targetIndex',
  };

  static Future<KingScanJournal> open({
    required String jobId,
    Directory? root,
  }) async {
    final normalized = jobId.trim();
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,159}$').hasMatch(normalized)) {
      throw ArgumentError.value(jobId, 'jobId', 'Expected a non-sensitive job identifier.');
    }
    final directory = root ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final id = sha256.convert(utf8.encode(normalized)).toString();
    final journal = KingScanJournal._(
      normalized,
      File(directory.path + '/king_scan_' + id + '.jsonl'),
    );
    await journal._recover();
    return journal;
  }

  Map<String, Object?>? get latestCheckpoint =>
      _latest == null ? null : Map<String, Object?>.unmodifiable(_latest!);

  int get sequence => _sequence;

  Map<String, Object?> _sanitizeCursor(Map source) {
    final safe = <String, Object?>{};
    for (final entry in source.entries) {
      final key = entry.key.toString();
      if (!_cursorFields.contains(key)) {
        throw ArgumentError.value(key, 'cursor', 'Unsupported checkpoint field.');
      }
      final value = entry.value;
      if (key == 'rangeOffsets') {
        if (value is! Map) throw ArgumentError.value(value, 'rangeOffsets');
        final offsets = <String, int>{};
        for (final range in value.entries) {
          final rawKey = range.key.toString();
          final offset = range.value;
          if (rawKey.isEmpty || offset is! int || offset < 0) {
            throw ArgumentError('Invalid range cursor entry.');
          }
          final opaqueKey = RegExp(r'^[a-f0-9]{64}$').hasMatch(rawKey)
              ? rawKey
              : sha256.convert(utf8.encode(rawKey)).toString();
          offsets[opaqueKey] = offset;
        }
        safe[key] = offsets;
      } else if (key == 'serverKeyHash') {
        if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
          throw ArgumentError('Invalid opaque server identity.');
        }
        safe[key] = value;
      } else {
        final minimum = (key == 'candidateIndex' || key == 'variantIndex') ? -1 : 0;
        if (value is! int || value < minimum) {
          throw ArgumentError.value(value, key, 'Invalid checkpoint integer.');
        }
        safe[key] = value;
      }
    }
    return safe;
  }

  Map<String, int> _sanitizeCounters(Map source) {
    if (source.length > 64) throw ArgumentError('Too many scanner counters.');
    final safe = <String, int>{};
    for (final entry in source.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,63}$').hasMatch(key) ||
          value is! int || value < 0) {
        throw ArgumentError('Invalid scanner counter.');
      }
      safe[key] = value;
    }
    return safe;
  }

  Future<void> _recover() async {
    if (!await _file.exists()) return;
    try {
      await for (final line in _file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        try {
          final decoded = jsonDecode(line);
          if (decoded is! Map ||
              decoded['version'] != 1 ||
              decoded['job'] != jobId ||
              decoded['sequence'] is! int) continue;
          final seq = decoded['sequence'] as int;
          if (seq <= _sequence) continue;
          final phase = decoded['phase']?.toString() ?? '';
          if (!RegExp(r'^[a-z][a-z0-9_-]{0,63}$').hasMatch(phase)) continue;
          final rawCursor = decoded['cursor'];
          final rawCounters = decoded['counters'];
          final normalized = <String, Object?>{
            'version': 1,
            'job': jobId,
            'sequence': seq,
            'timestampMs': decoded['timestampMs'] is int
                ? decoded['timestampMs'] as int : 0,
            'phase': phase,
            'phaseCompleted': decoded['phaseCompleted'] == true,
            'cursor': _sanitizeCursor(
              rawCursor is Map ? rawCursor : const <String, Object?>{},
            ),
            'counters': _sanitizeCounters(
              rawCounters is Map ? rawCounters : const <String, Object?>{},
            ),
          };
          _sequence = seq;
          _latest = normalized;
        } catch (_) {
          // Ignore torn, malformed, or privacy-invalid records.
        }
      }
      final length = await _file.length();
      if (length > 0) {
        final tail = await _file.openRead(length - 1, length).fold<List<int>>(
          <int>[],
          (bytes, chunk) => bytes..addAll(chunk),
        );
        _needsSeparator = tail.isNotEmpty && tail.last != 10;
      }
    } catch (error, stack) {
      logError(error, stack);
      rethrow;
    }
  }

  Future<void> commit({
    required String phase,
    required bool phaseCompleted,
    Map<String, Object?> cursor = const <String, Object?>{},
    Map<String, int> counters = const <String, int>{},
  }) {
    if (!RegExp(r'^[a-z][a-z0-9_-]{0,63}$').hasMatch(phase)) {
      throw ArgumentError.value(phase, 'phase', 'Expected a safe phase identifier.');
    }
    final safeCursor = _sanitizeCursor(cursor);
    final safeCounters = _sanitizeCounters(counters);
    final task = _writeTail.then((_) async {
      final nextSequence = _sequence + 1;
      final record = <String, Object?>{
        'version': 1,
        'job': jobId,
        'sequence': nextSequence,
        'timestampMs': DateTime.now().millisecondsSinceEpoch,
        'phase': phase,
        'phaseCompleted': phaseCompleted,
        'cursor': safeCursor,
        'counters': safeCounters,
      };
      final sink = _file.openWrite(mode: FileMode.append);
      try {
        if (_needsSeparator) sink.write('\n');
        sink.writeln(jsonEncode(record));
        await sink.flush();
      } finally {
        await sink.close();
      }
      _needsSeparator = false;
      _sequence = nextSequence;
      _latest = record;
    });
    _writeTail = task.catchError((Object error, StackTrace stack) {
      // The failed write may have left a partial final JSON line. Force a
      // separator before the next queued commit in this same process.
      _needsSeparator = true;
      logError(error, stack);
    });
    return task;
  }

  Stream<Map<String, Object?>> records() async* {
    await _writeTail;
    if (!await _file.exists()) return;
    await for (final line in _file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map ||
            decoded['version'] != 1 ||
            decoded['job'] != jobId) continue;
        final phase = decoded['phase']?.toString() ?? '';
        if (!RegExp(r'^[a-z][a-z0-9_-]{0,63}$').hasMatch(phase)) continue;
        final rawCursor = decoded['cursor'];
        final rawCounters = decoded['counters'];
        yield <String, Object?>{
          'version': 1,
          'job': jobId,
          'sequence': decoded['sequence'],
          'timestampMs': decoded['timestampMs'],
          'phase': phase,
          'phaseCompleted': decoded['phaseCompleted'] == true,
          'cursor': _sanitizeCursor(
            rawCursor is Map ? rawCursor : const <String, Object?>{},
          ),
          'counters': _sanitizeCounters(
            rawCounters is Map ? rawCounters : const <String, Object?>{},
          ),
        };
      } catch (_) {
        // Ignore invalid/torn records while preserving subsequent valid entries.
      }
    }
  }

  Future<void> flush() async {
    await _writeTail;
  }
}
