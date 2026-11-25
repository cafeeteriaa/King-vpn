// Unit tests for the pure NNIE core. Run from the generated Flutter project:
//   flutter test test/nnie_core_test.dart
// These cover logic only; they do not test real networks, VPN, or Android.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/nnie_core.dart';

List<int> _u16(int v) => [(v >> 8) & 255, v & 255];

/// Builds a DNS response: header, question for [qname], one answer with [rdata].
List<int> _response({
  required int id,
  int flags = 0x8180, // QR=1, RD=1, RA=1, RCODE=0
  String qname = 'google.com',
  required List<int> rdata,
  int an = 1,
  int recordType = 1,
}) {
  final out = <int>[
    ..._u16(id), ..._u16(flags), ..._u16(1), ..._u16(an), ..._u16(0), ..._u16(0),
  ];
  for (final label in qname.split('.')) {
    out..add(label.length)..addAll(label.codeUnits);
  }
  out.addAll([0, (recordType >> 8) & 255, recordType & 255, 0, 1]); // root, QTYPE, QCLASS=IN
  if (an > 0) {
    out.addAll([
      0xc0, 0x0c, // name: pointer to the question name
      ..._u16(recordType), ..._u16(1), // TYPE, CLASS=IN
      0, 0, 0, 60, // TTL
      ..._u16(rdata.length), ...rdata,
    ]);
  }
  return out;
}

List<int> _dnsNameWire(String name) {
  final out = <int>[];
  for (final label in name.split('.')) {
    out..add(label.length)..addAll(label.codeUnits);
  }
  out.add(0);
  return out;
}

/// Builds a valid CNAME chain followed by one A record. Each owner uses a
/// compression pointer to the prior encoded name, so the fixture also covers
/// pointer decoding across successive records.
List<int> _cnameChainResponse({
  int hops = 17,
  bool trailingByteInFirstCname = false,
}) {
  if (hops < 1) throw ArgumentError.value(hops, 'hops');
  const queryName = 'host0.example.com';
  final question = _dnsNameWire(queryName);
  final out = <int>[
    ..._u16(0x1234), ..._u16(0x8180),
    ..._u16(1), ..._u16(hops + 1), ..._u16(0), ..._u16(0),
    ...question, 0, 1, 0, 1,
  ];
  var previousNameOffset = 12;
  for (var i = 0; i < hops; i++) {
    final targetWire = _dnsNameWire('host${i + 1}.example.com');
    final rdata = <int>[
      ...targetWire,
      if (i == 0 && trailingByteInFirstCname) 0x7f,
    ];
    out.addAll([
      0xc0 | ((previousNameOffset >> 8) & 0x3f),
      previousNameOffset & 0xff,
      ..._u16(5), ..._u16(1),
      0, 0, 0, 60,
      ..._u16(rdata.length), ...rdata,
    ]);
    previousNameOffset = out.length - rdata.length;
  }
  out.addAll([
    0xc0 | ((previousNameOffset >> 8) & 0x3f),
    previousNameOffset & 0xff,
    ..._u16(1), ..._u16(1),
    0, 0, 0, 60,
    ..._u16(4), 8, 8, 8, 8,
  ]);
  return out;
}

void main() {
  group('androidVpnTunnelEvidence', () {
    test('plugin-managed path accepts an active VPN owned by this app', () {
      expect(
        androidVpnTunnelEvidence(
          serviceTunnelActive: null,
          activeVpnTransport: true,
          activeVpnOwnedByApp: true,
          requireServiceTunnel: false,
        ),
        isTrue,
      );
    });

    test('plugin-managed path stays unknown when owner UID is unavailable', () {
      expect(
        androidVpnTunnelEvidence(
          serviceTunnelActive: null,
          activeVpnTransport: true,
          activeVpnOwnedByApp: null,
          requireServiceTunnel: false,
        ),
        isNull,
      );
    });

    test('another VPN owner is rejected even when VPN transport is active', () {
      expect(
        androidVpnTunnelEvidence(
          serviceTunnelActive: true,
          activeVpnTransport: true,
          activeVpnOwnedByApp: false,
          requireServiceTunnel: true,
        ),
        isFalse,
      );
    });

    test('custom service path accepts its live TUN and active VPN transport', () {
      expect(
        androidVpnTunnelEvidence(
          serviceTunnelActive: true,
          activeVpnTransport: true,
          activeVpnOwnedByApp: null,
          requireServiceTunnel: true,
        ),
        isTrue,
      );
    });

    test('custom service path rejects a missing TUN or VPN transport', () {
      expect(
        androidVpnTunnelEvidence(
          serviceTunnelActive: false,
          activeVpnTransport: true,
          activeVpnOwnedByApp: null,
          requireServiceTunnel: true,
        ),
        isFalse,
      );
      expect(
        androidVpnTunnelEvidence(
          serviceTunnelActive: true,
          activeVpnTransport: false,
          activeVpnOwnedByApp: null,
          requireServiceTunnel: true,
        ),
        isFalse,
      );
    });
  });

  stableSortTests();
  group('NatSingleFlight', () {
    test('concurrent callers share one result and later calls can run again', () async {
      final flight = NatSingleFlight<int>();
      final gate = Completer<int>();
      var calls = 0;
      final first = flight.run(() {
        calls++;
        return gate.future;
      });
      final second = flight.run(() {
        calls++;
        return Future<int>.value(99);
      });

      expect(identical(first, second), isTrue);
      expect(calls, 1);
      gate.complete(7);
      expect(await first, 7);

      expect(await flight.run(() {
        calls++;
        return Future<int>.value(8);
      }), 8);
      expect(calls, 2);
    });

    test('a failed operation does not poison later retries', () async {
      final flight = NatSingleFlight<int>();
      await expectLater(
        flight.run(() => Future<int>.error(StateError('probe failed'))),
        throwsA(isA<StateError>()),
      );
      expect(await flight.run(() async => 4), 4);
    });
  });
  group('NatProbeEvidence.classify', () {
    test('a single failed sample is never proof of a national network', () {
      const ev = NatProbeEvidence(
        domesticDnsOk: false, domesticTcpOk: true,
        globalDnsOk: false, globalTcpOk: false, sampleCount: 1,
      );
      expect(ev.classify(), NatNetworkClass.unknown);
    });

    test('domestic reachable, global not reachable -> domesticOnlyLikely', () {
      const ev = NatProbeEvidence(
        domesticDnsOk: false, domesticTcpOk: true,
        globalDnsOk: false, globalTcpOk: false, sampleCount: 4,
      );
      expect(ev.classify(), NatNetworkClass.domesticOnlyLikely);
    });

    test('everything reachable -> globalReachable', () {
      const ev = NatProbeEvidence(
        domesticDnsOk: true, domesticTcpOk: true,
        globalDnsOk: true, globalTcpOk: true, sampleCount: 4,
      );
      expect(ev.classify(), NatNetworkClass.globalReachable);
    });

    test('suspected DNS poisoning -> dnsDegraded', () {
      const ev = NatProbeEvidence(
        domesticDnsOk: true, domesticTcpOk: true,
        globalDnsOk: false, globalTcpOk: false,
        dnsPoisonSuspected: true, sampleCount: 4,
      );
      expect(ev.classify(), NatNetworkClass.dnsDegraded);
    });

    test('DNS answers but TCP is blocked -> transportRestricted', () {
      const ev = NatProbeEvidence(
        domesticDnsOk: true, domesticTcpOk: false,
        globalDnsOk: true, globalTcpOk: false, sampleCount: 4,
      );
      expect(ev.classify(), NatNetworkClass.transportRestricted);
    });

    test('UDP DNS answer alone is not global reachability when TCP is blocked', () {
      // Domestic TCP works, resolvers answer, but no global TCP/443 connects.
      const ev = NatProbeEvidence(
        domesticDnsOk: false, domesticTcpOk: true,
        globalDnsOk: true, globalTcpOk: false, sampleCount: 6,
      );
      expect(ev.classify(), NatNetworkClass.transportRestricted);
    });

    test('domestic DNS alone never proves a working national data path', () {
      const ev = NatProbeEvidence(
        domesticDnsOk: true, domesticTcpOk: false,
        globalDnsOk: false, globalTcpOk: false, sampleCount: 8,
      );
      expect(ev.classify(), NatNetworkClass.transportRestricted);
    });

    test('global TCP reachability is recognized even if domestic targets fail', () {
      const ev = NatProbeEvidence(
        domesticDnsOk: false, domesticTcpOk: false,
        globalDnsOk: false, globalTcpOk: true, sampleCount: 4,
      );
      expect(ev.classify(), NatNetworkClass.globalReachable);
    });

    test('nothing reachable -> unknown, not domesticOnlyLikely', () {
      const ev = NatProbeEvidence(
        domesticDnsOk: false, domesticTcpOk: false,
        globalDnsOk: false, globalTcpOk: false, sampleCount: 4,
      );
      expect(ev.classify(), NatNetworkClass.unknown);
    });
  });

  group('NatDnsWireProbe', () {
    test('buildQuery encodes the name as length-prefixed labels', () {
      final q = NatDnsWireProbe.buildQuery('google.com', 0x1234);
      expect(q.sublist(0, 2), [0x12, 0x34]); // transaction ID
      expect(q[12], 6); // "google"
      expect(q.length, 12 + 7 + 4 + 1 + 4); // header + labels + root + type/class
    });

    test('buildQuery rejects DNS names exceeding the 255-octet wire limit', () {
      final labels = List<String>.filled(4, 'a' * 63);
      expect(() => NatDnsWireProbe.buildQuery(labels.join('.'), 0x1234),
          throwsA(isA<FormatException>()));
    });

    test('buildQuery can request AAAA records', () {
      final q = NatDnsWireProbe.buildQuery('google.com', 0x1234, recordType: 28);
      expect(q.sublist(q.length - 4), [0, 28, 0, 1]);
    });

    test('accepts a valid global-unicast AAAA answer', () {
      final bytes = _response(
        id: 0x1234,
        recordType: 28,
        rdata: [0x26, 0x06, 0x47, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x88],
      );
      expect(
        NatDnsWireProbe.parseResponse(bytes, 0x1234, 'google.com', recordType: 28),
        ['2606:4700::88'],
      );
    });

    test('rejects documentation IPv6 AAAA answers', () {
      final bytes = _response(
        id: 0x1234,
        recordType: 28,
        rdata: [0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1],
      );
      expect(
        () => NatDnsWireProbe.parseResponse(bytes, 0x1234, 'google.com', recordType: 28),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts a valid public A answer', () {
      final bytes = _response(id: 0x1234, rdata: [8, 8, 8, 8]);
      expect(NatDnsWireProbe.parseResponse(bytes, 0x1234, 'google.com'), ['8.8.8.8']);
    });

    test('rejects a mismatched transaction ID', () {
      final bytes = _response(id: 0x0001, rdata: [8, 8, 8, 8]);
      expect(() => NatDnsWireProbe.parseResponse(bytes, 0x1234, 'google.com'),
          throwsA(isA<FormatException>()));
    });

    test('rejects a response without the QR bit', () {
      final bytes = _response(id: 0x1234, flags: 0x0180, rdata: [8, 8, 8, 8]);
      expect(() => NatDnsWireProbe.parseResponse(bytes, 0x1234, 'google.com'),
          throwsA(isA<FormatException>()));
    });

    test('rejects a non-zero RCODE (e.g. NXDOMAIN)', () {
      final bytes = _response(id: 0x1234, flags: 0x8183, rdata: [8, 8, 8, 8]);
      expect(() => NatDnsWireProbe.parseResponse(bytes, 0x1234, 'google.com'),
          throwsA(isA<FormatException>()));
    });

    test('preserves block-page-looking private IPv4 as a DNS observation', () {
      final bytes = _response(id: 0x1234, rdata: [10, 10, 34, 34]);
      expect(
        NatDnsWireProbe.parseResponse(bytes, 0x1234, 'google.com'),
        ['10.10.34.34'],
      );
    });

    test('preserves RFC1918 IPv4 DNS answers for network-specific evaluation', () {
      final bytes = _response(id: 0x1234, rdata: [192, 168, 1, 1]);
      expect(
        NatDnsWireProbe.parseResponse(bytes, 0x1234, 'google.com'),
        ['192.168.1.1'],
      );
    });

    test('preserves documentation-space IPv6 as a DNS observation', () {
      final bytes = _response(
        id: 0x1234,
        recordType: 28,
        rdata: [
          0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 1,
        ],
      );
      final answer = NatDnsWireProbe.parseResponse(
        bytes, 0x1234, 'google.com', recordType: 28,
      ).single;
      expect(InternetAddress.tryParse(answer)?.rawAddress, [
        0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 1,
      ]);
    });

    test('rejects a question for a different name', () {
      final bytes = _response(id: 0x1234, qname: 'example.com', rdata: [8, 8, 8, 8]);
      expect(() => NatDnsWireProbe.parseResponse(bytes, 0x1234, 'google.com'),
          throwsA(isA<FormatException>()));
    });

    test('rejects compression pointers into the DNS header', () {
      final bytes = _response(id: 0x1234, rdata: [8, 8, 8, 8]);
      final answerOwner = bytes.length - 16;
      bytes[answerOwner] = 0xc0;
      bytes[answerOwner + 1] = 0;
      expect(() => NatDnsWireProbe.parseResponse(bytes, 0x1234, 'google.com'),
          throwsA(isA<FormatException>()));
    });

    test('rejects a truncated packet instead of crashing', () {
      expect(() => NatDnsWireProbe.parseResponse([0, 1, 2], 1, 'google.com'),
          throwsA(isA<FormatException>()));
    });

    test('accepts a CNAME chain longer than the former 16-hop ceiling', () {
      final bytes = _cnameChainResponse(hops: 17);
      expect(
        NatDnsWireProbe.parseResponse(bytes, 0x1234, 'host0.example.com'),
        ['8.8.8.8'],
      );
    });

    test('rejects CNAME RDATA with trailing bytes outside the encoded name', () {
      final bytes = _cnameChainResponse(
        hops: 1,
        trailingByteInFirstCname: true,
      );
      expect(
        () => NatDnsWireProbe.parseResponse(bytes, 0x1234, 'host0.example.com'),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts a fully qualified query name with a terminal root dot', () {
      final bytes = _response(id: 0x1234, rdata: [8, 8, 8, 8]);
      expect(
        NatDnsWireProbe.parseResponse(bytes, 0x1234, 'google.com.'),
        ['8.8.8.8'],
      );
    });

    test('rejects the reserved DNS header Z bit', () {
      final bytes = _response(
        id: 0x1234,
        flags: 0x81c0,
        rdata: [8, 8, 8, 8],
      );
      expect(
        () => NatDnsWireProbe.parseResponse(bytes, 0x1234, 'google.com'),
        throwsA(isA<FormatException>()),
      );
    });

    test('pre-cancelled DNS probes return without opening a socket', () async {
      final result = await NatDnsWireProbe.probe(
        '127.0.0.1',
        'example.com',
        cancelled: () => true,
      );
      expect(result.ok, isFalse);
      expect(result.error, 'cancelled');
    });

    test('cancellation callback exceptions fail closed before socket allocation', () async {
      final result = await NatDnsWireProbe.probe(
        '127.0.0.1',
        'example.com',
        cancelled: () => throw StateError('cancel state disposed'),
      );
      expect(result.ok, isFalse);
      expect(result.error, 'cancellation callback failed');
    });

    test('publicV4 classifies address ranges independently of DNS answer acceptance', () {
      expect(NatDnsWireProbe.publicV4([100, 64, 1, 1], 0), isFalse); // CGNAT
      expect(NatDnsWireProbe.publicV4([192, 168, 1, 1], 0), isFalse);
      expect(NatDnsWireProbe.publicV4([198, 18, 0, 1], 0), isFalse); // benchmarking
      expect(NatDnsWireProbe.publicV4([8, 8, 8, 8], 0), isTrue);
      expect(NatDnsWireProbe.publicV4([192, 0, 1, 1], 0), isTrue); // مشکل ۱۴: عمومی است
      expect(NatDnsWireProbe.publicV4([192, 0, 2, 1], 0), isFalse); // TEST-NET-1
    });
  });

  group('NatEndpointMemory', () {
    test('corrupted or wrongly typed JSON never throws', () {
      expect(() => NatEndpointMemory.fromJson(null), returnsNormally);
      expect(() => NatEndpointMemory.fromJson('garbage'), returnsNormally);
      expect(() => NatEndpointMemory.fromJson({'a': 'x', 's': [1], 'e': double.nan}),
          returnsNormally);
      final m = NatEndpointMemory.fromJson({'a': 'x', 's': -5, 'e': double.nan});
      expect(m.attempts, 0);
      expect(m.successes, 0);
      expect(m.ewmaConnectMs, 0);
    });

    test('success count is clamped to attempts for corrupted history', () {
      final overReported = NatEndpointMemory.fromJson({'a': 4, 's': 99});
      expect(overReported.attempts, 4);
      expect(overReported.successes, 4);
      expect(overReported.reliability, 1.0);

      final withoutAttempts = NatEndpointMemory.fromJson({'a': 0, 's': 5});
      expect(withoutAttempts.successes, 0);
      expect(withoutAttempts.reliability, 0.0);

      const invalidDirectValue = NatEndpointMemory(
        attempts: 2, successes: 8, failStreak: 0,
        ewmaConnectMs: 1000, lastSuccessMs: 1, stableSuccesses: 1,
      );
      expect(invalidDirectValue.reliability, 1.0);
    });

    test('toJson and fromJson round-trip', () {
      const m = NatEndpointMemory(
        attempts: 7, successes: 5, failStreak: 1,
        ewmaConnectMs: 1234.5, lastSuccessMs: 1700000000000, stableSuccesses: 3,
      );
      final back = NatEndpointMemory.fromJson(m.toJson());
      expect(back.attempts, 7);
      expect(back.successes, 5);
      expect(back.failStreak, 1);
      expect(back.ewmaConnectMs, 1234.5);
      expect(back.lastSuccessMs, 1700000000000);
      expect(back.stableSuccesses, 3);
    });

    test('stale endpoint history loses influence over time', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final fresh = NatEndpointMemory(
        attempts: 10, successes: 10, failStreak: 0,
        ewmaConnectMs: 1000, lastSuccessMs: now, stableSuccesses: 10,
      );
      final stale = NatEndpointMemory(
        attempts: 10, successes: 10, failStreak: 0,
        ewmaConnectMs: 1000,
        lastSuccessMs: now - const Duration(days: 30).inMilliseconds,
        stableSuccesses: 10,
      );
      expect(fresh.score, greaterThan(stale.score));
      expect(stale.score, lessThan(fresh.score * 0.25));
    });

    test('missing success timestamp treats historical evidence as stale', () {
      const m = NatEndpointMemory(
        attempts: 10, successes: 10, failStreak: 0,
        ewmaConnectMs: 1000, lastSuccessMs: 0, stableSuccesses: 10,
      );
      expect(m.score, lessThan(15));
    });

    test('a failure streak lowers the score', () {
      const healthy = NatEndpointMemory(
        attempts: 10, successes: 9, failStreak: 0,
        ewmaConnectMs: 2000, lastSuccessMs: 0, stableSuccesses: 2,
      );
      const failing = NatEndpointMemory(
        attempts: 10, successes: 9, failStreak: 5,
        ewmaConnectMs: 2000, lastSuccessMs: 0, stableSuccesses: 2,
      );
      expect(healthy.score, greaterThan(failing.score));
    });
  });

  group('natStageFor', () {
    NatAttemptStage stage({int v = 20, bool kcp = false, bool winner = false, bool cdn = false}) =>
        natStageFor(variantIndex: v, isKcp: kcp, isKnownWinner: winner, isCdnCompatible: cdn);

    test('variant 0 and a learned winner are quick', () {
      expect(stage(v: 0), NatAttemptStage.quick);
      expect(stage(v: 40, kcp: true, winner: true), NatAttemptStage.quick);
    });

    test('KCP without a learned winner is deferred to expensive', () {
      expect(stage(v: 5, kcp: true), NatAttemptStage.expensive);
    });

    test('mid-range variants are alternate, high indices are expensive', () {
      expect(stage(v: 20), NatAttemptStage.alternate);
      expect(stage(v: 40), NatAttemptStage.expensive);
    });

    test('CDN-compatible low indices are quick', () {
      expect(stage(v: 5, cdn: true), NatAttemptStage.quick);
    });
  });
}

void stableSortTests() {
  group('natStableSort', () {
    test('equal keys keep their original order', () {
      final items = [
        ('a', 1), ('b', 0), ('c', 1), ('d', 0), ('e', 1),
      ];
      natStableSort(items, (x, y) => x.$2.compareTo(y.$2));
      expect(items.map((e) => e.$1).toList(), ['b', 'd', 'a', 'c', 'e']);
    });

    test('natStableSorted leaves the input untouched', () {
      final input = [3, 1, 2];
      final out = natStableSorted(input, (a, b) => a.compareTo(b));
      expect(out, [1, 2, 3]);
      expect(input, [3, 1, 2]);
    });
  });
}
