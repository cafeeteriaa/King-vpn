// King VPN - NNIE pure core. No Flutter or app dependencies, so it can be unit
// tested with `flutter test` (test/nnie_core_test.dart).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

enum NatNetworkClass {
  globalReachable,
  domesticOnlyLikely,
  dnsDegraded,
  transportRestricted,
  unknown,
}

enum NatAttemptStage { quick, alternate, expensive }

/// Coalesces concurrent requests for the same asynchronous operation.
/// Every caller receives the same result/error; a later call can retry after
/// completion. This prevents overlapping network diagnosis from returning a
/// stale snapshot to a second caller.
class NatSingleFlight<T> {
  Future<T>? _pending;

  Future<T> run(Future<T> Function() action) {
    final active = _pending;
    if (active != null) return active;

    final completer = Completer<T>();
    final future = completer.future;
    _pending = future;
    Future<T>.sync(action).then((value) {
      if (identical(_pending, future)) _pending = null;
      completer.complete(value);
    }, onError: (Object error, StackTrace stack) {
      if (identical(_pending, future)) _pending = null;
      completer.completeError(error, stack);
    });
    return future;
  }
}

class NatProbeEvidence {
  const NatProbeEvidence({
    required this.domesticDnsOk,
    required this.domesticTcpOk,
    required this.globalDnsOk,
    required this.globalTcpOk,
    this.dnsPoisonSuspected = false,
    this.sampleCount = 1,
  });

  final bool domesticDnsOk;
  final bool domesticTcpOk;
  final bool globalDnsOk;
  final bool globalTcpOk;
  final bool dnsPoisonSuspected;
  final int sampleCount;

  NatNetworkClass classify() {
    // DNS replies prove resolver availability only. They must never be used as
    // proof that a domestic or global data path is reachable.
    if (sampleCount < 2) return NatNetworkClass.unknown;
    if (dnsPoisonSuspected) return NatNetworkClass.dnsDegraded;

    if (domesticTcpOk && globalTcpOk) {
      return NatNetworkClass.globalReachable;
    }
    if (domesticTcpOk && !globalTcpOk) {
      return globalDnsOk
          ? NatNetworkClass.transportRestricted
          : NatNetworkClass.domesticOnlyLikely;
    }
    if (!domesticTcpOk && globalTcpOk) {
      return NatNetworkClass.globalReachable;
    }
    // DNS may work while TCP/443 is blocked on both route groups. Report a
    // transport restriction, never "domestic only" or "global reachable".
    if (domesticDnsOk || globalDnsOk) {
      return NatNetworkClass.transportRestricted;
    }
    return NatNetworkClass.unknown;
  }
}

class NatDnsProbeResult {
  const NatDnsProbeResult(this.server, this.domain, this.elapsedMs,
      {this.addresses = const <String>[], this.error});
  final String server;
  final String domain;
  final int? elapsedMs;
  final List<String> addresses;
  final String? error;
  bool get ok => elapsedMs != null && addresses.isNotEmpty;
}

/// Strict DNS-over-UDP A/AAAA probe. It verifies transaction ID, QR/opcode,
/// question name/type/class, response source IP/port, RCODE and globally routable
/// answers. It is a resolver test only, not proof of VPN-server reachability.
class _NatDnsProbeCancelled implements Exception {
  const _NatDnsProbeCancelled();
}

class NatDnsWireProbe {
  static List<int> buildQuery(String domain, int id, {int queryType = 1}) {
    if (queryType != 1 && queryType != 28) {
      throw ArgumentError.value(queryType, 'queryType', 'Only A(1) and AAAA(28) are supported');
    }
    final labels = domain.toLowerCase().replaceAll(RegExp(r'\.$'), '').split('.');
    final out = <int>[
      (id >> 8) & 255, id & 255,
      0x01, 0x00, // RD=1
      0x00, 0x01, // QDCOUNT=1
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ];
    for (final label in labels) {
      final bytes = ascii.encode(label);
      if (bytes.isEmpty || bytes.length > 63) {
        throw FormatException('Invalid DNS label');
      }
      out..add(bytes.length)..addAll(bytes);
    }
    out.addAll(<int>[0, (queryType >> 8) & 255, queryType & 255, 0, 1]); // root, QTYPE, IN
    return out;
  }

  static bool publicV4(List<int> b, int p) {
    if (p + 4 > b.length) return false;
    final a = b[p], c = b[p + 1], d = b[p + 2], e = b[p + 3];
    if (a == 0 || a == 10 || a == 127 || a >= 224) return false;
    if (a == 100 && c >= 64 && c <= 127) return false; // 100.64/10
    if (a == 169 && c == 254) return false;
    if (a == 172 && c >= 16 && c <= 31) return false;
    if (a == 192 && c == 168) return false;
    if (a == 192 && c == 0 && (d == 0 || d == 2)) return false; // 192.0.0.0/24 و TEST-NET-1 (192.0.2.0/24) فقط
    if (a == 192 && c == 88 && d == 99) return false; // deprecated 6to4 relay anycast
    if (a == 198 && (c == 18 || c == 19)) return false; // benchmarking
    if (a == 198 && c == 51 && d == 100) return false; // TEST-NET-2
    if (a == 203 && c == 0 && d == 113) return false; // TEST-NET-3
    if (a >= 240) return false; // reserved / limited broadcast
    if (a == 10 && c == 10 && d == 34 && e == 34) return false;
    return true;
  }

  /// Reject non-global IPv6 ranges while retaining normal global unicast,
  /// including current public CDN and resolver addresses.
  static bool publicV6(List<int> b, int p) {
    if (p + 16 > b.length) return false;
    final address = b.sublist(p, p + 16);
    // Only the currently allocated global-unicast block 2000::/3 is
    // acceptable as a public Internet answer. This rejects translation,
    // discard-only, transition and other non-global address spaces by default.
    if ((address[0] & 0xe0) != 0x20) return false;
    final allZero = address.every((byte) => byte == 0);
    if (allZero) return false; // ::
    final loopback = address.take(15).every((byte) => byte == 0) && address[15] == 1;
    if (loopback) return false; // ::1
    if (address[0] == 0xff) return false; // multicast
    if (address[0] == 0xfe && (address[1] & 0xc0) == 0x80) return false; // fe80::/10
    if ((address[0] & 0xfe) == 0xfc) return false; // fc00::/7 unique-local
    if (address[0] == 0x20 && address[1] == 0x01 &&
        address[2] == 0x0d && address[3] == 0xb8) return false; // 2001:db8::/32
    final mappedV4 = address.take(10).every((byte) => byte == 0) &&
        address[10] == 0xff && address[11] == 0xff;
    if (mappedV4) return false; // IPv4-mapped IPv6
    final compatibleV4 = address.take(12).every((byte) => byte == 0);
    if (compatibleV4) return false; // deprecated ::/96 IPv4-compatible space
    if (address[0] == 0xfe && (address[1] & 0xc0) == 0xc0) {
      return false; // deprecated site-local fec0::/10
    }
    if (address[0] == 0x20 && address[1] == 0x01 &&
        address[2] == 0x00 && (address[3] & 0xf0) == 0x10) {
      return false; // ORCHID special-purpose range
    }
    if (address[0] == 0x20 && address[1] == 0x01 &&
        address[2] == 0x00 && (address[3] & 0xfe) == 0x00) {
      return false; // IETF protocol assignments 2001:0000::/23
    }
    if (address[0] == 0x3f && address[1] == 0xff &&
        (address[2] & 0xf0) == 0x00) {
      return false; // 3fff::/20 documentation prefix
    }
    return true;
  }

  static String _formatV6(List<int> b, int p) => List<String>.generate(
        8,
        (index) => ((b[p + index * 2] << 8) | b[p + index * 2 + 1])
            .toRadixString(16),
      ).join(':');

  static int _skipName(List<int> b, int pos) {
    var p = pos;
    var jumps = 0;
    while (p < b.length) {
      final n = b[p];
      if (n == 0) return p + 1;
      if ((n & 0xc0) == 0xc0) {
        if (p + 1 >= b.length) throw const FormatException('Bad DNS pointer');
        final ptr = ((n & 0x3f) << 8) | b[p + 1];
        if (ptr >= p || ptr >= b.length) {
          throw const FormatException('Invalid DNS compression pointer');
        }
        return p + 2;
      }
      if ((n & 0xc0) != 0 || n > 63 || p + 1 + n > b.length) {
        throw const FormatException('Bad DNS label');
      }
      p += n + 1;
      if (++jumps > 128) throw const FormatException('DNS name too long');
    }
    throw const FormatException('Truncated DNS name');
  }

  static String _readName(List<int> b, int start) {
    final labels = <String>[];
    var p = start;
    var resume = -1;
    var hops = 0;
    while (p < b.length && hops++ < 128) {
      final n = b[p];
      if (n == 0) {
        if (resume < 0) resume = p + 1;
        break;
      }
      if ((n & 0xc0) == 0xc0) {
        if (p + 1 >= b.length) throw const FormatException('Bad pointer');
        final ptr = ((n & 0x3f) << 8) | b[p + 1];
        // DNS compression pointers reference an earlier offset in this packet.
        // Reject forward/self/out-of-range pointers instead of returning a
        // truncated owner name that could pass the answer-owner checks.
        if (ptr >= p || ptr >= b.length) {
          throw const FormatException('Invalid DNS compression pointer');
        }
        if (resume < 0) resume = p + 2;
        p = ptr;
        continue;
      }
      if (n > 63 || p + 1 + n > b.length) throw const FormatException('Bad label');
      labels.add(ascii.decode(b.sublist(p + 1, p + 1 + n), allowInvalid: false).toLowerCase());
      p += n + 1;
    }
    if (resume < 0) throw const FormatException('Unterminated name');
    return labels.join('.');
  }

  static List<String> parseResponse(List<int> b, int id, String domain,
      {int queryType = 1}) {
    if (queryType != 1 && queryType != 28) {
      throw ArgumentError.value(queryType, 'queryType', 'Only A(1) and AAAA(28) are supported');
    }
    if (b.length < 17) throw const FormatException('Short DNS response');
    final rid = (b[0] << 8) | b[1];
    final flags = (b[2] << 8) | b[3];
    if (rid != id || (flags & 0x8000) == 0 || (flags & 0x7800) != 0) {
      throw const FormatException('DNS ID/QR/opcode mismatch');
    }
    if ((flags & 0x0200) != 0) throw const FormatException('Truncated DNS response');
    if ((flags & 0x000f) != 0) throw FormatException('DNS RCODE ${(flags & 15)}');
    final qd = (b[4] << 8) | b[5];
    final an = (b[6] << 8) | b[7];
    if (qd != 1 || an < 1) throw const FormatException('Missing DNS question/answer');
    var p = 12;
    final qname = _readName(b, p);
    p = _skipName(b, p);
    if (p + 4 > b.length) throw const FormatException('Truncated question');
    final qtype = (b[p] << 8) | b[p + 1];
    final qclass = (b[p + 2] << 8) | b[p + 3];
    p += 4;
    if (qname != domain.toLowerCase() || qtype != queryType || qclass != 1) {
      throw const FormatException('Question mismatch');
    }
    final records = <({String owner, int type, int cls, int rd, int rdlen})>[];
    final cnameTargets = <String, String>{};
    for (var i = 0; i < an; i++) {
      final owner = _readName(b, p);
      p = _skipName(b, p);
      if (p + 10 > b.length) throw const FormatException('Truncated RR');
      final type = (b[p] << 8) | b[p + 1];
      final cls = (b[p + 2] << 8) | b[p + 3];
      final rdlen = (b[p + 8] << 8) | b[p + 9];
      final rd = p + 10;
      if (rd + rdlen > b.length) throw const FormatException('Bad RDATA length');
      records.add((owner: owner, type: type, cls: cls, rd: rd, rdlen: rdlen));
      if (type == 5 && cls == 1 && rdlen > 0) {
        cnameTargets[owner] = _readName(b, rd);
      }
      p = rd + rdlen;
    }
    // Only accept A records owned by the queried QNAME or its validated CNAME
    // chain. An unrelated A record elsewhere in the answer section is ignored.
    final allowedOwners = <String>{domain.toLowerCase()};
    var owner = domain.toLowerCase();
    for (var hop = 0; hop < 16; hop++) {
      final target = cnameTargets[owner];
      if (target == null || !allowedOwners.add(target)) break;
      owner = target;
    }
    final ips = <String>[];
    for (final rr in records) {
      if (rr.type != queryType || rr.cls != 1 ||
          !allowedOwners.contains(rr.owner)) continue;
      if (queryType == 1 && rr.rdlen == 4) {
        if (!publicV4(b, rr.rd)) {
          throw const FormatException('Non-public/blockpage A answer for queried name');
        }
        ips.add('${b[rr.rd]}.${b[rr.rd + 1]}.${b[rr.rd + 2]}.${b[rr.rd + 3]}');
      } else if (queryType == 28 && rr.rdlen == 16) {
        if (!publicV6(b, rr.rd)) {
          throw const FormatException('Non-global/special-use AAAA answer for queried name');
        }
        ips.add(_formatV6(b, rr.rd));
      }
    }
    if (ips.isEmpty) {
      throw FormatException('No usable ${queryType == 1 ? 'A' : 'AAAA'} answer for queried name');
    }
    return ips;
  }

  static Future<NatDnsProbeResult> probe(String server, String domain,
      {Duration timeout = const Duration(seconds: 2),
      bool Function()? cancelled,
      int queryType = 1}) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    Timer? cancelWatcher;
    try {
      if (cancelled?.call() ?? false) {
        return NatDnsProbeResult(server, domain, null, error: 'cancelled');
      }
      final target = InternetAddress.tryParse(server);
      if (target == null ||
          (target.type != InternetAddressType.IPv4 &&
              target.type != InternetAddressType.IPv6)) {
        throw const FormatException('Resolver must be an IPv4 or IPv6 literal');
      }
      final bindAddress = target.type == InternetAddressType.IPv4
          ? InternetAddress.anyIPv4
          : InternetAddress.anyIPv6;
      final s = await RawDatagramSocket.bind(bindAddress, 0).timeout(timeout);
      socket = s;
      final id = Random.secure().nextInt(0x10000);
      final packet = buildQuery(domain, id, queryType: queryType);
      final sw = Stopwatch()..start();
      final completer = Completer<List<String>>();
      subscription = s.listen((event) {
        if (event != RawSocketEvent.read || completer.isCompleted) return;
        final dg = s.receive();
        if (dg == null) return;
        // RFC 5452: a matching ID alone is insufficient; verify source tuple.
        if (dg.port != 53 || dg.address.type != target.type) return;
        final sourceBytes = dg.address.rawAddress;
        final targetBytes = target.rawAddress;
        if (sourceBytes.length != targetBytes.length) return;
        for (var index = 0; index < sourceBytes.length; index++) {
          if (sourceBytes[index] != targetBytes[index]) return;
        }
        try {
          completer.complete(parseResponse(dg.data, id, domain, queryType: queryType));
        } catch (_) {
          // Ignore unrelated/malformed datagrams until timeout.
        }
      });
      if (cancelled != null) {
        cancelWatcher = Timer.periodic(const Duration(milliseconds: 100), (timer) {
          if (cancelled()) {
            timer.cancel();
            if (!completer.isCompleted) {
              completer.completeError(const _NatDnsProbeCancelled());
            }
          }
        });
      }
      if (s.send(packet, target, 53) <= 0) throw const SocketException('DNS send failed');
      final ips = await completer.future.timeout(timeout);
      sw.stop();
      return NatDnsProbeResult(server, domain, sw.elapsedMilliseconds, addresses: ips);
    } catch (e) {
      return NatDnsProbeResult(
        server,
        domain,
        null,
        error: e is _NatDnsProbeCancelled ? 'cancelled' : e.toString(),
      );
    } finally {
      cancelWatcher?.cancel();
      try {
        await subscription?.cancel();
      } finally {
        socket?.close();
      }
    }
  }
}

class NatEndpointMemory {
  const NatEndpointMemory({
    required this.attempts,
    required this.successes,
    required this.failStreak,
    required this.ewmaConnectMs,
    required this.lastSuccessMs,
    required this.stableSuccesses,
  });

  final int attempts;
  final int successes;
  final int failStreak;
  final double ewmaConnectMs;
  final int lastSuccessMs;
  final int stableSuccesses;

  double get reliability => attempts <= 0 ? 0.0 : (successes / attempts).clamp(0.0, 1.0).toDouble();
  double get score {
    final speed = ewmaConnectMs <= 0 ? 0.0 : (1.0 - (ewmaConnectMs / 30000).clamp(0.0, 1.0)).toDouble();
    final ageHours = lastSuccessMs == 0
        ? 720.0
        : max(0, DateTime.now().millisecondsSinceEpoch - lastSuccessMs) / 3600000.0;
    final recency = (1.0 - (ageHours / 168.0).clamp(0.0, 1.0)).toDouble();
    // Historical reliability/speed/stability must fade together. Otherwise a
    // once-good endpoint can keep a high score indefinitely after going stale.
    // A 7-day half-life is gradual and keeps recent verified experience useful.
    final historyDecay = exp(-ageHours * 0.6931471805599453 / 168.0);
    final historical = reliability * 55 +
        speed * 15 +
        min(stableSuccesses, 10) * 1.5;
    return historical * historyDecay + recency * 15 - failStreak * 4;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'a': attempts, 's': successes, 'f': failStreak,
        'e': ewmaConnectMs, 't': lastSuccessMs, 'v': stableSuccesses,
      };

  // Tolerant of corrupted or wrongly typed stored values: anything that is not a
  // finite number becomes 0, so one bad field can never crash the loader.
  static int _i(dynamic v) => v is num && v.isFinite ? v.toInt() : 0;
  static double _d(dynamic v) => v is num && v.isFinite ? v.toDouble() : 0.0;

  factory NatEndpointMemory.fromJson(dynamic value) {
    final m = value is Map ? value : const <dynamic, dynamic>{};
    final attempts = max(0, _i(m['a']));
    // Stored data can be corrupted or edited. A success count greater than
    // attempts would produce reliability above 100% and distort pilot ranking.
    final successes = max(0, _i(m['s'])).clamp(0, attempts).toInt();
    return NatEndpointMemory(
      attempts: attempts,
      successes: successes,
      failStreak: max(0, _i(m['f'])),
      ewmaConnectMs: max(0.0, _d(m['e'])),
      lastSuccessMs: max(0, _i(m['t'])),
      stableSuccesses: max(0, _i(m['v'])),
    );
  }
}


/// First stage is cheap and broad; expensive transports are deferred until
/// cheap compatible candidates have been exhausted. A ranking hint only: it never
/// bans a valid user-supplied configuration.
NatAttemptStage natStageFor({required int variantIndex, required bool isKcp,
    required bool isKnownWinner, required bool isCdnCompatible}) {
  if (isKnownWinner || variantIndex == 0) return NatAttemptStage.quick;
  if (isKcp) return NatAttemptStage.expensive;
  if (isCdnCompatible && variantIndex < 12) return NatAttemptStage.quick;
  if (variantIndex < 32) return NatAttemptStage.alternate;
  return NatAttemptStage.expensive;
}

/// Normalises a vmess:// payload to standard base64 with padding. Many vmess
/// links use the URL-safe alphabet (- and _), which plain base64.decode rejects.
String natB64Normalize(String raw) {
  var b = raw.trim().replaceAll('-', '+').replaceAll('_', '/');
  b = b.padRight(b.length + (4 - b.length % 4) % 4, '=');
  return b;
}

/// Stable in-place sort. Dart's List.sort is NOT stable, so items that compare
/// equal could swap places between runs. Here ties keep their original order,
/// which keeps the national search order deterministic and the learned order
/// meaningful.
void natStableSort<T>(List<T> list, int Function(T a, T b) cmp) {
  final tagged = <MapEntry<int, T>>[
    for (var i = 0; i < list.length; i++) MapEntry<int, T>(i, list[i]),
  ];
  tagged.sort((x, y) {
    final c = cmp(x.value, y.value);
    return c != 0 ? c : x.key.compareTo(y.key);
  });
  for (var i = 0; i < tagged.length; i++) {
    list[i] = tagged[i].value;
  }
}

/// Stable sorted copy; the input list is not modified.
List<T> natStableSorted<T>(Iterable<T> items, int Function(T a, T b) cmp) {
  final out = items.toList();
  natStableSort(out, cmp);
  return out;
}
