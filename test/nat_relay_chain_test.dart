import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/nat_relay_chain.dart';

void main() {
  Map<String, dynamic> exitConfig({bool collision = false}) => {
        'inbounds': [
          {'tag': 'tun-in', 'port': 10808}
        ],
        'outbounds': [
          {
            'tag': 'exit',
            'protocol': 'vless',
            'settings': {'vnext': []},
            'streamSettings': {
              'sockopt': {
                'tcpNoDelay': true,
                'dialerProxy': 'old-hop',
              }
            }
          },
          if (collision)
            {'tag': 'relay-hop', 'protocol': 'freedom', 'settings': {}},
          {'tag': 'direct', 'protocol': 'freedom', 'settings': {}},
        ],
      };

  Map<String, dynamic> relayConfig() => {
        'outbounds': [
          {
            'tag': 'relay',
            'protocol': 'vmess',
            'settings': {'vnext': []},
            'streamSettings': {
              'sockopt': {'tcpFastOpen': true, 'dialerProxy': 'nested-hop'}
            }
          }
        ],
      };

  group('fresh verified relay evidence', () {
    final now = DateTime.utc(2026, 11, 23, 12);

    test('accepts only a recent verified data-plane result', () {
      expect(
        natIsFreshVerifiedRelay(
          verified: true,
          verifiedAt: now.subtract(const Duration(minutes: 10)),
          now: now,
          maxAge: const Duration(hours: 48),
        ),
        isTrue,
      );
      expect(
        natIsFreshVerifiedRelay(
          verified: false,
          verifiedAt: now.subtract(const Duration(minutes: 1)),
          now: now,
          maxAge: const Duration(hours: 48),
        ),
        isFalse,
      );
    });

    test('rejects missing, stale, future, and invalid-age evidence', () {
      expect(
        natIsFreshVerifiedRelay(
          verified: true,
          verifiedAt: null,
          now: now,
          maxAge: const Duration(hours: 48),
        ),
        isFalse,
      );
      expect(
        natIsFreshVerifiedRelay(
          verified: true,
          verifiedAt: now.subtract(const Duration(hours: 48)),
          now: now,
          maxAge: const Duration(hours: 48),
        ),
        isFalse,
      );
      expect(
        natIsFreshVerifiedRelay(
          verified: true,
          verifiedAt: now.add(const Duration(seconds: 1)),
          now: now,
          maxAge: const Duration(hours: 48),
        ),
        isFalse,
      );
      expect(
        natIsFreshVerifiedRelay(
          verified: true,
          verifiedAt: now,
          now: now,
          maxAge: Duration.zero,
        ),
        isFalse,
      );
    });
  });

  group('national relay chain config', () {
    test('routes exit through relay and keeps unrelated socket options', () {
      final result = natBuildRelayChainConfig(
        jsonEncode(exitConfig()),
        jsonEncode(relayConfig()),
        keepInbounds: true,
      );
      expect(result, isNotNull);
      final decoded = jsonDecode(result!) as Map<String, dynamic>;
      final outbounds = decoded['outbounds'] as List;
      final exit = outbounds.firstWhere((x) => x['tag'] == 'exit');
      final relay = outbounds.firstWhere((x) => x['tag'] == 'relay-hop');
      final exitSockopt = exit['streamSettings']['sockopt'];
      final relaySockopt = relay['streamSettings']['sockopt'];

      expect(exitSockopt['dialerProxy'], 'relay-hop');
      expect(exitSockopt['tcpNoDelay'], isTrue);
      expect(relaySockopt['tcpFastOpen'], isTrue);
      expect(relaySockopt.containsKey('dialerProxy'), isFalse);
      expect(decoded['inbounds'], isNotEmpty);
    });

    test('chooses a collision-free relay tag', () {
      final result = natBuildRelayChainConfig(
        jsonEncode(exitConfig(collision: true)),
        jsonEncode(relayConfig()),
      );
      expect(result, isNotNull);
      final decoded = jsonDecode(result!) as Map<String, dynamic>;
      final outbounds = decoded['outbounds'] as List;
      final tags = outbounds.map((x) => x['tag']).toList();
      expect(tags.where((x) => x == 'relay-hop'), hasLength(1));
      expect(tags.where((x) => x == 'relay-hop-2'), hasLength(1));
      expect(outbounds.firstWhere((x) => x['tag'] == 'exit')
          ['streamSettings']['sockopt']['dialerProxy'], 'relay-hop-2');
    });

    test('removes exit inbounds unless explicitly requested', () {
      final result = natBuildRelayChainConfig(
        jsonEncode(exitConfig()),
        jsonEncode(relayConfig()),
      );
      expect(result, isNotNull);
      expect((jsonDecode(result!) as Map).containsKey('inbounds'), isFalse);
    });

    test('rejects unsupported or malformed proxy configurations', () {
      final unsupported = {
        'outbounds': [
          {'tag': 'direct', 'protocol': 'freedom'}
        ]
      };
      expect(
        natBuildRelayChainConfig(
          jsonEncode(unsupported),
          jsonEncode(relayConfig()),
        ),
        isNull,
      );
      expect(natBuildRelayChainConfig('{bad json', jsonEncode(relayConfig())),
          isNull);
      expect(
        natBuildRelayChainConfig(jsonEncode(exitConfig()), '{"outbounds":[]}'),
        isNull,
      );
    });
  });
}
