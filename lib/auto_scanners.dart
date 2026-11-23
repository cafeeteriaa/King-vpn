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
// AUTOFALLBACK: IPهای داخلی برای وقتی پوشه‌ی جهانی هنوز IP تمیز ندارد
const List<String> kAutoFallbackIps = [
  '104.16.0.1', '104.17.0.1', '104.18.0.1', '104.19.0.1', '104.20.0.1',
  '172.67.0.1', '162.159.0.1', '188.114.96.1', '188.114.97.1', '141.101.113.1',
];

bool _autoScanRunning = false;
bool _autoScanStop = false;
const String _autoScanCdnCursorKey = 'auto_scan_cdn_cursors_v1';
const String _autoScanDomainCursorKey = 'auto_scan_domain_cursor_v1';
const int _autoScanCdnBatchSize = 8;
const int _autoScanDomainBatchSize = 18; // full SNI/port/TLS pass fits the shared four-minute budget

// TLS با SNI مشخص: اگر هندشیک کامل شود، SNI برای آن IP قابل استفاده است
Future<int?> _autoSniOk(String ip, int port, String sni) async {
  final sw = Stopwatch()..start();
  Socket? raw;
  SecureSocket? secure;
  try {
    raw = await Socket.connect(ip, port, timeout: const Duration(seconds: 4));
    secure = await SecureSocket.secure(raw,
        host: sni, onBadCertificate: (_) => true)
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
        supportedProtocols: [alpn],
        onBadCertificate: (_) => true)
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

/// Resolve the project's SNI names to IPv6 endpoints in small cancellable batches.
/// The hostname remains the TLS SNI; only the TCP destination is the AAAA address.
Future<List<String>> _autoResolveIpv6Targets({required List<String> domains, bool Function()? cancelled}) async {
  final out = <String>{};
  const batchSize = 4;
  for (var offset = 0; offset < domains.length; offset += batchSize) {
    if (cancelled?.call() ?? false) break;
    final batch = domains.skip(offset).take(batchSize);
    final resolved = await Future.wait(batch.map((domain) async {
      try {
        return await InternetAddress.lookup(
          domain,
          type: InternetAddressType.IPv6,
        ).timeout(const Duration(seconds: 2));
      } catch (_) {
        return const <InternetAddress>[];
      }
    }));
    if (cancelled?.call() ?? false) break;
    for (final addresses in resolved) {
      for (final address in addresses) {
        if (address.type == InternetAddressType.IPv6 &&
            !_privateIp(address)) {
          out.add(address.address);
        }
      }
    }
  }
  return out.toList(growable: false);
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
  const scanBudget = Duration(minutes: 4);
  final scanClock = Stopwatch()..start();
  bool timedOut() => scanClock.elapsed >= scanBudget;
  bool cancelled() =>
      _autoScanStop || vpnActive() || vpnWanted() || nationalMode != scanNationalMode || timedOut();
  String cancellationMessage() => timedOut()
      ? 'مهلت چهار‌دقیقه‌ای اسکن تمام شد؛ نتایج ناقص ذخیره نشد'
      : ((vpnActive() || vpnWanted())
          ? 'با شروع اتصال VPN، اسکن برای جلوگیری از تداخل متوقف شد؛ نتایج ناقص ذخیره نشد'
          : 'اسکن متوقف شد؛ نتایج ناقص ذخیره نشد');
  try {
    await goldLoad();
    if (cancelled()) {
      say(cancellationMessage());
      return;
    }
    // Keep the discovered pool and CDN inventory independent, then rotate
    // through every configured CDN range with persisted per-range cursors.
    // Each run handles a memory-safe slice; later runs resume at the next IP.
    final base = [for (final entry in _goldIps.values) entry.ip];
    final prefs = await SharedPreferences.getInstance();
    final savedCursorJson = prefs.getString(_autoScanCdnCursorKey);
    final cdnCursors = <String, dynamic>{};
    if (savedCursorJson != null && savedCursorJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(savedCursorJson);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.value is num || entry.value is String) {
              cdnCursors['${entry.key}'] = entry.value;
            }
          }
        }
      } catch (e, stk) {
        logError(e, stk);
      }
    }
    final stagedCdnCursors = Map<String, dynamic>.of(cdnCursors);
    // Use the entire project domain inventory, not only the small seed list.
    // A persisted last-domain cursor rotates through it across completed runs.
    final domainInventory = <String>{
      ...kAutoSniDomains,
      ...dnsxFullDomains(),
      ...good.where((server) => !server.isIp).map((server) => server.host),
      ...pending.where((server) => !server.isIp).map((server) => server.host),
      ...fetchedAll.where((server) => !server.isIp).map((server) => server.host),
    }.where((domain) => domain.trim().isNotEmpty).toList()..sort();
    final savedDomainCursor = prefs.getString(_autoScanDomainCursorKey);
    final previousDomainIndex = savedDomainCursor == null
        ? -1
        : domainInventory.indexOf(savedDomainCursor);
    final domainStart = previousDomainIndex < 0
        ? 0
        : (previousDomainIndex + 1) % domainInventory.length;
    final domainBatch = <String>[
      for (var i = 0; i < min(_autoScanDomainBatchSize, domainInventory.length); i++)
        domainInventory[(domainStart + i) % domainInventory.length],
    ];
    final stagedDomainCursor = domainBatch.isEmpty ? savedDomainCursor : domainBatch.last;
    final cdnRanges = _liveCdnRanges.isNotEmpty ? _liveCdnRanges : [..._cfRanges, ..._cfRangesV6];
    unawaited(refreshCdnRanges());
    // Add AAAA answers from the same project SNI inventory. Combine exact
    // A/AAAA endpoints and CDN CIDRs in one fair cursor iterator so no source
    // is permanently starved by the order of a concatenated list.
    final ipv6DnsIps = await _autoResolveIpv6Targets(
      domains: domainBatch,
      cancelled: cancelled,
    );
    if (cancelled()) {
      say(cancellationMessage());
      return;
    }
    final targetRanges = <String>{
      ...base,
      ...ipv6DnsIps,
      ...cdnRanges,
      if (base.isEmpty && ipv6DnsIps.isEmpty && cdnRanges.isEmpty)
        ...kAutoFallbackIps,
    }.toList(growable: false);
    final ips = _getCfIps(
      batchSize: _autoScanCdnBatchSize,
      liveRanges: targetRanges,
      cursors: stagedCdnCursors,
    );
    say('تست با ${ips.length} IP از IPv4 و IPv6 (پوشه جهانی / CDN مستقل از نت ملی)');

    // SNI: خروجی خود دامنه‌هاست. هر دامنه یک بار؛ به محض یک IP سالم، همان دامنه ثبت می‌شود
    final sniHits = <String>[];
    var n = 0;
    sniLoop:
    for (final d in domainBatch) {
      n++;
      if (scanNationalMode) {
        await natManualYield(shouldAbort: () => cancelled());
        if (cancelled()) break sniLoop;
      }
      var ok = false;
      // Bounded parallel probes reduce worst-case scan time without creating
      // an unbounded socket burst on low-memory/mobile networks.
      for (var offset = 0; offset < ips.length; offset += 8) {
        if (cancelled()) break sniLoop;
        final batch = ips.skip(offset).take(8);
        final checks = await Future.wait(
          batch.map((ip) => _autoSniOk(ip, 443, d)),
        );
        if (checks.any((latency) => latency != null)) {
          ok = true;
          break;
        }
      }
      if (ok) sniHits.add(d);
      say('SNI $n/${domainBatch.length} • سالم: ${sniHits.length}');
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
      // Keep concurrency bounded; stop scheduling new batches after a hit.
      for (var offset = 0; offset < ips.length; offset += 8) {
        if (cancelled()) break portLoop;
        final batch = ips.skip(offset).take(8);
        final checks = await Future.wait(
          batch.map((ip) => _autoPortOk(ip, p)),
        );
        if (checks.any((reachable) => reachable)) {
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
    final tlsSni = sniHits.isNotEmpty
        ? sniHits.first
        : (domainBatch.isNotEmpty ? domainBatch.first : 'www.google.com');
    for (final alpn in const ['h2', 'http/1.1']) {
      if (cancelled()) break;
      var ok = false;
      for (var offset = 0; offset < ips.length; offset += 8) {
        if (cancelled()) break;
        final batch = ips.skip(offset).take(8);
        final selected = await Future.wait(
          batch.map((ip) => _autoAlpnOk(ip, tlsSni, alpn)),
        );
        for (final protocol in selected.whereType<String>()) {
          if (protocol.isNotEmpty && !tlsHits.contains(protocol)) {
            tlsHits.add(protocol);
            ok = true;
          }
        }
        if (ok) break;
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
    // Advance the CDN inventory only after the scan results have been committed.
    await prefs.setString(_autoScanCdnCursorKey, jsonEncode(stagedCdnCursors));
    if (stagedDomainCursor != null) {
      await prefs.setString(_autoScanDomainCursorKey, stagedDomainCursor);
    }
    say('تمام شد: ${sniHits.length} SNI و ${portHits.length} پورت در پوشه‌ی جهانی ذخیره شد؛ دامنه‌ها در نوبت‌های بعدی ادامه می‌یابند');
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
