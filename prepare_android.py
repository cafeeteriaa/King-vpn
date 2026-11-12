# =====================================================================
# ---- 31) V9-FIX: _hotPath — always app-private (kills PathAccessException) ----
# =====================================================================
print('\n[31] V9: hotPath app-private')
patch_hard('nat_ultra',
"""const String hotVisibleDir = '/storage/emulated/0/Download/King-VPN';
String _hotPath() {
  try {
    final v = Directory(hotVisibleDir);
    if (!v.existsSync()) v.createSync(recursive: true);
    final probe = File('$hotVisibleDir/.kv_probe');
    probe.writeAsStringSync('ok', flush: true);
    probe.deleteSync();
    return '$hotVisibleDir/hot_configs.txt';
  } catch (_) {}
  const dir = '/data/data/com.kingvpn.king_vpn/files';
  try {
    final d = Directory(dir);
    if (!d.existsSync()) d.createSync(recursive: true);
    return '$dir/hot_cache.txt';
  } catch (_) {
    return '${Directory.systemTemp.path}/hot_cache.txt';
  }
}
""",
"""const String hotVisibleDir = '/storage/emulated/0/Download/King-VPN';
// V9-FIX: cache ALWAYS lives in app-private dir (writable on Android 11+).
// The old code tried Download first and failed with errno=13/1 when a stale
// file with different ownership existed there. Now we write to app-private
// and export a timestamped copy to Download for user visibility (best-effort).
String _hotPath() {
  const dir = '/data/data/com.kingvpn.king_vpn/files';
  try {
    final d = Directory(dir);
    if (!d.existsSync()) d.createSync(recursive: true);
    return '$dir/hot_cache.txt';
  } catch (_) {
    return '${Directory.systemTemp.path}/hot_cache.txt';
  }
}
Future<void> hotExportToDownload() async {
  try {
    final src = File(_hotPath());
    if (!src.existsSync()) return;
    final v = Directory(hotVisibleDir);
    if (!v.existsSync()) v.createSync(recursive: true);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final dst = File('$hotVisibleDir/hot_configs_$ts.txt');
    await src.copy(dst.path);
    try {
      final all = v.listSync()
          .whereType<File>()
          .where((f) => f.path.contains('hot_configs_'))
          .toList()
        ..sort((a, b) {
          try { return b.statSync().modified.compareTo(a.statSync().modified); }
          catch (_) { return 0; }
        });
      for (var i = 3; i < all.length; i++) {
        try { all[i].deleteSync(); } catch (_) {}
      }
    } catch (_) {}
  } catch (e) {
    dbg('hotExport (best-effort, ignored): $e');
  }
}
""",
'V9: hotPath app-private')

# =====================================================================
# ---- 32) V9-FIX: tunUp — trust core CONNECTED, drop cellular names ----
# =====================================================================
print('\n[32] V9: tunUp fix')
patch_hard('main',
"""Future<bool?> tunUp() async {
  try {
    final l = await NetworkInterface.list();
    tunNames = l.map((i) => i.name).join(',');
    if (l.isEmpty) return null;
    return l.any((i) {
      final n = i.name.toLowerCase();
      // Broad OEM coverage: tun/ppp/vpn + Xiaomi/Huawei/Samsung/OPPO/Vivo quirks
      return n.startsWith('tun') ||
          n.startsWith('ppp') ||
          n.startsWith('vpn') ||
          n.startsWith('ipsec') ||
          n.startsWith('tap') ||
          n.startsWith('utun') ||
          n.startsWith('ccmni') ||
          n.startsWith('rmnet') ||
          n.startsWith('seth') ||
          n.startsWith('v4-rmnet') ||
          n.contains('tun') ||
          n.contains('ppp') ||
          n.contains('vpn') ||
          n.contains('ipsec') ||
          n.contains('xray') ||
          n.contains('v2ray');
    });
  } catch (_swE) {
    _swl('tunUp#1', _swE);
    return null;
  }
}""",
"""Future<bool?> tunUp() async {
  try {
    final l = await NetworkInterface.list(includeLoopback: false);
    tunNames = l.map((i) => i.name).join(',');
    if (l.isEmpty) return null;
    // V9-FIX: only real tunnel-like names count. Previously ccmni/rmnet/seth
    // (cellular interfaces) were treated as tunnel → false POSITIVE on mobile
    // data with no VPN, and later false NEGATIVE when they changed names.
    final hasTunnel = l.any((i) {
      final n = i.name.toLowerCase();
      return n.startsWith('tun') ||
          n.startsWith('ppp') ||
          n.startsWith('vpn') ||
          n.startsWith('ipsec') ||
          n.startsWith('tap') ||
          n.startsWith('utun') ||
          n.contains('xray') ||
          n.contains('v2ray');
    });
    if (hasTunnel) return true;
    // V9: if the core already reported CONNECTED, retry once (list() can be
    // flaky during transient states) and if still missing, trust the core.
    // This kills the unnecessary _restartTunnel loop when tun is briefly gone.
    if (lastState == 'CONNECTED') {
      await Future.delayed(const Duration(milliseconds: 400));
      try {
        final l2 = await NetworkInterface.list(includeLoopback: false);
        final ok2 = l2.any((i) {
          final n = i.name.toLowerCase();
          return n.startsWith('tun') ||
              n.startsWith('ppp') ||
              n.startsWith('vpn') ||
              n.startsWith('utun');
        });
        if (ok2) return true;
      } catch (_) {}
      // Core says CONNECTED and interface list is unreliable → trust core
      return true;
    }
    return false;
  } catch (_swE) {
    _swl('tunUp#1', _swE);
    return null;
  }
}""",
'V9: tunUp trust core CONNECTED')

# =====================================================================
# ---- 33) V9-FIX: E-NO-TUN false positive (split "تونل VPN" match) ----
# =====================================================================
print('\n[33] V9: E-NO-TUN split')
patch_hard('main',
"""  if (has('تونل VPN')) {
    return h('E-NO-TUN',
        'lib/main.dart → tunUp() و شاخه‌ی Tunnel guard در _startWatch؛ شکست شروع در _start (lastFail)',
        'NetworkInterface.list() اینترفیسی با نام tun/ppp ندید (نام‌های دیده‌شده در خط «tun:» بالا آمده). یعنی اندروید تونل نساخت یا با نام دیگری ساخته، یا مجوز VPN دست اپ دیگری است. آیکن کلید نمی‌آید.',
        'نام اینترفیس‌های خط «tun:» را ببین؛ اگر نام دیگری دارد شرط startsWith در tunUp() را گسترش بده. اگر هیچ نیست: _restartTunnel (خودکار تا ۲ بار) و بعد درخواست مجوز VPN.');
  }""",
"""  // V9-FIX: "ساخت دوباره تونل VPN..." is an AUTO-HEAL message, NOT an error.
  // The old broad 'تونل VPN' match tagged it as E-NO-TUN (false positive).
  if (has('ساخت دوباره تونل VPN')) {
    return h('E-TUN-RESTART',
        'lib/main.dart → _restartTunnel() از _startWatch',
        'ترمیم خودکار: ۲ بار tun دیده نشد → تونل دوباره ساخته شد. این یک عمل عادی است، نه خطا. بعد از این پیام معمولاً اتصال دوباره برقرار می‌شود.',
        'نیازی به اقدام نیست. اگر پشت سر هم تکرار شد، خط «tun:» و E-NO-TUN واقعی را ببین.');
  }
  if (has('تونل VPN نساخته') ||
      has('tun پیدا نشد') ||
      has('اندروید تونل VPN') ||
      has('وضعیت تونل اندروید')) {
    return h('E-NO-TUN',
        'lib/main.dart → tunUp() و شاخه‌ی Tunnel guard در _startWatch؛ شکست شروع در _start (lastFail)',
        'NetworkInterface.list() اینترفیسی با نام tun/ppp ندید. یعنی اندروید تونل نساخت یا مجوز VPN دست اپ دیگری است. آیکن کلید نمی‌آید.',
        'خط «tun:» را ببین؛ اگر نام دیگری دارد شرط startsWith در tunUp() را گسترش بده. اگر لیست خالی است: _restartTunnel (خودکار تا ۲ بار) و بعد درخواست مجوز VPN.');
  }""",
'E-NO-TUN split from restart')

# =====================================================================
# ---- 34) V9-NATGOLD: inject cached gold IPs directly in national round 0 ----
# =====================================================================
print('\n[34] V9: national round 0 gold inject')
patch_hard('main',
"""      if (round == 0 && nationalMode) {
        // NATFIRSTFAST: دور اول فقط جستجوی سریع است؛ اولین سرور سالمی که پیدا شد وصل می‌شود.
        // اسکن‌های سنگین IP/دامنه (چند دقیقه) در دورهای بعد و در پس‌زمینه‌ی اتصال اجرا می‌شوند.
        if (_pickList().isEmpty) await _natQuickStart();
      }""",
"""      if (round == 0 && nationalMode) {
        // NATFIRSTFAST: round 0 is a quick search; the first healthy server
        // connects. V9-NATGOLD: inject cached gold IPs BEFORE any scan.
        if (_pickList().isEmpty) {
          await _natQuickStart();
          if (pending.isEmpty) {
            try {
              final goldIps = goldIpList();
              final tpl = [...good, ...natTemplateSeeds].take(2).toList();
              if (goldIps.isNotEmpty && tpl.isNotEmpty) {
                final made = <Server>[];
                for (final gip in goldIps.take(20)) {
                  for (final t in tpl) {
                    try {
                      made.add(Server(
                        _natSetHost(t.link, gip.ip, t.host),
                        '${t.name} (gold)',
                        gip.ip,
                        gip.port,
                      ));
                    } catch (e, stk) { logError(e, stk); }
                  }
                }
                if (made.isNotEmpty) {
                  pending.insertAll(0, made);
                  dbg('V9-NATGOLD: ${made.length} gold configs injected '
                      '(from ${goldIps.length} gold IPs × ${tpl.length} templates)');
                }
              }
            } catch (e, stk) { logError(e, stk); }
          }
        }
      }""",
'V9-NATGOLD inject gold IPs')

# =====================================================================
# ---- 35) V9-SNI: expand natFrontSnis (better SNI rotation) ----
# =====================================================================
print('\n[35] V9: expand natFrontSnis')
patch_hard('nip_scan',
"""const natFrontSnis = <String>[
  'cdnjs.cloudflare.com',
  'www.cloudflare.com',
  'cloudflare.com',
  'speed.cloudflare.com',
];""",
"""const natFrontSnis = <String>[
  // V9: expanded SNI rotation set. All are CF-hosted, so handshaking with
  // any of them against a CF edge IP succeeds. Rotating through different
  // SNIs on each connection defeats a DPI that blocks specific SNIs.
  'cdnjs.cloudflare.com',
  'www.cloudflare.com',
  'cloudflare.com',
  'speed.cloudflare.com',
  'workers.dev',
  'dash.cloudflare.com',
  'developers.cloudflare.com',
  'community.cloudflare.com',
  'support.cloudflare.com',
  'blog.cloudflare.com',
  'one.one.one.one',
  '1.1.1.1',
  'cloudflare-dns.com',
  'cloudflareaccess.com',
  'static.cloudflareinsights.com',
  'challenge-platform.cloudflare.com',
];""",
'V9: expanded natFrontSnis')
