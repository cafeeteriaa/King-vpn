import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../lib/personal_folder_probe.dart';

void main() {
  group('PersonalFolderProbeCoordinator', () {
    test('ranks streamed profiles by latency and preserves last-good on ties', () async {
      final result = await PersonalFolderProbeCoordinator.rank(
        batches: Stream<List<String>>.fromIterable(<List<String>>[
          <String>['slow', 'preferred'],
          <String>['fast'],
        ]),
        probe: (link) async => <String, int>{
          'slow': 180,
          'preferred': 40,
          'fast': 40,
        }[link],
        fallbackLinks: () async => <String>[],
        isCancelled: () => false,
        concurrency: 2,
        total: 3,
        preferredLink: 'preferred',
        retryDelay: Duration.zero,
      );

      expect(result.links, <String>['preferred', 'fast', 'slow']);
      expect(result.probed, 3);
      expect(result.healthy, 3);
      expect(result.cancelled, isFalse);
    });

    test('retries failed profiles once without discarding successful candidates', () async {
      final attempts = <String, int>{};
      final lastVisibleResult = <String, int?>{};
      final result = await PersonalFolderProbeCoordinator.rank(
        batches: Stream<List<String>>.fromIterable(<List<String>>[
          <String>['recovers', 'healthy'],
          <String>['recovers-late'],
        ]),
        probe: (link) async {
          attempts.update(link, (value) => value + 1, ifAbsent: () => 1);
          if (link != 'healthy' && attempts[link] == 1) return null;
          if (link == 'healthy') return 20;
          return link == 'recovers' ? 50 : 60;
        },
        fallbackLinks: () async => <String>[],
        isCancelled: () => false,
        concurrency: 2,
        total: 3,
        retryDelay: Duration.zero,
        onResult: (link, latency) => lastVisibleResult[link] = latency,
      );

      expect(lastVisibleResult['recovers'], 50);
      expect(lastVisibleResult['recovers-late'], 60);
      expect(attempts['recovers'], 2);
      expect(attempts['recovers-late'], 2);
      expect(attempts['healthy'], 1);
      expect(result.links, <String>['healthy', 'recovers', 'recovers-late']);
      expect(result.probed, 3);
      expect(result.healthy, 3);
    });

    test('uses the complete second pass as real-core fallback when all probes fail', () async {
      var fallbackReads = 0;
      final result = await PersonalFolderProbeCoordinator.rank(
        batches: Stream<List<String>>.fromIterable(<List<String>>[
          <String>['one', 'two'],
          <String>['three'],
        ]),
        probe: (_) async => null,
        fallbackLinks: () async {
          fallbackReads++;
          return <String>['one', 'two', 'three'];
        },
        isCancelled: () => false,
        concurrency: 2,
        total: 3,
        retryDelay: Duration.zero,
      );

      expect(fallbackReads, 1);
      expect(result.links, <String>['one', 'two', 'three']);
      expect(result.probed, 3);
      expect(result.healthy, 0);
    });

    test('never exceeds configured concurrent probes', () async {
      var active = 0;
      var peak = 0;
      final links = List<String>.generate(41, (i) => 'node-$i');
      final result = await PersonalFolderProbeCoordinator.rank(
        batches: Stream<List<String>>.fromIterable(<List<String>>[
          links.sublist(0, 13),
          links.sublist(13, 29),
          links.sublist(29),
        ]),
        probe: (link) async {
          active++;
          if (active > peak) peak = active;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          active--;
          return int.parse(link.substring(5));
        },
        fallbackLinks: () async => <String>[],
        isCancelled: () => false,
        concurrency: 3,
        total: links.length,
        retryDelay: Duration.zero,
      );

      expect(peak, lessThanOrEqualTo(3));
      expect(result.links, hasLength(links.length));
      expect(result.healthy, links.length);
    });

    test('cancellation stops reading further batches and skips fallback', () async {
      var cancelled = false;
      var fallbackReads = 0;
      final result = await PersonalFolderProbeCoordinator.rank(
        batches: (() async* {
          yield <String>['one', 'two'];
          cancelled = true;
          yield <String>['three'];
        })(),
        probe: (_) async => 10,
        fallbackLinks: () async {
          fallbackReads++;
          return <String>[];
        },
        isCancelled: () => cancelled,
        concurrency: 1,
        total: 3,
        retryDelay: Duration.zero,
      );

      expect(result.cancelled, isTrue);
      expect(result.probed, 2);
      expect(result.links, <String>['one', 'two']);
      expect(fallbackReads, 0);
    });
  });
}
