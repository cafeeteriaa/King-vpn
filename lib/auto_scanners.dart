part of 'main.dart';

// AUTOSCAN: اسکنر خودکار SNI و پورت. بدون ورودی دستی؛ IPهای تمیز پوشه‌ی جهانی را تست می‌کند
// و نتیجه را همان‌جا ذخیره می‌کند (کلیدهای 'sni' و 'port').
const List<String> kAutoSniDomains = [
  'www.google.com', 'www.youtube.com', 'www.instagram.com', 'www.microsoft.com',
  'www.apple.com', 'www.cloudflare.com', 'speed.cloudflare.com', 'www.digikala.com',
  'www.aparat.com', 'www.snapp.ir', 'www.divar.ir', 'www.wikipedia.org',
  'www.amazon.com', 'dl.google.com', 'www.whatsapp.com', 'www.telegram.org',
  'www.spotify.com', 'www.github.com',
];
const List<int> kAutoPorts = [443, 8443, 2053, 2083, 2087, 2096];
const int kAutoIpLimit = 40;

bool _autoScanRunning = false;
bool _autoScanStop = false;

// TLS با SNI مشخص: اگر هندشیک کامل شود، SNI برای آن IP قابل استفاده است
Future<int?> _autoSniOk(String ip, int port, String sni) async {
  final sw = Stopwatch()..start();
  try {
    final s = await SecureSocket.connect(ip, port,
        host: sni,
        timeout: const Duration(seconds: 4),
        onBadCertificate: (_) => true);
    s.destroy();
    return sw.elapsedMilliseconds;
  } catch (_) {
    return null;
  }
}

// ALPN (پروتکل لایه‌ی TLS): خروجی خود نام پروتکل است، مثل h2 یا http/1.1
Future<String?> _autoAlpnOk(String ip, String sni, String alpn) async {
  try {
    final s = await SecureSocket.connect(ip, 443,
        host: sni,
        timeout: const Duration(seconds: 4),
        supportedProtocols: [alpn],
        onBadCertificate: (_) => true);
    final sel = s.selectedProtocol;
    s.destroy();
    return sel;
  } catch (_) {
    return null;
  }
}

Future<bool> _autoPortOk(String ip, int port) async {
  try {
    final s = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 1500));
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> autoScanRun(void Function(String) say) async {
  if (_autoScanRunning) {
    say('اسکن در حال اجراست');
    return;
  }
  _autoScanRunning = true;
  _autoScanStop = false;
  try {
    await goldLoad();
    final ips = [for (final c in _goldIps.values.take(kAutoIpLimit)) c.ip];
    if (ips.isEmpty) {
      say('IP تمیزی در پوشه نیست؛ اول «اسکن خودکار IP» را اجرا کن');
      return;
    }

    // SNI: خروجی خود دامنه‌هاست. هر دامنه یک بار؛ به محض یک IP سالم، همان دامنه ثبت می‌شود
    final sniHits = <String>[];
    var n = 0;
    sniLoop:
    for (final d in kAutoSniDomains) {
      n++;
      var ok = false;
      for (final ip in ips) {
        if (_autoScanStop) break sniLoop;
        if (await _autoSniOk(ip, 443, d) != null) {
          ok = true;
          break;
        }
      }
      if (ok) sniHits.add(d);
      say('SNI $n/${kAutoSniDomains.length} • سالم: ${sniHits.length}');
    }

    // پورت: خروجی خود شماره‌ی پورت است. هر پورت یک بار؛ به محض یک IP سالم، همان پورت ثبت می‌شود
    final portHits = <String>[];
    var m = 0;
    portLoop:
    for (final p in kAutoPorts) {
      m++;
      var ok = false;
      for (final ip in ips) {
        if (_autoScanStop) break portLoop;
        if (await _autoPortOk(ip, p)) {
          ok = true;
          break;
        }
      }
      if (ok) portHits.add('$p');
      say('پورت $m/${kAutoPorts.length} • سالم: ${portHits.length}');
    }

    // TLS/ALPN: خروجی نام پروتکل‌های TLS است؛ روی اولین دامنه‌ی سالم (یا پیش‌فرض) تست می‌شود
    final tlsHits = <String>[];
    final tlsSni = sniHits.isNotEmpty ? sniHits.first : 'www.google.com';
    for (final alpn in const ['h2', 'http/1.1']) {
      if (_autoScanStop) break;
      var ok = false;
      for (final ip in ips) {
        final sel = await _autoAlpnOk(ip, tlsSni, alpn);
        if (sel != null && sel.isNotEmpty) {
          if (!tlsHits.contains(sel)) tlsHits.add(sel);
          ok = true;
          break;
        }
      }
      if (ok) say('TLS: $alpn ✓');
    }

    await goldAddScan('tls', tlsHits);
    await goldAddScan('sni', sniHits);
    await goldAddScan('port', portHits);
    say('تمام شد: ${sniHits.length} SNI و ${portHits.length} پورت در پوشه‌ی جهانی ذخیره شد');
  } catch (e, stk) {
    logError(e, stk);
    say('خطا در اسکن خودکار');
  } finally {
    _autoScanRunning = false;
  }
}

Future<void> autoScanSheet(BuildContext context) async {
  var status = _autoScanRunning ? 'در حال اجرا...' : 'آماده';
  var open = true;
  StateSetter? setS;
  void say(String t) {
    status = t;
    if (open && setS != null) setS!(() {});
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx2, ss) {
      setS = ss;
      return AlertDialog(
        title: const Text('اسکن خودکار SNI و پورت'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('بدون ورودی دستی: IPهای تمیز پوشه‌ی جهانی تست می‌شوند و نتیجه همان‌جا ذخیره می‌شود.'),
              const SizedBox(height: 8),
              Text(status),
              const SizedBox(height: 8),
              Text('SNI: ${(_goldScan['sni'] ?? const []).length} • پورت: ${(_goldScan['port'] ?? const []).length} • TLS: ${(_goldScan['tls'] ?? const []).length}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _autoScanRunning ? null : () => autoScanRun(say),
            child: const Text('شروع'),
          ),
          TextButton(
            onPressed: () => _autoScanStop = true,
            child: const Text('توقف'),
          ),
          TextButton(
            onPressed: () => goldShowList(context),
            child: const Text('پوشه‌ی جهانی'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('بستن'),
          ),
        ],
      );
    }),
  );
  open = false;
}
