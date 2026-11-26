import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/nat_ip_scan.dart';

void main() {
  group('IP range expansion limits', () {
    test('CIDR expansion rejects non-positive output limits', () {
      expect(natExpandCidr('10.0.0.0/24', maxPerBlock: 0), isEmpty);
      expect(natExpandCidr('10.0.0.0/24', maxPerBlock: -1), isEmpty);
    });

    test('CIDR sampling never exceeds a non-divisible output limit', () {
      final sampled24 = natExpandCidr('10.0.0.0/24', maxPerBlock: 100);
      final sampled16 = natExpandCidr('10.1.0.0/16', maxPerBlock: 1000);
      expect(sampled24, isNotEmpty);
      expect(sampled24.length, lessThanOrEqualTo(100));
      expect(sampled16, isNotEmpty);
      expect(sampled16.length, lessThanOrEqualTo(1000));
      expect(sampled24.toSet(), hasLength(sampled24.length));
      expect(sampled16.toSet(), hasLength(sampled16.length));
    });

    test('dash range expansion rejects non-positive output limits', () {
      expect(natExpandDash('10.0.0.1-10.0.0.3', maxCount: 0), isEmpty);
      expect(natExpandDash('10.0.0.1-10.0.0.3', maxCount: -1), isEmpty);
    });

    test('NAT scan rejects invalid budgets, timeouts, and ports without probing', () async {
      expect(await natScanIps(['127.0.0.1'], budget: Duration.zero), isEmpty);
      expect(await natScanIps(['127.0.0.1'], timeout: Duration.zero), isEmpty);
      expect(await natScanIps(['127.0.0.1'], port: 0), isEmpty);
      expect(await natScanIps(['127.0.0.1'], port: 65536), isEmpty);
    });

    test('scan without explicit hit or time limits checks the full supplied list', () async {
      final listener = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      try {
        final hits = await natScanIps(
          ['127.0.0.1', '127.0.0.1'],
          port: listener.port,
          concurrency: 1,
          timeout: const Duration(seconds: 1),
        );
        expect(hits, hasLength(2));
        expect(hits.map((hit) => hit.ip), everyElement('127.0.0.1'));
      } finally {
        await listener.close();
      }
    });

    test('adaptive concurrency always returns a bounded integer', () {
      expect(natAdaptiveConcurrency(0), isA<int>());
      expect(natAdaptiveConcurrency(0), inInclusiveRange(8, 64));
      expect(natAdaptiveConcurrency(1), 1);
      expect(natAdaptiveConcurrency(999999), lessThanOrEqualTo(256));
    });

    test('cancelled NAT scan exits without opening sockets', () async {
      final result = await natScanIps(
        ['127.0.0.1'],
        cancelled: () => true,
      );
      expect(result, isEmpty);
    });

    test('valid limits preserve expected expansion', () {
      expect(natExpandCidr('10.0.0.0/30', maxPerBlock: 4), hasLength(4));
      expect(natExpandDash('10.0.0.1-10.0.0.3', maxCount: 3), hasLength(3));
    });
  });
}
