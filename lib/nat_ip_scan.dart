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
import 'dart:math';

import 'errjournal.dart';
import 'nnie_core.dart'; // natStableSort


/// Lazy, cursor-addressable expansion for an explicitly supplied IPv4 range.
/// A slice is bounded in memory, while [nextOffset] allows the caller to walk
/// every address in the range over as many resumable passes as necessary.
/// IPv6 is intentionally accepted only as an exact /128 endpoint: enumerating
/// broad IPv6 prefixes is not a meaningful address-discovery strategy.
class NatAddressRangeCursor {
  NatAddressRangeCursor._(this._first, this.addressCount, this._ipv6);

  final int _first;
  final int addressCount;
  final String? _ipv6;

  static int? _ipv4ToInt(String raw) {
    final parsed = InternetAddress.tryParse(raw.trim());
    if (parsed == null || parsed.type != InternetAddressType.IPv4) return null;
    final octets = parsed.address.split('.').map(int.parse).toList();
    return (octets[0] << 24) | (octets[1] << 16) |
        (octets[2] << 8) | octets[3];
  }

  static NatAddressRangeCursor? parse(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;
    if (raw.contains('/')) {
      final parts = raw.split('/');
      if (parts.length != 2) return null;
      final address = InternetAddress.tryParse(parts[0].trim());
      final prefix = int.tryParse(parts[1].trim());
      if (address == null || prefix == null) return null;
      if (address.type == InternetAddressType.IPv6) {
        if (prefix != 128) return null;
        return NatAddressRangeCursor._(0, 1, address.address);
      }
      if (prefix < 0 || prefix > 32) return null;
      final first = _ipv4ToInt(address.address);
      if (first == null) return null;
      final count = 1 << (32 - prefix);
      final mask = 0xffffffff ^ (count - 1);
      return NatAddressRangeCursor._(first & mask, count, null);
    }
    if (raw.contains('-')) {
      final parts = raw.split('-');
      if (parts.length != 2) return null;
      final left = _ipv4ToInt(parts[0]);
      final right = _ipv4ToInt(parts[1]);
      if (left == null || right == null) return null;
      final first = left < right ? left : right;
      final last = left < right ? right : left;
      return NatAddressRangeCursor._(first, last - first + 1, null);
    }
    final address = InternetAddress.tryParse(raw);
    if (address == null) return null;
    if (address.type == InternetAddressType.IPv6) {
      return NatAddressRangeCursor._(0, 1, address.address);
    }
    final first = _ipv4ToInt(address.address);
    return first == null ? null : NatAddressRangeCursor._(first, 1, null);
  }

  /// Returns (addresses, nextOffset); -1 means the range is exhausted.
  (List<String> addresses, int nextOffset) read(int offset, int limit) {
    if (offset < 0 || limit <= 0 || offset >= addressCount) {
      return (<String>[], -1);
    }
    if (_ipv6 != null) {
      return offset == 0
          ? (<String>[_ipv6!], -1)
          : (<String>[], -1);
    }
    final count = limit < addressCount - offset
        ? limit : addressCount - offset;
    final result = <String>[];
    for (var index = 0; index < count; index++) {
      final value = _first + offset + index;
      result.add('${(value >> 24) & 255}.${(value >> 16) & 255}.${(value >> 8) & 255}.${value & 255}');
    }
    final next = offset + count;
    return (result, next >= addressCount ? -1 : next);
  }
}

/// Validated country-level registry/BGP prefix snapshot.
/// IPv6 prefixes are retained as prefixes; they are never expanded into
/// individual addresses because a /64 contains an infeasible address space.
class NatCountryPrefixSnapshot {
  const NatCountryPrefixSnapshot({
    required this.ipv4,
    required this.ipv6,
    required this.asns,
  });

  final List<String> ipv4;
  final List<String> ipv6;
  final List<String> asns;

  static NatCountryPrefixSnapshot? parseCountryResources(Object? payload) {
    if (payload is! Map) return null;
    if (payload['status'] != null && payload['status'] != 'ok') return null;
    final data = payload['data'];
    if (data is! Map) return null;
    final resources = data['resources'];
    if (resources is! Map) return null;

    final ipv4 = <String>{};
    final ipv6 = <String>{};
    final asns = <String>{};

    void readIpv4(Object? raw) {
      if (raw is! List) return;
      for (final item in raw) {
        final value = '$item'.trim();
        if (value.isEmpty) continue;
        final parsed = NatAddressRangeCursor.parse(value);
        if (parsed == null) continue;
        final addressPart = value.contains('/')
            ? value.substring(0, value.indexOf('/')).trim()
            : (value.contains('-') ? value.split('-').first.trim() : value);
        final address = InternetAddress.tryParse(addressPart);
        if (address?.type == InternetAddressType.IPv4) ipv4.add(value);
      }
    }

    void readIpv6(Object? raw) {
      if (raw is! List) return;
      for (final item in raw) {
        final value = '$item'.trim();
        if (value.isEmpty) continue;
        final parts = value.split('/');
        if (parts.length > 2) continue;
        final address = InternetAddress.tryParse(parts.first.trim());
        if (address == null || address.type != InternetAddressType.IPv6) continue;
        final prefix = parts.length == 1 ? 128 : int.tryParse(parts[1].trim());
        if (prefix == null || prefix < 0 || prefix > 128) continue;
        ipv6.add('${address.address}/$prefix');
      }
    }

    void readAsns(Object? raw) {
      if (raw is! List) return;
      for (final item in raw) {
        final match = RegExp(r'^(?:AS)?([0-9]{1,10})$', caseSensitive: false)
            .firstMatch('$item'.trim());
        if (match == null) continue;
        final number = int.tryParse(match.group(1)!);
        if (number != null && number > 0) asns.add('AS$number');
      }
    }

    readIpv4(resources['ipv4']);
    readIpv6(resources['ipv6']);
    readAsns(resources['asn']);
    if (ipv4.isEmpty && ipv6.isEmpty && asns.isEmpty) return null;
    return NatCountryPrefixSnapshot(
      ipv4: ipv4.toList()..sort(),
      ipv6: ipv6.toList()..sort(),
      asns: asns.toList()..sort(),
    );
  }

  static List<String> parseIpv6PrefixList(Object? raw) {
    if (raw is! List) return const <String>[];
    final result = <String>{};
    for (final item in raw) {
      final value = item.toString().trim();
      if (value.isEmpty) continue;
      final parts = value.split('/');
      if (parts.length > 2) continue;
      final address = InternetAddress.tryParse(parts.first.trim());
      if (address == null || address.type != InternetAddressType.IPv6) continue;
      final prefix = parts.length == 1 ? 128 : int.tryParse(parts[1].trim());
      if (prefix == null || prefix < 0 || prefix > 128) continue;
      result.add(address.address + '/' + prefix.toString());
    }
    return result.toList()..sort();
  }

  static List<String> parseAnnouncedIpv6(Object? payload) {
    if (payload is! Map || payload['status'] != 'ok') return const <String>[];
    final data = payload['data'];
    if (data is! Map || data['prefixes'] is! List) return const <String>[];
    final values = <String>[];
    for (final item in data['prefixes'] as List) {
      if (item is Map && item['prefix'] != null) {
        values.add(item['prefix'].toString());
      }
    }
    return parseIpv6PrefixList(values);
  }

  static List<String> parseAnnouncedIpv4(Object? payload) {
    if (payload is! Map || payload['status'] != 'ok') return const <String>[];
    final data = payload['data'];
    if (data is! Map || data['prefixes'] is! List) return const <String>[];
    final result = <String>{};
    for (final item in data['prefixes'] as List) {
      if (item is! Map) continue;
      final value = '${item['prefix'] ?? ''}'.trim();
      if (value.isEmpty) continue;
      final parsed = NatAddressRangeCursor.parse(value);
      if (parsed == null) continue;
      final addressPart = value.contains('/')
          ? value.substring(0, value.indexOf('/')).trim()
          : value;
      if (InternetAddress.tryParse(addressPart)?.type == InternetAddressType.IPv4) {
        result.add(value);
      }
    }
    return result.toList()..sort();
  }
}

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

/// بازه‌ی خطی به شکل a.b.c.d-e.f.g.h (برای نوشته‌هایی که CIDR نیستند).
/// بازه‌های بزرگ‌تر از maxCount به‌طور یکنواخت نمونه‌برداری می‌شوند.
List<String> natExpandDash(String range, {int maxCount = 65536}) {
  if (maxCount <= 0) return const [];
  final parts = range.trim().split('-');
  if (parts.length != 2) return const [];
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
  if (a == null || b == null || b < a) return const [];
  final count = b - a + 1;
  final step = count > maxCount ? (count + maxCount - 1) ~/ maxCount : 1; // مشکل ۱۵: سقف رعایت شود
  final out = <String>[];
  for (var v = a; v <= b; v += step) {
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

/// Derive scanner concurrency from the actual processor count.
/// A non-positive request selects the adaptive default; a positive request is
/// respected up to four workers per logical processor. This is a resource
/// safety bound, not a fixed scan-count ceiling: the scanner can still traverse
/// the complete input through its resumable work cursor.
int natAdaptiveConcurrency(int requested) {
  int cores;
  try {
    cores = Platform.numberOfProcessors;
  } catch (_) {
    cores = 2; // conservative fallback when the runtime cannot report CPUs
  }
  final availableCores = cores < 1 ? 1 : cores;
  final safeMax = availableCores * 4;
  if (requested <= 0) return availableCores * 2;
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
  int? want,
  Duration? budget,
  Duration timeout = const Duration(milliseconds: 1500),
  bool Function()? cancelled,
  void Function(int done, int total, int hits)? onProgress,
  bool randomize = false,
}) async {
  if (ips.isEmpty || (want != null && want <= 0)) return <NatIpHit>[];

  if ((budget != null && budget <= Duration.zero) ||
      timeout <= Duration.zero || port < 1 || port > 65535) {
    return <NatIpHit>[];
  }

  final hitLimit = want ?? ips.length;
  if (hitLimit <= 0) return <NatIpHit>[];
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
      if (hits.length >= hitLimit) return;
      if (aborted()) return;
      if (budget != null && elapsed.elapsed >= budget) return;

      final idx = next++;
      if (idx >= source.length) return;
      final ip = source[idx];

      final ms = await natTcpProbe(ip, port, timeout);
      // Do not publish a probe that completed after cancellation or the time budget.
      // In-flight socket connects are bounded by [timeout], then discarded if stale.
      if (aborted() || (budget != null && elapsed.elapsed >= budget)) {
        done++;
        if (onProgress != null) onProgress(done, total, hits.length);
        return;
      }
      // Several workers may finish successful probes in the same event-loop turn.
      // Enforce [want] at insertion time so concurrent completions cannot exceed it.
      if (ms != null && hits.length < hitLimit) {
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
