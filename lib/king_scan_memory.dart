part of 'main.dart';

/// Append-only, crash-tolerant scanner journal.
///
/// Only phase names, aggregate counters and opaque cursors are stored. Raw
/// server links, IP addresses, configured ranges and credentials are excluded.
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
    if (normalized.isEmpty || normalized.length > 160) {
      throw ArgumentError.value(jobId, 'jobId', 'Must contain 1..160 characters.');
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
          if (rawKey.isEmpty || offset is! int || offset < -1) {
            throw ArgumentError('Invalid range cursor entry.');
          }
          final opaqueKey = RegExp(r'^[a-f0-9]{64}
        }
        safe[key] = offsets;
      } else if (key == 'serverKeyHash') {
        if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
          throw ArgumentError('Invalid opaque server identity.');
        }
        safe[key] = value;
      } else {
        if (value is! int || value < 0) {
          throw ArgumentError.value(value, key, 'Cursor values must be non-negative integers.');
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
          final rawCursor = decoded['cursor'];
          final rawCounters = decoded['counters'];
          final phase = decoded['phase']?.toString() ?? '';
          if (phase.isEmpty) continue;
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
          // A torn, malformed, or privacy-invalid record is ignored.
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
    if (phase.trim().isEmpty || phase.length > 64) {
      throw ArgumentError.value(phase, 'phase');
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
      final handle = await _file.open(mode: FileMode.append);
      try {
        if (_needsSeparator) await handle.writeString('\n');
        await handle.writeString('${jsonEncode(record)}\n');
        // RandomAccessFile.flush asks the platform to flush file contents,
        // stronger than merely draining an IOSink's in-process buffer.
        await handle.flush();
      } finally {
        await handle.close();
      }
      _needsSeparator = false;
      _sequence = nextSequence;
      _latest = record;
    });
    _writeTail = task.catchError((Object error, StackTrace stack) {
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
        final rawCursor = decoded['cursor'];
        final rawCounters = decoded['counters'];
        yield <String, Object?>{
          'version': 1,
          'job': jobId,
          'sequence': decoded['sequence'],
          'timestampMs': decoded['timestampMs'],
          'phase': decoded['phase'],
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
).hasMatch(rawKey)
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
        if (value is! int || value < 0) {
          throw ArgumentError.value(value, key, 'Cursor values must be non-negative integers.');
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
          final rawCursor = decoded['cursor'];
          final rawCounters = decoded['counters'];
          final phase = decoded['phase']?.toString() ?? '';
          if (phase.isEmpty) continue;
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
          // A torn, malformed, or privacy-invalid record is ignored.
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
    if (phase.trim().isEmpty || phase.length > 64) {
      throw ArgumentError.value(phase, 'phase');
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
        final rawCursor = decoded['cursor'];
        final rawCounters = decoded['counters'];
        yield <String, Object?>{
          'version': 1,
          'job': jobId,
          'sequence': decoded['sequence'],
          'timestampMs': decoded['timestampMs'],
          'phase': decoded['phase'],
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
