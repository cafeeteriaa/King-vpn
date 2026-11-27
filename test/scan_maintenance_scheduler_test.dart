import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/scan_maintenance_scheduler.dart';

void main() {
  group('KING scan maintenance scheduler', () {
    test('runs DNS then IP in order', () async {
      final events = <String>[];
      final scheduler = KingScanMaintenanceScheduler(
        shouldRun: () => true,
        runDns: () async => events.add('dns'),
        runIp: () async => events.add('ip'),
      );

      await scheduler.runOnce();

      expect(events, ['dns', 'ip']);
      scheduler.dispose();
    });

    test('coalesces overlapping cycles instead of running scanners concurrently', () async {
      final gate = Completer<void>();
      final events = <String>[];
      var dnsCalls = 0;
      final scheduler = KingScanMaintenanceScheduler(
        shouldRun: () => true,
        runDns: () {
          dnsCalls++;
          events.add('dns-start');
          return gate.future.whenComplete(() => events.add('dns-end'));
        },
        runIp: () async => events.add('ip'),
      );

      final first = scheduler.runOnce();
      final second = scheduler.runOnce();
      expect(identical(first, second), isTrue);
      expect(dnsCalls, 1);
      expect(events, ['dns-start']);

      gate.complete();
      await first;

      expect(events, ['dns-start', 'dns-end', 'ip']);
      scheduler.dispose();
    });

    test('does not start IP when the app becomes ineligible after DNS', () async {
      var eligible = true;
      var ipCalls = 0;
      final scheduler = KingScanMaintenanceScheduler(
        shouldRun: () => eligible,
        runDns: () async => eligible = false,
        runIp: () async => ipCalls++,
      );

      await scheduler.runOnce();

      expect(ipCalls, 0);
      scheduler.dispose();
    });

    test('continues to IP after a DNS failure and reports the error', () async {
      final events = <String>[];
      final errors = <Object>[];
      final scheduler = KingScanMaintenanceScheduler(
        shouldRun: () => true,
        runDns: () async => throw StateError('DNS unavailable'),
        runIp: () async => events.add('ip'),
        onError: (error, _) => errors.add(error),
      );

      await scheduler.runOnce();

      expect(errors, hasLength(1));
      expect(events, ['ip']);
      scheduler.dispose();
    });

    test('stop invalidates an in-flight cycle before the next scanner starts', () async {
      final gate = Completer<void>();
      final events = <String>[];
      final scheduler = KingScanMaintenanceScheduler(
        shouldRun: () => true,
        runDns: () => gate.future,
        runIp: () async => events.add('ip'),
      );

      final run = scheduler.runOnce();
      scheduler.stop();
      gate.complete();
      await run;

      expect(events, isEmpty);
      expect(scheduler.isScheduled, isFalse);
      scheduler.dispose();
    });

    test('rejects a zero or negative schedule interval', () {
      expect(
        () => KingScanMaintenanceScheduler(
          shouldRun: () => true,
          runDns: () async {},
          runIp: () async {},
          interval: Duration.zero,
        ),
        throwsArgumentError,
      );
    });
  });
}
