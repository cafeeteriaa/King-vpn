# سیاست نسخهٔ آخرین پایدار برای هسته‌های VPN در KING VPN

تاریخ ممیزی: **2026-11-26**

## قانون پذیرش

- هر هستهٔ جدید باید در زمان ادغام روی آخرین release پایدار رسمی upstream باشد؛ نسخهٔ قدیمی‌تر، شاخهٔ شناور یا commit نامشخص پذیرفته نیست.
- «آخرین نسخه» فقط با tag/release رسمی upstream یا رجیستری رسمی معتبر می‌شود؛ نسخهٔ برنامهٔ wrapper به‌تنهایی نسخهٔ موتور را اثبات نمی‌کند.
- برای هر جزء native باید نسخه، tag، commit دقیق، منبع artifact، checksum، ABI و مجوز ثبت شود.
- اگر release پایدار رسمی قابل‌تأیید نیست، یا dependencyها و build reproducible نیستند، آن موتور وارد APK نمی‌شود. اگر قبلاً وارد شده باشد، تا جایگزینی با نسخهٔ آخرین پایدار از build/release حذف می‌شود.
- هر ارتقای نسخه باید سه دور بازبینی، تست CI، اعتبارسنجی APK و آزمون runtime روی دستگاه واقعی داشته باشد. ارتقای خودکار بدون تست ممنوع است.
- این ممیزی snapshot تاریخ بالاست؛ پیش از هر ادغام/انتشار دوباره باید latest upstream بررسی شود.

## وضعیت نسخه‌ها در زمان ممیزی

| هسته / جزء | آخرین نسخهٔ پایدار رسمیِ بررسی‌شده | شناسهٔ دقیق / وضعیت |
|---|---|---|
| Psiphon tunnel-core | `v2.0.43` | commit `66e249dde58a8f90fed17d3773d987942f100425` |
| Psiphon Android library | `v2.0.43` | commit `7ba832f9d693b69889e6c1582dac2d3e5b51e6ad`; AAR `ca.psiphon:psiphontunnel:2.0.43` |
| AmneziaWG Android | `v3.1.20260814` | commit `5c16489e2cd9ed3a0a7a27c7445bba5238132f86` |
| sing-box core | `v1.14.4` | آخرین release پایدار رسمی در زمان ممیزی |
| sing-box Android libbox artifact | `libbox-v1.14.4-lx.25` | commit plugin `72f76fb714e07637a560774a7f2fdd3ae11884c4`; AAR SHA-256 `8f25b6600b2f1f1104636c9cb92941c756a6322e1f2ce0e5e97b9a6bc41d3bba` |
| WireGuard Android tunnel | `1.0.20260102` | آخرین نسخهٔ موجود در Maven Central که در ممیزی رجیستری تأیید شد |
| Xray-core | `v26.11.9` | آخرین release پایدار رسمی؛ نسخهٔ واقعاً بسته‌بندی‌شده در زنجیرهٔ فعلی Xray باید جداگانه از artifact/plugin استخراج و تطبیق داده شود |

## اصلاحات لازم و وضعیت اجرایی

### Psiphon
پیش‌نویس قبلی به‌اشتباه `v2.0.42` را pin کرده بود. این نسخه با آخرین `v2.0.43` جایگزین شد:
- Core commit: `66e249dde58a8f90fed17d3773d987942f100425`
- Android library commit: `7ba832f9d693b69889e6c1582dac2d3e5b51e6ad`
- AAR SHA-1 منتشرشده: `c5adb96568633b828c9d9e9d88d98a32fe3f89ca`
- Android Library release ZIP SHA-256: `6ad02dfa8fd98173f6aaaf89258b3eb69953c81ab61b1f32604bd2c2f68750b5`
- Release: https://github.com/Psiphon-Labs/psiphon-tunnel-core/releases/tag/v2.0.43

Psiphon هنوز در KING VPN اجرایی نشده است؛ نسخهٔ جدید فقط در طرح ادغام و pinهای پژوهشی ثبت شده است.

### AmneziaWG
adapter اولیهٔ KING با JNI API که در آخرین release رسمی `v3.1.20260814` بررسی شد، هم‌نام است. اما native library و pipeline ساخت هنوز کامل نیست. upstream در همین release مقدار Go در `go.mod` را `1.25.0` و Makefile را `1.24.2` قرار داده است؛ تا رفع reproducible این ناسازگاری، نباید موتور عملیاتی اعلام شود.

### sing-box
Core `v1.14.4` آخرین release پایدار رسمی است. اما artifact اندروید جدیدتر با tag `libbox-v1.14.4-lx.25` منتشر شده است. اسکریپت build در PR63 اکنون properties را به همان artifact و SHA-256 رسمی بازنویسی می‌کند؛ CI باید ثابت کند Gradle واقعاً همین artifact را دریافت و hash آن را تأیید می‌کند.

### WireGuard و Xray
- WireGuard موجود در PR58 حفظ می‌شود؛ dependency اندروید `com.wireguard.android:tunnel:1.0.20260102` در Maven Central آخرین نسخهٔ بررسی‌شده است.
- Xray موجود حذف یا تضعیف نمی‌شود. آخرین upstream در زمان ممیزی `v26.11.9` است، ولی باید نسخهٔ واقعی در artifact `flutter_v2ray_client` یا `libv2ray` استخراج شود؛ تا زمان تطبیق، ادعای «آخرین Xray بسته‌بندی‌شده» نداریم.

## منابع رسمی

- https://github.com/Psiphon-Labs/psiphon-tunnel-core/releases
- https://github.com/amnezia-vpn/amneziawg-android/releases
- https://github.com/SagerNet/sing-box/releases
- https://github.com/QUSAD-prod/sing_box/releases
- https://central.sonatype.com/artifact/com.wireguard.android/tunnel
- https://github.com/XTLS/Xray-core/releases
- https://pub.dev/packages/flutter_v2ray_client/versions
