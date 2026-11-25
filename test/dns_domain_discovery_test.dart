import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/dns_domain_discovery.dart';

void main() {
  group('Majestic global DNS domain discovery', () {
    test('extracts the Domain column and ignores the CSV header', () {
      expect(
        kingMajesticDomainFromCsvLine(
          '1,1,example.com,com,10,20,example.com,com,1,1,10,20',
        ),
        'example.com',
      );
      expect(
        kingMajesticDomainFromCsvLine(
          'GlobalRank,TldRank,Domain,TLD,RefSubNets,RefIPs',
        ),
        isNull,
      );
    });

    test('normalizes host casing and rejects malformed rows', () {
      expect(
        kingMajesticDomainFromCsvLine('2,2,WWW.Example.ORG,org,5,10'),
        'www.example.org',
      );
      expect(kingMajesticDomainFromCsvLine('bad,row'), isNull);
      expect(kingMajesticDomainFromCsvLine('3,3,999.999.999.999,com'), isNull);
    });
  });
}
