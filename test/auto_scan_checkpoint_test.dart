import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/main.dart';

void main() {
  group('KING auto-scan checkpoint', () {
    test('round-trips all independent inventory cursors in one snapshot', () {
      final encoded = kingEncodeAutoScanCheckpoint(
        cdn: {'cloudflare-v4': 1234, 'cloudflare-v6': '2001:db8::10'},
        domain: 'edge.example.net',
        port: 8443,
      );
      final decoded = kingDecodeAutoScanCheckpoint(encoded: encoded);
      expect(decoded.cdn, {
        'cloudflare-v4': 1234,
        'cloudflare-v6': '2001:db8::10',
      });
      expect(decoded.domain, 'edge.example.net');
      expect(decoded.port, 8443);
    });

    test('migrates legacy cursor keys when no v2 checkpoint exists', () {
      final decoded = kingDecodeAutoScanCheckpoint(
        encoded: null,
        legacyCdnJson: '{"cf4":17,"cf6":"2001:db8::4","bad":[]} ',
        legacyDomain: 'legacy.example',
        legacyPort: 2053,
      );
      expect(decoded.cdn, {'cf4': 17, 'cf6': '2001:db8::4'});
      expect(decoded.domain, 'legacy.example');
      expect(decoded.port, 2053);
    });

    test('a valid empty v2 cursor does not resurrect stale legacy progress', () {
      final encoded = kingEncodeAutoScanCheckpoint(
        cdn: const {},
        domain: null,
        port: null,
      );
      final decoded = kingDecodeAutoScanCheckpoint(
        encoded: encoded,
        legacyCdnJson: '{"old":9}',
        legacyDomain: 'stale.example',
        legacyPort: 443,
      );
      expect(decoded.cdn, isEmpty);
      expect(decoded.domain, isNull);
      expect(decoded.port, isNull);
    });

    test('corrupt v2 state falls back to legacy cursors independently', () {
      final decoded = kingDecodeAutoScanCheckpoint(
        encoded: '{broken-json',
        legacyCdnJson: '{broken-cdn',
        legacyDomain: 'safe.example',
        legacyPort: 443,
      );
      expect(decoded.cdn, isEmpty);
      expect(decoded.domain, 'safe.example');
      expect(decoded.port, 443);
    });

    test('rejects invalid persisted port values', () {
      final decoded = kingDecodeAutoScanCheckpoint(
        encoded: '{"version":2,"cdn":{},"domain":"x.example","port":70000}',
        legacyPort: 8443,
      );
      expect(decoded.port, isNull);
    });
  });
}
