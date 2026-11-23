import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/nat_sni_policy.dart';

void main() {
  Map<String, dynamic> tlsProxy(String protocol, String name,
          {bool ech = false, bool insecure = true}) =>
      {
        'protocol': protocol,
        'settings': <String, dynamic>{},
        'streamSettings': {
          'security': 'tls',
          'tlsSettings': {
            'serverName': name,
            if (ech) 'echConfigList': 'AAECAw==',
            if (insecure) 'allowInsecure': true,
          },
        },
      };

  test('changes only the primary TLS proxy and keeps certificate validation', () {
    final source = {
      'outbounds': [
        tlsProxy('vless', 'origin.example'),
        tlsProxy('trojan', 'relay.example'),
        tlsProxy('freedom', 'direct.example'),
      ],
    };

    final result = jsonDecode(natSetPrimaryProxyTlsServerName(
      jsonEncode(source),
      'front.example',
    )) as Map<String, dynamic>;
    final outbounds = result['outbounds'] as List;
    final primaryTls = outbounds[0]['streamSettings']['tlsSettings'];
    final relayTls = outbounds[1]['streamSettings']['tlsSettings'];
    final directTls = outbounds[2]['streamSettings']['tlsSettings'];

    expect(primaryTls['serverName'], 'front.example');
    expect(primaryTls.containsKey('allowInsecure'), isFalse);
    expect(relayTls['serverName'], 'relay.example');
    expect(relayTls['allowInsecure'], isTrue);
    expect(directTls['serverName'], 'direct.example');
  });

  test('leaves ECH-enabled primary proxy and later hops unchanged', () {
    final source = {
      'outbounds': [
        tlsProxy('vless', 'ech-origin.example', ech: true),
        tlsProxy('trojan', 'relay.example'),
      ],
    };

    final result = jsonDecode(natSetPrimaryProxyTlsServerName(
      jsonEncode(source),
      'front.example',
    )) as Map<String, dynamic>;
    final outbounds = result['outbounds'] as List;

    expect(outbounds[0]['streamSettings']['tlsSettings']['serverName'],
        'ech-origin.example');
    expect(outbounds[1]['streamSettings']['tlsSettings']['serverName'],
        'relay.example');
  });

  test('does not rewrite non-TLS or malformed proxy configurations', () {
    final nonTls = jsonEncode({
      'outbounds': [
        {'protocol': 'vless', 'streamSettings': {'security': 'reality'}}
      ],
    });
    expect(natSetPrimaryProxyTlsServerName(nonTls, 'front.example'), nonTls);
    expect(natSetPrimaryProxyTlsServerName('{broken', 'front.example'),
        '{broken');
    expect(natSetPrimaryProxyTlsServerName(
      jsonEncode({'outbounds': [{'protocol': 'freedom'}]}),
      'front.example',
    ), jsonEncode({'outbounds': [{'protocol': 'freedom'}]}));
  });

  test('rejects an empty override without modifying the config', () {
    final source = jsonEncode({
      'outbounds': [tlsProxy('vless', 'origin.example')],
    });
    expect(natSetPrimaryProxyTlsServerName(source, '  '), source);
  });
}
