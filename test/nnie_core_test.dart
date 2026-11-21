// Unit tests for the pure NNIE core. Run from the generated Flutter project:
//   flutter test test/nnie_core_test.dart
// These cover logic only; they do not test real networks, VPN, or Android.
import 'dart:async';

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
}) {
  final out = <int>[
    ..._u16(id), ..._u16(flags), ..._u16(1), ..._u16(an), ..._u16(0), ..._u16(0),
  ];
  for (final label in qname.split('.')) {
    out..add(label.length)..addAll(label.codeUnits);
  }
  out.addAll([0, 0, 1, 0, 1]); // root, QTYPE=A, QCLASS=IN
  if (an > 0) {
    out.addAll([
      0xc0, 0x0c, // name: pointer to the question name
      ..._u16(1), ..._u16(1), // TYPE=A, CLASS=IN
      0, 0, 0, 60, // TTL
      ..._u16(rdata.length), ...rdata,
    ]);
  }
  return out;
}

void main() {
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
  group('domestic candidate ordering', () {
    test('verified national traffic wins over ASN and geographic-only hints', () {
      final input = ['geo-label', 'other', 'iran-asn', 'verified-domain', 'verified-ip'];
      final ordered = natPrioritizeDomesticEvidence<String>(
        input,
        verifiedNational: (value) => value.startsWith('verified-'),
        iranAsnAddress: (value) => value == 'iran-asn',
      );
      expect(ordered, [
        'verified-domain', 'verified-ip', 'iran-asn', 'geo-label', 'other',
      ]);
      // Stable partitioning must not mutate the source inventory.
      expect(input, ['geo-label', 'other', 'iran-asn', 'verified-domain', 'verified-ip']);
    });

    test('preserves source order inside each evidence tier', () {
      final ordered = natPrioritizeDomesticEvidence<int>(
        [5, 3, 4, 2, 1],
        verifiedNational: (value) => value == 3 || value == 1,
        iranAsnAddress: (value) => value == 4 || value == 2,
      );
      expect(ordered, [3, 1, 4, 2, 5]);
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

    test('IPv4 and IPv6 DNS evidence remain independent', () {
      const ipv4Only = NatProbeEvidence(
        domesticDnsOk: false, domesticTcpOk: true,
        globalDnsOk: true, globalTcpOk: false,
        globalIpv4DnsOk: true, globalIpv6DnsOk: false, sampleCount: 4,
      );
      expect(ipv4Only.ipv4Reachability, NatIpFamilyReachability.dnsOnly);
      expect(ipv4Only.ipv6Reachability, NatIpFamilyReachability.unknown);

      const ipv6Only = NatProbeEvidence(
        domesticDnsOk: false, domesticTcpOk: true,
        globalDnsOk: true, globalTcpOk: false,
        globalIpv4DnsOk: false, globalIpv6DnsOk: true, sampleCount: 4,
      );
      expect(ipv6Only.ipv4Reachability, NatIpFamilyReachability.unknown);
      expect(ipv6Only.ipv6Reachability, NatIpFamilyReachability.dnsOnly);
    });

    test('family state reports TCP reachability only for its own family', () {
      const ev = NatProbeEvidence(
        domesticDnsOk: false, domesticTcpOk: true,
        globalDnsOk: true, globalTcpOk: false,
        globalIpv4DnsOk: true, globalIpv4TcpOk: true,
        globalIpv6DnsOk: true, globalIpv6TcpOk: false, sampleCount: 4,
      );
      expect(ev.ipv4Reachability, NatIpFamilyReachability.tcpReachable);
      expect(ev.ipv6Reachability, NatIpFamilyReachability.dnsOnly);
    });

    test('literal IPv4 evidence independently proves a global data path', () {
      const ev = NatProbeEvidence(
        domesticDnsOk: false, domesticTcpOk: false,
        globalDnsOk: true, globalTcpOk: false,
        globalIpv4TcpOk: true, sampleCount: 4,
      );
      expect(ev.classify(), NatNetworkClass.globalReachable);
    });

    test('literal IPv6 evidence independently proves a global data path', () {
      const ev = NatProbeEvidence(
        domesticDnsOk: false, domesticTcpOk: false,
        globalDnsOk: true, globalTcpOk: false,
        globalIpv6TcpOk: true, sampleCount: 4,
      );
      expect(ev.classify(), NatNetworkClass.globalReachable);
    });

    test('IPv4 success does not set the IPv6 evidence field', () {
      const ev = NatProbeEvidence(
        domesticDnsOk: false, domesticTcpOk: true,
        globalDnsOk: true, globalTcpOk: false,
        globalIpv4TcpOk: true, globalIpv6TcpOk: false, sampleCount: 4,
      );
      expect(ev.globalIpv4TcpOk, isTrue);
      expect(ev.globalIpv6TcpOk, isFalse);
    });

    test('DNS query volume does not change the independent TCP sample count', () {
      const oneEndpoint = NatProbeEvidence(
        domesticDnsOk: true, domesticTcpOk: true,
        globalDnsOk: true, globalTcpOk: false, sampleCount: 1,
      );
      expect(oneEndpoint.classify(), NatNetworkClass.unknown);
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
      expect(q.length, 12 + 7 + 4 + 4); // header + labels + root/type/class
    });

    test('buildQuery rejects a name longer than the DNS 255-octet limit', () {
      final label = List<String>.filled(63, 'a').join();
      final labels = List<String>.filled(4, label);
      expect(
        () => NatDnsWireProbe.buildQuery(labels.join('.'), 0x1234),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts a valid public A answer', () {
      final bytes = _response(id: 0x1234, rdata: [8, 8, 8, 8]);
      expect(NatDnsWireProbe.parseResponse(bytes, 0x1234, 'google.com'), ['8.8.8.8']);
    });

    test('rejects CNAME names that spill beyond their RDATA length', () {
      final bytes = <int>[
        ..._u16(0x1234), ..._u16(0x8180), ..._u16(1), ..._u16(2),
        ..._u16(0), ..._u16(0),
        6, 103, 111, 111, 103, 108, 101, 3, 99, 111, 109, 0,
        0, 1, 0, 1, // Question: google.com A IN
        0xc0, 0x0c, // CNAME owner: google.com
        0, 5, 0, 1, // TYPE=CNAME, CLASS=IN
        0, 0, 0, 60, 0, 1, 3, // RDLENGTH=1, but the label continues
        3, 102, 111, 111, 0, // Next RR owner "foo" completes the fake CNAME
        0, 1, 0, 1, // TYPE=A, CLASS=IN
        0, 0, 0, 60, 0, 4, 8, 8, 8, 8,
      ];
      expect(
        () => NatDnsWireProbe.parseResponse(bytes, 0x1234, 'google.com'),
        throwsA(isA<FormatException>()),
      );
    });

    test('buildQuery supports AAAA records', () {
      final query = NatDnsWireProbe.buildQuery('google.com', 0x1234, type: 28);
      expect(query.sublist(query.length - 4), [0, 28, 0, 1]);
    });

    test('publicV6 accepts global unicast and rejects special-use ranges', () {
      expect(NatDnsWireProbe.publicV6([
        0x20, 0x01, 0x48, 0x60, 0x48, 0x60, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0x88,
      ], 0), isTrue);
      expect(NatDnsWireProbe.publicV6(List<int>.filled(16, 0), 0), isFalse);
      expect(NatDnsWireProbe.publicV6([
        0xfc, ...List<int>.filled(15, 0x01),
      ], 0), isFalse);
      expect(NatDnsWireProbe.publicV6([
        0x20, 0x01, 0x0d, 0xb8, ...List<int>.filled(12, 0),
      ], 0), isFalse);
      expect(NatDnsWireProbe.publicV6([
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
      ], 0), isFalse); // loopback
      expect(NatDnsWireProbe.publicV6([
        0xfe, 0x80, ...List<int>.filled(14, 0x01),
      ], 0), isFalse); // link-local
      expect(NatDnsWireProbe.publicV6([
        0xff, 0x02, ...List<int>.filled(14, 0x01),
      ], 0), isFalse); // multicast
      expect(NatDnsWireProbe.publicV6([
        0x20, 0x01, 0, 1, ...List<int>.filled(12, 0x01),
      ], 0), isFalse); // IANA special-purpose block
      expect(NatDnsWireProbe.publicV6([
        0x3f, 0xff, 0, 0, ...List<int>.filled(12, 0x01),
      ], 0), isFalse); // documentation
    });

    test('accepts a valid public AAAA answer', () {
      final out = <int>[
        ..._u16(0x1234), ..._u16(0x8180), ..._u16(1), ..._u16(1),
        ..._u16(0), ..._u16(0),
        6, 103, 111, 111, 103, 108, 101, 3, 99, 111, 109, 0,
        0, 28, 0, 1,
        0xc0, 0x0c, 0, 28, 0, 1, 0, 0, 0, 60, 0, 16,
        0x20, 0x01, 0x48, 0x60, 0x48, 0x60, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0x88,
      ];
      expect(
        NatDnsWireProbe.parseResponse(out, 0x1234, 'google.com', type: 28),
        ['2001:4860:4860::88'],
      );
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

    test('rejects a block-page answer in private space', () {
      final bytes = _response(id: 0x1234, rdata: [10, 10, 34, 34]);
      expect(() => NatDnsWireProbe.parseResponse(bytes, 0x1234, 'google.com'),
          throwsA(isA<FormatException>()));
    });

    test('rejects a question for a different name', () {
      final bytes = _response(id: 0x1234, qname: 'example.com', rdata: [8, 8, 8, 8]);
      expect(() => NatDnsWireProbe.parseResponse(bytes, 0x1234, 'google.com'),
          throwsA(isA<FormatException>()));
    });

    test('rejects a truncated packet instead of crashing', () {
      expect(() => NatDnsWireProbe.parseResponse([0, 1, 2], 1, 'google.com'),
          throwsA(isA<FormatException>()));
    });

    test('rejects a self-referencing DNS compression pointer', () {
      final bytes = <int>[
        ..._u16(0x1234), ..._u16(0x8180), ..._u16(1), ..._u16(1),
        ..._u16(0), ..._u16(0),
        0xc0, 0x0c, // QNAME points to itself at offset 12
        0, 1, 0, 1, // QTYPE=A, QCLASS=IN (reach the name parser)
      ];
      expect(() => NatDnsWireProbe.parseResponse(bytes, 0x1234, 'google.com'),
          throwsA(isA<FormatException>()));
    });

    test('rejects a DNS compression pointer into the message header', () {
      final bytes = <int>[
        ..._u16(0x1234), ..._u16(0x8180), ..._u16(1), ..._u16(1),
        ..._u16(0), ..._u16(0),
        0xc0, 0x00, // points to transaction ID/header, not a prior DNS name
        0, 1, 0, 1,
      ];
      expect(() => NatDnsWireProbe.parseResponse(bytes, 0x1234, 'google.com'),
          throwsA(isA<FormatException>()));
    });

    test('rejects an expanded DNS name longer than 255 octets', () {
      final bytes = <int>[
        ..._u16(0x1234), ..._u16(0x8180), ..._u16(1), ..._u16(1),
        ..._u16(0), ..._u16(0),
        ...List<int>.generate(4, (_) => 63).expand((length) => [
          length, ...List<int>.filled(length, 97),
        ]),
        0, 0, 1, 0, 1,
      ];
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

    test('publicV4 rejects special-use ranges and accepts public addresses', () {
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

  group('NatIpv4CidrIndex', () {
    test('matches addresses inside IPv4 CIDRs without scanning the ranges', () {
      final index = NatIpv4CidrIndex([
        '2.144.0.0/18',
        '5.10.248.0/23',
        '192.0.2.0/24',
        'invalid/99',
      ]);
      expect(index.contains('2.144.1.10'), isTrue);
      expect(index.contains('2.144.64.1'), isFalse);
      expect(index.contains('5.10.249.254'), isTrue);
      expect(index.contains('5.10.250.1'), isFalse);
      expect(index.contains('192.0.2.10'), isTrue);
    });

    test('rejects IPv6, malformed addresses, and malformed CIDRs', () {
      final index = NatIpv4CidrIndex([
        '2001:db8::/32',
        '10.0.0.0/33',
        '10.0.0.0/not-a-prefix',
        '10.0.0.0',
      ]);
      expect(index.contains('10.0.0.1'), isFalse);
      expect(index.contains('2001:db8::1'), isFalse);
      expect(index.contains('not-an-ip'), isFalse);
    });

    test('merges overlapping ranges and supports a full IPv4 range', () {
      final overlapping = NatIpv4CidrIndex([
        '10.0.0.0/8',
        '10.10.0.0/16',
        '10.20.0.0/16',
      ]);
      expect(overlapping.contains('10.30.1.1'), isTrue);
      expect(overlapping.contains('11.0.0.1'), isFalse);

      final allIpv4 = NatIpv4CidrIndex(['0.0.0.0/0']);
      expect(allIpv4.contains('8.8.8.8'), isTrue);
    });

    test('matches only the exact address in a /32 range', () {
      final single = NatIpv4CidrIndex(['203.0.113.9/32']);
      expect(single.contains('203.0.113.9'), isTrue);
      expect(single.contains('203.0.113.10'), isFalse);
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
