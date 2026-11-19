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
// AUTOFALLBACK: IPهای داخلی برای وقتی پوشه‌ی جهانی هنوز IP تمیز ندارد
const List<String> kAutoFallbackIps = [
  '104.16.0.1', '104.17.0.1', '104.18.0.1', '104.19.0.1', '104.20.0.1',
  '172.67.0.1', '162.159.0.1', '188.114.96.1', '188.114.97.1', '141.101.113.1',
];

bool _autoScanRunning = false;
bool _autoScanStop = false;

// TLS با SNI مشخص: اگر هندشیک کامل شود، SNI برای آن IP قابل استفاده است
Future<int?> _autoSniOk(String ip, int port, String sni) async {
  final sw = Stopwatch()..start();
  try {
    final raw = await Socket.connect(ip, port, timeout: const Duration(seconds: 4));
    final s = await SecureSocket.secure(raw,
        host: sni, onBadCertificate: (_) => true);
    s.destroy();
    return sw.elapsedMilliseconds;
  } catch (_) {
    return null;
  }
}

// ALPN (پروتکل لایه‌ی TLS): خروجی خود نام پروتکل است، مثل h2 یا http/1.1
Future<String?> _autoAlpnOk(String ip, String sni, String alpn) async {
  try {
    final raw = await Socket.connect(ip, 443, timeout: const Duration(seconds: 4));
    final s = await SecureSocket.secure(raw,
        host: sni,
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
  if (nationalMode) {
    say('این اسکنر فقط برای مسیر جهانی است؛ اسکن IP نت ملی از موتور و مخزن مستقل خودش استفاده می‌کند.');
    return;
  }
  _autoScanRunning = true;
  _autoScanStop = false;
  try {
    await goldLoad();
    // GLOBAL-ONLY: این اسکنر هرگز بازه‌ها، IPها یا سهمیه‌ی نت ملی را نمی‌خواند.
    final global = [for (final c in _goldIps.values.take(kAutoIpLimit)) c.ip];
    final cdnSample = <String>[];
    if (global.isEmpty) {
      for (final r in _cfRanges.take(8)) {
        cdnSample.addAll(natExpandCidr(r, maxPerBlock: 3));
        if (cdnSample.length >= 20) break;
      }
    }
    final ips = global.isNotEmpty
        ? global
        : (cdnSample.isNotEmpty ? cdnSample : kAutoFallbackIps);
    say('تست جهانی با ${ips.length} IP از مخزن جهانی');

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
    say('تمام شد: ${sniHits.length} SNI و ${portHits.length} پورت در مخزن جهانی ذخیره شد');
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
              // SCANSHOW: نتایج همین‌جا روی صفحه با دکمه‌ی کپی
              for (final k in const ['sni', 'port', 'tls'])
                if ((_goldScan[k] ?? const <String>[]).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(k == 'sni' ? 'SNIهای سالم:' : (k == 'port' ? 'پورت‌های سالم:' : 'TLSهای سالم:')),
                  SelectableText((_goldScan[k] ?? const <String>[]).join('\n')),
                  TextButton.icon(
                    onPressed: () => Clipboard.setData(ClipboardData(
                        text: (_goldScan[k] ?? const <String>[]).join('\n'))),
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text('کپی ${k == 'sni' ? 'SNIها' : (k == 'port' ? 'پورت‌ها' : 'TLSها')}'),
                  ),
                ],
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
