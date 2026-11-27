import 'dart:async';

/// Streaming ranking for personal VPN profiles.
///
/// The coordinator never materializes Server objects for the whole archive.
/// It consumes storage batches, probes with bounded concurrency, retains only
/// successful link/latency pairs, and rereads the archive only when every
/// probe fails so the real-core connection fallback remains available.
class PersonalFolderProbeResult {
  const PersonalFolderProbeResult({
    required this.links,
    required this.probed,
    required this.healthy,
    required this.cancelled,
  });

  final List<String> links;
  final int probed;
  final int healthy;
  final bool cancelled;
}

class _PersonalFolderScore {
  const _PersonalFolderScore(this.link, this.milliseconds, this.sequence);

  final String link;
  final int milliseconds;
  final int sequence;
}

class PersonalFolderProbeCoordinator {
  PersonalFolderProbeCoordinator._();

  static Future<PersonalFolderProbeResult> rank({
    required Stream<List<String>> batches,
    required Future<int?> Function(String link) probe,
    required Future<List<String>> Function() fallbackLinks,
    required bool Function() isCancelled,
    int concurrency = 8,
    int retryBatchSize = 128,
    int total = 0,
    String preferredLink = '',
    Duration retryDelay = const Duration(seconds: 2),
    void Function(String link, int? milliseconds)? onResult,
    void Function(int completed, int total, int healthy)? onProgress,
  }) async {
    if (concurrency <= 0) {
      throw ArgumentError.value(concurrency, 'concurrency');
    }
    if (retryBatchSize <= 0) {
      throw ArgumentError.value(retryBatchSize, 'retryBatchSize');
    }
    final scores = <_PersonalFolderScore>[];
    final failedLinks = <String>[];
    var completed = 0;
    var sequence = 0;
    var cancelled = false;

    Future<List<String>> runPass(
      List<String> links, {
      required bool retry,
    }) async {
      final failed = <String>[];
      var cursor = 0;
      Future<void> worker() async {
        while (!isCancelled()) {
          if (cursor >= links.length) return;
          final link = links[cursor++];
          int? latency;
          try {
            latency = await probe(link);
            if (latency != null && latency < 0) latency = null;
          } catch (_) {
            latency = null;
          }
          if (latency == null) {
            failed.add(link);
          } else {
            scores.add(_PersonalFolderScore(link, latency, sequence++));
          }
          try {
            onResult?.call(link, latency);
            if (!retry) {
              completed++;
              onProgress?.call(completed, total, scores.length);
            }
          } catch (_) {}
        }
      }

      await Future.wait([
        for (var i = 0; i < concurrency && i < links.length; i++) worker(),
      ]);
      return failed;
    }

    await for (final batch in batches) {
      if (isCancelled()) {
        cancelled = true;
        break;
      }
      failedLinks.addAll(await runPass(batch, retry: false));
    }

    // Match the original full-inventory behavior: retry failed candidates once
    // after the first pass is complete, with one delay for the whole archive.
    // If every first-pass probe failed, skip ping retries and preserve the
    // ordered real-core fallback exactly as before.
    if (!isCancelled() && scores.isNotEmpty && failedLinks.isNotEmpty) {
      if (retryDelay > Duration.zero) {
        await Future<void>.delayed(retryDelay);
      }
      for (var start = 0; start < failedLinks.length; start += retryBatchSize) {
        if (isCancelled()) break;
        final end = (start + retryBatchSize < failedLinks.length)
            ? start + retryBatchSize
            : failedLinks.length;
        await runPass(failedLinks.sublist(start, end), retry: true);
      }
    }

    if (isCancelled()) cancelled = true;
    if (scores.isEmpty && !cancelled) {
      failedLinks.clear();
      final fallback = await fallbackLinks();
      return PersonalFolderProbeResult(
        links: List<String>.unmodifiable(fallback),
        probed: completed,
        healthy: 0,
        cancelled: false,
      );
    }

    failedLinks.clear();
    scores.sort((a, b) {
      final byLatency = a.milliseconds.compareTo(b.milliseconds);
      if (byLatency != 0) return byLatency;
      final aPreferred = a.link == preferredLink ? 0 : 1;
      final bPreferred = b.link == preferredLink ? 0 : 1;
      if (aPreferred != bPreferred) return aPreferred.compareTo(bPreferred);
      return a.sequence.compareTo(b.sequence);
    });
    return PersonalFolderProbeResult(
      links: List<String>.unmodifiable(scores.map((score) => score.link)),
      probed: completed,
      healthy: scores.length,
      cancelled: cancelled,
    );
  }
}
