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
  Socket? raw;
  SecureSocket? secure;
  try {
    raw = await Socket.connect(ip, port, timeout: const Duration(seconds: 4));
    secure = await SecureSocket.secure(raw,
        host: sni)
        .timeout(const Duration(seconds: 4));
    return sw.elapsedMilliseconds;
  } catch (_) {
    return null;
  } finally {
    try { secure?.destroy(); } catch (e, st) { logError(e, st); }
    try { raw?.destroy(); } catch (e, st) { logError(e, st); }
  }
}

// ALPN (پروتکل لایه‌ی TLS): خروجی خود نام پروتکل است، مثل h2 یا http/1.1
Future<String?> _autoAlpnOk(String ip, String sni, String alpn) async {
  Socket? raw;
  SecureSocket? secure;
  try {
    raw = await Socket.connect(ip, 443, timeout: const Duration(seconds: 4));
    secure = await SecureSocket.secure(raw,
        host: sni,
        supportedProtocols: [alpn])
        .timeout(const Duration(seconds: 4));
    return secure.selectedProtocol;
  } catch (_) {
    return null;
  } finally {
    try { secure?.destroy(); } catch (e, st) { logError(e, st); }
    try { raw?.destroy(); } catch (e, st) { logError(e, st); }
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

Future<void> autoScanRun(void Function(String) say,
    {bool Function()? isVpnActive, bool Function()? isVpnWanted}) async {
  bool vpnActive() => isVpnActive?.call() ?? false;
  bool vpnWanted() => isVpnWanted?.call() ?? false;
  // Scanning through an active VPN tunnel can produce misleading direct-IP results
  // and compete with the live tunnel; keep diagnostics idle until it is disconnected.
  if (vpnActive() || vpnWanted()) {
    say('برای جلوگیری از اختلال، ابتدا VPN را قطع کنید');
    return;
  }
  if (_autoScanRunning || dnsxManualBusy || _dnsxAutoBusy || ipAutoBusy || _natRangeScanBusy) {
    say('اسکن دیگری در حال اجراست');
    return;
  }
  _autoScanRunning = true;
  dnsxManualBusy = true;
  _autoScanStop = false;
  final scanNationalMode = nationalMode;
  // No fixed elapsed-time cutoff: the user, VPN lifecycle, or network-mode
  // transition can cancel the scan; completed inventory is committed together.
  bool cancelled() =>
      _autoScanStop || vpnActive() || vpnWanted() || nationalMode != scanNationalMode;
  String cancellationMessage() => (vpnActive() || vpnWanted())
      ? 'با شروع اتصال VPN، اسکن برای جلوگیری از تداخل متوقف شد؛ نتایج ناقص ذخیره نشد'
      : 'اسکن متوقف شد؛ نتایج ناقص ذخیره نشد';
  try {
    await goldLoad();
    if (cancelled()) {
      say(cancellationMessage());
      return;
    }
    // GLOBALONLY: فقط IPهای تمیز پوشه‌ی جهانی. بازه‌های ISP نت ملی حذف شدند (جدایی از نت ملی).
    // اگر پوشه‌ی جهانی هنوز خالی است، از بازه‌های CDN (Cloudflare) نمونه‌برداری می‌شود، نه ISP داخلی.
    // FOLDERALL: IPهای پوشه اول؛ در نت ملی IPهای ISP داخلی هم اضافه می‌شود (بهینه برای نت ملی)
    // This is the generic/global SNI and port scanner. National ISP ranges
    // belong exclusively to the National Net engine and are never borrowed here.
    final base = [for (final entry in _goldIps.values) entry.ip];
    final cdnSample = <String>[];
    if (base.isEmpty) {
      for (final r in _cfRanges) {
        cdnSample.addAll(natExpandCidr(r, maxPerBlock: 3));
      }
    }
    final ips = base.isNotEmpty
        ? base
        : (cdnSample.isNotEmpty ? cdnSample : kAutoFallbackIps);
    say('تست با ${ips.length} IP (پوشه جهانی / CDN مستقل از نت ملی)');

    // SNI: خروجی خود دامنه‌هاست. هر دامنه یک بار؛ به محض یک IP سالم، همان دامنه ثبت می‌شود
    final sniHits = <String>[];
    var n = 0;
    sniLoop:
    for (final d in kAutoSniDomains) {
      n++;
      if (scanNationalMode) {
        await natManualYield(shouldAbort: () => cancelled());
        if (cancelled()) break sniLoop;
      }
      var ok = false;
      for (final ip in ips) {
        if (cancelled()) break sniLoop;
        if (await _autoSniOk(ip, 443, d) != null) {
          ok = true;
          break;
        }
      }
      if (ok) sniHits.add(d);
      say('SNI $n/${kAutoSniDomains.length} • سالم: ${sniHits.length}');
    }

    if (cancelled()) {
      say(cancellationMessage());
      return;
    }

    // پورت: خروجی خود شماره‌ی پورت است. هر پورت یک بار؛ به محض یک IP سالم، همان پورت ثبت می‌شود
    final portHits = <String>[];
    var m = 0;
    portLoop:
    for (final p in kAutoPorts) {
      m++;
      if (scanNationalMode) {
        await natManualYield(shouldAbort: () => cancelled());
        if (cancelled()) break portLoop;
      }
      var ok = false;
      for (final ip in ips) {
        if (cancelled()) break portLoop;
        if (await _autoPortOk(ip, p)) {
          ok = true;
          break;
        }
      }
      if (ok) portHits.add('$p');
      say('پورت $m/${kAutoPorts.length} • سالم: ${portHits.length}');
    }

    if (cancelled()) {
      say(cancellationMessage());
      return;
    }

    // TLS/ALPN: خروجی نام پروتکل‌های TLS است؛ روی اولین دامنه‌ی سالم (یا پیش‌فرض) تست می‌شود
    final tlsHits = <String>[];
    final tlsSni = sniHits.isNotEmpty ? sniHits.first : 'www.google.com';
    for (final alpn in const ['h2', 'http/1.1']) {
      if (cancelled()) break;
      var ok = false;
      for (final ip in ips) {
        if (cancelled()) break;
        final sel = await _autoAlpnOk(ip, tlsSni, alpn);
        if (sel != null && sel.isNotEmpty) {
          if (!tlsHits.contains(sel)) tlsHits.add(sel);
          ok = true;
          break;
        }
      }
      if (ok) say('TLS: $alpn ✓');
    }

    if (cancelled()) {
      say(cancellationMessage());
      return;
    }
    // Commit the three result groups together only after every scan phase completes.
    final saved = await goldAddScans(
      {'tls': tlsHits, 'sni': sniHits, 'port': portHits},
      shouldAbort: () => cancelled(),
    );
    if (!saved) {
      say(cancellationMessage());
      return;
    }
    say('تمام شد: ${sniHits.length} SNI و ${portHits.length} پورت در پوشه‌ی جهانی ذخیره شد');
  } catch (e, stk) {
    logError(e, stk);
    say('خطا در اسکن خودکار');
  } finally {
    _autoScanRunning = false;
    dnsxManualBusy = false;
  }
}

Future<void> autoScanSheet(BuildContext context,
    {bool Function()? isVpnActive, bool Function()? isVpnWanted}) async {
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
            onPressed: _autoScanRunning
                ? null
                : () => autoScanRun(say,
                    isVpnActive: isVpnActive, isVpnWanted: isVpnWanted),
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
  // Closing the dialog is also a cancellation request; do not leave background
  // socket probes running after the user has dismissed the scanner.
  _autoScanStop = true;
  open = false;
}
