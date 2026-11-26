# سیاست نسخهٔ آخرین پایدار و فهرست هسته‌های VPN در KING VPN

تاریخ ممیزی: **2026-11-26**

## قانون پذیرش

- هر هستهٔ جدید باید در زمان ادغام روی آخرین release پایدار رسمی upstream باشد؛ نسخهٔ قدیمی‌تر، شاخهٔ شناور یا commit نامشخص پذیرفته نیست.
- «آخرین نسخه» فقط با tag/release رسمی upstream یا رجیستری رسمی معتبر می‌شود؛ نسخهٔ برنامهٔ wrapper به‌تنهایی نسخهٔ موتور را اثبات نمی‌کند.
- برای هر جزء native باید نسخه، tag، commit دقیق، منبع artifact، checksum، ABI و مجوز ثبت شود.
- اگر release پایدار رسمی قابل‌تأیید نیست، یا dependencyها و build reproducible نیستند، آن موتور وارد APK نمی‌شود.
- هر ارتقای نسخه باید سه دور بازبینی، تست CI، اعتبارسنجی APK و آزمون runtime روی دستگاه واقعی داشته باشد.
- این ممیزی snapshot تاریخ بالاست؛ پیش از هر ادغام/انتشار دوباره باید latest upstream بررسی شود.

## فهرست نسخه‌های بررسی‌شده

| هسته / جزء | نسخهٔ بررسی‌شده | وضعیت |
|---|---|---|
| AmneziaWG Android | `v3.1.20260814` | commit `5c16489e2cd9ed3a0a7a27c7445bba5238132f86`؛ adapter اولیه هست، native build و runtime هنوز کامل نیست |
| sing-box core | `v1.14.4` | release پایدار upstream؛ باید artifact Android و checksum در CI تأیید شود |
| sing-box Android libbox | `libbox-v1.14.4-lx.25` | commit plugin `72f76fb714e07637a560774a7f2fdd3ae11884c4`; AAR SHA-256 `8f25b6600b2f1f1104636c9cb92941c756a6322e1f2ce0e5e97b9a6bc41d3bba` |
| WireGuard Android tunnel | `1.0.20260102` | نسخهٔ Maven Central که در ممیزی قبلی بررسی شد؛ پیش از release دوباره بررسی شود |
| Xray-core | `v26.11.9` | آخرین upstream ثبت‌شده در ممیزی قبلی؛ نسخهٔ واقعاً بسته‌بندی‌شده در artifact فعلی باید استخراج و تطبیق داده شود |

## سیاست قطعی حذف OpenVPN

**OpenVPN در KING VPN ممنوع و از نقشهٔ ادغام حذف است.**

این ممنوعیت شامل تمام نسخه‌ها، پیاده‌سازی‌ها و وابستگی‌های مستقیم یا غیرمستقیم است، از جمله:
- OpenVPN 2 و OpenVPN 3؛
- `ics-openvpn` و هر wrapper یا fork متکی بر آن؛
- اپ‌ها و پروژه‌های VPN که برای تونل اصلی یا مسیر fallback خود از OpenVPN استفاده می‌کنند؛
- هر dependency، submodule، AAR، native library، JNI bridge، service، profile parser یا کد build مخصوص OpenVPN.

وجود پروتکل‌های دیگر در همان محصول، آن محصول را از این شرط معاف نمی‌کند؛ اگر tunnel اصلی یا fallback VPN آن بر OpenVPN متکی باشد، حذف می‌شود.

### RiseupVPN / Bitmask — حذف‌شده

RiseupVPN/Bitmask از فهرست انتخاب KING حذف شد؛ چون Bitmask Android از `ics-openvpn` استفاده می‌کند. سند `docs/RISEUPVPN_CORE_INTEGRATION_FA.md` فقط سابقهٔ این تصمیم است و هیچ مجوزی برای ادغام آن ایجاد نمی‌کند.

### Psiphon — ردشده برای ادغام

Psiphon همچنان از ادغام KING خارج است؛ کاربر اپ رسمی آن را جداگانه نصب می‌کند. هیچ کتابخانه یا پل اتصال Psiphon در KING اضافه نشود.

## هسته‌های حفظ‌شده

- Xray هرگز حذف یا تضعیف نمی‌شود.
- WireGuard مستقل موجود حفظ می‌شود.
- sing-box و AmneziaWG فقط پس از تکمیل native build، coordinator، تست ABI و runtime واقعی فعال می‌شوند.
- Hysteria2 و سایر پروتکل‌ها باید به‌عنوان فناوری مستقل از OpenVPN بررسی شوند؛ پشتیبانی parser یا outbound در Xray به‌معنی هستهٔ مستقل نیست.

## معیار جایگزین بعدی

جایگزین Psiphon/Riseup باید:
1. هیچ وابستگی OpenVPN مستقیم یا غیرمستقیم نداشته باشد؛
2. برای استفادهٔ کاربر، خرید/اجاره/راه‌اندازی سرور اختصاصی نخواهد؛
3. هزینه، حساب و مجوز سرویس به‌صورت جداگانه بررسی شوند؛
4. هستهٔ واقعی Android و API قابل ادغام با TUN coordinator داشته باشد؛
5. آخرین نسخه، commit، checksum، ABI و مجوز pin شوند؛
6. سه دور بازبینی، CI، APK validation و runtime test روی دستگاه واقعی را بگذراند.

## منابع

- https://github.com/leapcode/bitmask_android
- https://github.com/amnezia-vpn/amneziawg-android/releases
- https://github.com/SagerNet/sing-box/releases
- https://central.sonatype.com/artifact/com.wireguard.android/tunnel
- https://github.com/XTLS/Xray-core/releases
