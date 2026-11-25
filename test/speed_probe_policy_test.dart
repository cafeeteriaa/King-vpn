import 'package:flutter_test/flutter_test.dart';
import '../lib/speed_probe_policy.dart';

void main() {
  group('speed probe response policy', () {
    test('accepts complete and partial content responses', () {
      expect(isUsableSpeedProbeResponse(200, 'application/octet-stream'), isTrue);
      expect(isUsableSpeedProbeResponse(206, 'application/octet-stream'), isTrue);
    });

    test('rejects redirects, auth failures, rate limits and server errors', () {
      for (final status in [301, 302, 304, 401, 403, 404, 429, 500, 503]) {
        expect(isUsableSpeedProbeResponse(status, 'application/octet-stream'), isFalse, reason: '$status');
      }
    });

    test('rejects HTML captive portals and JSON error pages even on HTTP 200', () {
      expect(isUsableSpeedProbeResponse(200, 'text/html; charset=utf-8'), isFalse);
      expect(isUsableSpeedProbeResponse(200, 'application/json'), isFalse);
      expect(isUsableSpeedProbeResponse(200, null), isTrue);
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

  group('throughput sample validity', () {
    test('only positive finite samples are valid', () {
      expect(isValidThroughputSample(0.01), isTrue);
      expect(isValidThroughputSample(null), isFalse);
      expect(isValidThroughputSample(0), isFalse);
      expect(isValidThroughputSample(-1), isFalse);
      expect(isValidThroughputSample(double.nan), isFalse);
      expect(isValidThroughputSample(double.infinity), isFalse);
    });
  });

  group('rolling throughput history statistics', () {
    test('median handles odd and even sample windows', () {
      expect(medianThroughput([9, 1, 5]), 5);
      expect(medianThroughput([10, 2, 8, 4]), 6);
    });

    test('median ignores invalid observations and handles empty history', () {
      expect(medianThroughput([double.nan, -1, 0, 6]), 6);
      expect(medianThroughput([double.nan, -1, 0]), isNull);
      expect(medianThroughput([]), isNull);
    });
  });

  group('throughput stability evidence', () {
    test('stable repeated samples keep full ranking weight', () {
      expect(throughputStabilityFactor([8, 8, 8]), 1);
    });

    test('variable samples receive a lower ranking weight', () {
      final stable = throughputStabilityFactor([8, 8, 8]);
      final variable = throughputStabilityFactor([2, 8, 14]);
      expect(variable, lessThan(stable));
      expect(variable, greaterThan(0));
    });

    test('even-sized windows use the central-pair median', () {
      expect(throughputStabilityFactor([2, 8, 14, 20]), closeTo(1 / (1 + 6 / 11), 0.000001));
    });

    test('one sample and invalid samples do not invent instability', () {
      expect(throughputStabilityFactor([8]), 1);
      expect(throughputStabilityFactor([0, -1, double.nan]), 1);
    });
  });
}
