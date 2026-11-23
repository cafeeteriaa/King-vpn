import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/nat_ip_scan.dart';

void main() {
  group('IP range expansion and caller-controlled batches', () {
    test('scanner targets are validated, unique, and not truncated at 4096', () {
      final targets = natBoundScanTargets([
        ' 192.0.2.1 ', '192.0.2.1', 'not-an-ip', '2001:db8::1',
        ...List<String>.generate(5000, (i) => '10.${(i ~/ 65536) % 256}.${(i ~/ 256) % 256}.${i % 256}'),
      ], maxCount: 100000);
      expect(targets, containsAll(['192.0.2.1', '2001:db8::1']));
      expect(targets.toSet(), hasLength(targets.length));
      expect(targets, hasLength(5002));
      expect(natBoundScanTargets(['example.com', 'bad'],), isEmpty);
      expect(natBoundScanTargets(['192.0.2.1'], maxCount: 0), isEmpty);
    });

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

    test('CIDR expansion honors the caller batch instead of a hidden 4096 ceiling', () {
      expect(natExpandCidr('10.0.0.0/8', maxPerBlock: 5000), hasLength(5000));
    });

    test('dash range expansion honors the caller batch instead of a hidden 4096 ceiling', () {
      expect(natExpandDash('10.0.0.0-10.0.255.255', maxCount: 5000), hasLength(5000));
    });

    test('IPv6 CIDR expansion supports explicit small ranges', () {
      final result = natExpandIpv6Cidr('2001:db8::1/126', maxPerBlock: 8);
      expect(result, hasLength(4));
      expect(result.toSet(), hasLength(4));
      expect(result.every((ip) => ip.contains(':')), isTrue);
    });

    test('IPv6 CIDR sampling honors caller batch and rejects invalid input', () {
      final sampled = natExpandIpv6Cidr('2001:db8::/32', maxPerBlock: 5000);
      expect(sampled, hasLength(5000));
      expect(natExpandIpv6Cidr('10.0.0.0/24'), isEmpty);
      expect(natExpandIpv6Cidr('2001:db8::/129'), isEmpty);
      expect(natExpandIpv6Cidr('2001:db8::/64', maxPerBlock: 0), isEmpty);
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
