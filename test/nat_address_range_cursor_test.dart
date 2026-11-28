import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/nat_ip_scan.dart';

void main() {
  group('NatAddressRangeCursor', () {
    test('walks a CIDR completely in bounded resumable slices', () {
      final range = NatAddressRangeCursor.parse('192.0.2.7/30')!;
      expect(range.addressCount, 4);
      final first = range.read(0, 2);
      expect(first.$1, ['192.0.2.4', '192.0.2.5']);
      expect(first.$2, 2);
      final second = range.read(first.$2, 2);
      expect(second.$1, ['192.0.2.6', '192.0.2.7']);
      expect(second.$2, -1);
    });

    test('does not sample or truncate a full IPv4 address space', () {
      final range = NatAddressRangeCursor.parse('0.0.0.0/0')!;
      expect(range.addressCount, 4294967296);
      final tail = range.read(4294967294, 8);
      expect(tail.$1, ['255.255.255.254', '255.255.255.255']);
      expect(tail.$2, -1);
    });

    test('normalizes reversed explicit IPv4 ranges', () {
      final range = NatAddressRangeCursor.parse('198.51.100.3-198.51.100.1')!;
      expect(range.addressCount, 3);
      expect(range.read(0, 10).$1,
          ['198.51.100.1', '198.51.100.2', '198.51.100.3']);
    });

    test('accepts exact IPv6 endpoints without enumerating broad prefixes', () {
      final exact = NatAddressRangeCursor.parse('2001:db8::1/128')!;
      expect(exact.read(0, 1).$1, ['2001:db8::1']);
      expect(exact.read(1, 1).$2, -1);
      expect(NatAddressRangeCursor.parse('2001:db8::/64'), isNull);
    });

    test('rejects malformed, negative, and zero-sized requests safely', () {
      expect(NatAddressRangeCursor.parse('not-an-ip'), isNull);
      final range = NatAddressRangeCursor.parse('203.0.113.1')!;
      expect(range.read(-1, 5).$1, isEmpty);
      expect(range.read(0, 0).$1, isEmpty);
      expect(range.read(1, 5).$2, -1);
    });
  });
}
