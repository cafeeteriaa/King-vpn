import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/config_lab.dart';

void main() {
  group('KingConfigDocument', () {
    test('parses and edits VLESS without losing credentials or unrelated fields', () {
      const source =
          'vless://user-id@example.com:443?encryption=none&type=ws&security=tls&sni=edge.example&path=%2Fsocket#profile';
      final parsed = KingConfigDocument.parse(source);
      final edited = parsed.withOverrides({
        'address': '203.0.113.10',
        'port': 8443,
        'sni': 'front.example',
        'host': 'origin.example',
      });
      final output = Uri.parse(edited.toShareLink());

      expect(output.scheme, 'vless');
      expect(output.userInfo, 'user-id');
      expect(output.host, '203.0.113.10');
      expect(output.port, 8443);
      expect(output.queryParameters['encryption'], 'none');
      expect(output.queryParameters['type'], 'ws');
      expect(output.queryParameters['sni'], 'front.example');
      expect(output.queryParameters['host'], 'origin.example');
      expect(output.queryParameters['path'], '/socket');
      expect(output.fragment, 'profile');
    });

    test('parses, edits and re-encodes VMess JSON', () {
      final payload = base64Url.encode(utf8.encode(jsonEncode({
        'v': '2',
        'ps': 'test-profile',
        'add': 'node.example',
        'port': '443',
        'id': 'secret-id',
        'net': 'ws',
        'tls': 'tls',
        'sni': 'node.example',
        'host': 'node.example',
        'path': '/ws',
      }))).replaceAll('=', '');
      final parsed = KingConfigDocument.parse('vmess://$payload#vmess-tag');
      final output = KingConfigDocument.parse(parsed.withOverrides({
        'address': '192.0.2.8',
        'port': 2053,
        'sni': 'front.example',
      }).toShareLink());

      expect(output.address, '192.0.2.8');
      expect(output.port, 2053);
      expect(output.sni, 'front.example');
      expect(output.values['id'], 'secret-id');
      expect(output.values['ps'], 'test-profile');
      expect(output.toShareLink(), endsWith('#vmess-tag'));
    });

    test('rejects invalid ports and unsupported fields instead of corrupting links', () {
      final parsed = KingConfigDocument.parse(
        'vless://id@example.com:443?type=tcp&security=none',
      );
      expect(
        () => parsed.withOverrides({'port': 70000}),
        throwsFormatException,
      );
      expect(
        () => parsed.withOverrides({'uuid': 'new-secret'}),
        throwsFormatException,
      );
    });

    test('rejects unsupported protocol schemes', () {
      expect(
        () => KingConfigDocument.parse('wireguard://profile'),
        throwsFormatException,
      );
    });
  });

  group('KingConfigAutoScanner', () {
    test('scans the configured endpoint without probing unrelated hosts', () async {
      final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      try {
        final config = KingConfigDocument.parse(
          'vless://id@127.0.0.1:${listener.port}?type=tcp&security=none',
        );
        final results = await const KingConfigAutoScanner().scan(config);
        expect(results.any((r) => r.kind == KingConfigProbeKind.dns && r.success), isTrue);
        expect(results.any((r) => r.kind == KingConfigProbeKind.tcp && r.success), isTrue);
        expect(results.where((r) => r.value.contains('127.0.0.1')), isNotEmpty);
      } finally {
        await listener.close();
      }
    });

    test('supports cancellation before opening probes', () async {
      final config = KingConfigDocument.parse(
        'vless://id@127.0.0.1:443?type=tcp&security=none',
      );
      final results = await const KingConfigAutoScanner().scan(
        config,
        cancelled: () => true,
      );
      expect(results, hasLength(1));
      expect(results.single.kind, KingConfigProbeKind.dns);
    });

    test('builds deduplicated manual test variants', () {
      final config = KingConfigDocument.parse(
        'vless://id@example.com:443?type=ws&security=tls&sni=example.com',
      );
      final variants = const KingConfigAutoScanner().buildVariants(
        config,
        addresses: ['192.0.2.1', '192.0.2.1'],
        ports: [8443],
        snis: ['front.example'],
      );
      expect(variants, hasLength(7));
      expect(variants.map((v) => v.config).toSet(), hasLength(7));
    });
  });

  group('KingConfigRepairEngine', () {
    test('accepts only a variant verified by the real-engine callback', () async {
      final variants = [
        const KingConfigVariant(label: 'bad', config: 'bad', probes: []),
        const KingConfigVariant(label: 'good', config: 'good', probes: []),
      ];
      final attempted = <String>[];
      final selected = await const KingConfigRepairEngine().chooseWorkingVariant(
        variants,
        connectAndVerifyTraffic: (config) async {
          attempted.add(config);
          return config == 'good';
        },
      );
      expect(attempted, ['bad', 'good']);
      expect(selected, 'good');
    });

    test('returns null when every real connection attempt fails', () async {
      final selected = await const KingConfigRepairEngine().chooseWorkingVariant(
        const [KingConfigVariant(label: 'bad', config: 'bad', probes: [])],
        connectAndVerifyTraffic: (_) async => false,
      );
      expect(selected, isNull);
    });
  });
}
