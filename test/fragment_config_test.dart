import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/main.dart' as app;

void main() {
  test('TLS fragmentation is wired through a real Xray outbound and survives sanitization', () {
    final previous = <bool>[
      app.fragEnabled,
      app.muxEnabled,
      app.secureDns,
      app.blockQuic,
      app.lanDirect,
      app.routeOnly,
      app.iranRoute,
      app.iranMore,
    ];
    try {
      app.fragEnabled = true;
      app.muxEnabled = false;
      app.secureDns = false;
      app.blockQuic = false;
      app.lanDirect = false;
      app.routeOnly = false;
      app.iranRoute = false;
      app.iranMore = false;

      final source = jsonEncode(<String, dynamic>{
        'inbounds': <dynamic>[],
        'outbounds': <dynamic>[
          <String, dynamic>{
            'tag': 'frag-out',
            'protocol': 'blackhole',
            'settings': <String, dynamic>{},
          },
          <String, dynamic>{
            'tag': 'frag-out',
            'protocol': 'freedom',
            'settings': <String, dynamic>{},
          },
          <String, dynamic>{
            'tag': 'proxy',
            'protocol': 'vless',
            'settings': <String, dynamic>{
              'vnext': <dynamic>[
                <String, dynamic>{
                  'address': 'edge.example.test',
                  'port': 443,
                  'users': <dynamic>[
                    <String, dynamic>{'id': '00000000-0000-4000-8000-000000000001'},
                  ],
                },
              ],
            },
            'streamSettings': <String, dynamic>{
              'network': 'tcp',
              'security': 'tls',
              'tlsSettings': <String, dynamic>{'serverName': 'edge.example.test'},
              'sockopt': <String, dynamic>{},
            },
          },
        ],
        'routing': <String, dynamic>{'rules': <dynamic>[]},
      });

      final configured = jsonDecode(app.withNpvAmCore(source)) as Map<String, dynamic>;
      final outbounds = configured['outbounds'] as List<dynamic>;
      final proxy = outbounds.firstWhere(
        (entry) => entry is Map && entry['tag'] == 'proxy',
      ) as Map;
      final proxyStream = proxy['streamSettings'] as Map;
      final sockopt = proxyStream['sockopt'] as Map;
      expect(sockopt['dialerProxy'], 'frag-out');

      final fragmentOutbound = outbounds.firstWhere(
        (entry) => entry is Map && entry['tag'] == 'frag-out',
      ) as Map;
      expect(fragmentOutbound['protocol'], 'freedom');
      final settings = fragmentOutbound['settings'] as Map;
      final fragment = settings['fragment'] as Map;
      expect(fragment['packets'], 'tlshello');
      expect(fragment['length'], app.fragLen);
      expect(fragment['interval'], app.fragInt);

      final sanitized = jsonDecode(app.sanitizeCfg(jsonEncode(configured))) as Map<String, dynamic>;
      final sanitizedOutbounds = sanitized['outbounds'] as List<dynamic>;
      final sanitizedProxy = sanitizedOutbounds.firstWhere(
        (entry) => entry is Map && entry['tag'] == 'proxy',
      ) as Map;
      final sanitizedStream = sanitizedProxy['streamSettings'] as Map;
      final sanitizedSockopt = sanitizedStream['sockopt'] as Map;
      expect(sanitizedSockopt['dialerProxy'], 'frag-out');
      expect(
        sanitizedOutbounds.where((entry) => entry is Map && entry['tag'] == 'frag-out'),
        hasLength(1),
      );
    } finally {
      app.fragEnabled = previous[0];
      app.muxEnabled = previous[1];
      app.secureDns = previous[2];
      app.blockQuic = previous[3];
      app.lanDirect = previous[4];
      app.routeOnly = previous[5];
      app.iranRoute = previous[6];
      app.iranMore = previous[7];
    }
  });
}
