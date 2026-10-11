part of 'main.dart';

// ADS REMOTE ================================================================
// تبلیغ‌ها بدون ساخت دوباره‌ی اپ، از یک فایل JSON آنلاین خوانده می‌شوند.
// فایل را (مثلاً در یک Gist عمومی گیت‌هاب) بساز و آدرس «raw» آن را این‌جا بگذار.
// نمونه‌ی محتوای فایل:
//   {"enabled": true, "seconds": 10,
//    "urls": ["https://example.com/ad1", "https://example.com/ad2"]}
// enabled=false  => تبلیغ کلاً خاموش
// urls           => چند لینک بگذاری، هر بار یکی به‌صورت تصادفی نشان داده می‌شود
// seconds        => حداقل زمان دیدن تبلیغ (۳ تا ۶۰)
const String adsConfigUrl = 'PUT_RAW_GIST_URL_HERE';

bool _adsApply(String body) {
  try {
    final j = jsonDecode(body);
    if (j is! Map) return false;
    if (j['enabled'] is bool) requireRewardedAd = j['enabled'] as bool;
    final u = j['urls'];
    if (u is List) {
      final l = u
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.startsWith('https://'))
          .toList();
      if (l.isNotEmpty) {
        l.shuffle();
        _adUrls = l;
      }
    }
    final s = j['seconds'];
    if (s is int && s >= 3 && s <= 60) _adSeconds = s;
    return true;
  } catch (e) {
    logError(e);
    return false;
  }
}

// اول آخرین تنظیم ذخیره‌شده اعمال می‌شود (سریع)، بعد از اینترنت به‌روز می‌شود.
Future<void> adsRemoteLoad() async {
  SharedPreferences? p;
  try {
    p = await SharedPreferences.getInstance();
    final cached = p.getString('ads_cfg');
    if (cached != null) _adsApply(cached);
  } catch (e) {
    logError(e);
  }
  if (!adsConfigUrl.startsWith('https://')) return;
  try {
    final r = await http
        .get(Uri.parse(adsConfigUrl))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode == 200 && _adsApply(r.body)) {
      await p?.setString('ads_cfg', r.body);
    }
  } catch (e) {
    logError(e);
  }
}
