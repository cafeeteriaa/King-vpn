import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/nat_ip_scan.dart';

void main() {
  group('automatic scan port ranking', () {
    test('uses port evidence beyond the first 100 known servers', () {
      final earlyPorts = List<int>.generate(100, (index) => 1000 + index);
      final laterPorts = List<int>.filled(8, 9443);
      final ports = natRankPorts(
        knownPorts: [...earlyPorts, ...laterPorts],
        commonPorts: const [443, 80],
      );
      expect(ports.first, 9443);
      expect(ports, containsAll([443, 80]));
    });

    test('weights remembered successful ports and rejects invalid ports', () {
      final ports = natRankPorts(
        knownPorts: [8443, 443, 443],
        rememberedPorts: [8443, 8443, -1, 65536],
        commonPorts: const [443, 80, 443, 0],
      );
      expect(ports.take(2), [8443, 443]);
      expect(ports.where((port) => port == 443), hasLength(1));
      expect(ports, isNot(contains(-1)));
      expect(ports, isNot(contains(65536)));
    });
  });

  group('fair scan-port deadline allocation', () {
    test('shares the remaining deadline across every untested port', () {
      final share = natFairPortBudget(
        const Duration(minutes: 2),
        36,
      );
      expect(share.inMilliseconds, 3333);
      expect(
        share * 36,
        lessThanOrEqualTo(const Duration(minutes: 2)),
      );
    });

    test('gives later ports the full time released by an early result', () {
      expect(
        natFairPortBudget(const Duration(seconds: 47), 1),
        const Duration(seconds: 47),
      );
      expect(
        natFairPortBudget(const Duration(seconds: 40), 4),
        const Duration(seconds: 10),
      );
    });

    test('returns zero for exhausted deadlines or no remaining ports', () {
      expect(
        natFairPortBudget(Duration.zero, 3),
        Duration.zero,
      );
      expect(
        natFairPortBudget(const Duration(seconds: 2), 0),
        Duration.zero,
      );
    });
  });

  group('configured National Net range scheduling', () {
    test('round-robins across the complete inventory beyond 128 ranges', () {
      final ranges = List<String>.generate(300, (i) => 'range-$i');
      var cursor = 0;
      final visited = <String>{};
      for (var batch = 0; batch < 19; batch++) {
        final result = natConfiguredRangeBatch(
          ranges: ranges,
          cursor: cursor,
          limit: 16,
          expand: (range, budget) {
            expect(budget, greaterThan(0));
            return List<String>.generate(budget, (i) => '$range-ip-$i');
          },
        );
        expect(result.addresses.length, lessThanOrEqualTo(16));
        visited.addAll(result.addresses.map((address) => address.split('-ip-').first));
        cursor = result.nextCursor;
      }
      expect(visited, hasLength(300));
      expect(cursor, 4);
    });

    test('normalizes negative cursors before indexing configured ranges', () {
      final ranges = ['a', 'b', 'c', 'd'];
      final result = natConfiguredRangeBatch(
        ranges: ranges,
        cursor: -1,
        limit: 2,
        expand: (range, _) => [range],
      );
      expect(result.addresses, ['d', 'a']);
      expect(result.nextCursor, 1);
    });

    test('distributes a bounded budget across all ranges and deduplicates', () {
      final result = natConfiguredRangeBatch(
        ranges: ['a', 'b', 'c'],
        cursor: 1,
        limit: 8,
        expand: (range, budget) =>
            List<String>.filled(budget, range == 'b' ? 'shared' : range),
      );
      expect(result.addresses, ['shared', 'c', 'a']);
      expect(result.nextCursor, 1);
    });

    test('invalid ranges still advance fairly and invalid limits do not', () {
      final skipped = natConfiguredRangeBatch(
        ranges: ['bad-a', 'good-b', 'bad-c'],
        cursor: 0,
        limit: 2,
        expand: (range, budget) => range == 'good-b' ? ['10.0.0.1'] : const [],
      );
      expect(skipped.addresses, ['10.0.0.1']);
      expect(skipped.nextCursor, 2);
      final empty = natConfiguredRangeBatch(
        ranges: ['a', 'b'],
        cursor: 1,
        limit: 0,
        expand: (_, __) => fail('must not expand'),
      );
      expect(empty.addresses, isEmpty);
      expect(empty.nextCursor, 1);
    });
  });

  group('IP range expansion limits', () {
    test('CIDR expansion rejects non-positive output limits', () {
      expect(natExpandCidr('10.0.0.0/24', maxPerBlock: 0), isEmpty);
      expect(natExpandCidr('10.0.0.0/24', maxPerBlock: -1), isEmpty);
    });

    test('CIDR sampling never exceeds a non-divisible output limit', () {
      final sampled24 = natExpandCidr('10.0.0.0/24', maxPerBlock: 100);
      final sampled16 = natExpandCidr('10.1.0.0/16', maxPerBlock: 1000);
      expect(sampled24, isNotEmpty);
      expect(sampled24.length, lessThanOrEqualTo(100));
      expect(sampled16, isNotEmpty);
      expect(sampled16.length, lessThanOrEqualTo(1000));
      expect(sampled24.toSet(), hasLength(sampled24.length));
      expect(sampled16.toSet(), hasLength(sampled16.length));
    });

    test('dash range expansion rejects non-positive output limits', () {
      expect(natExpandDash('10.0.0.1-10.0.0.3', maxCount: 0), isEmpty);
      expect(natExpandDash('10.0.0.1-10.0.0.3', maxCount: -1), isEmpty);
    });

    test('NAT scan rejects invalid budgets, timeouts, and ports without probing', () async {
      expect(await natScanIps(['127.0.0.1'], budget: Duration.zero), isEmpty);
      expect(await natScanIps(['127.0.0.1'], timeout: Duration.zero), isEmpty);
      expect(await natScanIps(['127.0.0.1'], port: 0), isEmpty);
      expect(await natScanIps(['127.0.0.1'], port: 65536), isEmpty);
    });

    test('adaptive concurrency always returns a bounded integer', () {
      expect(natAdaptiveConcurrency(0), isA<int>());
      expect(natAdaptiveConcurrency(0), inInclusiveRange(8, 64));
      expect(natAdaptiveConcurrency(1), 1);
      expect(natAdaptiveConcurrency(999999), lessThanOrEqualTo(256));
    });

    test('cancelled NAT scan exits without opening sockets', () async {
      final result = await natScanIps(
        ['127.0.0.1'],
        cancelled: () => true,
      );
      expect(result, isEmpty);
    });

    test('valid limits preserve expected expansion', () {
      expect(natExpandCidr('10.0.0.0/30', maxPerBlock: 4), hasLength(4));
      expect(natExpandDash('10.0.0.1-10.0.0.3', maxCount: 3), hasLength(3));
    });
  });
}
