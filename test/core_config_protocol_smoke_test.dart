import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import '../lib/main.dart' as king;

Map<String, dynamic> _parseVless(String link) {
  final raw = V2ray.parseFromURL(link).getFullConfiguration();
  return jsonDecode(raw) as Map<String, dynamic>;
}

void _expectVlessEndpoint(String link, String expectedAddress) {
  final config = _parseVless(link);
  final outbounds = config['outbounds'] as List;
  final outbound = outbounds.first as Map;
  expect(outbound['protocol'], 'vless');
  final settings = outbound['settings'] as Map;
  final vnext = settings['vnext'] as List;
  final server = vnext.first as Map;
  expect(server['address'], expectedAddress);
  expect(server['port'], 443);
  final users = server['users'] as List;
  expect(users, isNotEmpty);
  expect((users.first as Map)['id'], '00000000-0000-4000-8000-000000000001');
  final stream = outbound['streamSettings'] as Map;
  expect(stream['network'], 'tcp');
  expect(stream['security'], 'tls');
  expect((stream['tlsSettings'] as Map)['serverName'], 'example.com');
}

void main() {
  group('KING server IPv6 endpoint classification', () {
    test('preserves IPv6 literal and recognizes Cloudflare IPv6 range', () {
      final server = king.Server.parse(
        'vless://00000000-0000-4000-8000-000000000001@[2606:4700::1111]:443'
        '?encryption=none&security=tls&sni=example.com&type=tcp#cf-v6',
      );
      expect(server, isNotNull);
      expect(server!.host, '2606:4700::1111');
      expect(server.isIp, isTrue);
      expect(server.cdn, isTrue);
    });

    test('does not classify an unrelated public IPv6 resolver as Cloudflare', () {
      final server = king.Server.parse(
        'vless://00000000-0000-4000-8000-000000000001@[2001:4860:4860::8888]:443'
        '?encryption=none&security=tls&sni=example.com&type=tcp#google-v6',
      );
      expect(server, isNotNull);
      expect(server!.isIp, isTrue);
      expect(server.cdn, isFalse);
    });
  });

  group('current Xray/V2Ray VLESS config adapter smoke tests', () {
    test('parses a VLESS TLS endpoint with an IPv4 destination', () {
      _expectVlessEndpoint(
        'vless://00000000-0000-4000-8000-000000000001@192.0.2.10:443'
        '?encryption=none&security=tls&sni=example.com&type=tcp#king-v4',
        '192.0.2.10',
      );
    });

    test('parses a VLESS TLS endpoint with a bracketed IPv6 destination', () {
      _expectVlessEndpoint(
        'vless://00000000-0000-4000-8000-000000000001@[2001:db8::10]:443'
        '?encryption=none&security=tls&sni=example.com&type=tcp#king-v6',
        '2001:db8::10',
      );
    });
  });
}
