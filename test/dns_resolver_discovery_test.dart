import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/dns_resolver_discovery.dart';

void main() {
  group('kingParsePublicDnsResolvers', () {
    test('retains every valid IPv4 and IPv6 resolver without scope filtering', () {
      expect(
        kingParsePublicDnsResolvers('''
8.8.8.8
1.1.1.1
10.0.0.53
192.168.1.1
127.0.0.1
2001:4860:4860::8888
fe80::1
# comment
not-an-ip
'''),
        containsAll([
          '8.8.8.8',
          '1.1.1.1',
          '10.0.0.53',
          '192.168.1.1',
          '127.0.0.1',
          '2001:4860:4860::8888',
          'fe80::1',
        ]),
      );
    });

    test('accepts whitespace, CSV separators and bracketed IPv6 literals', () {
      expect(
        kingParsePublicDnsResolvers('8.8.4.4, 9.9.9.9\n[2606:4700:4700::1111]'),
        containsAll(['8.8.4.4', '9.9.9.9', '2606:4700:4700::1111']),
      );
    });

    test('deduplicates normalized addresses and ignores malformed tokens', () {
      final result = kingParsePublicDnsResolvers(
        '1.1.1.1\n1.1.1.1\n999.999.999.999\nexample.com',
      );
      expect(result, ['1.1.1.1']);
    });
  });
}
