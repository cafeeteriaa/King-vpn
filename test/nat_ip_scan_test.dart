import 'dart:io';

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

    test('CIDR expansion accepts the complete IPv4 address space', () {
      final fullSpace = natExpandCidr('0.0.0.0/0', maxPerBlock: 4);
      expect(fullSpace, isNotEmpty);
      expect(fullSpace, hasLength(4));
    });

    test('IPv6 CIDR expansion supports /0 through /128 without 32-bit truncation', () {
      expect(natExpandIpv6Cidr('::/0', maxPerBlock: 3), hasLength(3));
      expect(natExpandIpv6Cidr('2001:db8::/32', maxPerBlock: 4), hasLength(4));
      expect(natExpandIpv6Cidr('2001:db8::1/128'), hasLength(1));
      expect(natExpandIpv6Cidr('2001:db8::/129'), isEmpty);
    });

    test('single IPv4 and IPv6 addresses are exhausted after one probe', () {
      for (final address in ['192.0.2.1', '2001:4860:4860::8888']) {
        final first = natExpandIpRangeCursor(address, '0', maxPerBlock: 8);
        expect(first.addresses, [address]);
        expect(first.nextCursor, 'done');
        final second = natExpandIpRangeCursor(
          address, first.nextCursor, maxPerBlock: 8,
        );
        expect(second.addresses, isEmpty);
        expect(second.nextCursor, 'done');
      }
      final v6 = natExpandIpRangeCursor('2001:4860::1/128', '0');
      expect(v6.addresses, ['2001:4860::1']);
      expect(v6.nextCursor, 'done');
    });

    test('generic IP range cursor accepts IPv4 /0 and wraps at the full address-space boundary', () {
      final batch = natExpandIpRangeCursor(
        '0.0.0.0/0', '4294967294', maxPerBlock: 3,
      );
      expect(batch.addresses, [
        '255.255.255.254',
        '255.255.255.255',
        '0.0.0.0',
      ]);
      expect(batch.nextCursor, '1');
    });

    test('non-wrapping cursors visit every IPv4 and IPv6 address exactly once', () {
      for (final range in ['192.0.2.0/30', '2001:db8::/126']) {
        var cursor = '0';
        final addresses = <String>[];
        while (cursor != 'done') {
          final batch = natExpandIpRangeCursor(
            range,
            cursor,
            maxPerBlock: 2,
            wrap: false,
          );
          addresses.addAll(batch.addresses);
          cursor = batch.nextCursor;
        }
        expect(addresses, hasLength(4));
        expect(addresses.toSet(), hasLength(4));
        final again = natExpandIpRangeCursor(
          range, cursor, maxPerBlock: 2, wrap: false,
        );
        expect(again.addresses, isEmpty);
      }
    });

    test('IPv6 range cursors cover each address and wrap without 64-bit truncation', () {
      final first = natExpandIpv6RangeCursor(
        '2001:db8::/126', '0', maxPerBlock: 2,
      );
      expect(first.addresses, ['2001:db8::', '2001:db8::1']);
      expect(first.nextCursor, '2');

      final second = natExpandIpv6RangeCursor(
        '2001:db8::/126', first.nextCursor, maxPerBlock: 2,
      );
      expect(second.addresses, ['2001:db8::2', '2001:db8::3']);
      expect(second.nextCursor, '0');

      final hugeCursor = natExpandIpv6RangeCursor(
        '::/0', '18446744073709551616', maxPerBlock: 1,
      );
      expect(hugeCursor.addresses, hasLength(1));
      expect(InternetAddress.tryParse(hugeCursor.addresses.single)?.type,
          InternetAddressType.IPv6);
      expect(hugeCursor.nextCursor, '18446744073709551617');
    });

    test('IPv6 dash ranges resume from a 128-bit cursor', () {
      final batch = natExpandIpv6RangeCursor(
        '2001:db8::1-2001:db8::3', '2', maxPerBlock: 2,
      );
      expect(batch.addresses, ['2001:db8::3', '2001:db8::1']);
      expect(batch.nextCursor, '1');
    });

    test('linear dash range expansion accepts IPv6 endpoints', () {
      expect(
        natExpandDash('2001:db8::1-2001:db8::3', maxCount: 3),
        ['2001:db8::1', '2001:db8::2', '2001:db8::3'],
      );
      expect(
        natExpandDash('2001:db8::1-2001:db8::3', maxCount: 2),
        ['2001:db8::1', '2001:db8::2'],
      );
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
