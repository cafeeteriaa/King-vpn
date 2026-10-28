part of 'main.dart';

// UPDATE CHECK + Remote heal flags ==========================================
// appBuild را با هر Release یکی بالا ببر و update.json را آپدیت کن.
const int appBuild = 3;
const String updateConfigUrl =
    'https://gist.githubusercontent.com/cafeeteriaa/0e04f5efe29b8101eb554c6e9a41d969/raw';

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

      final latest = (map['latest'] as num?)?.toInt() ?? 0;
      final minB = (map['min'] as num?)?.toInt() ?? 0;
      var url = (map['url'] as String?)?.trim() ?? '';
      final apk = (map['apk'] as String?)?.trim() ?? '';
      if (url.isEmpty) url = 'https://t.me/kingvpnn57';
      final msg = (map['message'] as String?)?.trim() ?? '';
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
                      await _downloadAndInstallApk(apk);
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

  Future<void> _downloadAndInstallApk(String apkUrl) async {
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
      // MUXCAP: 32 streams per core made most servers fail in the tests
      if (mc != null && mc >= 8) muxConc = mc.clamp(8, 16);
      dbg('ترمیم از راه دور اعمال شد: $_remoteHeal');
    } catch (e, stk) { logError(e, stk); }
  }
}
