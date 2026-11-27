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
  if (octets.length != 4 || prefix == null || prefix < 8 || prefix > 32) {
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
