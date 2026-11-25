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

  group('KING auto-scan fair inventory batches', () {
    test('wraps from the saved cursor without dropping inventory entries', () {
      expect(
        kingNextInventoryBatch(
          ['a', 'b', 'c', 'd', 'e'],
          batchSize: 3,
          lastValue: 'd',
        ),
        ['e', 'a', 'b'],
      );
    });

    test('an unknown cursor restarts safely and a large batch covers all entries', () {
      expect(
        kingNextInventoryBatch([1, 2, 3], batchSize: 20, lastValue: 99),
        [1, 2, 3],
      );
    });

    test('empty inventory and non-positive batch sizes are safe', () {
      expect(kingNextInventoryBatch<int>([], batchSize: 10), isEmpty);
      expect(kingNextInventoryBatch([1, 2], batchSize: 0), isEmpty);
      expect(kingNextInventoryBatch([1, 2], batchSize: -4), isEmpty);
    });

    test('batch output is immutable and source inventory is unchanged', () {
      final source = [1, 2, 3, 4];
      final batch = kingNextInventoryBatch(
        source,
        batchSize: 2,
        lastValue: 2,
      );
      expect(batch, [3, 4]);
      expect(source, [1, 2, 3, 4]);
      expect(() => batch.add(5), throwsUnsupportedError);
    });
  });


  group('IP Auto atomic state snapshot', () {
    test('round-trips hits, retry backlog, cursors and position together', () {
      final encoded = ipAutoEncodeSnapshot(
        hits: ['192.0.2.1|443'],
        pending: ['2001:db8::1|8443'],
        cursors: {'block:192.0.2.0/24': '17', 'port': 8443},
        position: 91,
      );
      final decoded = ipAutoDecodeSnapshot(encoded: encoded);
      expect(decoded.hits, ['192.0.2.1|443']);
      expect(decoded.pending, ['2001:db8::1|8443']);
      expect(decoded.cursors, {
        'block:192.0.2.0/24': '17',
        'port': 8443,
      });
      expect(decoded.position, 91);
    });

    test('migrates independent legacy keys when no v2 snapshot exists', () {
      final decoded = ipAutoDecodeSnapshot(
        encoded: null,
        legacyHits: '192.0.2.1|443\ninvalid',
        legacyPending: '2001:db8::1|8443',
        legacyCursors: '{"range":"21","bad":[]} ',
        legacyPosition: '12',
      );
      expect(decoded.hits, ['192.0.2.1|443']);
      expect(decoded.pending, ['2001:db8::1|8443']);
      expect(decoded.cursors, {'range': '21'});
      expect(decoded.position, 12);
    });

    test('valid v2 snapshot is authoritative over stale legacy values', () {
      final encoded = ipAutoEncodeSnapshot(
        hits: const [],
        pending: const [],
        cursors: const {},
        position: 0,
      );
      final decoded = ipAutoDecodeSnapshot(
        encoded: encoded,
        legacyHits: '192.0.2.9|443',
        legacyPending: '192.0.2.8|443',
        legacyCursors: '{"old":99}',
        legacyPosition: '999',
      );
      expect(decoded.hits, isEmpty);
      expect(decoded.pending, isEmpty);
      expect(decoded.cursors, isEmpty);
      expect(decoded.position, 0);
    });

    test('corrupt v2 snapshot falls back without losing readable legacy state', () {
      final decoded = ipAutoDecodeSnapshot(
        encoded: '{broken',
        legacyHits: '192.0.2.2|443',
        legacyPending: '192.0.2.3|443',
        legacyCursors: '{broken',
        legacyPosition: '-5',
      );
      expect(decoded.hits, ['192.0.2.2|443']);
      expect(decoded.pending, ['192.0.2.3|443']);
      expect(decoded.cursors, isEmpty);
      expect(decoded.position, 0);
    });

    test('rejects malformed v2 shape and negative position', () {
      final decoded = ipAutoDecodeSnapshot(
        encoded: '{"version":2,"hits":[],"pending":[],"cursors":{},"position":-1}',
        legacyHits: '192.0.2.4|443',
      );
      expect(decoded.hits, ['192.0.2.4|443']);
    });
  });

}
