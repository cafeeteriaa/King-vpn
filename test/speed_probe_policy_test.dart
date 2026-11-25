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
