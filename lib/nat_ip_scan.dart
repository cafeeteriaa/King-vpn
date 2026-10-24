// NAT IP SCAN ==============================================================
// اسکن سریع آدرس‌های IP برای پیدا کردن سرورهای قابل‌دسترس در نت ملی.
// فقط اتصال TCP می‌زند؛ یعنی هنوز تایید نمی‌کند که VPN کار می‌کند،
// فقط می‌گوید آن آدرس و پورت جواب می‌دهد. تایید نهایی را موتور اصلی انجام می‌دهد.

import 'dart:async';
import 'dart:io';
import 'dart:math';

class NatIpHit {
  final String ip;
  final int ms;
  const NatIpHit(this.ip, this.ms);
}

/// یک بلوک CIDR مثل «5.160.0.0/16» را به فهرست IP تبدیل می‌کند.
/// برای بلوک‌های بزرگ، فقط [maxPerBlock] آدرس پراکنده برمی‌گرداند.
List<String> natExpandCidr(String cidr, {int maxPerBlock = 4096}) {
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
  final step = size > maxPerBlock ? size ~/ maxPerBlock : 1;
  final out = <String>[];
  for (var i = 0; i < size; i += step) {
    final v = start + i;
    out.add('${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}');
  }
  return out;
}

/// اتصال TCP به ip:port. اگر جواب داد زمان پاسخ را برمی‌گرداند، وگرنه null.
Future<int?> natTcpProbe(String ip, int port, Duration timeout) async {
  final sw = Stopwatch()..start();
  try {
    final s = await Socket.connect(ip, port, timeout: timeout);
    sw.stop();
    s.destroy();
    return sw.elapsedMilliseconds;
  } catch (_) {
    return null;
  }
}

/// اسکن هم‌زمان فهرست IP. وقتی [want] آدرس سالم پیدا شد، یا [budget] تمام شد،
/// یا [cancelled] true برگرداند، متوقف می‌شود.
/// نتیجه از سریع‌ترین به کندترین مرتب است.
Future<List<NatIpHit>> natScanIps(
  List<String> ips, {
  int port = 443,
  int concurrency = 150,
  int want = 20,
  Duration budget = const Duration(seconds: 90),
  Duration timeout = const Duration(milliseconds: 1500),
  bool Function()? cancelled,
}) async {
  final hits = <NatIpHit>[];
  final deadline = DateTime.now().add(budget);
  var next = 0;

  Future<void> worker() async {
    while (true) {
      if (hits.length >= want) return;
      if (cancelled != null && cancelled()) return;
      if (DateTime.now().isAfter(deadline)) return;
      if (next >= ips.length) return;
      final ip = ips[next++];
      final ms = await natTcpProbe(ip, port, timeout);
      if (ms != null) hits.add(NatIpHit(ip, ms));
    }
  }

  final n = min(concurrency, max(ips.length, 1));
  await Future.wait(List.generate(n, (_) => worker()));
  hits.sort((a, b) => a.ms.compareTo(b.ms));
  return hits;
}
