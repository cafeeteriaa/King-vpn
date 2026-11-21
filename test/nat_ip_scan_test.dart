import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/nat_ip_scan.dart';

void main() {
  group('dual-stack scanner endpoint helpers', () {
    test('exact host CIDR preserves IPv4 and IPv6 as single hosts', () {
      expect(natExactHostCidr('192.0.2.8'), '192.0.2.8/32');
      expect(natExactHostCidr('2001:db8::8'), '2001:db8::8/128');
      expect(natExactHostCidr('not-an-ip'), isNull);
    });
    test('persisted scanner endpoints accept valid IPv4 and IPv6 only', () {
      expect(natIsIpPortCandidate('192.0.2.8|443'), isTrue);
      expect(natIsIpPortCandidate('2001:db8::8|443'), isTrue);
      expect(natIsIpPortCandidate('2001:db8::8|0'), isFalse);
      expect(natIsIpPortCandidate('example.com|443'), isFalse);
      expect(natIsIpPortCandidate('192.0.2.8|70000'), isFalse);
    });
  });

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

    test('IPv6 CIDR dispatch expands a small subnet without losing IPv4 behavior', () {
      expect(
        natExpandCidr('2001:db8::1/126'),
        ['2001:db8::', '2001:db8::1', '2001:db8::2', '2001:db8::3'],
      );
      expect(natExpandCidr('10.0.0.0/30'), [
        '10.0.0.0', '10.0.0.1', '10.0.0.2', '10.0.0.3',
      ]);
    });

    test('IPv6 CIDR sampling stays bounded for very large prefixes', () {
      final sampled = natExpandCidr('2001:4860::/32', maxPerBlock: 17);
      expect(sampled, hasLength(17));
      expect(sampled.toSet(), hasLength(17));
      expect(sampled.every((ip) => ip.contains(':')), isTrue);
      expect(natExpandCidr('::/0', maxPerBlock: 8), hasLength(8));
    });

    test('IPv6 CIDR helper rejects malformed and non-IPv6 inputs', () {
      expect(natExpandIpv6Cidr('10.0.0.0/24'), isEmpty);
      expect(natExpandIpv6Cidr('2001:db8::/129'), isEmpty);
      expect(natExpandIpv6Cidr('2001:db8::/64', maxPerBlock: 0), isEmpty);
      expect(natExpandIpv6Cidr('not-an-ip/64'), isEmpty);
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

    test('NAT scanner returns no hits for hostname-only input', () async {
      expect(
        await natScanIps(['localhost', 'example.com']),
        isEmpty,
      );
      expect(
        await natTcpProbe('localhost', 443, const Duration(seconds: 1)),
        isNull,
      );
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

    test('CIDR and dash expansion clamp excessive caller limits', () {
      final cidr = natExpandCidr('10.0.0.0/8', maxPerBlock: 999999999);
      final dash = natExpandDash(
        '0.0.0.0-255.255.255.255',
        maxCount: 999999999,
      );
      expect(cidr, hasLength(65536));
      expect(dash, hasLength(65536));
    });

    test('valid limits preserve expected expansion', () {
      expect(natExpandCidr('10.0.0.0/30', maxPerBlock: 4), hasLength(4));
      expect(natExpandDash('10.0.0.1-10.0.0.3', maxCount: 3), hasLength(3));
    });
  });
}
