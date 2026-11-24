// NAT IP SCAN ==============================================================
// اسکن سریع آدرس‌های IP برای پیدا کردن سرورهای قابل‌دسترس در نت ملی.
// فقط اتصال TCP می‌زند؛ یعنی هنوز تایید نمی‌کند که VPN کار می‌کند،
// فقط می‌گوید آن آدرس و پورت جواب می‌دهد. تایید نهایی را موتور اصلی انجام می‌دهد.
//
// IMPROVEMENTS over previous version:
//   • Adaptive concurrency: based on Platform.numberOfProcessors, clamped to
//     device-safe range. Never too small, never CPU-crushing.
//   • Guaranteed socket cleanup: every Socket is destroyed in a finally block,
//     so slow/timed-out probes never leak file descriptors.
//   • Live cancellation: in-flight workers exit as soon as cancelled() returns
//     true — no waiting for individual timeouts.
//   • Progress callbacks: optional onProgress(done, total, hits) for live UI.
//   • Optional randomize: shuffle the candidate list to avoid hitting the same
//     subnet first every run.
//   • Timeout accuracy: the Stopwatch is stopped exactly when the connect
//     returns, not after potential catch/finally work.
//   • No artificial caps: the caller controls want/budget/concurrency. We
//     only enforce a device-safe ceiling for concurrency to prevent OOM.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

import 'errjournal.dart';
import 'nnie_core.dart'; // natStableSort

/// Normalize persisted list/range cursors before using them as indexes.
/// Corrupt, negative, or non-numeric state restarts at the first item.
int natCursorIndex(Object? value, int length) {
  if (length <= 0) return 0;
  final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
  if (parsed == null || parsed < 0) return 0;
  return parsed % length;
}

/// Build the complete 0..65535 port-number inventory for one transport.
/// Preferred values affect order only; they never exclude another port.
List<int> natBuildFullPortInventory(
  Iterable<int> preferredPorts, {
  int firstPort = 0,
  int lastPort = 65535,
}) {
  if (firstPort < 0 || lastPort > 65535 || firstPort > lastPort) {
    return const <int>[];
  }
  final seen = <int>{};
  final out = <int>[];
  for (final port in preferredPorts) {
    if (port < firstPort || port > lastPort || !seen.add(port)) continue;
    out.add(port);
  }
  for (var port = firstPort; port <= lastPort; port++) {
    if (seen.add(port)) out.add(port);
  }
  return out;
}

/// Select active TCP ports by the configured scan scope.
///
/// Explicitly saved user ranges retain the complete 1..65535 inventory.
/// Exact configured server addresses remain limited to their declared ports.
/// This keeps broad scanning intentional and resumable without silently
/// narrowing a user-supplied IP Clean range to ports already seen in configs.
List<int> natPortsForActiveScan({
  required Iterable<int> fullInventory,
  required Iterable<int> configuredEndpointPorts,
  required bool hasExplicitRanges,
}) {
  final configured = configuredEndpointPorts
      .where((port) => port >= 1 && port <= 65535)
      .toSet();
  final seen = <int>{};
  final out = <int>[];
  for (final port in fullInventory) {
    if (port < 1 || port > 65535) continue;
    if (!hasExplicitRanges && !configured.contains(port)) continue;
    if (seen.add(port)) out.add(port);
  }
  return out;
}

/// UDP and TCP have independent inventories/cursors at their consumers.
List<int> natBuildFullUdpPortInventory(Iterable<int> preferredPorts) =>
    natBuildFullPortInventory(preferredPorts, firstPort: 0, lastPort: 65535);

class NatIpHit {
  final String ip;
  final int ms;
  const NatIpHit(this.ip, this.ms);

  @override
  String toString() => '$ip ($ms ms)';
}

/// بلوک CIDR مثل «5.160.0.0/16» را به فهرست IP تبدیل می‌کند.
/// برای بلوک‌های بزرگ، فقط [maxPerBlock] آدرس پراکنده برمی‌گرداند.
List<String> natExpandCidr(String cidr, {int maxPerBlock = 4096}) {
  if (maxPerBlock <= 0) return const [];
  final parts = cidr.trim().split('/');
  if (parts.length != 2) return const [];
  final octets = parts[0].split('.');
  final prefix = int.tryParse(parts[1].trim());
  if (octets.length != 4 || prefix == null || prefix < 0 || prefix > 32) {
    return const [];
  }
  int base = 0;
  for (final o in octets) {
    final v = int.tryParse(o.trim());
    if (v == null || v < 0 || v > 255) return const [];
    base = (base << 8) | v;
  }
  final size = 1 << (32 - prefix);
  final start = base & ~(size - 1) & 0xFFFFFFFF;
  // Ceiling division is required: floor division can exceed maxPerBlock
  // for non-divisible subnet sizes (e.g. /24 with a limit of 100 yields 128).
  final step = size > maxPerBlock ? (size + maxPerBlock - 1) ~/ maxPerBlock : 1;
  final out = <String>[];
  for (var i = 0; i < size; i += step) {
    final v = start + i;
    out.add('${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}');
  }
  return out;
}

/// Expand an IPv6 CIDR in deterministic, evenly spaced chunks.
/// IPv6 ranges are 128-bit; BigInt avoids truncation to Dart's 64-bit int.
List<String> natExpandIpv6Cidr(String cidr, {int maxPerBlock = 4096}) {
  if (maxPerBlock <= 0) return const [];
  final parts = cidr.trim().split('/');
  if (parts.length != 2) return const [];
  final address = InternetAddress.tryParse(parts[0].trim());
  final prefix = int.tryParse(parts[1].trim());
  if (address == null ||
      address.type != InternetAddressType.IPv6 ||
      prefix == null ||
      prefix < 0 ||
      prefix > 128) {
    return const [];
  }
  final bytes = address.rawAddress;
  var base = BigInt.zero;
  for (final byte in bytes) {
    base = (base << 8) | BigInt.from(byte);
  }
  final hostBits = 128 - prefix;
  final size = BigInt.one << hostBits;
  final mask = prefix == 0 ? BigInt.zero :
      ((BigInt.one << 128) - BigInt.one) ^ (size - BigInt.one);
  base &= mask;
  final count = size > BigInt.from(maxPerBlock)
      ? maxPerBlock : size.toInt();
  final step = size > BigInt.from(maxPerBlock)
      ? (size + BigInt.from(maxPerBlock) - BigInt.one) ~/ BigInt.from(maxPerBlock)
      : BigInt.one;
  final out = <String>[];
  for (var i = 0; i < count; i++) {
    var value = base + BigInt.from(i) * step;
    final raw = List<int>.filled(16, 0);
    for (var j = 15; j >= 0; j--) {
      raw[j] = (value & BigInt.from(255)).toInt();
      value >>= 8;
    }
    out.add(InternetAddress.fromRawAddress(Uint8List.fromList(raw)).address);
  }
  return out;
}

/// Resumable, lossless iterator for IPv4 and IPv6 literals, CIDRs and
/// linear ranges. Decimal-string cursors preserve the full 128-bit IPv6 space.
({List<String> addresses, String nextCursor}) natExpandIpRangeCursor(
  String range,
  String cursor, {
  int maxPerBlock = 4096,
  bool wrap = true,
}) {
  if (maxPerBlock <= 0 || cursor == 'done') {
    return (addresses: const <String>[], nextCursor: cursor);
  }
  // Persisted cursors may be stale or malformed. A negative offset would
  // otherwise produce negative BigInt addresses before raw-byte conversion.
  final parsedCursor = BigInt.tryParse(cursor);
  final current = parsedCursor == null || parsedCursor.isNegative
      ? BigInt.zero
      : parsedCursor;
  BigInt? first;
  BigInt? last;
  int byteLength = 0;

  BigInt toValue(InternetAddress address) {
    var value = BigInt.zero;
    for (final byte in address.rawAddress) {
      value = (value << 8) | BigInt.from(byte);
    }
    return value;
  }

  if (range.contains('/')) {
    final parts = range.trim().split('/');
    if (parts.length != 2) {
      return (addresses: const <String>[], nextCursor: cursor);
    }
    final address = InternetAddress.tryParse(parts[0].trim());
    final prefix = int.tryParse(parts[1].trim());
    if (address == null || prefix == null) {
      return (addresses: const <String>[], nextCursor: cursor);
    }
    byteLength = address.rawAddress.length;
    final width = byteLength * 8;
    if (prefix < 0 || prefix > width) {
      return (addresses: const <String>[], nextCursor: cursor);
    }
    final size = BigInt.one << (width - prefix);
    final mask = prefix == 0 ? BigInt.zero :
        ((BigInt.one << width) - BigInt.one) ^ (size - BigInt.one);
    first = toValue(address) & mask;
    last = first + size - BigInt.one;
  } else if (range.contains('-')) {
    final parts = range.trim().split('-');
    if (parts.length != 2) {
      return (addresses: const <String>[], nextCursor: cursor);
    }
    final start = InternetAddress.tryParse(parts[0].trim());
    final end = InternetAddress.tryParse(parts[1].trim());
    if (start == null || end == null || start.type != end.type) {
      return (addresses: const <String>[], nextCursor: cursor);
    }
    byteLength = start.rawAddress.length;
    final startValue = toValue(start);
    final endValue = toValue(end);
    first = startValue <= endValue ? startValue : endValue;
    last = startValue <= endValue ? endValue : startValue;
  } else {
    final address = InternetAddress.tryParse(range.trim());
    if (address == null) {
      return (addresses: const <String>[], nextCursor: cursor);
    }
    return (addresses: [address.address], nextCursor: 'done');
  }

  final size = last! - first! + BigInt.one;
  if (size == BigInt.one && current > BigInt.zero) {
    return (addresses: const <String>[], nextCursor: 'done');
  }
  if (!wrap && current >= size) {
    return (addresses: const <String>[], nextCursor: 'done');
  }
  final offset = wrap ? current % size : current;
  final remaining = size - offset;
  // Wrapping cursors fill the requested batch across the end of the range;
  // non-wrapping cursors stop exactly at exhaustion and return the done marker.
  final take = size == BigInt.one
      ? 1
      : (wrap
          // A wrapped slice may cross the range boundary, but never repeats
          // an address inside the same batch when the range is smaller.
          ? (size < BigInt.from(maxPerBlock) ? size.toInt() : maxPerBlock)
          : min(
              maxPerBlock,
              remaining > BigInt.from(maxPerBlock) ? maxPerBlock : remaining.toInt(),
            ));
  final addresses = <String>[];
  for (var i = 0; i < take; i++) {
    final value = first + ((offset + BigInt.from(i)) % size);
    final bytes = List<int>.filled(byteLength, 0);
    var encoded = value;
    for (var index = byteLength - 1; index >= 0; index--) {
      bytes[index] = (encoded & BigInt.from(255)).toInt();
      encoded >>= 8;
    }
    addresses.add(InternetAddress.fromRawAddress(Uint8List.fromList(bytes)).address);
  }
  final nextOffset = offset + BigInt.from(take);
  return (
    addresses: addresses,
    nextCursor: size == BigInt.one
        ? 'done'
        : (wrap
            ? (nextOffset % size).toString()
            : (nextOffset >= size ? 'done' : nextOffset.toString())),
  );
}

/// IPv6-specific façade retained for callers that need strict family validation.
({List<String> addresses, String nextCursor}) natExpandIpv6RangeCursor(
  String range,
  String cursor, {
  int maxPerBlock = 4096,
}) {
  bool ipv6;
  if (range.contains('/')) {
    final parts = range.trim().split('/');
    ipv6 = parts.length == 2 &&
        InternetAddress.tryParse(parts[0].trim())?.type == InternetAddressType.IPv6;
  } else if (range.contains('-')) {
    final parts = range.trim().split('-');
    ipv6 = parts.length == 2 &&
        InternetAddress.tryParse(parts[0].trim())?.type == InternetAddressType.IPv6 &&
        InternetAddress.tryParse(parts[1].trim())?.type == InternetAddressType.IPv6;
  } else {
    ipv6 = InternetAddress.tryParse(range.trim())?.type == InternetAddressType.IPv6;
  }
  if (!ipv6) return (addresses: const <String>[], nextCursor: cursor);
  return natExpandIpRangeCursor(range, cursor, maxPerBlock: maxPerBlock);
}

/// Linear IPv4 or IPv6 address range. Large ranges are returned as a
/// resumable-sized slice; use natExpandIpRangeCursor for subsequent slices.
List<String> natExpandDash(String range, {int maxCount = 65536}) {
  if (maxCount <= 0) return const [];
  final parts = range.trim().split('-');
  if (parts.length != 2) return const [];
  final startAddress = InternetAddress.tryParse(parts[0].trim());
  final endAddress = InternetAddress.tryParse(parts[1].trim());
  if (startAddress?.type == InternetAddressType.IPv6 &&
      endAddress?.type == InternetAddressType.IPv6) {
    return natExpandIpRangeCursor(
      range,
      '0',
      maxPerBlock: maxCount,
    ).addresses;
  }
  int? toInt(String ip) {
    final o = ip.trim().split('.');
    if (o.length != 4) return null;
    var v = 0;
    for (final x in o) {
      final n = int.tryParse(x.trim());
      if (n == null || n < 0 || n > 255) return null;
      v = (v << 8) | n;
    }
    return v;
  }
  final a = toInt(parts[0]);
  final b = toInt(parts[1]);
  if (a == null || b == null) return const [];
  // Match the generic IPv4/IPv6 cursor semantics for reversed endpoints.
  final first = min(a, b);
  final last = max(a, b);
  final count = last - first + 1;
  final step = count > maxCount ? (count + maxCount - 1) ~/ maxCount : 1; // مشکل ۱۵: سقف رعایت شود
  final out = <String>[];
  for (var v = first; v <= last; v += step) {
    out.add('${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}');
  }
  return out;
}

/// اتصال TCP به ip:port. اگر جواب داد زمان پاسخ را برمی‌گرداند، وگرنه null.
/// تضمین: سوکت در هر حالتی (موفق، خطا، تایم‌اوت) بسته می‌شود.
Future<int?> natTcpProbe(String ip, int port, Duration timeout) async {
  final sw = Stopwatch()..start();
  Socket? s;
  try {
    s = await Socket.connect(ip, port, timeout: timeout);
    sw.stop();
    return sw.elapsedMilliseconds;
  } catch (e) {
    // خطای شبکه عادی است. با پیشوند SILENT- سقف ۳۰۰ بار در ژورنال اعمال می‌شود
    // (قبلاً هر تایم‌اوت یک ورودی کامل با stack می‌ساخت و در یک اسکن هزاران بار).
    errJournalAdd(e, kind: 'SILENT-NATIP');
    return null;
  } finally {
    // Belt-and-braces: destroy even if the catch path was bypassed
    try {
      s?.destroy();
    } catch (e) {
      errJournalAdd(e, kind: 'SILENT-DESTROY');
    }
  }
}

/// Clamp a user-supplied concurrency to what this device can actually sustain.
/// 0 or negative = auto (based on CPU count). Very high values = clamped.
int natAdaptiveConcurrency(int requested) {
  int cores;
  try {
    cores = Platform.numberOfProcessors;
  } catch (_) {
    cores = 4; // conservative fallback
  }
  // Safe ceiling: 4 × CPU cores. 8-core phone → 32. 4-core → 16. 2-core → 8.
  // Absolute ceiling: 256 (never reasonable on a phone, but respected if asked).
  final safeMax = (cores * 4).clamp(16, 256).toInt();
  if (requested <= 0) {
    return (cores * 2).clamp(8, 64).toInt();
  }
  return requested.clamp(1, safeMax).toInt();
}

/// اسکن هم‌زمان فهرست IP. وقتی [want] آدرس سالم پیدا شد، یا [budget] تمام شد،
/// یا [cancelled] true برگرداند، متوقف می‌شود.
/// نتیجه از سریع‌ترین به کندترین مرتب است.
///
/// IMPROVEMENTS:
///   • Concurrency is clamped by [natAdaptiveConcurrency] — never too small,
///     never device-crushing.
///   • Live cancellation: in-flight probes exit as soon as cancelled() is true.
///   • Progress reporting via [onProgress] (called every few completions).
///   • Optional [randomize] to shuffle the scan order.
///   • No artificial caps on the caller's intent.
Future<List<NatIpHit>> natScanIps(
  List<String> ips, {
  int port = 443,
  int concurrency = 16,
  int want = 20,
  Duration budget = const Duration(seconds: 90),
  Duration timeout = const Duration(milliseconds: 1500),
  bool Function()? cancelled,
  void Function(int done, int total, int hits)? onProgress,
  bool randomize = false,
}) async {
  if (ips.isEmpty || want <= 0) return <NatIpHit>[];

  if (budget <= Duration.zero || timeout <= Duration.zero ||
      port < 1 || port > 65535) {
    return <NatIpHit>[];
  }

  final effective = natAdaptiveConcurrency(concurrency);
  // Stopwatch is monotonic; wall-clock changes must not extend or truncate a scan.
  final elapsed = Stopwatch()..start();
  final hits = <NatIpHit>[];

  // Optional shuffle so the same subnet is not hit first on every run.
  final source = randomize ? (List<String>.of(ips)..shuffle(Random())) : ips;

  var next = 0;
  var done = 0;
  final total = source.length;

  bool aborted() => cancelled?.call() ?? false;

  Future<void> worker() async {
    while (true) {
      if (hits.length >= want) return;
      if (aborted()) return;
      if (elapsed.elapsed >= budget) return;

      final idx = next++;
      if (idx >= source.length) return;
      final ip = source[idx];

      final ms = await natTcpProbe(ip, port, timeout);
      // Do not publish a probe that completed after cancellation or the time budget.
      // In-flight socket connects are bounded by [timeout], then discarded if stale.
      if (aborted() || elapsed.elapsed >= budget) {
        done++;
        if (onProgress != null) onProgress(done, total, hits.length);
        return;
      }
      // Several workers may finish successful probes in the same event-loop turn.
      // Enforce [want] at insertion time so concurrent completions cannot exceed it.
      if (ms != null && hits.length < want) {
        hits.add(NatIpHit(ip, ms));
      }

      done++;
      // Report every 5 completions (or immediately on a hit) — keeps UI fresh
      // without spamming the callback for thousands of failures.
      if (onProgress != null && (done % 5 == 0 || ms != null)) {
        onProgress(done, total, hits.length);
      }
    }
  }

  // Spawn exactly [effective] workers, each pulling from the shared counter.
  final workers = <Future<void>>[
    for (var i = 0; i < effective && i < total; i++) worker(),
  ];
  await Future.wait(workers);

  natStableSort(hits, (a, b) => a.ms.compareTo(b.ms));
  if (onProgress != null) onProgress(done, total, hits.length);
  return hits;
}
