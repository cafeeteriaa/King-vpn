import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/background_concurrency_policy.dart';

void main() {
  group('Adaptive background probe concurrency', () {
    test('preserves requested concurrency when CPU is cool', () {
      expect(
        adaptiveBackgroundConcurrency(
          requestedWorkers: 8,
          cpuHeat: 0,
          nationalMode: false,
        ),
        8,
      );
    });

    test('reduces concurrency under moderate CPU pressure', () {
      expect(
        adaptiveBackgroundConcurrency(
          requestedWorkers: 8,
          cpuHeat: 1,
          nationalMode: false,
        ),
        2,
      );
    });

    test('uses one background worker under severe CPU pressure', () {
      expect(
        adaptiveBackgroundConcurrency(
          requestedWorkers: 12,
          cpuHeat: 2,
          nationalMode: false,
        ),
        1,
      );
      expect(
        adaptiveBackgroundConcurrency(
          requestedWorkers: 3,
          cpuHeat: 3,
          nationalMode: true,
          nationalWorkers: 3,
        ),
        1,
      );
    });

    test('keeps national-mode concurrency policy when CPU is cool', () {
      expect(
        adaptiveBackgroundConcurrency(
          requestedWorkers: 16,
          cpuHeat: 0,
          nationalMode: true,
          nationalWorkers: 3,
        ),
        3,
      );
    });

    test('normalizes invalid values and respects the configured safe maximum', () {
      expect(
        adaptiveBackgroundConcurrency(
          requestedWorkers: 0,
          cpuHeat: 0,
          nationalMode: false,
        ),
        1,
      );
      expect(
        adaptiveBackgroundConcurrency(
          requestedWorkers: 100,
          cpuHeat: 0,
          nationalMode: false,
          maxWorkers: 6,
        ),
        6,
      );
    });
  });
}
