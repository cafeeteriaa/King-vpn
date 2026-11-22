import 'package:flutter_test/flutter_test.dart';
import '../lib/dns_policy.dart';

void main() {
  group('national DNS server policy', () {
    const domestic = <dynamic>['178.22.122.100'];

    test('filters routed DoH string servers when secure DNS is disabled', () {
      expect(
        mergeNationalDnsServers(
          domesticFirst: domestic,
          existing: const ['https://1.1.1.1/dns-query', '8.8.8.8'],
          secureDns: false,
        ),
        ['178.22.122.100', '8.8.8.8'],
      );
    });

    test('filters encrypted local-mode DoH and DoQ strings', () {
      expect(
        mergeNationalDnsServers(
          domesticFirst: domestic,
          existing: const [
            'https+local://1.1.1.1/dns-query',
            'quic+local://dns.adguard.com',
            'HTTPS://8.8.8.8/dns-query',
            'tcp://8.8.8.8:53',
          ],
          secureDns: false,
        ),
        ['178.22.122.100', 'tcp://8.8.8.8:53'],
      );
    });

    test('filters encrypted DnsServerObject entries by address', () {
      const doh = {
        'address': 'https://8.8.8.8/dns-query',
        'domains': ['domain:example.com'],
        'skipFallback': true,
      };
      const dohLocal = {'address': 'https+local://1.1.1.1/dns-query'};
      const doqLocal = {'address': 'quic+local://dns.adguard.com'};
      const udp = {
        'address': '9.9.9.9',
        'domains': ['domain:example.org'],
      };
      expect(
        mergeNationalDnsServers(
          domesticFirst: domestic,
          existing: const [doh, dohLocal, doqLocal, udp],
          secureDns: false,
        ),
        ['178.22.122.100', udp],
      );
    });

    test('retains encrypted DNS objects when secure DNS is enabled', () {
      const doh = {'address': 'https://1.1.1.1/dns-query'};
      const dohLocal = {'address': 'https+local://1.1.1.1/dns-query'};
      const doqLocal = {'address': 'quic+local://dns.adguard.com'};
      expect(
        mergeNationalDnsServers(
          domesticFirst: domestic,
          existing: const [doh, dohLocal, doqLocal],
          secureDns: true,
        ),
        ['178.22.122.100', doh, dohLocal, doqLocal],
      );
    });

    test('keeps domestic resolvers first, then bounded DoH fallback, then existing DNS', () {
      const secureFallback = <dynamic>[
        {'address': 'https://1.1.1.1/dns-query', 'timeoutMs': 1500},
      ];
      const existingDoh = {'address': 'https://8.8.8.8/dns-query'};
      expect(
        mergeNationalDnsServers(
          domesticFirst: domestic,
          existing: const [existingDoh, '185.51.200.2'],
          secureDns: true,
          secureFallback: secureFallback,
        ),
        ['178.22.122.100', secureFallback.single, existingDoh, '185.51.200.2'],
      );
    });

    test('global Secure DNS remains active in endless-search mode', () {
      expect(shouldApplyGlobalSecureDns(
        secureDns: true,
        ultraMode: false,
      ), isTrue);
      expect(shouldSerializeDnsQueries(
        secureDns: true,
        nationalMode: false,
        ultraMode: false,
      ), isTrue);
    });

    test('national Secure DNS remains sequential even with Ultra enabled', () {
      expect(shouldSerializeDnsQueries(
        secureDns: true,
        nationalMode: true,
        ultraMode: true,
      ), isTrue);
    });

    test('global Ultra mode keeps control of its DNS matrix', () {
      expect(shouldApplyGlobalSecureDns(
        secureDns: true,
        ultraMode: true,
      ), isFalse);
      expect(shouldSerializeDnsQueries(
        secureDns: true,
        nationalMode: false,
        ultraMode: true,
      ), isFalse);
    });

    test('disabling Secure DNS does not force serial queries', () {
      expect(shouldSerializeDnsQueries(
        secureDns: false,
        nationalMode: true,
        ultraMode: false,
      ), isFalse);
    });

    test('global Secure DNS tries DoH before plaintext fallback and deduplicates', () {
      const doh = {'address': 'https://1.1.1.1/dns-query', 'timeoutMs': 1500};
      expect(
        mergeGlobalDnsServers(
          encryptedFirst: const [doh, 'https://8.8.8.8/dns-query'],
          plaintextFallback: const ['1.1.1.1', '8.8.8.8', '1.1.1.1'],
        ),
        [doh, 'https://8.8.8.8/dns-query', '1.1.1.1', '8.8.8.8'],
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
