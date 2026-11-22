import 'package:flutter_test/flutter_test.dart';
import '../lib/dns_policy.dart';

void main() {
  group('national DNS server policy', () {
    const domestic = <dynamic>['178.22.122.100'];

    test('filters DoH string servers when secure DNS is disabled', () {
      expect(
        mergeNationalDnsServers(
          domesticFirst: domestic,
          existing: const ['https://1.1.1.1/dns-query', '8.8.8.8'],
          secureDns: false,
        ),
        ['178.22.122.100', '8.8.8.8'],
      );
    });

    test('filters DoH DnsServerObject entries by their address field', () {
      const doh = {
        'address': 'https://8.8.8.8/dns-query',
        'domains': ['domain:example.com'],
        'skipFallback': true,
      };
      const udp = {
        'address': '9.9.9.9',
        'domains': ['domain:example.org'],
      };
      expect(
        mergeNationalDnsServers(
          domesticFirst: domestic,
          existing: const [doh, udp],
          secureDns: false,
        ),
        ['178.22.122.100', udp],
      );
    });

    test('retains DoH objects when secure DNS is enabled', () {
      const doh = {'address': 'https://1.1.1.1/dns-query'};
      expect(
        mergeNationalDnsServers(
          domesticFirst: domestic,
          existing: const [doh],
          secureDns: true,
        ),
        ['178.22.122.100', doh],
      );
    });

    test('keeps domestic resolvers first and removes duplicate entries', () {
      expect(
        mergeNationalDnsServers(
          domesticFirst: domestic,
          existing: const ['178.22.122.100', '185.51.200.2'],
          secureDns: false,
        ),
        ['178.22.122.100', '185.51.200.2'],
      );
    });
  });
}
