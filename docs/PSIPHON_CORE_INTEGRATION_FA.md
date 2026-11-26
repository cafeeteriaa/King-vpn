# ارزیابی و طرح ادغام Psiphon در KING VPN

وضعیت: **انتخاب‌شده برای ادغام؛ هنوز در KING VPN پیاده‌سازی یا روی دستگاه آزمایش نشده است.** این سند جایگزین ادغام اجرایی نیست.

## تصمیم

Psiphon بهترین گزینهٔ فعلی برای مسیر «VPN ضدسانسور در سطح Psiphon» است و به‌عنوان مسیر اول ادغام انتخاب می‌شود. سرویس خروجی و سرورهای شبکه را خود Psiphon فراهم می‌کند؛ کاربر KING VPN به سرور اختصاصی، حساب یا خرید لایسنس نیاز ندارد. طرح رایگان Basic بدون حساب ارائه می‌شود؛ طرح Plus اختیاری و پولی است و نباید پیش‌نیاز KING باشد.

منابع رسمی:
- هسته: https://github.com/Psiphon-Labs/psiphon-tunnel-core
- کلاینت Android: https://github.com/Psiphon-Inc/psiphon-android
- کتابخانهٔ Android: https://github.com/Psiphon-Labs/psiphon-tunnel-core-Android-library
- راهنمای رسمی کتابخانه: https://github.com/Psiphon-Labs/psiphon-tunnel-core/blob/v2.0.43/MobileLibrary/Android/README.md
- مجوز هسته: GPL-3.0؛ مجوز و notices تمام اجزای بستهٔ AAR و dependencyها باید جداگانه ثبت و بررسی شوند.

## آخرین نسخهٔ پایدار رسمی (ممیزی 2026-11-26)

آخرین release پایدار رسمی در زمان این ممیزی `v2.0.43` است (منتشرشده در 2026-11-17). نسخهٔ `v2.0.42` که در پیش‌نویس قبلی آمده بود قدیمی بود و جایگزین شد.

## نسخه‌های upstream پین‌شده

- Psiphon tunnel-core release: `v2.0.43`
- commit هسته: `66e249dde58a8f90fed17d3773d987942f100425`
- مخزن Android Maven library، tag: `v2.0.43`
- commit مخزن Android library: `7ba832f9d693b69889e6c1582dac2d3e5b51e6ad`
- مختصات AAR رسمی: `ca.psiphon:psiphontunnel:2.0.42`
- مخزن Maven نسخه‌دار: `https://raw.githubusercontent.com/Psiphon-Labs/psiphon-tunnel-core-Android-library/v2.0.43`
- SHA-1 منتشرشده برای AAR: `c5adb96568633b828c9d9e9d88d98a32fe3f89ca`
- SHA-256 آرشیو رسمی Android Library در release: `6ad02dfa8fd98173f6aaaf89258b3eb69953c81ab61b1f32604bd2c2f68750b5`

از شاخهٔ شناور `master` یا نسخهٔ بدون pin استفاده نشود. قبل از ادغام واقعی، latest release دوباره از GitHub بررسی و checksum AAR نهایی نیز جداگانه ثبت شود.

## یافتهٔ مهم معماری Android

کتابخانهٔ رسمی Android، API جاوای `ca.psiphon.PsiphonTunnel` و callbackهای `HostService` را عرضه می‌کند. پس از شروع، پورت SOCKS/HTTP محلی را از callbackهایی مانند `onListeningSocksProxyPort` اعلام می‌کند. نمونهٔ رسمی TunneledWebView نیز از همین proxy محلی استفاده می‌کند.

کلاینت رسمی Android برای VPN تمام‌دستگاه، لایهٔ جداگانهٔ خودش را دارد: سرویس Android از `VpnService` و Builder خودش استفاده می‌کند و سپس Psiphon را اجرا می‌کند. واردکردن مستقیم آن سرویس به KING، مالک دوم TUN می‌سازد و با معماری مالکیت واحد KING ناسازگار است.

## معماری ادغام در KING

1. کتابخانهٔ رسمی Psiphon در همان فرایند/سرویس foreground متعلق به KING اجرا شود؛ از سرویس مستقل VPN رسمی Psiphon یا `VpnService.Builder` دوم استفاده نشود.
2. پیاده‌سازی `HostService.bindToDevice(fd)` باید سوکت‌های خروجی Psiphon را با `VpnService.protect(fd)` از حلقهٔ TUN خارج کند؛ شکست protect باید شروع را متوقف کند.
3. تنظیمات معتبر tunnel-core و فهرست server entryهای رسمی باید از upstream رسمی Android با revision ثابت استخراج شوند. config ساختگی، server entry حدسی یا credential متعلق به سرویس ثالث وارد نشود.
4. شروع Psiphon تا دریافت پورت SOCKS و callback اتصال واقعی، موفق تلقی نشود.
5. Xray موجود به‌عنوان تنها مالک TUN و packet engine استفاده شود؛ outbound SOCKS آن به پورت loopback اعلام‌شده از Psiphon متصل شود. تمام مسیرهای IPv4/IPv6 و DNS باید به‌صورت fail-closed بررسی شوند تا هیچ ترافیکی ناخواسته مستقیم خارج نشود.
6. پشتیبانی SOCKS از UDP، DNS، IPv6، reconnect و رفتار قطع شبکه باید از کد upstream و تست واقعی اثبات شود. اگر یک نوع ترافیک پشتیبانی نشد، آن را direct نکنیم و اتصال را با وضعیت ناقص «کامل» اعلام نکنیم.
7. ترتیب توقف: ابتدا Xray و TUN آن با تأیید واقعی متوقف شوند؛ سپس Psiphon متوقف و منابعش آزاد شوند. مالکیت coordinator فقط پس از تأیید توقف هستهٔ صاحب TUN آزاد شود.
8. پورت محلی، آمار، منطقه، خطا، وضعیت reconnect و علت شکست از callbackهای واقعی گزارش شوند؛ وضعیت Connected یا ترافیک ساختگی ممنوع است.

## ریسک‌های فنی و الزامات پیش از فعال‌سازی

- AAR شامل کد Go بومی است؛ تداخل کلاس‌ها/Runtimeهای gomobile با libbox و Xray باید در build و در بارگذاری هم‌زمان بررسی شود.
- AAR و تمام وابستگی‌های transitve باید از نظر مجوز، notices و سازگاری GPL-3.0 ممیزی شوند؛ GPL پروژه مجوز dependencyهای دیگر را تغییر نمی‌دهد.
- config و server entryها باید از همان نسخهٔ رسمی استخراج شوند و چرخهٔ به‌روزرسانی امن داشته باشند.
- پشتیبانی ABI، 16 KB page alignment، امضای JNI، محافظت socket، IPv4/IPv6، DNS، UDP، network change، reconnect، stop timeout و crash recovery باید در CI و دستگاه واقعی آزموده شوند.
- این مسیر «Psiphon transport + Xray TUN» است، نه ادعای وجود یک VpnService مستقل Psiphon در KING. این انتخاب برای جلوگیری از رقابت دو مالک TUN است.

## معیار پذیرش

- build قابل بازتولید و dependencyهای version-pinned؛
- بررسی checksum و license notices؛
- تست منفی برای جلوگیری از direct leak در شکست SOCKS؛
- تست end-to-end از طریق تونل برای DNS و مقصدهای IPv4/IPv6 و آزمون جداگانهٔ UDP؛
- handoff و stop/restart بدون آزادکردن زودهنگام TUN؛
- سه دور بازبینی تغییرات و تست روی دستگاه Android واقعی.

تا وقتی موارد بالا اثبات نشده‌اند، Psiphon در رابط کاربری به‌عنوان «آماده/متصل» نمایش داده نمی‌شود.
