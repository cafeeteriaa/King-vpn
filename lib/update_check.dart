part of 'main.dart';

// UPDATE + SELF-HEAL =======================================================
// ۱) چک نسخه‌ی آنلاین → لینک / دانلود APK → نصب با تأیید کاربر
// ۲) قوانین ترمیم از راه دور (heal) بدون نیاز به بیلد جدید
// ۳) موتور خودترمیمی محلی قوی‌تر از تصمیم‌های دستی
//
// update.json نمونه:
// {
//   "latest": 2,
//   "min": 1,
//   "url": "https://t.me/kingvpnn57",
//   "apk": "https://example.com/king-vpn.apk",
//   "message": "رفع تعویض بی‌خودی خلبان + توربو پایدار",
//   "heal": {
//     "pilotHoldSec": 180,
//     "turboForce": true,
//     "muxConc": 32,
//     "autoClearBlacklistAfter": 5,
//     "orphanFailoverSec": 20
//   }
// }
const int appBuild = 2;
const String updateConfigUrl =
    'https://gist.githubusercontent.com/cafeeteriaa/0e04f5efe29b8101eb554c6e9a41d969/raw';

bool _updateChecked = false;
Map<String, dynamic> _remoteHeal = {};
DateTime? _lastSelfHeal;
int _healNoHealthy = 0;
int _healCoreDrop = 0;
int _healOrphan = 0;

extension UpdateCheck on _HomePageState {
  Future<void> checkForUpdate() async {
    if (_updateChecked) return;
    _updateChecked = true;
    try {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      final r = await http
          .get(Uri.parse(updateConfigUrl))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body);
      if (j is! Map) return;
      final map = Map<String, dynamic>.from(j);

      // قوانین ترمیم از راه دور — بدون نصب APK هم اعمال می‌شود
      final heal = map['heal'];
      if (heal is Map) {
        _remoteHeal = Map<String, dynamic>.from(heal);
        _applyRemoteHeal();
      }

      final latest = (map['latest'] as num?)?.toInt() ?? 0;
      final min = (map['min'] as num?)?.toInt() ?? 0;
      var url = (map['url'] as String?)?.trim() ?? '';
      final apk = (map['apk'] as String?)?.trim() ?? '';
      if (url.isEmpty) url = 'https://t.me/kingvpnn57';
      final msg = (map['message'] as String?)?.trim() ?? '';
      final force = appBuild < min;
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
              title: const Text('🔄 آپدیت / ترمیم نسخه'),
              content: Text(
                msg.isNotEmpty
                    ? msg
                    : (force
                        ? 'این نسخه قدیمی است. برای ادامه باید آپدیت کنید.\n'
                            'نسخه‌ی جدید مشکلات اتصال و خلبان را ترمیم می‌کند.'
                        : 'نسخه‌ی جدید آماده است.\n'
                            'رفع تعویض بی‌خودی، توربو پایدارتر، گزارش خطا کامل.\n'
                            'Build فعلی: $appBuild → هدف: $latest'),
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
                    child: const Text('دانلود و نصب مستقیم'),
                  ),
                FilledButton(
                  onPressed: () async {
                    final open = apk.isNotEmpty ? apk : url;
                    try {
                      if (await launchUrl(Uri.parse(open),
                          mode: LaunchMode.externalApplication)) {
                        if (ctx.mounted) Navigator.pop(ctx);
                        return;
                      }
                    } catch (_) {}
                    await Clipboard.setData(ClipboardData(text: open));
                    _set('لینک آپدیت کپی شد');
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text(apk.isNotEmpty ? 'باز کردن لینک APK' : 'دانلود نسخه‌ی جدید'),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      logError(e);
    }
  }

  /// دانلود APK و باز کردن صفحه‌ی نصب (اندروید یک‌بار تأیید کاربر می‌خواهد)
  Future<void> _downloadAndInstallApk(String apkUrl) async {
    try {
      _set('در حال دانلود نسخه‌ی جدید...');
      final r = await http
          .get(Uri.parse(apkUrl))
          .timeout(const Duration(minutes: 3));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
        _set('دانلود آپدیت ناموفق — لینک را دستی باز کن');
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
        return;
      }
      final dir = await Directory.systemTemp.createTemp('king_upd_');
      final file = File('${dir.path}/king-vpn-update.apk');
      await file.writeAsBytes(r.bodyBytes, flush: true);
      _set('دانلود شد — صفحه‌ی نصب را تأیید کن');
      // اندروید: باز کردن فایل APK (کاربر باید «نصب از منابع ناشناس» را اجازه دهد)
      final ok = await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
        await Clipboard.setData(ClipboardData(text: apkUrl));
        _set('لینک APK کپی شد — از مرورگر نصب کن');
      }
    } catch (e) {
      logError(e);
      try {
        await launchUrl(Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication);
      } catch (_) {}
      _set('آپدیت: لینک را در مرورگر باز کن و نصب کن');
    }
  }

  void _applyRemoteHeal() {
    try {
      if (_remoteHeal['turboForce'] == true) {
        turboSpeed = true;
        muxEnabled = true;
      }
      final mc = (_remoteHeal['muxConc'] as num?)?.toInt();
      if (mc != null && mc >= 8) muxConc = mc.clamp(8, 64);
      final hold = (_remoteHeal['pilotHoldSec'] as num?)?.toInt();
      if (hold != null && hold >= 60) {
        // فقط لاگ؛ hold در خلبان از کد خوانده می‌شود — مقدار را در dbg نگه می‌داریم
        dbg('ترمیم از راه دور: pilotHold≈${hold}s turbo=$turboSpeed mux=$muxConc');
      }
    } catch (_) {}
  }

  /// موتور خودترمیمی — هر تیک واچ‌داگ / خلبان صدا زده می‌شود
  Future<void> kingSelfHeal({String reason = ''}) async {
    if (!mounted) return;
    final now = DateTime.now();
    if (_lastSelfHeal != null &&
        now.difference(_lastSelfHeal!) < const Duration(seconds: 15)) {
      return;
    }
    _lastSelfHeal = now;
    try {
      // ۱) همگام هسته/اپ
      _syncCore();

      // ۲) می‌خواهد وصل باشد ولی قطع است و کاری نمی‌کند
      if (wantVpn &&
          !connected &&
          !busy &&
          !switching &&
          !searching) {
        _healOrphan++;
        final need = (_remoteHeal['orphanFailoverSec'] as num?)?.toInt() ?? 20;
        if (_healOrphan >= 2) {
          dbg('خودترمیمی: اتصال یتیم → connect/failover');
          _shProb('selfheal:orphan',
              'خودترمیمی: wantVpn ولی بیکار بود → اتصال مجدد');
          _healOrphan = 0;
          try {
            await connect();
          } catch (e) {
            logError(e);
          }
        }
      } else {
        _healOrphan = 0;
      }

      // ۳) سرور سالم نیست — بعد از چند بار لیست سیاه را نرم پاک کن
      final clearAfter =
          (_remoteHeal['autoClearBlacklistAfter'] as num?)?.toInt() ?? 5;
      if (!connected && good.isEmpty && failed.length > 30) {
        _healNoHealthy++;
        if (_healNoHealthy >= clearAfter) {
          dbg('خودترمیمی: پاک‌سازی نرم لیست سیاه (${failed.length})');
          _shProb('selfheal:blacklist',
              'خودترمیمی: لیست سیاه بزرگ بود → پاک‌سازی نرم');
          final cut = DateTime.now().subtract(const Duration(minutes: 30));
          failed.removeWhere((_, t) => t.isBefore(cut));
          _healNoHealthy = 0;
          if (!busy && wantVpn) {
            try {
              await connect();
            } catch (_) {}
          }
        }
      } else {
        _healNoHealthy = 0;
      }

      // ۴) توربو/Mux همیشه برای اتصال پایدار
      if (connected && turboSpeed) {
        if (!muxEnabled) muxEnabled = true;
        if (muxConc < 16) muxConc = 16;
      }

      // ۵) هسته قطع مکرر
      if (wantVpn &&
          connected == false &&
          lastWhy.contains('هسته/اندروید')) {
        _healCoreDrop++;
        if (_healCoreDrop >= 3 && !busy) {
          dbg('خودترمیمی: CORE-DROP مکرر → failover');
          _shProb('selfheal:core-drop',
              'خودترمیمی: قطع مکرر هسته → تعویض سرور');
          _healCoreDrop = 0;
          try {
            await _failover();
          } catch (_) {}
        }
      } else if (connected) {
        _healCoreDrop = 0;
      }

      if (reason.isNotEmpty) {
        dbg('خودترمیمی تیک ($reason)');
      }
    } catch (e) {
      logError(e);
    }
  }
}
