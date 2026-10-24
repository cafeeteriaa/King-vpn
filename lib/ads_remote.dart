part of 'main.dart';

// ADS REMOTE ================================================================
// تبلیغ‌ها بدون ساخت دوباره‌ی اپ، از یک فایل JSON آنلاین (Gist) خوانده می‌شوند.
// نمونه‌ی محتوای فایل:
// {
//   "enabled": true,
//   "seconds": 10,
//   "urls": ["https://example.com/ad1"],
//   "ads": [
//     {"title": "عنوان", "text": "متن تبلیغ", "image": "https://.../a.jpg",
//      "video": "https://.../a.mp4", "link": "https://t.me/xxx"}
//   ]
// }
// enabled=false => تبلیغ کلاً خاموش
// urls          => صفحه‌ی وب آماده (اختیاری)
// ads           => تبلیغ خودت: هر کدام از title/text/image/video/link را که
//                  خواستی بگذار (همه اختیاری‌اند). link با لمس تبلیغ باز می‌شود.
// اگر هم urls و هم ads بگذاری، هر بار یکی به‌صورت تصادفی نشان داده می‌شود.
// seconds       => حداقل زمان دیدن تبلیغ (۳ تا ۶۰)
const String adsConfigUrl =
    'https://gist.githubusercontent.com/cafeeteriaa/f403c732c9cd963deca653054c998bf4/raw/ads.json';

String _adEsc(String s) => const HtmlEscape().convert(s);

String? _adStr(dynamic v, {bool https = false}) {
  if (v is! String) return null;
  final t = v.trim();
  if (t.isEmpty) return null;
  if (https && !t.startsWith('https://')) return null;
  return t;
}

// یک تبلیغ (متن/عکس/فیلم) را به صفحه‌ی HTML تبدیل می‌کند.
// خروجی با «<» شروع می‌شود تا AdPage بداند HTML است.
String? _adBuildHtml(Map m) {
  final title = _adStr(m['title']);
  final text = _adStr(m['text']);
  final image = _adStr(m['image'], https: true);
  final video = _adStr(m['video'], https: true);
  final link = _adStr(m['link'], https: true);
  if (title == null && text == null && image == null && video == null) {
    return null;
  }
  final b = StringBuffer();
  b.write('<!DOCTYPE html><html dir="rtl"><head>'
      '<meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<style>'
      'body{margin:0;padding:20px;background:#1A1710;color:#fff;'
      'font-family:sans-serif;text-align:center;line-height:1.9}'
      'h1{color:#E0B656;font-size:22px;margin:12px 0}'
      'p{font-size:17px;white-space:pre-wrap;margin:12px 0}'
      'img,video{max-width:100%;border-radius:12px;margin:12px 0}'
      'a.b{display:inline-block;margin-top:16px;padding:12px 28px;'
      'background:#E0B656;color:#000;border-radius:10px;'
      'text-decoration:none;font-weight:bold}'
      '</style></head><body>');
  if (title != null) b.write('<h1>${_adEsc(title)}</h1>');
  if (image != null) {
    final img = '<img src="${_adEsc(image)}">';
    b.write(link != null ? '<a href="${_adEsc(link)}">$img</a>' : img);
  }
  if (video != null) {
    b.write('<video src="${_adEsc(video)}" controls autoplay muted '
        'playsinline loop></video>');
  }
  if (text != null) b.write('<p>${_adEsc(text)}</p>');
  if (link != null) {
    b.write('<a class="b" href="${_adEsc(link)}">مشاهده بیشتر</a>');
  }
  b.write('</body></html>');
  return b.toString();
}

bool _adsApply(String body) {
  try {
    final j = jsonDecode(body);
    if (j is! Map) return false;
    // remote config may not turn the ad gate back on (gate is off in this build)
    // if (j['enabled'] is bool) requireRewardedAd = j['enabled'] as bool;
    final all = <String>[];
    String? firstLink;
    final u = j['urls'];
    if (u is List) {
      for (final e in u.whereType<String>()) {
        final t = e.trim();
        if (t.startsWith('https://')) {
          all.add(t);
          firstLink ??= t;
        }
      }
    }
    final a = j['ads'];
    if (a is List) {
      for (final e in a) {
        if (e is! Map) continue;
        final h = _adBuildHtml(e);
        if (h != null) {
          all.add(h);
          firstLink ??= _adStr(e['link'], https: true);
        }
      }
    }
    if (all.isNotEmpty) {
      all.shuffle();
      _adUrls = all;
      if (firstLink != null) _adFallbackUrl = firstLink;
    }
    final s = j['seconds'];
    if (s is int && s >= 3 && s <= 60) _adSeconds = s;
    return true;
  } catch (e, stk) {
    logError(e, stk);
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
  } catch (e, stk) {
    logError(e, stk);
  }
  if (!adsConfigUrl.startsWith('https://')) return;
  try {
    final r = await http
        .get(Uri.parse(adsConfigUrl))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode == 200 && _adsApply(r.body)) {
      await p?.setString('ads_cfg', r.body);
    }
  } catch (e, stk) {
    logError(e, stk);
  }
}
