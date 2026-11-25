import 'package:flutter_test/flutter_test.dart';
import '../lib/speed_probe_policy.dart';

void main() {
  group('speed probe response policy', () {
    test('accepts complete and partial content responses', () {
      expect(isUsableSpeedProbeStatus(200), isTrue);
      expect(isUsableSpeedProbeStatus(206), isTrue);
    });

    test('rejects redirects, auth failures, rate limits and server errors', () {
      for (final status in [301, 302, 304, 401, 403, 404, 429, 500, 503]) {
        expect(isUsableSpeedProbeStatus(status), isFalse, reason: '$status');
      }
    });

    test('converts bytes and elapsed time to MiB per second', () {
      expect(throughputMegabytesPerSecond(
        bytes: 2 * 1024 * 1024,
        elapsedMilliseconds: 2000,
      ), 1.0);
    });

    test('rejects empty or zero-duration measurements', () {
      expect(throughputMegabytesPerSecond(bytes: 0, elapsedMilliseconds: 1000), isNull);
      expect(throughputMegabytesPerSecond(bytes: 100, elapsedMilliseconds: 0), isNull);
      expect(throughputMegabytesPerSecond(bytes: -1, elapsedMilliseconds: 1000), isNull);
    });
  });
}

  group('age-adjusted throughput ranking', () {
    final now = DateTime.utc(2026, 11, 25, 12);

    test('fresh measurements retain their measured throughput', () {
      expect(ageAdjustedThroughput(
        megabytesPerSecond: 8,
        measuredAt: now,
        now: now,
      ), 8);
    });

    test('older measurements decay continuously instead of expiring', () {
      final value = ageAdjustedThroughput(
        megabytesPerSecond: 8,
        measuredAt: now.subtract(const Duration(minutes: 15)),
        now: now,
      );
      expect(value, closeTo(4, 0.000001));
      expect(value, greaterThan(0));
    });

    test('missing, invalid and future measurements are not ranked', () {
      expect(ageAdjustedThroughput(megabytesPerSecond: null, measuredAt: now, now: now), isNull);
      expect(ageAdjustedThroughput(megabytesPerSecond: 0, measuredAt: now, now: now), isNull);
      expect(ageAdjustedThroughput(megabytesPerSecond: 2, measuredAt: null, now: now), isNull);
      expect(ageAdjustedThroughput(megabytesPerSecond: 2, measuredAt: now.add(const Duration(seconds: 1)), now: now), isNull);
    });
  });

  group('age-adjusted throughput ranking', () {
    final now = DateTime.utc(2026, 11, 25, 12);

    test('fresh measurements retain their measured throughput', () {
      expect(ageAdjustedThroughput(
        megabytesPerSecond: 8,
        measuredAt: now,
        now: now,
      ), 8);
    });

    test('older measurements decay continuously instead of expiring', () {
      final value = ageAdjustedThroughput(
        megabytesPerSecond: 8,
        measuredAt: now.subtract(const Duration(minutes: 15)),
        now: now,
      );
      expect(value, closeTo(4, 0.000001));
      expect(value, greaterThan(0));
    });

    test('missing, invalid and future measurements are not ranked', () {
      expect(ageAdjustedThroughput(megabytesPerSecond: null, measuredAt: now, now: now), isNull);
      expect(ageAdjustedThroughput(megabytesPerSecond: 0, measuredAt: now, now: now), isNull);
      expect(ageAdjustedThroughput(megabytesPerSecond: 2, measuredAt: null, now: now), isNull);
      expect(ageAdjustedThroughput(megabytesPerSecond: 2, measuredAt: now.add(const Duration(seconds: 1)), now: now), isNull);
    });
  });

}
