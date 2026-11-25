import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/nat_ip_scan.dart';

void main() {
  group('natQueueSplit', () {
    test('preserves all unique overflow candidates when active queue is bounded', () {
      final split = natQueueSplit<int>(
        incoming: [1, 2, 3, 2],
        active: [3, 4],
        overflow: [4, 5, 6],
        keyOf: (value) => '$value',
        activeLimit: 3,
      );
      expect(split.active, [1, 2, 3]);
      expect(split.overflow, [4, 5, 6]);
      expect([...split.active, ...split.overflow].toSet(), {1, 2, 3, 4, 5, 6});
    });

    test('zero active capacity keeps every unique candidate in overflow', () {
      final split = natQueueSplit<String>(
        incoming: ['a', 'b'],
        active: ['b', 'c'],
        overflow: ['d'],
        keyOf: (value) => value,
        activeLimit: 0,
      );
      expect(split.active, isEmpty);
      expect(split.overflow, ['a', 'b', 'c', 'd']);
    });
  });

  group('exact endpoint template indexing', () {
    test('retains every matching configuration without cross-port substitution', () {
      final indexed = natIndexEndpointTemplates<String>(
        sources: [
          (endpoint: 'vless-ws-config', addresses: ['192.0.2.10', '2001:0db8:0000:0000:0000:0000:0000:0010'], port: 443),
          (endpoint: 'trojan-tls-config', addresses: ['192.0.2.10'], port: 443),
          (endpoint: 'different-port-config', addresses: ['192.0.2.10'], port: 8443),
          (endpoint: 'outside-active-scope', addresses: ['192.0.2.99'], port: 443),
          (endpoint: 'duplicate-source', addresses: ['192.0.2.10'], port: 443),
          (endpoint: 'invalid-port', addresses: ['192.0.2.10'], port: 65536),
        ],
        keyOf: (endpoint) => endpoint,
        addressScope: {'192.0.2.10', '2001:db8::10'},
      );
      expect(indexed.keys, containsAll([
        '192.0.2.10|443', '2001:db8::10|443', '192.0.2.10|8443',
      ]));
      expect(indexed['192.0.2.10|443'], ['vless-ws-config', 'trojan-tls-config']);
      expect(indexed['192.0.2.10|8443'], ['different-port-config']);
      expect(indexed.containsKey('192.0.2.99|443'), isFalse);
      expect(() => indexed['192.0.2.10|443']!.add('mutation'), throwsUnsupportedError);
    });

    test('rejects malformed addresses and invalid endpoint ports', () {
      final indexed = natIndexEndpointTemplates<String>(
        sources: [
          (endpoint: 'bad-address', addresses: ['not-an-ip'], port: 443),
          (endpoint: 'bad-port', addresses: ['192.0.2.1'], port: 0),
        ],
        keyOf: (endpoint) => endpoint,
      );
      expect(indexed, isEmpty);
    });
  });
  group('IP range expansion limits', () {
    test('full port inventory includes every valid port once after priority seeds', () {
      expect(
        natBuildFullPortInventory([4, 2, 4, 99], firstPort: 1, lastPort: 5),
        [4, 2, 1, 3, 5],
      );
      final allPorts = natBuildFullPortInventory([443, 443, 65535]);
      expect(allPorts, hasLength(65535));
      expect(allPorts.toSet(), hasLength(65535));
      expect(allPorts.take(2), [443, 65535]);
      expect(allPorts, isNot(contains(0)));
      expect(allPorts, contains(1));
      expect(allPorts, contains(65535));
      final zeroBased = natBuildFullPortInventory([443], firstPort: 0);
      expect(zeroBased, hasLength(65536));
      expect(zeroBased, contains(0));
      expect(natBuildFullPortInventory([443], firstPort: 5, lastPort: 4), isEmpty);
    });

    test('explicit IP Clean ranges keep the complete TCP port inventory', () {
      final fullTcp = natBuildFullPortInventory(
        [443, 2053, 443],
        firstPort: 1,
        lastPort: 65535,
      );
      final rangePorts = natPortsForActiveScan(
        fullInventory: fullTcp,
        configuredEndpointPorts: [443],
        hasExplicitRanges: true,
      );
      expect(rangePorts, hasLength(65535));
      expect(rangePorts.toSet(), hasLength(65535));
      expect(rangePorts.take(2), [443, 2053]);
      expect(rangePorts.last, 65535);

      final exactEndpointPorts = natPortsForActiveScan(
        fullInventory: fullTcp,
        configuredEndpointPorts: [443, 0, 65536, 443],
        hasExplicitRanges: false,
      );
      expect(exactEndpointPorts, [443]);
    });

    test('persisted outer cursor indexes recover from negative and malformed values', () {
      expect(natCursorIndex('-1', 7), 0);
      expect(natCursorIndex('broken', 7), 0);
      expect(natCursorIndex(null, 7), 0);
      expect(natCursorIndex('15', 7), 1);
      expect(natCursorIndex(8, 7), 1);
      expect(natCursorIndex(8, 0), 0);
    });

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

    test('CIDR expansion accepts the complete IPv4 address space', () {
      final fullSpace = natExpandCidr('0.0.0.0/0', maxPerBlock: 4);
      expect(fullSpace, isNotEmpty);
      expect(fullSpace, hasLength(4));
    });

    test('IPv6 CIDR expansion supports /0 through /128 without 32-bit truncation', () {
      expect(natExpandIpv6Cidr('::/0', maxPerBlock: 3), hasLength(3));
      expect(natExpandIpv6Cidr('2001:db8::/32', maxPerBlock: 4), hasLength(4));
      expect(natExpandIpv6Cidr('2001:db8::1/128'), hasLength(1));
      expect(natExpandIpv6Cidr('2001:db8::/129'), isEmpty);
    });

    test('single IPv4 and IPv6 addresses are exhausted after one probe', () {
      for (final address in ['192.0.2.1', '2001:4860:4860::8888']) {
        final first = natExpandIpRangeCursor(address, '0', maxPerBlock: 8);
        expect(first.addresses, [address]);
        expect(first.nextCursor, 'done');
        final second = natExpandIpRangeCursor(
          address, first.nextCursor, maxPerBlock: 8,
        );
        expect(second.addresses, isEmpty);
        expect(second.nextCursor, 'done');
      }
      final v6 = natExpandIpRangeCursor('2001:4860::1/128', '0');
      expect(v6.addresses, ['2001:4860::1']);
      expect(v6.nextCursor, 'done');
    });

    test('generic IP range cursor accepts IPv4 /0 and wraps at the full address-space boundary', () {
      final batch = natExpandIpRangeCursor(
        '0.0.0.0/0', '4294967294', maxPerBlock: 3,
      );
      expect(batch.addresses, [
        '255.255.255.254',
        '255.255.255.255',
        '0.0.0.0',
      ]);
      expect(batch.nextCursor, '1');
    });

    test('wrapped batches never duplicate a small IPv4 or IPv6 range', () {
      for (final range in ['192.0.2.0/30', '2001:db8::/126']) {
        final batch = natExpandIpRangeCursor(
          range,
          '3',
          maxPerBlock: 8,
          wrap: true,
        );
        expect(batch.addresses, hasLength(4));
        expect(batch.addresses.toSet(), hasLength(4));
        expect(batch.nextCursor, '3');
      }
    });

    test('IPv4 and IPv6 dash ranges both normalize reversed endpoints', () {
      expect(
        natExpandDash('192.0.2.3-192.0.2.1', maxCount: 3),
        ['192.0.2.1', '192.0.2.2', '192.0.2.3'],
      );
      expect(
        natExpandDash('2001:db8::3-2001:db8::1', maxCount: 3),
        ['2001:db8::1', '2001:db8::2', '2001:db8::3'],
      );
    });

    test('negative persisted cursors safely restart IPv4 and IPv6 ranges', () {
      for (final range in ['192.0.2.0/30', '2001:db8::/126']) {
        final batch = natExpandIpRangeCursor(
          range,
          '-1',
          maxPerBlock: 2,
          wrap: false,
        );
        expect(batch.addresses, hasLength(2));
        expect(batch.nextCursor, '2');
      }
      final malformed = natExpandIpRangeCursor(
        '2001:db8::/126',
        'not-a-cursor',
        maxPerBlock: 2,
        wrap: false,
      );
      expect(malformed.addresses, ['2001:db8::', '2001:db8::1']);
      expect(malformed.nextCursor, '2');
    });

    test('non-wrapping cursors visit every IPv4 and IPv6 address exactly once', () {
      for (final range in ['192.0.2.0/30', '2001:db8::/126']) {
        var cursor = '0';
        final addresses = <String>[];
        while (cursor != 'done') {
          final batch = natExpandIpRangeCursor(
            range,
            cursor,
            maxPerBlock: 2,
            wrap: false,
          );
          addresses.addAll(batch.addresses);
          cursor = batch.nextCursor;
        }
        expect(addresses, hasLength(4));
        expect(addresses.toSet(), hasLength(4));
        final again = natExpandIpRangeCursor(
          range, cursor, maxPerBlock: 2, wrap: false,
        );
        expect(again.addresses, isEmpty);
      }
    });

    test('IPv6 range cursors cover each address and wrap without 64-bit truncation', () {
      final first = natExpandIpv6RangeCursor(
        '2001:db8::/126', '0', maxPerBlock: 2,
      );
      expect(first.addresses, ['2001:db8::', '2001:db8::1']);
      expect(first.nextCursor, '2');

      final second = natExpandIpv6RangeCursor(
        '2001:db8::/126', first.nextCursor, maxPerBlock: 2,
      );
      expect(second.addresses, ['2001:db8::2', '2001:db8::3']);
      expect(second.nextCursor, '0');

      final hugeCursor = natExpandIpv6RangeCursor(
        '::/0', '18446744073709551616', maxPerBlock: 1,
      );
      expect(hugeCursor.addresses, hasLength(1));
      expect(InternetAddress.tryParse(hugeCursor.addresses.single)?.type,
          InternetAddressType.IPv6);
      expect(hugeCursor.nextCursor, '18446744073709551617');
    });

    test('IPv6 dash ranges resume from a 128-bit cursor', () {
      final batch = natExpandIpv6RangeCursor(
        '2001:db8::1-2001:db8::3', '2', maxPerBlock: 2,
      );
      expect(batch.addresses, ['2001:db8::3', '2001:db8::1']);
      expect(batch.nextCursor, '1');
    });

    test('linear dash range expansion accepts IPv6 endpoints', () {
      expect(
        natExpandDash('2001:db8::1-2001:db8::3', maxCount: 3),
        ['2001:db8::1', '2001:db8::2', '2001:db8::3'],
      );
      expect(
        natExpandDash('2001:db8::1-2001:db8::3', maxCount: 2),
        ['2001:db8::1', '2001:db8::2'],
      );
    });

    test('dash range expansion rejects non-positive output limits', () {
      expect(natExpandDash('10.0.0.1-10.0.0.3', maxCount: 0), isEmpty);
      expect(natExpandDash('10.0.0.1-10.0.0.3', maxCount: -1), isEmpty);
    });

    test('TCP probe cancels an in-flight connection when the caller stops', () async {
      var stop = false;
      var cancelCalls = 0;
      final pending = Completer<Socket>();
      final task = ConnectionTask.fromSocket<Socket>(pending.future, () {
        cancelCalls++;
        if (!pending.isCompleted) {
          pending.completeError(const SocketException('cancelled'));
        }
      });
      final probe = IOOverrides.runZoned(
        () => natTcpProbe(
          '192.0.2.1',
          443,
          const Duration(seconds: 5),
          cancelled: () => stop,
        ),
        socketStartConnect: (host, port, {sourceAddress, sourcePort = 0}) async => task,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      stop = true;
      expect(await probe.timeout(const Duration(milliseconds: 300)), isNull);
      expect(cancelCalls, 1);
    });

    test('TCP probe stops waiting for startConnect when the caller cancels', () async {
      var stop = false;
      var cancelCalls = 0;
      final startPending = Completer<ConnectionTask<Socket>>();
      final pendingSocket = Completer<Socket>();
      final lateTask = ConnectionTask.fromSocket<Socket>(pendingSocket.future, () {
        cancelCalls++;
        if (!pendingSocket.isCompleted) {
          pendingSocket.completeError(const SocketException('cancelled before connect'));
        }
      });
      lateTask.socket.then<void>((_) {}, onError: (Object _, StackTrace __) {});
      final probe = IOOverrides.runZoned(
        () => natTcpProbe(
          '192.0.2.1',
          443,
          const Duration(seconds: 5),
          cancelled: () => stop,
        ),
        socketStartConnect: (host, port, {sourceAddress, sourcePort = 0}) =>
            startPending.future,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      stop = true;
      expect(await probe.timeout(const Duration(milliseconds: 300)), isNull);
      startPending.complete(lateTask);
      await Future<void>.delayed(Duration.zero);
      expect(cancelCalls, 1);
    });

    test('TCP probe cancels its pending task when the connect timeout expires', () async {
      var cancelCalls = 0;
      final pending = Completer<Socket>();
      final task = ConnectionTask.fromSocket<Socket>(pending.future, () {
        cancelCalls++;
        if (!pending.isCompleted) {
          pending.completeError(const SocketException('timed out'));
        }
      });
      final result = await IOOverrides.runZoned(
        () => natTcpProbe(
          '192.0.2.1',
          443,
          const Duration(milliseconds: 40),
        ),
        socketStartConnect: (host, port, {sourceAddress, sourcePort = 0}) async => task,
      );
      expect(result, isNull);
      expect(cancelCalls, 1);
    });

    test('TCP probe reaches a local IPv4 listener', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      try {
        final latency = await natTcpProbe(
          InternetAddress.loopbackIPv4.address,
          server.port,
          const Duration(seconds: 2),
        );
        expect(latency, isNotNull);
      } finally {
        await server.close();
      }
    });

    test('TCP probe reaches a local IPv6 listener when the runner supports IPv6', () async {
      ServerSocket? server;
      try {
        server = await ServerSocket.bind(InternetAddress.loopbackIPv6, 0);
      } on SocketException {
        // Some CI/container hosts disable IPv6 loopback; do not misreport that
        // host configuration as an application regression.
        return;
      }
      try {
        final latency = await natTcpProbe(
          InternetAddress.loopbackIPv6.address,
          server.port,
          const Duration(seconds: 2),
        );
        expect(latency, isNotNull);
      } finally {
        await server.close();
      }
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

    test('throwing cancellation callback fails closed without opening sockets', () async {
      var attempts = 0;
      final result = await IOOverrides.runZoned(
        () => natScanIps(
          ['127.0.0.1'],
          cancelled: () => throw StateError('cancellation state unavailable'),
        ),
        socketStartConnect: (host, port, {sourceAddress, sourcePort = 0}) async {
          attempts++;
          throw const SocketException('must not be reached');
        },
      );
      expect(result, isEmpty);
      expect(attempts, 0);
    });

    test('throwing progress callback cannot discard a successful hit', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      try {
        final result = await natScanIps(
          [InternetAddress.loopbackIPv4.address],
          port: server.port,
          concurrency: 1,
          want: 1,
          budget: const Duration(seconds: 2),
          timeout: const Duration(seconds: 1),
          onProgress: (done, total, hits) =>
              throw StateError('progress consumer disposed'),
        );
        expect(result, hasLength(1));
        expect(result.single.ip, InternetAddress.loopbackIPv4.address);
      } finally {
        await server.close();
      }
    });

    test('valid limits preserve expected expansion', () {
      expect(natExpandCidr('10.0.0.0/30', maxPerBlock: 4), hasLength(4));
      expect(natExpandDash('10.0.0.1-10.0.0.3', maxCount: 3), hasLength(3));
    });
  });
}
