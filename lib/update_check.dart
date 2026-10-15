part of 'main.dart';

// UPDATE CHECK =============================================================
// برنامه موقع باز شدن یک فایل JSON آنلاین را می‌خواند و اگر نسخه‌اش قدیمی
// بود پیام آپدیت نشان می‌دهد.
//
// هر بار که نسخه‌ی جدید می‌سازی:
//   ۱) عدد appBuild پایین را یکی بیشتر کن (مثلاً 1 بشود 2)
//   ۲) فایل داخل Gist آپدیت (0e04f5efe29b...) را ادیت کن
//
// نمونه‌ی محتوای update.json:
// {
//   "latest": 2,
//   "min": 2,
//   "url": "https://t.me/kingvpnn57",
//   "message": "نسخه‌ی جدید آمد. لطفاً آپدیت کنید."
// }
// latest => شماره‌ی آخرین نسخه. اگر نسخه‌ی کاربر کمتر باشد پیام آپدیت
//           با دکمه‌ی «بعداً» نشان داده می‌شود.
// min    => کمترین نسخه‌ی مجاز. اگر نسخه‌ی کاربر کمتر باشد پیام آپدیت
//           اجباری است و بسته نمی‌شود.
// url    => لینک دانلود نسخه‌ی جدید (کانال تلگرام یا GitHub Release)
// message => متن پیام (اختیاری)
const int appBuild = 1;
const String updateConfigUrl =
    'https://gist.githubusercontent.com/cafeeteriaa/0e04f5efe29b8101eb554c6e9a41d969/raw';

bool _updateChecked = false;

extension UpdateCheck on _HomePageState {
  Future<void> checkForUpdate() async {
    if (_updateChecked) return;
    _updateChecked = true;
    try {
      await Future.delayed(const Duration(seconds: 4));
      if (!mounted) return;
      final r = await http
          .get(Uri.parse(updateConfigUrl))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body);
      if (j is! Map) return;
      final latest = (j['latest'] as num?)?.toInt() ?? 0;
      final min = (j['min'] as num?)?.toInt() ?? 0;
      var url = (j['url'] as String?)?.trim() ?? '';
      if (url.isEmpty) url = 'https://t.me/kingvpnn57';
      final msg = (j['message'] as String?)?.trim() ?? '';
      final force = appBuild < min;
      if (!force && appBuild >= latest) return;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: !force,
        builder: (ctx) => // ignore: deprecated_member_use
            WillPopScope(
          onWillPop: () async => !force,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('🔄 آپدیت جدید'),
              content: Text(msg.isNotEmpty
                  ? msg
                  : (force
                      ? 'این نسخه قدیمی است. برای ادامه حتماً برنامه را آپدیت کنید.'
                      : 'نسخه‌ی جدید برنامه آمده است. لطفاً آپدیت کنید.')),
              actions: [
                if (!force)
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('بعداً')),
                FilledButton(
                  onPressed: () async {
                    if (url.isEmpty) return;
                    try {
                      if (await launchUrl(Uri.parse(url),
                          mode: LaunchMode.externalApplication)) {
                        return;
                      }
                    } catch (_) {}
                    await Clipboard.setData(ClipboardData(text: url));
                    _set('لینک دانلود کپی شد');
                  },
                  child: const Text('دانلود نسخه‌ی جدید'),
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
}
