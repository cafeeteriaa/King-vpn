part of 'main.dart';

/// Append-only, crash-tolerant scanner journal.
///
/// The journal stores phase checkpoints and opaque counters, never raw server
/// links, credentials, UUIDs, endpoint addresses, or DNS query contents.
/// It keeps only the latest checkpoint in memory; history is streamed from disk.
class KingScanJournal {
  KingScanJournal._(this.jobId, this._file);

  final String jobId;
  final File _file;
  Future<void> _writeTail = Future<void>.value();
  Map<String, Object?>? _latest;
  int _sequence = 0;
  bool _needsSeparator = false;

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
      File('${directory.path}/king_scan_$id.jsonl'),
    );
    await journal._recover();
    return journal;
  }

  Map<String, Object?>? get latestCheckpoint =>
      _latest == null ? null : Map<String, Object?>.unmodifiable(_latest!);

  int get sequence => _sequence;

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
              decoded['sequence'] is! int) {
            continue;
          }
          final seq = decoded['sequence'] as int;
          if (seq <= _sequence) continue;
          _sequence = seq;
          _latest = Map<String, Object?>.from(decoded);
        } catch (_) {
          // A torn or malformed record is ignored; later complete records survive.
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

  /// Atomically advances the durable phase checkpoint after a completed unit.
  ///
  /// Callers must only advance cursors for work whose results have already
  /// been durably committed by the owning inventory subsystem.
  Future<void> commit({
    required String phase,
    required bool phaseCompleted,
    Map<String, Object?> cursor = const <String, Object?>{},
    Map<String, int> counters = const <String, int>{},
  }) {
    if (phase.trim().isEmpty || phase.length > 64) {
      throw ArgumentError.value(phase, 'phase');
    }
    final task = _writeTail.then((_) async {
      final nextSequence = _sequence + 1;
      final record = <String, Object?>{
        'version': 1,
        'job': jobId,
        'sequence': nextSequence,
        'timestampMs': DateTime.now().millisecondsSinceEpoch,
        'phase': phase,
        'phaseCompleted': phaseCompleted,
        'cursor': cursor,
        'counters': counters,
      };
      final sink = _file.openWrite(mode: FileMode.append);
      if (_needsSeparator) sink.write('\n');
      sink.writeln(jsonEncode(record));
      await sink.flush();
      await sink.close();
      _needsSeparator = false;
      _sequence = nextSequence;
      _latest = record;
    });
    _writeTail = task.catchError((Object error, StackTrace stack) {
      logError(error, stack);
    });
    return task;
  }

  /// Streams the append-only audit history without loading the journal in RAM.
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
        if (decoded is Map &&
            decoded['version'] == 1 &&
            decoded['job'] == jobId) {
          yield Map<String, Object?>.from(decoded);
        }
      } catch (_) {
        // Preserve forward recovery when a process was killed mid-write.
      }
    }
  }

  Future<void> flush() async {
    await _writeTail;
  }
}
