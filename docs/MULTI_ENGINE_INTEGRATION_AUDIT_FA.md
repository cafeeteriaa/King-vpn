# ممیزی یکپارچه‌سازی موتورهای KING VPN

تاریخ ممیزی: 2026-11-26  
شاخه: `feature/king-multi-network-engines`

## اصل معماری

- Xray موتور فعال فعلی است و مسیر موجود آن نباید برای آزمایش موتورهای دیگر تغییر کند.
- هر موتور full-device باید مالکیت انحصاری Android `VpnService`/TUN را بگیرد. سوئیچ فقط پس از تأیید توقف و آزادشدن TUN موتور قبلی مجاز است.
- ابزارهای local transport/DPI نباید به‌اشتباه به‌عنوان VPN server engine وارد چرخه failover شوند. آن‌ها فقط در حالت standalone سازگار یا به‌صورت proxy-chain کنار موتور تونل قابل اجرا هستند.
- `CONNECTED` یا شروع پردازه، موفقیت اتصال نیست؛ باید عبور واقعی TCP و UDP/DNS از تونل بررسی شود.
- کاتالوگ، parser و feed به‌تنهایی adapter اجرایی محسوب نمی‌شوند.

## وضعیت ۱۲ گزینه

| موتور | نقش در KING VPN | مسیر فنی قابل اتکا | مانع/کار باقیمانده |
|---|---|---|---|
| Xray | full-device، موتور اصلی | پلاگین فعلی `flutter_v2ray_client` | حفظ مسیر و regression tests |
| Hysteria 2 | full-device | هسته Go رسمی؛ Bedlam نمونه Android با TUN و gVisor | استخراج/بسته‌بندی core بدون کپی کل اپ، ABIها، lifecycle و مجوز اجزای همراه |
| sing-box | full-device و چندپروتکلی | هسته sing-box و SFA؛ SFA خودش TUN اندروید را پیاده می‌کند | ساخت integration بومی با نسخه pin‌شده؛ GPL-3.0 و الزامات نام/نشان و انتشار مشتقات باید بررسی شوند |
| nthLink / Leaf | full-device | SDKهای Leaf و Outline در قالب اپ Android | template رسمی نیازمند backend و پیاده‌سازی توابع Core و VPN client است؛ بدون backend معتبر قابل فعال‌سازی نیست |
| Shroudly | local transport یا standalone VPN | سورس Android شامل VpnService و hev-socks5-tunnel | باید حالت proxy-only و API قابل‌استفاده برای chaining جدا شود؛ نباید VPNService دوم هم‌زمان بالا بیاید |
| ByeDPI | local DPI transport | اپ Android از ByeDPI و SOCKS5 استفاده می‌کند | سرویس فعلی آن VPN محلی خودش را می‌سازد؛ برای chaining باید هسته محلی بدون مالکیت دوم TUN استخراج شود |
| PowerTunnel | local proxy/DPI | Core و SDK افزونه دارد | نسخه Android قدیمی‌تر است؛ سازگاری SDK، وابستگی MITM و مجوز GPL-3.0 باید بررسی شود |
| AmneziaWG | full-device | fork مبتنی بر WireGuard-Go و Android tunnel app | استفاده از tunnel core مستقل از UI، پارامترهای AWG و نسخه دقیق protocol؛ مجوز تمام اجزای bundled |
| OpenVPN | full-device | OpenVPN 3 یک C++ class library با API دارد | ساخت NDK/JNI، مدیریت credentials/certificates و TUN lifecycle؛ از ics-openvpn به‌عنوان کتابخانه استفاده نشود چون نگهدارنده صریحاً هدف library بودن را رد کرده و GPL دارد |
| Shadowsocks | full-device با TUN adapter | هسته Shadowsocks و پیاده‌سازی Android | پروژه shadowsocks-android اعلام کرده core برای استفاده مجدد عمومی طراحی نشده؛ باید core مستقل قابل‌استفاده و مجوز آن انتخاب شود |
| OpenConnect | full-device | libopenconnect و کلاینت Android متن‌باز | JNI/NDK، گواهی و MFA، و بازبینی نگهداری پروژه Android؛ نیازمند gateway سازگار |
| WireGuard | full-device | کتابخانه رسمی tunnel در Maven Central و GoBackend | اضافه‌کردن dependency، service lifecycle، import و parse امن .conf و آزمون واقعی |

## منابع فنی upstream

- Hysteria: https://github.com/apernet/hysteria
- Bedlam Android reference: https://github.com/0xSVV/Bedlam
- sing-box core: https://github.com/SagerNet/sing-box
- SFA Android: https://github.com/SagerNet/sing-box-for-android
- nthLink Android template: https://github.com/nthlink/nthlink-os-android
- Shroudly: https://github.com/umutxyp/Shroudly
- ByeDPI Android: https://github.com/dovecoteescapee/ByeDPIAndroid
- PowerTunnel Android: https://github.com/krlvm/PowerTunnel-Android
- AmneziaWG Android: https://github.com/amnezia-vpn/amneziawg-android
- OpenVPN 3 core: https://github.com/OpenVPN/openvpn3
- Shadowsocks Android: https://github.com/shadowsocks/shadowsocks-android
- OpenConnect Android: https://github.com/cernekee/ics-openconnect
- WireGuard Android/tunnel: https://git.zx2c4.com/wireguard-android/

## وضعیت پیاده‌سازی مخزن

- `king_network_engines.dart`: رجیستری ۱۲ گزینه و نقش آن‌ها.
- `king_engine_sources.dart`: فهرست منابع و parserهای شناخته‌شده؛ این لایه موتور اجرا نمی‌کند.
- `king_auto_switch.dart`: هماهنگ‌کننده Dart؛ اکنون فقط adapterهایی با نقش full-device را وارد چرخه سوئیچ می‌کند.
- سوئیچ failover اکنون در صورت شکست teardown موتور قبلی متوقف می‌شود؛ تا وقتی آزادشدن TUN تأیید نشده موتور بعدی شروع نمی‌شود.
- ابزارهای local DPI از چرخه VPN مستقل جدا شده‌اند.
- فقط Xray در وضعیت integrated است. سایر گزینه‌ها هنوز adapter عملیاتی کامل ندارند.
- اجرای CI و تست دستگاه برای هر موتور باید قبل از ارتقای وضعیت آن به integrated انجام شود.

## مراحل پذیرش هر موتور

1. تثبیت upstream commit/tag و دریافت license و notices همه اجزا.
2. ساخت core برای ABIهای مورد پشتیبانی و بررسی اندازه، crash و مصرف حافظه.
3. پیاده‌سازی adapter بومی Android؛ بدون مالکیت هم‌زمان TUN.
4. اتصال parser/import و منبع سرور معتبر مختص پروتکل.
5. آزمون start/stop، network handover، process death، battery restrictions و عدم نشت DNS.
6. بررسی عبور واقعی TCP، UDP، IPv4، IPv6 و DNS.
7. آزمون failover و rollback به Xray.
8. سه بازبینی مستقل: معماری/regression، Android/security/licensing، و CI/device.

هیچ موتور با صرف ثبت در catalog یا اضافه‌شدن URL به‌عنوان «اضافه‌شده و آماده اتصال» معرفی نمی‌شود.
