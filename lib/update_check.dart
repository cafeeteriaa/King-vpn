part of 'main.dart';

// UPDATE CHECK + Remote heal flags ==========================================
// The signed-release workflow injects its monotonically increasing build number.
const int appBuild = int.fromEnvironment('KING_APP_BUILD', defaultValue: 3);
const String updateConfigUrl =
    'https://api.github.com/repos/cafeeteriaa/King-vpn/releases/latest';

bool _updateChecked = false;
Map<String, dynamic> _remoteHeal = {};

extension UpdateCheck on _HomePageState {
  Future<void> checkForUpdate() async {
    if (_updateChecked) return;
    _updateChecked = true;
    try {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      final r = await http
          .get(Uri.parse(updateConfigUrl))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body);
      if (j is! Map) return;
      final map = Map<String, dynamic>.from(j);

      final heal = map['heal'];
      if (heal is Map) {
        _remoteHeal = Map<String, dynamic>.from(heal);
        _applyRemoteHeal();
      }

      if (map['draft'] == true || map['prerelease'] == true) return;
      final body = (map['body'] ?? '').toString();
      final latest = int.tryParse(
            RegExp(r'(?m)^KING_BUILD:\\s*(\\d+)\\s*
      if (!force && appBuild >= latest) return;
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: !force,
        builder: (ctx) => PopScope(
          canPop: !force,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('🚀 آپدیت King VPN'),
              content: Text(
                msg.isNotEmpty
                    ? msg
                    : 'نسخه‌ی جدید با موتور خودترمیمی قوی‌تر آماده است.\n'
                        'Build $appBuild → $latest\n'
                        'دانلود کن و نصب کن تا ترمیم‌های عمیق‌تر فعال شوند.',
              ),
              actions: [
                if (!force)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('بعداً'),
                  ),
                if (apk.isNotEmpty)
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _downloadAndInstallApk(apk, sha256Expected);
                    },
                    child: const Text('دانلود و نصب'),
                  ),
                FilledButton(
                  onPressed: () async {
                    final open = apk.isNotEmpty ? apk : url;
                    try {
                      await launchUrl(Uri.parse(open),
                          mode: LaunchMode.externalApplication);
                    } catch (e, stk) {
                      logError(e, stk);
                      await Clipboard.setData(ClipboardData(text: open));
                      _set('لینک آپدیت کپی شد');
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text(apk.isNotEmpty ? 'لینک APK' : 'دانلود'),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e, stk) {
      logError(e, stk);
    }
  }

  Future<void> _downloadAndInstallApk(String apkUrl, String sha256Expected) async {
    try {
      _set('⬇ در حال دانلود نسخه‌ی جدید...');
      kingHealText.value = 'دانلود آپدیت...';
      final r = await http
          .get(Uri.parse(apkUrl))
          .timeout(const Duration(minutes: 4));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
        _set('دانلود ناموفق — لینک را باز کن');
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
        return;
      }
      final dir = await Directory.systemTemp.createTemp('king_upd_');
      final file = File('${dir.path}/king-vpn-update.apk');
      await file.writeAsBytes(r.bodyBytes, flush: true);
      // Fail closed: missing, malformed, mismatched or unreadable digests
      // must never fall through to the Android package installer.
      try {
        final bytes = await file.readAsBytes();
        if (!verifySha256Bytes(bytes, sha256Expected)) {
          _set('❌ هش نامعتبر است یا با فایل تطابق ندارد؛ نصب لغو شد');
          kingHealText.value = '❌ اصالت APK تأیید نشد';
          try { await file.delete(); } catch (e, st) { logError(e, st); }
          return;
        }
      } catch (e, st) {
        logError(e, st);
        _set('❌ بررسی اصالت APK ناموفق بود؛ نصب متوقف شد');
        kingHealText.value = '❌ خطا در بررسی SHA-256؛ نصب لغو شد';
        try { await file.delete(); } catch (cleanup, cleanupSt) { logError(cleanup, cleanupSt); }
        return;
      }
      _set('✅ دانلود شد — نصب را تأیید کن');
      kingHealText.value = 'APK آماده — تأیید نصب اندروید';
      final ok = await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
        await Clipboard.setData(ClipboardData(text: apkUrl));
        _set('لینک APK کپی شد');
      }
    } catch (e, stk) {
      logError(e, stk);
      try {
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
      } catch (e, stk) { logError(e, stk); }
      _set('آپدیت: از مرورگر نصب کن');
    }
  }

  void _applyRemoteHeal() {
    try {
      if (_remoteHeal['turboForce'] == true) {
        turboSpeed = true;
        muxEnabled = true;
      }
      final mc = (_remoteHeal['muxConc'] as num?)?.toInt();
      // MUXCAP: سقف امن ۳۲ (بالاتر از این HOL blocking شدید می‌شود).
      if (mc != null && mc >= 8) muxConc = mc.clamp(8, 32);
      dbg('ترمیم از راه دور اعمال شد: $_remoteHeal');
    } catch (e, stk) { logError(e, stk); }
  }
}
)
                    .firstMatch(body)
                    ?.group(1) ??
                '',
          ) ??
          0;
      final minB = int.tryParse(
            RegExp(r'(?m)^KING_MIN_BUILD:\\s*(\\d+)\\s*
      if (!force && appBuild >= latest) return;
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: !force,
        builder: (ctx) => PopScope(
          canPop: !force,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('🚀 آپدیت King VPN'),
              content: Text(
                msg.isNotEmpty
                    ? msg
                    : 'نسخه‌ی جدید با موتور خودترمیمی قوی‌تر آماده است.\n'
                        'Build $appBuild → $latest\n'
                        'دانلود کن و نصب کن تا ترمیم‌های عمیق‌تر فعال شوند.',
              ),
              actions: [
                if (!force)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('بعداً'),
                  ),
                if (apk.isNotEmpty)
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _downloadAndInstallApk(apk, sha256Expected);
                    },
                    child: const Text('دانلود و نصب'),
                  ),
                FilledButton(
                  onPressed: () async {
                    final open = apk.isNotEmpty ? apk : url;
                    try {
                      await launchUrl(Uri.parse(open),
                          mode: LaunchMode.externalApplication);
                    } catch (e, stk) {
                      logError(e, stk);
                      await Clipboard.setData(ClipboardData(text: open));
                      _set('لینک آپدیت کپی شد');
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text(apk.isNotEmpty ? 'لینک APK' : 'دانلود'),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e, stk) {
      logError(e, stk);
    }
  }

  Future<void> _downloadAndInstallApk(String apkUrl, String sha256Expected) async {
    try {
      _set('⬇ در حال دانلود نسخه‌ی جدید...');
      kingHealText.value = 'دانلود آپدیت...';
      final r = await http
          .get(Uri.parse(apkUrl))
          .timeout(const Duration(minutes: 4));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
        _set('دانلود ناموفق — لینک را باز کن');
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
        return;
      }
      final dir = await Directory.systemTemp.createTemp('king_upd_');
      final file = File('${dir.path}/king-vpn-update.apk');
      await file.writeAsBytes(r.bodyBytes, flush: true);
      // Fail closed: missing, malformed, mismatched or unreadable digests
      // must never fall through to the Android package installer.
      try {
        final bytes = await file.readAsBytes();
        if (!verifySha256Bytes(bytes, sha256Expected)) {
          _set('❌ هش نامعتبر است یا با فایل تطابق ندارد؛ نصب لغو شد');
          kingHealText.value = '❌ اصالت APK تأیید نشد';
          try { await file.delete(); } catch (e, st) { logError(e, st); }
          return;
        }
      } catch (e, st) {
        logError(e, st);
        _set('❌ بررسی اصالت APK ناموفق بود؛ نصب متوقف شد');
        kingHealText.value = '❌ خطا در بررسی SHA-256؛ نصب لغو شد';
        try { await file.delete(); } catch (cleanup, cleanupSt) { logError(cleanup, cleanupSt); }
        return;
      }
      _set('✅ دانلود شد — نصب را تأیید کن');
      kingHealText.value = 'APK آماده — تأیید نصب اندروید';
      final ok = await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
        await Clipboard.setData(ClipboardData(text: apkUrl));
        _set('لینک APK کپی شد');
      }
    } catch (e, stk) {
      logError(e, stk);
      try {
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
      } catch (e, stk) { logError(e, stk); }
      _set('آپدیت: از مرورگر نصب کن');
    }
  }

  void _applyRemoteHeal() {
    try {
      if (_remoteHeal['turboForce'] == true) {
        turboSpeed = true;
        muxEnabled = true;
      }
      final mc = (_remoteHeal['muxConc'] as num?)?.toInt();
      // MUXCAP: سقف امن ۳۲ (بالاتر از این HOL blocking شدید می‌شود).
      if (mc != null && mc >= 8) muxConc = mc.clamp(8, 32);
      dbg('ترمیم از راه دور اعمال شد: $_remoteHeal');
    } catch (e, stk) { logError(e, stk); }
  }
}
)
                    .firstMatch(body)
                    ?.group(1) ??
                '',
          ) ??
          0;
      final sha256Expected = RegExp(r'(?i)^SHA256:\\s*([a-f0-9]{64})\\s*
      if (!force && appBuild >= latest) return;
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: !force,
        builder: (ctx) => PopScope(
          canPop: !force,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('🚀 آپدیت King VPN'),
              content: Text(
                msg.isNotEmpty
                    ? msg
                    : 'نسخه‌ی جدید با موتور خودترمیمی قوی‌تر آماده است.\n'
                        'Build $appBuild → $latest\n'
                        'دانلود کن و نصب کن تا ترمیم‌های عمیق‌تر فعال شوند.',
              ),
              actions: [
                if (!force)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('بعداً'),
                  ),
                if (apk.isNotEmpty)
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _downloadAndInstallApk(apk, sha256Expected);
                    },
                    child: const Text('دانلود و نصب'),
                  ),
                FilledButton(
                  onPressed: () async {
                    final open = apk.isNotEmpty ? apk : url;
                    try {
                      await launchUrl(Uri.parse(open),
                          mode: LaunchMode.externalApplication);
                    } catch (e, stk) {
                      logError(e, stk);
                      await Clipboard.setData(ClipboardData(text: open));
                      _set('لینک آپدیت کپی شد');
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text(apk.isNotEmpty ? 'لینک APK' : 'دانلود'),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e, stk) {
      logError(e, stk);
    }
  }

  Future<void> _downloadAndInstallApk(String apkUrl, String sha256Expected) async {
    try {
      _set('⬇ در حال دانلود نسخه‌ی جدید...');
      kingHealText.value = 'دانلود آپدیت...';
      final r = await http
          .get(Uri.parse(apkUrl))
          .timeout(const Duration(minutes: 4));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
        _set('دانلود ناموفق — لینک را باز کن');
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
        return;
      }
      final dir = await Directory.systemTemp.createTemp('king_upd_');
      final file = File('${dir.path}/king-vpn-update.apk');
      await file.writeAsBytes(r.bodyBytes, flush: true);
      // Fail closed: missing, malformed, mismatched or unreadable digests
      // must never fall through to the Android package installer.
      try {
        final bytes = await file.readAsBytes();
        if (!verifySha256Bytes(bytes, sha256Expected)) {
          _set('❌ هش نامعتبر است یا با فایل تطابق ندارد؛ نصب لغو شد');
          kingHealText.value = '❌ اصالت APK تأیید نشد';
          try { await file.delete(); } catch (e, st) { logError(e, st); }
          return;
        }
      } catch (e, st) {
        logError(e, st);
        _set('❌ بررسی اصالت APK ناموفق بود؛ نصب متوقف شد');
        kingHealText.value = '❌ خطا در بررسی SHA-256؛ نصب لغو شد';
        try { await file.delete(); } catch (cleanup, cleanupSt) { logError(cleanup, cleanupSt); }
        return;
      }
      _set('✅ دانلود شد — نصب را تأیید کن');
      kingHealText.value = 'APK آماده — تأیید نصب اندروید';
      final ok = await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
        await Clipboard.setData(ClipboardData(text: apkUrl));
        _set('لینک APK کپی شد');
      }
    } catch (e, stk) {
      logError(e, stk);
      try {
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
      } catch (e, stk) { logError(e, stk); }
      _set('آپدیت: از مرورگر نصب کن');
    }
  }

  void _applyRemoteHeal() {
    try {
      if (_remoteHeal['turboForce'] == true) {
        turboSpeed = true;
        muxEnabled = true;
      }
      final mc = (_remoteHeal['muxConc'] as num?)?.toInt();
      // MUXCAP: سقف امن ۳۲ (بالاتر از این HOL blocking شدید می‌شود).
      if (mc != null && mc >= 8) muxConc = mc.clamp(8, 32);
      dbg('ترمیم از راه دور اعمال شد: $_remoteHeal');
    } catch (e, stk) { logError(e, stk); }
  }
}
,
              multiLine: true)
          .firstMatch(body)
          ?.group(1)
          ?.toLowerCase() ??
          '';
      final assets = map['assets'] is List ? map['assets'] as List : const [];
      final apkAsset = assets.whereType<Map>().cast<Map>().where((asset) =>
          asset['name']?.toString() == 'king-vpn.apk').firstOrNull;
      final apk = apkAsset?['browser_download_url']?.toString() ?? '';
      final url = map['html_url']?.toString() ?? '';
      final parsedApk = Uri.tryParse(apk);
      if (latest <= 0 ||
          sha256Expected.length != 64 ||
          parsedApk == null ||
          parsedApk.scheme != 'https' ||
          parsedApk.host != 'github.com') {
        return;
      }
      final msg = body
          .replaceAll(RegExp(r'(?m)^KING_(?:BUILD|MIN_BUILD):.*
      if (!force && appBuild >= latest) return;
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: !force,
        builder: (ctx) => PopScope(
          canPop: !force,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('🚀 آپدیت King VPN'),
              content: Text(
                msg.isNotEmpty
                    ? msg
                    : 'نسخه‌ی جدید با موتور خودترمیمی قوی‌تر آماده است.\n'
                        'Build $appBuild → $latest\n'
                        'دانلود کن و نصب کن تا ترمیم‌های عمیق‌تر فعال شوند.',
              ),
              actions: [
                if (!force)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('بعداً'),
                  ),
                if (apk.isNotEmpty)
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _downloadAndInstallApk(apk, sha256Expected);
                    },
                    child: const Text('دانلود و نصب'),
                  ),
                FilledButton(
                  onPressed: () async {
                    final open = apk.isNotEmpty ? apk : url;
                    try {
                      await launchUrl(Uri.parse(open),
                          mode: LaunchMode.externalApplication);
                    } catch (e, stk) {
                      logError(e, stk);
                      await Clipboard.setData(ClipboardData(text: open));
                      _set('لینک آپدیت کپی شد');
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text(apk.isNotEmpty ? 'لینک APK' : 'دانلود'),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e, stk) {
      logError(e, stk);
    }
  }

  Future<void> _downloadAndInstallApk(String apkUrl, String sha256Expected) async {
    try {
      _set('⬇ در حال دانلود نسخه‌ی جدید...');
      kingHealText.value = 'دانلود آپدیت...';
      final r = await http
          .get(Uri.parse(apkUrl))
          .timeout(const Duration(minutes: 4));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
        _set('دانلود ناموفق — لینک را باز کن');
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
        return;
      }
      final dir = await Directory.systemTemp.createTemp('king_upd_');
      final file = File('${dir.path}/king-vpn-update.apk');
      await file.writeAsBytes(r.bodyBytes, flush: true);
      // Fail closed: missing, malformed, mismatched or unreadable digests
      // must never fall through to the Android package installer.
      try {
        final bytes = await file.readAsBytes();
        if (!verifySha256Bytes(bytes, sha256Expected)) {
          _set('❌ هش نامعتبر است یا با فایل تطابق ندارد؛ نصب لغو شد');
          kingHealText.value = '❌ اصالت APK تأیید نشد';
          try { await file.delete(); } catch (e, st) { logError(e, st); }
          return;
        }
      } catch (e, st) {
        logError(e, st);
        _set('❌ بررسی اصالت APK ناموفق بود؛ نصب متوقف شد');
        kingHealText.value = '❌ خطا در بررسی SHA-256؛ نصب لغو شد';
        try { await file.delete(); } catch (cleanup, cleanupSt) { logError(cleanup, cleanupSt); }
        return;
      }
      _set('✅ دانلود شد — نصب را تأیید کن');
      kingHealText.value = 'APK آماده — تأیید نصب اندروید';
      final ok = await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
        await Clipboard.setData(ClipboardData(text: apkUrl));
        _set('لینک APK کپی شد');
      }
    } catch (e, stk) {
      logError(e, stk);
      try {
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
      } catch (e, stk) { logError(e, stk); }
      _set('آپدیت: از مرورگر نصب کن');
    }
  }

  void _applyRemoteHeal() {
    try {
      if (_remoteHeal['turboForce'] == true) {
        turboSpeed = true;
        muxEnabled = true;
      }
      final mc = (_remoteHeal['muxConc'] as num?)?.toInt();
      // MUXCAP: سقف امن ۳۲ (بالاتر از این HOL blocking شدید می‌شود).
      if (mc != null && mc >= 8) muxConc = mc.clamp(8, 32);
      dbg('ترمیم از راه دور اعمال شد: $_remoteHeal');
    } catch (e, stk) { logError(e, stk); }
  }
}
), '')
          .replaceAll(RegExp(r'(?m)^SHA256:.*
      if (!force && appBuild >= latest) return;
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: !force,
        builder: (ctx) => PopScope(
          canPop: !force,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('🚀 آپدیت King VPN'),
              content: Text(
                msg.isNotEmpty
                    ? msg
                    : 'نسخه‌ی جدید با موتور خودترمیمی قوی‌تر آماده است.\n'
                        'Build $appBuild → $latest\n'
                        'دانلود کن و نصب کن تا ترمیم‌های عمیق‌تر فعال شوند.',
              ),
              actions: [
                if (!force)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('بعداً'),
                  ),
                if (apk.isNotEmpty)
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _downloadAndInstallApk(apk, sha256Expected);
                    },
                    child: const Text('دانلود و نصب'),
                  ),
                FilledButton(
                  onPressed: () async {
                    final open = apk.isNotEmpty ? apk : url;
                    try {
                      await launchUrl(Uri.parse(open),
                          mode: LaunchMode.externalApplication);
                    } catch (e, stk) {
                      logError(e, stk);
                      await Clipboard.setData(ClipboardData(text: open));
                      _set('لینک آپدیت کپی شد');
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text(apk.isNotEmpty ? 'لینک APK' : 'دانلود'),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e, stk) {
      logError(e, stk);
    }
  }

  Future<void> _downloadAndInstallApk(String apkUrl, String sha256Expected) async {
    try {
      _set('⬇ در حال دانلود نسخه‌ی جدید...');
      kingHealText.value = 'دانلود آپدیت...';
      final r = await http
          .get(Uri.parse(apkUrl))
          .timeout(const Duration(minutes: 4));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
        _set('دانلود ناموفق — لینک را باز کن');
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
        return;
      }
      final dir = await Directory.systemTemp.createTemp('king_upd_');
      final file = File('${dir.path}/king-vpn-update.apk');
      await file.writeAsBytes(r.bodyBytes, flush: true);
      // Fail closed: missing, malformed, mismatched or unreadable digests
      // must never fall through to the Android package installer.
      try {
        final bytes = await file.readAsBytes();
        if (!verifySha256Bytes(bytes, sha256Expected)) {
          _set('❌ هش نامعتبر است یا با فایل تطابق ندارد؛ نصب لغو شد');
          kingHealText.value = '❌ اصالت APK تأیید نشد';
          try { await file.delete(); } catch (e, st) { logError(e, st); }
          return;
        }
      } catch (e, st) {
        logError(e, st);
        _set('❌ بررسی اصالت APK ناموفق بود؛ نصب متوقف شد');
        kingHealText.value = '❌ خطا در بررسی SHA-256؛ نصب لغو شد';
        try { await file.delete(); } catch (cleanup, cleanupSt) { logError(cleanup, cleanupSt); }
        return;
      }
      _set('✅ دانلود شد — نصب را تأیید کن');
      kingHealText.value = 'APK آماده — تأیید نصب اندروید';
      final ok = await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
        await Clipboard.setData(ClipboardData(text: apkUrl));
        _set('لینک APK کپی شد');
      }
    } catch (e, stk) {
      logError(e, stk);
      try {
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
      } catch (e, stk) { logError(e, stk); }
      _set('آپدیت: از مرورگر نصب کن');
    }
  }

  void _applyRemoteHeal() {
    try {
      if (_remoteHeal['turboForce'] == true) {
        turboSpeed = true;
        muxEnabled = true;
      }
      final mc = (_remoteHeal['muxConc'] as num?)?.toInt();
      // MUXCAP: سقف امن ۳۲ (بالاتر از این HOL blocking شدید می‌شود).
      if (mc != null && mc >= 8) muxConc = mc.clamp(8, 32);
      dbg('ترمیم از راه دور اعمال شد: $_remoteHeal');
    } catch (e, stk) { logError(e, stk); }
  }
}
), '')
          .trim();
      final force = appBuild < minB;
      if (!force && appBuild >= latest) return;
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: !force,
        builder: (ctx) => PopScope(
          canPop: !force,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('🚀 آپدیت King VPN'),
              content: Text(
                msg.isNotEmpty
                    ? msg
                    : 'نسخه‌ی جدید با موتور خودترمیمی قوی‌تر آماده است.\n'
                        'Build $appBuild → $latest\n'
                        'دانلود کن و نصب کن تا ترمیم‌های عمیق‌تر فعال شوند.',
              ),
              actions: [
                if (!force)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('بعداً'),
                  ),
                if (apk.isNotEmpty)
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _downloadAndInstallApk(apk, sha256Expected);
                    },
                    child: const Text('دانلود و نصب'),
                  ),
                FilledButton(
                  onPressed: () async {
                    final open = apk.isNotEmpty ? apk : url;
                    try {
                      await launchUrl(Uri.parse(open),
                          mode: LaunchMode.externalApplication);
                    } catch (e, stk) {
                      logError(e, stk);
                      await Clipboard.setData(ClipboardData(text: open));
                      _set('لینک آپدیت کپی شد');
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text(apk.isNotEmpty ? 'لینک APK' : 'دانلود'),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e, stk) {
      logError(e, stk);
    }
  }

  Future<void> _downloadAndInstallApk(String apkUrl, String sha256Expected) async {
    try {
      _set('⬇ در حال دانلود نسخه‌ی جدید...');
      kingHealText.value = 'دانلود آپدیت...';
      final r = await http
          .get(Uri.parse(apkUrl))
          .timeout(const Duration(minutes: 4));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
        _set('دانلود ناموفق — لینک را باز کن');
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
        return;
      }
      final dir = await Directory.systemTemp.createTemp('king_upd_');
      final file = File('${dir.path}/king-vpn-update.apk');
      await file.writeAsBytes(r.bodyBytes, flush: true);
      // Fail closed: missing, malformed, mismatched or unreadable digests
      // must never fall through to the Android package installer.
      try {
        final bytes = await file.readAsBytes();
        if (!verifySha256Bytes(bytes, sha256Expected)) {
          _set('❌ هش نامعتبر است یا با فایل تطابق ندارد؛ نصب لغو شد');
          kingHealText.value = '❌ اصالت APK تأیید نشد';
          try { await file.delete(); } catch (e, st) { logError(e, st); }
          return;
        }
      } catch (e, st) {
        logError(e, st);
        _set('❌ بررسی اصالت APK ناموفق بود؛ نصب متوقف شد');
        kingHealText.value = '❌ خطا در بررسی SHA-256؛ نصب لغو شد';
        try { await file.delete(); } catch (cleanup, cleanupSt) { logError(cleanup, cleanupSt); }
        return;
      }
      _set('✅ دانلود شد — نصب را تأیید کن');
      kingHealText.value = 'APK آماده — تأیید نصب اندروید';
      final ok = await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
        await Clipboard.setData(ClipboardData(text: apkUrl));
        _set('لینک APK کپی شد');
      }
    } catch (e, stk) {
      logError(e, stk);
      try {
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
      } catch (e, stk) { logError(e, stk); }
      _set('آپدیت: از مرورگر نصب کن');
    }
  }

  void _applyRemoteHeal() {
    try {
      if (_remoteHeal['turboForce'] == true) {
        turboSpeed = true;
        muxEnabled = true;
      }
      final mc = (_remoteHeal['muxConc'] as num?)?.toInt();
      // MUXCAP: سقف امن ۳۲ (بالاتر از این HOL blocking شدید می‌شود).
      if (mc != null && mc >= 8) muxConc = mc.clamp(8, 32);
      dbg('ترمیم از راه دور اعمال شد: $_remoteHeal');
    } catch (e, stk) { logError(e, stk); }
  }
}
