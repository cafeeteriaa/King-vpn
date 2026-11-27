import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import '../lib/king_scan_scheduler.dart';

void main() {
  group('KingNationalScannerEngine', () {
    Future<void> Function() noop() => () async {};

    test('runs national discovery phases in strict serial order', () async {
      final engine = KingNationalScannerEngine();
      final events = <String>[];
      final report = await engine.runDiscoveryCycle(
        isNationalMode: () => true,
        canRun: () => true,
        shouldStop: () => false,
        diagnoseNetwork: () async { events.add('diagnose'); },
        scanDns: () async { events.add('dns'); },
        scanConfiguredEndpoints: () async { events.add('endpoints'); },
        scanConfiguredRanges: () async { events.add('ranges'); },
      );

      expect(events, ['diagnose', 'dns', 'endpoints', 'ranges']);
      expect(report.completed, isTrue);
      expect(report.cyclesCompleted, 1);
      expect(report.results.map((r) => r.status),
          everyElement(KingNationalScanStatus.completed));
      expect(engine.isRunning, isFalse);
    });

    test('refuses to run when the active mode is not national', () async {
      final engine = KingNationalScannerEngine();
      var calls = 0;
      final report = await engine.runDiscoveryCycle(
        isNationalMode: () => false,
        canRun: () => true,
        shouldStop: () => false,
        diagnoseNetwork: () async { calls++; },
        scanDns: noop(),
        scanConfiguredEndpoints: noop(),
        scanConfiguredRanges: noop(),
      );

      expect(calls, 0);
      expect(report.cyclesCompleted, 0);
      expect(report.results.single.status, KingNationalScanStatus.skipped);
    });

    test('cancellation between phases prevents later scanner work', () async {
      final engine = KingNationalScannerEngine();
      var safe = true;
      final events = <String>[];
      final report = await engine.runDiscoveryCycle(
        isNationalMode: () => true,
        canRun: () => safe,
        shouldStop: () => !safe,
        diagnoseNetwork: () async { events.add('diagnose'); safe = false; },
        scanDns: () async { events.add('dns'); },
        scanConfiguredEndpoints: noop(),
        scanConfiguredRanges: noop(),
      );

      expect(events, ['diagnose']);
      expect(report.cancelled, isTrue);
      expect(report.results.last.status, KingNationalScanStatus.cancelled);
    });

    test('records phase failure without hiding it or skipping independent phases', () async {
      final engine = KingNationalScannerEngine();
      final events = <String>[];
      final report = await engine.runDiscoveryCycle(
        isNationalMode: () => true,
        canRun: () => true,
        shouldStop: () => false,
        diagnoseNetwork: () async { throw StateError('diagnostic unavailable'); },
        scanDns: () async { events.add('dns'); },
        scanConfiguredEndpoints: () async { events.add('endpoints'); },
        scanConfiguredRanges: () async { events.add('ranges'); },
      );

      expect(events, ['dns', 'endpoints', 'ranges']);
      expect(report.hasFailures, isTrue);
      expect(report.results.first.status, KingNationalScanStatus.failed);
      expect(report.results.first.error, 'StateError');
      expect(report.completed, isFalse);
    });

    test('coalesces overlapping requests into one sequential follow-up cycle', () async {
      final engine = KingNationalScannerEngine();
      final entered = Completer<void>();
      final release = Completer<void>();
      var diagnoseRuns = 0;
      final first = engine.runDiscoveryCycle(
        isNationalMode: () => true,
        canRun: () => true,
        shouldStop: () => false,
        diagnoseNetwork: () async {
          diagnoseRuns++;
          if (diagnoseRuns == 1) {
            entered.complete();
            await release.future;
          }
        },
        scanDns: noop(),
        scanConfiguredEndpoints: noop(),
        scanConfiguredRanges: noop(),
      );
      await entered.future;
      final second = engine.runDiscoveryCycle(
        isNationalMode: () => true,
        canRun: () => true,
        shouldStop: () => false,
        diagnoseNetwork: noop(),
        scanDns: noop(),
        scanConfiguredEndpoints: noop(),
        scanConfiguredRanges: noop(),
      );
      expect(identical(first, second), isTrue);
      release.complete();
      final report = await first;

      expect(diagnoseRuns, 2);
      expect(report.cyclesCompleted, 2);
      expect(engine.isRunning, isFalse);
    });
  });
}
