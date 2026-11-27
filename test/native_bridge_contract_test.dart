import 'package:flutter_test/flutter_test.dart';

import '../lib/native_bridge_contract.dart';

void main() {
  const packageName = 'com.kingvpn.king_vpn';

  Map<String, dynamic> validInfo() => <String, dynamic>{
        'protocolVersion': 1,
        'channel': 'vpn/bg',
        'packageName': packageName,
        'engineAttached': true,
        'vpnSettings': true,
        'back': true,
        'alive': true,
        'androidSdk': 35,
      };

  group('Android background bridge contract', () {
    test('accepts the complete current native contract', () {
      expect(
        bgBridgeInfoMatches(
          validInfo(),
          expectedProtocolVersion: 1,
          expectedPackageName: packageName,
        ),
        isTrue,
      );
    });

    test('rejects a wrong package or detached Flutter engine', () {
      final wrongPackage = validInfo()..['packageName'] = 'com.example.other';
      final detached = validInfo()..['engineAttached'] = false;

      expect(
        bgBridgeInfoMatches(
          wrongPackage,
          expectedProtocolVersion: 1,
          expectedPackageName: packageName,
        ),
        isFalse,
      );
      expect(
        bgBridgeInfoMatches(
          detached,
          expectedProtocolVersion: 1,
          expectedPackageName: packageName,
        ),
        isFalse,
      );
    });

    test('rejects missing or false capabilities and protocol mismatches', () {
      for (final capability in <String>['vpnSettings', 'back', 'alive']) {
        final broken = validInfo()..[capability] = false;
        expect(
          bgBridgeInfoMatches(
            broken,
            expectedProtocolVersion: 1,
            expectedPackageName: packageName,
          ),
          isFalse,
          reason: 'must reject unavailable $capability capability',
        );
      }

      expect(
        bgBridgeInfoMatches(
          validInfo(),
          expectedProtocolVersion: 2,
          expectedPackageName: packageName,
        ),
        isFalse,
      );
    });

    test('rejects invalid Android SDK metadata', () {
      final invalidSdk = validInfo()..['androidSdk'] = 0;
      expect(
        bgBridgeInfoMatches(
          invalidSdk,
          expectedProtocolVersion: 1,
          expectedPackageName: packageName,
        ),
        isFalse,
      );
    });
  });
}
