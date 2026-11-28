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


/// Append-only, sharded inventory for large scanner result sets.
///
/// Records are partitioned by a SHA-256 identity prefix. Writes check only the
/// identities in the incoming batch while streaming the affected shard, so
/// loading or deduplicating a batch never materializes the complete inventory.
/// Payloads are local scanner data; checkpoint cursors must remain opaque.
class KingDiskInventory {
  KingDiskInventory._(this._directory, this.name);

  final Directory _directory;
  final String name;
  static final Map<String, Future<void>> _writeQueues = <String, Future<void>>{};

  Future<void> get _writeTail =>
      _writeQueues[_directory.path] ?? Future<void>.value();

  static Future<KingDiskInventory> open({
    required String name,
    Directory? root,
  }) async {
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}$').hasMatch(name)) {
      throw ArgumentError.value(name, 'name', 'Expected a safe inventory name.');
    }
    final base = root ?? await getApplicationSupportDirectory();
    final directory = Directory(base.path + '/king_inventory_' + name);
    await directory.create(recursive: true);
    return KingDiskInventory._(directory, name);
  }

  String _identity(String key) {
    final normalized = key.trim();
    if (normalized.isEmpty || normalized.length > 4096) {
      throw ArgumentError.value(key, 'key', 'Inventory identity is empty or too long.');
    }
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  /// Adds only previously unseen identities. The existing shard is streamed
  /// and only incoming identities are retained in memory for deduplication.
  Future<int> appendBatch(Iterable<Map<String, Object?>> records) {
    final path = _directory.path;
    final previous = _writeQueues[path] ?? Future<void>.value();
    final task = previous.then((_) async {
      final grouped = <String, List<MapEntry<String, Map<String, Object?>>>>{};
      for (final record in records) {
        final key = record['key'];
        if (key is! String) {
          throw ArgumentError('Every inventory record must include a string key.');
        }
        final identity = _identity(key);
        final payload = Map<String, Object?>.from(record)..remove('key');
        grouped.putIfAbsent(identity.substring(0, 2), () => <MapEntry<String, Map<String, Object?>>>[])
            .add(MapEntry(identity, payload));
      }
      var added = 0;
      for (final entry in grouped.entries) {
        final file = File(_directory.path + '/' + entry.key + '.jsonl');
        final wanted = <String>{for (final item in entry.value) item.key};
        final existing = <String>{};
        if (await file.exists()) {
          await for (final line in file.openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
            if (line.trim().isEmpty) continue;
            try {
              final decoded = jsonDecode(line);
              if (decoded is Map && decoded['id'] is String &&
                  wanted.contains(decoded['id'])) {
                existing.add(decoded['id'] as String);
              }
            } catch (_) {
              // Ignore torn/malformed records; continue through later records.
            }
          }
        }
        var needsSeparator = false;
        if (await file.exists()) {
          final length = await file.length();
          if (length > 0) {
            final tail = await file.openRead(length - 1, length).first;
            needsSeparator = tail.isNotEmpty && tail.last != 10;
          }
        }
        final sink = file.openWrite(mode: FileMode.append);
        try {
          if (needsSeparator) sink.write('\n');
          for (final item in entry.value) {
            if (!existing.add(item.key)) continue;
            sink.writeln(jsonEncode(<String, Object?>{
              'version': 1,
              'id': item.key,
              'payload': item.value,
            }));
            added++;
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
      }
      return added;
    });
    _writeQueues[path] = task.then<void>((_) {}, onError: (Object error, StackTrace stack) {
      logError(error, stack);
    });
    return task;
  }

  /// Replaces incoming identities atomically per shard. This keeps endpoint
  /// metadata (such as last-seen timestamps) current without rewriting the
  /// complete inventory or loading a shard into memory.
  Future<int> upsertBatch(Iterable<Map<String, Object?>> records) {
    final path = _directory.path;
    final previous = _writeQueues[path] ?? Future<void>.value();
    final task = previous.then((_) async {
      final grouped = <String, Map<String, Map<String, Object?>>>{};
      for (final record in records) {
        final key = record['key'];
        if (key is! String) {
          throw ArgumentError('Every inventory record must include a string key.');
        }
        final identity = _identity(key);
        final payload = Map<String, Object?>.from(record)..remove('key');
        grouped.putIfAbsent(identity.substring(0, 2), () => <String, Map<String, Object?>>{})[identity] = payload;
      }
      var written = 0;
      for (final entry in grouped.entries) {
        final file = File(_directory.path + '/' + entry.key + '.jsonl');
        final temporary = File(file.path + '.tmp');
        final sink = temporary.openWrite();
        try {
          if (await file.exists()) {
            await for (final line in file.openRead()
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
              if (line.trim().isEmpty) continue;
              try {
                final decoded = jsonDecode(line);
                if (decoded is Map && decoded['id'] is String &&
                    entry.value.containsKey(decoded['id'])) {
                  continue;
                }
                if (decoded is Map && decoded['version'] == 1 &&
                    decoded['id'] is String && decoded['payload'] is Map) {
                  sink.writeln(line);
                }
              } catch (_) {
                // A torn record is discarded while valid records are retained.
              }
            }
          }
          for (final item in entry.value.entries) {
            sink.writeln(jsonEncode(<String, Object?>{
              'version': 1,
              'id': item.key,
              'payload': item.value,
            }));
            written++;
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        try {
          await temporary.rename(file.path);
        } catch (_) {
          if (await temporary.exists()) await temporary.delete();
          rethrow;
        }
      }
      return written;
    });
    _writeQueues[path] = task.then<void>((_) {}, onError: (Object error, StackTrace stack) {
      logError(error, stack);
    });
    return task;
  }

  /// Streams records shard-by-shard; the full inventory is never hydrated.
  Stream<Map<String, Object?>> records() async* {
    await _writeTail;
    final shards = _directory.list(followLinks: false)
        .where((entity) => entity is File && entity.path.endsWith('.jsonl'));
    await for (final entity in shards) {
      final file = entity as File;
      await for (final line in file.openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        try {
          final decoded = jsonDecode(line);
          if (decoded is! Map || decoded['version'] != 1 ||
              decoded['id'] is! String || decoded['payload'] is! Map) continue;
          yield <String, Object?>{
            'id': decoded['id'] as String,
            ...Map<String, Object?>.from(decoded['payload'] as Map),
          };
        } catch (_) {
          // Skip only the invalid record, not the rest of the shard.
        }
      }
    }
  }
}
