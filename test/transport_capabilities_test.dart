import 'package:flutter_test/flutter_test.dart';
import '../lib/transport_capabilities.dart';

void main() {
  group('KING dual-stack capability registry', () {
    test('every catalog entry declares IPv4 and IPv6 family support', () {
      expect(kingTransportCapabilities, isNotEmpty);
      for (final capability in kingTransportCapabilities) {
        expect(capability.supports(KingAddressFamily.ipv4), isTrue,
            reason: capability.id);
        expect(capability.supports(KingAddressFamily.ipv6), isTrue,
            reason: capability.id);
      }
    });

    test('only capabilities backed by the current Xray/V2Ray config are runnable', () {
      expect(kingCapabilityCanRun('vless', KingAddressFamily.ipv4), isTrue);
      expect(kingCapabilityCanRun('vless', KingAddressFamily.ipv6), isTrue);
      expect(kingCapabilityCanRun('reality', KingAddressFamily.ipv4), isTrue);
      expect(kingCapabilityCanRun('reality', KingAddressFamily.ipv6), isTrue);
      expect(kingCapabilityCanRun('hysteria2', KingAddressFamily.ipv4), isFalse);
      expect(kingCapabilityCanRun('hysteria2', KingAddressFamily.ipv6), isFalse);
      expect(kingCapabilityCanRun('zapret-fake', KingAddressFamily.ipv4), isFalse);
      expect(kingCapabilityCanRun('zapret-fake', KingAddressFamily.ipv6), isFalse);
    });

    test('requested strategy groups are discoverable', () {
      expect(kingCapabilitiesByCategory('dpi'), isNotEmpty);
      expect(kingCapabilitiesByCategory('vpn'), isNotEmpty);
      expect(kingCapabilitiesByCategory('pluggable-transport'), isNotEmpty);
      expect(kingCapabilitiesByCategory('fronting-cdn'), isNotEmpty);
      expect(kingCapabilitiesByCategory('advanced-network'), isNotEmpty);
      expect(kingCapabilityById('slipnet-micro'), isNotNull);
      expect(kingCapabilityById('b4-fakesni-1'), isNotNull);
      expect(kingCapabilityById('b4-fakesni-2'), isNotNull);
      expect(kingCapabilityById('zerodpi-ip-bypass-plus'), isNotNull);
      expect(kingCapabilityById('tuic-v5'), isNotNull);
      expect(kingCapabilityById('pt-snowflake'), isNotNull);
    });

    test('unknown engines cannot be selected', () {
      expect(kingCapabilityCanRun('not-a-real-engine', KingAddressFamily.ipv4), isFalse);
      expect(kingCapabilityCanRun('not-a-real-engine', KingAddressFamily.ipv6), isFalse);
    });
  });
}
