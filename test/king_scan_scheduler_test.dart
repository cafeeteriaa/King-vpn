import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import '../lib/king_scan_scheduler.dart';

void main() {
  group('KingScanScheduler', () {
    test('runs DNS then IP serially', () async {
      final scheduler = KingScanScheduler();
      final events = <String>[];
      await scheduler.requestCycle(
        canRun: () => true,
        runDns: () async { events.add('dns'); },
        runIp: () async { events.add('ip'); },
      );
      expect(events, ['dns', 'ip']);
      expect(scheduler.isRunning, isFalse);
    });

    test('does not start IP when the environment becomes unsafe after DNS', () async {
      final scheduler = KingScanScheduler();
      var safe = true;
      var ipRuns = 0;
      await scheduler.requestCycle(
        canRun: () => safe,
        runDns: () async { safe = false; },
        runIp: () async { ipRuns++; },
      );
      expect(ipRuns, 0);
    });

    test('coalesces overlapping requests into one sequential follow-up', () async {
      final scheduler = KingScanScheduler();
      final entered = Completer<void>();
      final release = Completer<void>();
      var dnsRuns = 0;
      var ipRuns = 0;
      final first = scheduler.requestCycle(
        canRun: () => true,
        runDns: () async {
          dnsRuns++;
          if (dnsRuns == 1) {
            entered.complete();
            await release.future;
          }
        },
        runIp: () async { ipRuns++; },
      );
      await entered.future;
      await scheduler.requestCycle(
        canRun: () => true,
        runDns: () async { dnsRuns++; },
        runIp: () async { ipRuns++; },
      );
      release.complete();
      await first;
      expect(dnsRuns, 2);
      expect(ipRuns, 2);
      expect(scheduler.isRunning, isFalse);
    });
  });
}
