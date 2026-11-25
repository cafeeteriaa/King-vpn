import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/king_domain_inventory.dart';

void main() {
  group('kingNormalizeDomainHosts', () {
    test('normalizes project rules, case and trailing root dots', () {
      expect(
        kingNormalizeDomainHosts([
          ' DOMAIN:Example.COM ',
          'full:api.example.com.',
          'example.com',
          'internal.service.ir',
        ]),
        ['example.com', 'api.example.com', 'internal.service.ir'],
      );
    });

    test('keeps IPv4 and IPv6 relay literals out of domain inventories', () {
      expect(
        kingNormalizeDomainHosts([
          '192.0.2.1',
          'domain:198.51.100.2',
          '2001:db8::1',
          'full:2001:db8::2',
          'vpn.example.com',
        ]),
        ['vpn.example.com'],
      );
    });

    test('rejects malformed labels and excessive DNS name lengths', () {
      expect(
        kingNormalizeDomainHosts([
          '.example.com',
          'bad..example.com',
          '-bad.example.com',
          'bad-.example.com',
          'bad_label.example.com',
          List.filled(64, 'a').join() + '.example.com',
          List.filled(40, 'longlabel').join('.') + '.example.com',
        ]),
        isEmpty,
      );
    });

    test('does not discard valid single-character and punycode labels', () {
      expect(
        kingNormalizeDomainHosts(['a.example', 'xn--bcher-kva.example']),
        ['a.example', 'xn--bcher-kva.example'],
      );
    });
  });
}
