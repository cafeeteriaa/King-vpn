# طرح جایگزینی Psiphon با RiseupVPN / Bitmask در KING VPN

تاریخ ممیزی: **2026-11-26**

وضعیت: **جایگزین انتخاب‌شده برای مسیر مهندسی؛ هنوز در KING VPN ادغام اجرایی یا روی دستگاه آزمایش نشده است.**

## تصمیم

جایگزین Psiphon در KING VPN، سرویس **RiseupVPN** با استفاده از کد متن‌باز کلاینت **Bitmask Android** و زیرساخت رسمی Riseup است.

دلایل انتخاب:
- سرویس RiseupVPN برای کاربر رایگان است و ثبت‌نام/حساب کاربری لازم ندارد.
- کاربر نیازی به خرید، اجاره یا راه‌اندازی سرور اختصاصی ندارد؛ gatewayها را سرویس‌دهنده فراهم می‌کند.
- کد کلاینت Bitmask Android تحت GPL-3.0 منتشر شده و upstream آن برای ساخت نسخه‌های سفارشی/برندشده استفاده می‌شود.
- Bitmask Android از OpenVPN، API سرویس‌دهندهٔ LEAP و ابزارهای Pluggable Transport برای عبور از اختلال/مسدودسازی مسیر bootstrap پشتیبانی می‌کند.
- این مسیر از نظر معماری به سرویس‌دهنده و کلاینت متن‌باز مشخص متکی است؛ برخلاف Psiphon، در منابع رسمی بررسی‌شده شرط صریحی مبنی بر انحصار دسترسی شبکه به اپ منتشرشدهٔ خود سرویس‌دهنده پیدا نشد. با این حال، پیش از فعال‌سازی نهایی باید شرایط جاری سرویس و امکان استفاده از کلاینت مشتق‌شده دوباره بررسی شود.

## هزینه و حساب کاربری

طبق صفحهٔ رسمی Riseup:
- اتصال بدون پیکربندی دستی و بدون ساخت حساب کاربری ارائه می‌شود.
- سرویس بابت استفاده از VPN هزینهٔ اجباری دریافت نمی‌کند.
- سرویس با کمک مالی کاربران تأمین می‌شود و Riseup درخواست کمک مالی می‌کند؛ کمک مالی شرط فنی اتصال یا مجوز اجباری استفاده نیست.
- صفحهٔ رسمی هزینهٔ ارائهٔ سرویس را حدود 60 دلار آمریکا برای هر نفر در سال برآورد می‌کند؛ این برآورد هزینهٔ زیرساخت/پایداری سرویس است، نه صورتحساب یا الزام پرداخت برای کاربر.

KING VPN نباید هیچ پرداخت، اشتراک، کلید فعال‌سازی یا حساب اجباری اضافه کند. اگر شرایط سرویس در آینده تغییر کرد و پرداخت اجباری شد، این مسیر باید دوباره ارزیابی شود.

## نسخه‌ها و منابع upstream در ممیزی

### RiseupVPN Android

- F-Droid package: `se.leap.riseupvpn`
- آخرین نسخهٔ ثبت‌شده در F-Droid در زمان ممیزی: `1.6.3`
- versionCode: `186000`
- تاریخ انتشار F-Droid: `2026-07-21`
- مجوز: GPL-3.0-only
- ABIهای منتشرشده: `arm64-v8a`, `armeabi-v7a`, `x86`, `x86_64`
- حداقل Android: 7.0

### Bitmask Android

- F-Droid package: `se.leap.bitmaskclient`
- نسخهٔ F-Droid ثبت‌شده: `1.7.1`
- versionCode: `188000`
- تاریخ انتشار F-Droid: `2026-11-11`
- مجوز upstream: GPL-3.0
- مخزن کد عمومی: https://github.com/leapcode/bitmask_android
- مخزن اصلی توسعهٔ LEAP: https://0xacab.org/leap/bitmask_android

نسخهٔ Bitmask و RiseupVPN دو package/build مجزا هستند؛ شمارهٔ نسخهٔ یکی نباید به‌عنوان نسخهٔ دیگری ثبت شود. قبل از ساخت KING باید source tarball همان نسخه، commit دقیق، submodule SHAها، artifactها و checksumها از metadata رسمی F-Droid و upstream استخراج و pin شوند. این سند هنوز commit نهایی یا checksum باینری را ادعا نمی‌کند.

## اجزای upstream و معماری

README مخزن Bitmask Android وابستگی‌های زیر را اعلام می‌کند:
1. `ics-openvpn`: پیاده‌سازی OpenVPN Android.
2. `bitmask-core-android`: کلاینت API سرویس‌دهندهٔ LEAP و کتابخانهٔ Pluggable Transport.
3. `tor-android`: محافظت از ارتباط bootstrap/configuration در برابر مسدودسازی.

مخزن upstream از submoduleهای Git استفاده می‌کند و build آن به JDK 21، Android SDK/NDK و build native وابسته است. بنابراین فقط اضافه‌کردن یک dependency Maven یا کپی‌کردن UI کافی نیست؛ باید source و تمام submoduleها به‌صورت بازتولیدپذیر build شوند.

## معماری ادغام الزامی در KING

1. از کد رسمی Bitmask Android و اجزای رسمی آن استفاده شود؛ کد سرویس‌دهنده یا gateway ساختگی تولید نشود.
2. provider configuration و کلیدها/گواهی‌های سرویس فقط از API و سازوکار رسمی Riseup/LEAP دریافت شوند؛ هیچ credential محرمانه‌ای در APK hardcode نشود.
3. فقط یک `VpnService` و یک TUN فعال وجود داشته باشد. سرویس مستقل Bitmask نباید به‌صورت موازی TUN دوم ایجاد کند.
4. `ics-openvpn` باید با coordinator موجود KING سازگار شود و FD مربوط به TUN متعلق به KING را دریافت کند؛ مسیر `OPENTUN`/management upstream باید بررسی و با API کنترل‌شدهٔ KING تطبیق داده شود.
5. اگر انتقال امن FD و نگه‌داری descriptor در طول عمر tunnel قابل‌اثبات نبود، اتصال نباید شروع شود؛ TUN owner فعلی نباید زودهنگام آزاد شود.
6. ترافیک socketهای transport باید با `VpnService.protect(fd)` از TUN خارج شود تا loop ایجاد نشود.
7. Core/transport باید از همان gateway configuration رسمی، protocol order، UDP/TCP fallback و سازوکار failover upstream استفاده کند.
8. قابلیت‌های Pluggable Transport فقط در صورت پشتیبانی واقعی provider و نسخهٔ upstream فعال شوند؛ نام قابلیت یا UI بدون backend واقعی ممنوع است.
9. DNS، IPv4، IPv6، UDP، reconnect، تغییر شبکه، قطع ناگهانی، kill process، stop timeout و handoff باید end-to-end تست شوند.
10. Xray و WireGuard حفظ می‌شوند؛ Riseup/Bitmask یک گزینهٔ transport/engine جدید در کنار آن‌ها است، نه جایگزین آن‌ها.

## سازگاری و ریسک‌های مهم

- upstream Bitmask از `ics-openvpn` استفاده می‌کند؛ این هسته با OpenVPN 3 یکسان نیست. نباید آن را اشتباهاً OpenVPN 3 معرفی کرد یا هستهٔ OpenVPN 3 برنامه‌ریزی‌شده را بدون تصمیم مهندسی حذف کرد.
- Bitmask Core شامل کد Go و Pluggable Transport است؛ تداخل Go runtime/JNI با libbox و سایر کتابخانه‌های native باید در build و اجرای هم‌زمان بررسی شود.
- Tor bootstrap به معنی اجرای Tor به‌عنوان VPN تمام‌دستگاه نیست؛ نقش آن در Bitmask باید مطابق upstream محدود به مسیر bootstrap/configuration باقی بماند.
- نسخهٔ F-Droid، source commit، submodule revisions، ABI، NDK، checksum و مجوز تک‌تک اجزا باید pin شوند.
- سیاست privacy و retention سرویس باید از مستندات جاری Riseup بررسی شود؛ ادعای no-IP-logs در حال حاضر ادعای رسمی خود سرویس‌دهنده است و ممیزی مستقل تلقی نمی‌شود.
- ظرفیت، پایداری و دسترس‌پذیری gatewayهای Riseup تضمین‌شده فرض نشود. هیچ سقف مصنوعی در KING اضافه نمی‌شود، اما سرویس‌دهنده ممکن است به‌صورت عملی ظرفیت یا سیاست استفادهٔ خودش را داشته باشد.

## معیار پذیرش عملیاتی

- دریافت source و submoduleهای دقیق نسخهٔ انتخاب‌شده؛
- ثبت commit SHA، tag/version، checksum، ABI و مجوزها؛
- build بازتولیدپذیر Release برای ABIهای هدف؛
- adapter واقعی برای TUN FD متعلق به KING و تست عدم ایجاد TUN دوم؛
- تست محافظت socket و عدم نشت مستقیم در شکست transport؛
- تست DNS، IPv4، IPv6، TCP، UDP، network switch و reconnect؛
- تست handoff بین Riseup/Bitmask، Xray، WireGuard و sing-box با coordinator واحد؛
- تست runtime روی دستگاه Android واقعی و اعتبارسنجی APK؛
- سه دور بازبینی مستقل تغییرات، علاوه بر CI و تست‌های خودکار.

تا تکمیل این معیارها، Riseup/Bitmask در وضعیت «انتخاب‌شده برای ادغام» باقی می‌ماند و نباید در UI به‌عنوان هستهٔ آماده یا متصل نمایش داده شود.

## منابع

- RiseupVPN service: https://riseup.net/en/vpn
- Riseup Android instructions: https://riseup.net/en/android
- Bitmask Android source: https://github.com/leapcode/bitmask_android
- Bitmask Android changelog: https://github.com/leapcode/bitmask_android/blob/master/CHANGELOG
- Bitmask Android F-Droid: https://f-droid.org/packages/se.leap.bitmaskclient/
- RiseupVPN F-Droid: https://f-droid.org/packages/se.leap.riseupvpn/
- LEAP Bitmask Android project: https://0xacab.org/leap/bitmask_android
