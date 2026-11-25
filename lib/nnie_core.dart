// King VPN - NNIE pure core. No Flutter or app dependencies, so it can be unit
// tested with `flutter test` (test/nnie_core_test.dart).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

enum NatNetworkClass {
  globalReachable,
  domesticOnlyLikely,
  dnsDegraded,
  transportRestricted,
  unknown,
}

enum NatAttemptStage { quick, alternate, expensive }

/// Validates Android VPN evidence for the selected service path.
/// The default Flutter plugin path has no KingVpnService descriptor. It uses
/// Android's active VPN owner UID on API 30+, or the active VPN transport plus
/// this package's current VpnService grant on API 24–29. The optional custom
/// service path requires its live TUN plus an active VPN transport.
bool? androidVpnTunnelEvidence({
  required bool? serviceTunnelActive,
  required bool? activeVpnTransport,
  required bool? activeVpnOwnedByApp,
  required bool requireServiceTunnel,
}) {
  if (activeVpnTransport == false || activeVpnOwnedByApp == false) {
    return false;
  }
  if (requireServiceTunnel) {
    if (serviceTunnelActive == false) return false;
    if (serviceTunnelActive == true && activeVpnTransport == true) {
      return true;
    }
    return null;
  }
  if (activeVpnTransport == true && activeVpnOwnedByApp == true) {
    return true;
  }
  return null;
}

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

/// Strict DNS-over-UDP A-query probe. It verifies transaction ID, QR/opcode,
/// question name/type/class, response source IP/port, RCODE and public A answers.
/// It is a resolver test only; it is NOT a test of the VPN server's reachability.
class _NatDnsProbeCancelled implements Exception {
  const _NatDnsProbeCancelled();
}

class NatDnsWireProbe {
  static List<int> buildQuery(String domain, int id, {int recordType = 1}) {
    if (recordType != 1 && recordType != 28) throw ArgumentError.value(recordType, 'recordType');
    final labels = domain.toLowerCase().replaceAll(RegExp(r'\.$'), '').split('.');
    final out = <int>[
      (id >> 8) & 255, id & 255,
      0x01, 0x00, // RD=1
      0x00, 0x01, // QDCOUNT=1
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ];
    var wireNameLength = 1;
    final encodedLabels = <List<int>>[];
    for (final label in labels) {
      final bytes = ascii.encode(label);
      if (bytes.isEmpty || bytes.length > 63) {
        throw FormatException('Invalid DNS label');
      }
      wireNameLength += bytes.length + 1;
      if (wireNameLength > 255) {
        throw const FormatException('DNS name exceeds 255 wire octets');
      }
      encodedLabels.add(bytes);
    }
    for (final bytes in encodedLabels) {
      out..add(bytes.length)..addAll(bytes);
    }
    out.addAll(<int>[0, (recordType >> 8) & 255, recordType & 255, 0, 1]); // root, QTYPE, IN
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

  static bool publicV6(List<int> b, int p) {
    if (p + 16 > b.length) return false;
    final first = b[p];
    // Global unicast only; exclude unspecified, loopback, ULA, link-local,
    // multicast, IPv4-mapped and documentation prefix 2001:db8::/32.
    if ((first & 0xe0) != 0x20) return false; // 2000::/3
    if (b[p] == 0x20 && b[p + 1] == 0x01 &&
        b[p + 2] == 0x0d && b[p + 3] == 0xb8) return false;
    if (b.sublist(p, p + 12).every((x) => x == 0) &&
        b[p + 12] == 0 && b[p + 13] == 0 && b[p + 14] == 0 &&
        b[p + 15] == 1) return false;
    return true;
  }

  /// Decode one DNS name and report the byte offset immediately after its
  /// encoded representation. [encodedEnd] bounds only the bytes consumed at
  /// the original location; compression pointers may refer to earlier packet
  /// data, as required by RFC 1035.
  static ({String name, int nextOffset}) _decodeName(
    List<int> b,
    int start, {
    int? encodedEnd,
  }) {
    if (start < 12 ||
        start >= b.length ||
        (encodedEnd != null &&
            (encodedEnd < start || encodedEnd > b.length))) {
      throw const FormatException('Invalid DNS name bounds');
    }
    final labels = <String>[];
    var p = start;
    var nextOffset = -1;
    var jumped = false;
    var expandedWireLength = 1; // terminating root octet
    while (true) {
      if (p >= b.length || (!jumped && encodedEnd != null && p >= encodedEnd)) {
        throw const FormatException('Truncated DNS name');
      }
      final length = b[p];
      if (length == 0) {
        if (!jumped) nextOffset = p + 1;
        break;
      }
      if ((length & 0xc0) == 0xc0) {
        if (p + 1 >= b.length ||
            (!jumped && encodedEnd != null && p + 2 > encodedEnd)) {
          throw const FormatException('Truncated DNS compression pointer');
        }
        final pointer = ((length & 0x3f) << 8) | b[p + 1];
        if (pointer < 12 || pointer >= p || pointer >= b.length) {
          throw const FormatException('Invalid DNS compression pointer target');
        }
        if (!jumped) {
          nextOffset = p + 2;
          jumped = true;
        }
        p = pointer;
        continue;
      }
      if ((length & 0xc0) != 0 ||
          length > 63 ||
          p + 1 + length > b.length ||
          (!jumped && encodedEnd != null && p + 1 + length > encodedEnd)) {
        throw const FormatException('Invalid or truncated DNS label');
      }
      expandedWireLength += length + 1;
      if (expandedWireLength > 255) {
        throw const FormatException('Expanded DNS name exceeds 255 wire octets');
      }
      labels.add(
        ascii.decode(b.sublist(p + 1, p + 1 + length), allowInvalid: false).toLowerCase(),
      );
      p += length + 1;
    }
    if (nextOffset < 0) throw const FormatException('Unterminated DNS name');
    return (name: labels.join('.'), nextOffset: nextOffset);
  }

  static List<String> parseResponse(
    List<int> b,
    int id,
    String domain, {
    int recordType = 1,
  }) {
    if (recordType != 1 && recordType != 28) {
      throw ArgumentError.value(recordType, 'recordType');
    }
    if (b.length < 17) throw const FormatException('Short DNS response');
    final rid = (b[0] << 8) | b[1];
    final flags = (b[2] << 8) | b[3];
    if (rid != id || (flags & 0x8000) == 0 || (flags & 0x7800) != 0) {
      throw const FormatException('DNS ID/QR/opcode mismatch');
    }
    if ((flags & 0x0200) != 0) {
      throw const FormatException('Truncated DNS response');
    }
    if ((flags & 0x0040) != 0) {
      throw const FormatException('Reserved DNS header Z bit is set');
    }
    if ((flags & 0x000f) != 0) {
      throw FormatException('DNS RCODE ${flags & 15}');
    }
    final qd = (b[4] << 8) | b[5];
    final an = (b[6] << 8) | b[7];
    if (qd != 1 || an < 1) {
      throw const FormatException('Missing DNS question/answer');
    }

    var p = 12;
    final question = _decodeName(b, p);
    p = question.nextOffset;
    if (p + 4 > b.length) throw const FormatException('Truncated question');
    final qtype = (b[p] << 8) | b[p + 1];
    final qclass = (b[p + 2] << 8) | b[p + 3];
    p += 4;
    final expectedName = domain.toLowerCase().replaceAll(RegExp(r'\.$'), '');
    if (question.name != expectedName || qtype != recordType || qclass != 1) {
      throw const FormatException('Question mismatch');
    }

    final records = <({String owner, int type, int cls, int rd, int rdlen})>[];
    final cnameTargets = <String, String>{};
    for (var i = 0; i < an; i++) {
      final ownerName = _decodeName(b, p);
      final owner = ownerName.name;
      p = ownerName.nextOffset;
      if (p + 10 > b.length) throw const FormatException('Truncated RR');
      final type = (b[p] << 8) | b[p + 1];
      final cls = (b[p + 2] << 8) | b[p + 3];
      final rdlen = (b[p + 8] << 8) | b[p + 9];
      final rd = p + 10;
      final rdEnd = rd + rdlen;
      if (rdEnd > b.length) throw const FormatException('Bad RDATA length');
      records.add((owner: owner, type: type, cls: cls, rd: rd, rdlen: rdlen));

      if (type == 5 && cls == 1) {
        if (rdlen == 0) throw const FormatException('Empty CNAME RDATA');
        final targetName = _decodeName(b, rd, encodedEnd: rdEnd);
        if (targetName.nextOffset != rdEnd) {
          throw const FormatException('CNAME RDATA length mismatch');
        }
        final previousTarget = cnameTargets[owner];
        if (previousTarget != null && previousTarget != targetName.name) {
          throw const FormatException('Conflicting CNAME targets for one owner');
        }
        cnameTargets[owner] = targetName.name;
      }
      p = rdEnd;
    }

    // Follow the finite CNAME records actually present in this response.
    // Cycle detection makes this loop terminate without an arbitrary hop cap.
    final allowedOwners = <String>{expectedName};
    var currentOwner = expectedName;
    while (true) {
      final target = cnameTargets[currentOwner];
      if (target == null || !allowedOwners.add(target)) break;
      currentOwner = target;
    }

    final ips = <String>[];
    for (final rr in records) {
      if (rr.type != recordType ||
          rr.cls != 1 ||
          !allowedOwners.contains(rr.owner)) {
        continue;
      }
      if (recordType == 1) {
        if (rr.rdlen != 4 || !publicV4(b, rr.rd)) {
          throw const FormatException(
            'Non-public/blockpage A answer for queried name',
          );
        }
        ips.add('${b[rr.rd]}.${b[rr.rd + 1]}.${b[rr.rd + 2]}.${b[rr.rd + 3]}');
      } else {
        if (rr.rdlen != 16 || !publicV6(b, rr.rd)) {
          throw const FormatException(
            'Non-public/blockpage AAAA answer for queried name',
          );
        }
        ips.add(
          InternetAddress.fromRawAddress(
            Uint8List.fromList(b.sublist(rr.rd, rr.rd + 16)),
          ).address,
        );
      }
    }
    if (ips.isEmpty) {
      throw const FormatException('No usable A/AAAA answer for queried name');
    }
    return ips;
  }

  static Future<T> _waitForProbe<T>(
    Future<T> operation,
    Duration timeout,
    Future<void>? cancellation,
  ) {
    final futures = <Future<T>>[operation];
    if (cancellation != null) {
      futures.add(cancellation.then<T>((_) => throw const _NatDnsProbeCancelled()));
    }
    return Future.any<T>(futures).timeout(timeout);
  }

  static Future<NatDnsProbeResult> probe(String server, String domain,
      {Duration timeout = const Duration(seconds: 2),
      bool Function()? cancelled,
      int recordType = 1}) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    Timer? cancelWatcher;
    Completer<void>? cancellationSignal;
    var cancellationCallbackFailed = false;

    bool cancellationRequested() {
      if (cancellationCallbackFailed) return true;
      try {
        final requested = cancelled?.call() ?? false;
        if (requested && cancellationSignal != null && !cancellationSignal!.isCompleted) {
          cancellationSignal!.complete();
        }
        return requested;
      } catch (_) {
        cancellationCallbackFailed = true;
        if (cancellationSignal != null && !cancellationSignal!.isCompleted) {
          cancellationSignal!.complete();
        }
        return true;
      }
    }

    try {
      final target = InternetAddress.tryParse(server);
      if (target == null || (target.type != InternetAddressType.IPv4 &&
          target.type != InternetAddressType.IPv6)) {
        throw const FormatException('Resolver must be an IP literal');
      }
      if (recordType != 1 && recordType != 28) {
        throw ArgumentError.value(recordType, 'recordType');
      }
      final id = Random.secure().nextInt(0x10000);
      final packet = buildQuery(domain, id, recordType: recordType);
      if (cancelled != null) {
        cancellationSignal = Completer<void>();
        if (cancellationRequested()) {
          return NatDnsProbeResult(server, domain, null,
              error: cancellationCallbackFailed ? 'cancellation callback failed' : 'cancelled');
        }
        cancelWatcher = Timer.periodic(const Duration(milliseconds: 100), (timer) {
          if (cancellationRequested()) timer.cancel();
        });
      }
      final bindAddress = target.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6 : InternetAddress.anyIPv4;
      final bindFuture = RawDatagramSocket.bind(bindAddress, 0);
      late final RawDatagramSocket activeSocket;
      try {
        activeSocket = await _waitForProbe(bindFuture, timeout, cancellationSignal?.future);
        socket = activeSocket;
      } catch (_) {
        // The underlying bind cannot be cancelled by Future.timeout/Future.any.
        // Close a socket that the OS may deliver after timeout or cancellation.
        unawaited(bindFuture.then<void>(
          (lateSocket) => lateSocket.close(),
          onError: (Object _) {},
        ));
        rethrow;
      }
      final sw = Stopwatch()..start();
      final completer = Completer<List<String>>();
      subscription = activeSocket.listen((event) {
        if (event != RawSocketEvent.read || completer.isCompleted) return;
        final dg = activeSocket.receive();
        if (dg == null) return;
        // RFC 5452: a matching ID alone is insufficient; verify source tuple.
        if (dg.port != 53 || dg.address.address != target.address) return;
        try {
          completer.complete(parseResponse(dg.data, id, domain, recordType: recordType));
        } catch (_) {
          // Ignore unrelated/malformed datagrams until timeout.
        }
      });
      if (activeSocket.send(packet, target, 53) <= 0) {
        throw const SocketException('DNS send failed');
      }
      final ips = await _waitForProbe(completer.future, timeout, cancellationSignal?.future);
      sw.stop();
      return NatDnsProbeResult(server, domain, sw.elapsedMilliseconds, addresses: ips);
    } catch (e) {
      return NatDnsProbeResult(
        server,
        domain,
        null,
        error: cancellationCallbackFailed
            ? 'cancellation callback failed'
            : (e is _NatDnsProbeCancelled ? 'cancelled' : e.toString()),
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
), '');
    if (question.name != expectedName || qtype != recordType || qclass != 1) {
      throw const FormatException('Question mismatch');
    }

    final records = <({String owner, int type, int cls, int rd, int rdlen})>[];
    final cnameTargets = <String, String>{};
    for (var i = 0; i < an; i++) {
      final ownerName = _decodeName(b, p);
      final owner = ownerName.name;
      p = ownerName.nextOffset;
      if (p + 10 > b.length) throw const FormatException('Truncated RR');
      final type = (b[p] << 8) | b[p + 1];
      final cls = (b[p + 2] << 8) | b[p + 3];
      final rdlen = (b[p + 8] << 8) | b[p + 9];
      final rd = p + 10;
      final rdEnd = rd + rdlen;
      if (rdEnd > b.length) throw const FormatException('Bad RDATA length');
      records.add((owner: owner, type: type, cls: cls, rd: rd, rdlen: rdlen));

      if (type == 5 && cls == 1) {
        if (rdlen == 0) throw const FormatException('Empty CNAME RDATA');
        final targetName = _decodeName(b, rd, encodedEnd: rdEnd);
        if (targetName.nextOffset != rdEnd) {
          throw const FormatException('CNAME RDATA length mismatch');
        }
        final previousTarget = cnameTargets[owner];
        if (previousTarget != null && previousTarget != targetName.name) {
          throw const FormatException('Conflicting CNAME targets for one owner');
        }
        cnameTargets[owner] = targetName.name;
      }
      p = rdEnd;
    }

    // Follow the finite CNAME records actually present in this response.
    // Cycle detection makes this loop terminate without an arbitrary hop cap.
    final allowedOwners = <String>{expectedName};
    var currentOwner = expectedName;
    while (true) {
      final target = cnameTargets[currentOwner];
      if (target == null || !allowedOwners.add(target)) break;
      currentOwner = target;
    }

    final ips = <String>[];
    for (final rr in records) {
      if (rr.type != recordType ||
          rr.cls != 1 ||
          !allowedOwners.contains(rr.owner)) {
        continue;
      }
      if (recordType == 1) {
        if (rr.rdlen != 4 || !publicV4(b, rr.rd)) {
          throw const FormatException(
            'Non-public/blockpage A answer for queried name',
          );
        }
        ips.add('${b[rr.rd]}.${b[rr.rd + 1]}.${b[rr.rd + 2]}.${b[rr.rd + 3]}');
      } else {
        if (rr.rdlen != 16 || !publicV6(b, rr.rd)) {
          throw const FormatException(
            'Non-public/blockpage AAAA answer for queried name',
          );
        }
        ips.add(
          InternetAddress.fromRawAddress(
            Uint8List.fromList(b.sublist(rr.rd, rr.rd + 16)),
          ).address,
        );
      }
    }
    if (ips.isEmpty) {
      throw const FormatException('No usable A/AAAA answer for queried name');
    }
    return ips;
  }

  static Future<T> _waitForProbe<T>(
    Future<T> operation,
    Duration timeout,
    Future<void>? cancellation,
  ) {
    final futures = <Future<T>>[operation];
    if (cancellation != null) {
      futures.add(cancellation.then<T>((_) => throw const _NatDnsProbeCancelled()));
    }
    return Future.any<T>(futures).timeout(timeout);
  }

  static Future<NatDnsProbeResult> probe(String server, String domain,
      {Duration timeout = const Duration(seconds: 2),
      bool Function()? cancelled,
      int recordType = 1}) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    Timer? cancelWatcher;
    Completer<void>? cancellationSignal;
    var cancellationCallbackFailed = false;

    bool cancellationRequested() {
      if (cancellationCallbackFailed) return true;
      try {
        final requested = cancelled?.call() ?? false;
        if (requested && cancellationSignal != null && !cancellationSignal!.isCompleted) {
          cancellationSignal!.complete();
        }
        return requested;
      } catch (_) {
        cancellationCallbackFailed = true;
        if (cancellationSignal != null && !cancellationSignal!.isCompleted) {
          cancellationSignal!.complete();
        }
        return true;
      }
    }

    try {
      final target = InternetAddress.tryParse(server);
      if (target == null || (target.type != InternetAddressType.IPv4 &&
          target.type != InternetAddressType.IPv6)) {
        throw const FormatException('Resolver must be an IP literal');
      }
      if (recordType != 1 && recordType != 28) {
        throw ArgumentError.value(recordType, 'recordType');
      }
      final id = Random.secure().nextInt(0x10000);
      final packet = buildQuery(domain, id, recordType: recordType);
      if (cancelled != null) {
        cancellationSignal = Completer<void>();
        if (cancellationRequested()) {
          return NatDnsProbeResult(server, domain, null,
              error: cancellationCallbackFailed ? 'cancellation callback failed' : 'cancelled');
        }
        cancelWatcher = Timer.periodic(const Duration(milliseconds: 100), (timer) {
          if (cancellationRequested()) timer.cancel();
        });
      }
      final bindAddress = target.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6 : InternetAddress.anyIPv4;
      final bindFuture = RawDatagramSocket.bind(bindAddress, 0);
      late final RawDatagramSocket activeSocket;
      try {
        activeSocket = await _waitForProbe(bindFuture, timeout, cancellationSignal?.future);
        socket = activeSocket;
      } catch (_) {
        // The underlying bind cannot be cancelled by Future.timeout/Future.any.
        // Close a socket that the OS may deliver after timeout or cancellation.
        unawaited(bindFuture.then<void>(
          (lateSocket) => lateSocket.close(),
          onError: (Object _) {},
        ));
        rethrow;
      }
      final sw = Stopwatch()..start();
      final completer = Completer<List<String>>();
      subscription = activeSocket.listen((event) {
        if (event != RawSocketEvent.read || completer.isCompleted) return;
        final dg = activeSocket.receive();
        if (dg == null) return;
        // RFC 5452: a matching ID alone is insufficient; verify source tuple.
        if (dg.port != 53 || dg.address.address != target.address) return;
        try {
          completer.complete(parseResponse(dg.data, id, domain, recordType: recordType));
        } catch (_) {
          // Ignore unrelated/malformed datagrams until timeout.
        }
      });
      if (activeSocket.send(packet, target, 53) <= 0) {
        throw const SocketException('DNS send failed');
      }
      final ips = await _waitForProbe(completer.future, timeout, cancellationSignal?.future);
      sw.stop();
      return NatDnsProbeResult(server, domain, sw.elapsedMilliseconds, addresses: ips);
    } catch (e) {
      return NatDnsProbeResult(
        server,
        domain,
        null,
        error: cancellationCallbackFailed
            ? 'cancellation callback failed'
            : (e is _NatDnsProbeCancelled ? 'cancelled' : e.toString()),
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
