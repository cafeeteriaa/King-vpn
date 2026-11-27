import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/main.dart';

void main() {
  group('KING Net Melli exact endpoint inventory', () {
    test('keeps IPv4 and IPv6 as exact host targets only', () {
      expect(
        natSeedBlocks(<String>[
          '203.0.113.10',
          '2001:db8::1',
          '2001:db8::1',
          '10.0.0.1',
        ]),
        <String>['203.0.113.10/32', '2001:db8::1/128', '10.0.0.1/32'],
      );
    });

    test('does not infer neighboring subnets from a single endpoint', () {
      final blocks = natSeedBlocks(<String>['2001:db8::abcd']);
      expect(blocks, <String>['2001:db8::abcd/128']);
      expect(blocks, isNot(contains('2001:db8::/64')));
    });
  });
}
