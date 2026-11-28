import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/nat_ip_scan.dart';

void main() {
  group('RIPE country and BGP prefix inventory parsing', () {
    test('parses IPv4, IPv6 prefixes and ASN identifiers independently', () {
      final snapshot = NatCountryPrefixSnapshot.parseCountryResources({
        'status': 'ok',
        'data': {
          'resources': {
            'ipv4': [
              '2.144.0.0/18',
              '5.10.20.1',
              '5.10.30.0-5.10.30.7',
              'not-an-ip',
              '2001:db8::/32',
            ],
            'ipv6': [
              '2001:db8::/32',
              '2001:db8:1::/48',
              '2001:db8::1',
              '192.0.2.0/24',
              '2001:db8::/129',
            ],
            'asn': ['AS12880', '12881', 'AS0', 'invalid', -1],
          },
        },
      });

      expect(snapshot, isNotNull);
      expect(snapshot!.ipv4, containsAll([
        '2.144.0.0/18',
        '5.10.20.1',
        '5.10.30.0-5.10.30.7',
      ]));
      expect(snapshot.ipv4, hasLength(3));
      expect(snapshot.ipv6, containsAll([
        '2001:db8::/32',
        '2001:db8:1::/48',
        '2001:db8::1/128',
      ]));
      expect(snapshot.ipv6, hasLength(3));
      expect(snapshot.asns, ['AS12880', 'AS12881']);
    });

    test('rejects unsuccessful or malformed country responses', () {
      expect(NatCountryPrefixSnapshot.parseCountryResources(null), isNull);
      expect(NatCountryPrefixSnapshot.parseCountryResources({
        'status': 'error',
        'data': {'resources': {'ipv4': ['2.144.0.0/18']}},
      }), isNull);
      expect(NatCountryPrefixSnapshot.parseCountryResources({
        'status': 'ok',
        'data': {'resources': {'ipv4': ['not-an-ip'], 'ipv6': ['bad'], 'asn': []}},
      }), isNull);
    });

    test('parses announced IPv4 prefixes and ignores IPv6 or malformed entries', () {
      final prefixes = NatCountryPrefixSnapshot.parseAnnouncedIpv4({
        'status': 'ok',
        'data': {
          'prefixes': [
            {'prefix': '2.144.0.0/18'},
            {'prefix': '5.10.20.0/24'},
            {'prefix': '2001:db8::/32'},
            {'prefix': 'bad'},
            {'other': 'missing-prefix'},
          ],
        },
      });
      expect(prefixes, ['2.144.0.0/18', '5.10.20.0/24']);
      expect(
        NatCountryPrefixSnapshot.parseAnnouncedIpv4({'status': 'error'}),
        isEmpty,
      );
      expect(
        NatCountryPrefixSnapshot.parseAnnouncedIpv6({
          'status': 'ok',
          'data': {
            'prefixes': [
              {'prefix': '2001:db8::/32'},
              {'prefix': '2.144.0.0/18'},
              {'prefix': '2001:db8::/129'},
            ],
          },
        }),
        ['2001:db8::/32'],
      );
    });
  });
}
