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

    test('adaptive concurrency follows device CPU capacity without a fixed global cap', () {
      final cores = Platform.numberOfProcessors < 1 ? 1 : Platform.numberOfProcessors;
      expect(natAdaptiveConcurrency(0), cores * 2);
      expect(natAdaptiveConcurrency(-1), cores * 2);
      expect(natAdaptiveConcurrency(1), 1);
      expect(natAdaptiveConcurrency(cores * 4), cores * 4);
      expect(natAdaptiveConcurrency(999999), cores * 4);
    });

    test('scans an explicit IPv6 endpoint when loopback IPv6 is available', () async {
      ServerSocket? listener;
      try {
        listener = await ServerSocket.bind(InternetAddress.loopbackIPv6, 0);
      } on SocketException {
        // Some CI/container environments disable IPv6 loopback entirely.
        return;
      }
      final accepted = listener.listen((socket) => socket.destroy());
      try {
        final hits = await natScanIps(
          <String>['::1'],
          port: listener.port,
          concurrency: 1,
          want: 1,
          timeout: const Duration(seconds: 2),
        );
        expect(hits, hasLength(1));
        expect(hits.single.ip, '::1');
      } finally {
        await accepted.cancel();
        await listener.close();
      }
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
  group('resumable address range cursor', () {
    test('walks an explicit range exactly once across multiple slices', () {
      final cursor = NatAddressRangeCursor.parse('10.0.0.1-10.0.0.4')!;
      expect(cursor.addressCount, 4);

      final first = cursor.read(0, 2);
      expect(first.$1, ['10.0.0.1', '10.0.0.2']);
      expect(first.$2, 2);

      final second = cursor.read(first.$2, 2);
      expect(second.$1, ['10.0.0.3', '10.0.0.4']);
      expect(second.$2, -1);

      expect(cursor.read(0, 2).$1, first.$1);
      final exhausted = cursor.read(4, 2);
      expect(exhausted.$1, isEmpty);
      expect(exhausted.$2, -1);
    });

    test('supports the complete IPv4 space through bounded resumable slices', () {
      final cursor = NatAddressRangeCursor.parse('203.0.113.9/0')!;
      expect(cursor.addressCount, 4294967296);

      final beginning = cursor.read(0, 3);
      expect(beginning.$1, ['0.0.0.0', '0.0.0.1', '0.0.0.2']);
      expect(beginning.$2, 3);

      final ending = cursor.read(4294967294, 8);
      expect(ending.$1, ['255.255.255.254', '255.255.255.255']);
      expect(ending.$2, -1);
    });

    test('normalizes CIDR host bits and validates range direction', () {
      final cidr = NatAddressRangeCursor.parse('10.0.0.7/30')!;
      expect(cidr.addressCount, 4);
      expect(cidr.read(0, 8).$1,
          ['10.0.0.4', '10.0.0.5', '10.0.0.6', '10.0.0.7']);

      final reversed = NatAddressRangeCursor.parse('10.0.0.4-10.0.0.1')!;
      expect(reversed.read(0, 4).$1,
          ['10.0.0.1', '10.0.0.2', '10.0.0.3', '10.0.0.4']);
      expect(NatAddressRangeCursor.parse('10.0.0.1/33'), isNull);
      expect(NatAddressRangeCursor.parse('10.0.0.1/24/8'), isNull);
    });

    test('accepts exact IPv6 endpoints but does not expand broad prefixes', () {
      final address = NatAddressRangeCursor.parse('2001:4860:4860::8888/128')!;
      expect(address.addressCount, 1);
      expect(address.read(0, 1).$1, hasLength(1));
      expect(NatAddressRangeCursor.parse('2001:4860::/64'), isNull);
      expect(NatAddressRangeCursor.parse('2001:4860::1'), isNotNull);
    });

    test('rejects invalid offsets and non-positive slice sizes', () {
      final cursor = NatAddressRangeCursor.parse('192.0.2.1/32')!;
      final negativeOffset = cursor.read(-1, 1);
      expect(negativeOffset.$1, isEmpty);
      expect(negativeOffset.$2, -1);
      final zeroLimit = cursor.read(0, 0);
      expect(zeroLimit.$1, isEmpty);
      expect(zeroLimit.$2, -1);
      final negativeLimit = cursor.read(0, -4);
      expect(negativeLimit.$1, isEmpty);
      expect(negativeLimit.$2, -1);
      final exhausted = cursor.read(1, 1);
      expect(exhausted.$1, isEmpty);
      expect(exhausted.$2, -1);
    });
  });

}
