# ممیزی فنی ادغام هستهٔ مستقل Hysteria 2 در KING VPN

وضعیت این سند: پژوهش و طراحی؛ **هسته هنوز به KING VPN اضافه یا روی دستگاه اجرا نشده است.**

## نتیجهٔ فنی

برای داشتن Hysteria 2 مستقل از Xray و sing-box، مسیر عملی قابل اتکا استفاده از Hysteria core در Go به‌همراه یک لایهٔ Android/Kotlin و یک TUN userspace stack است. نمونهٔ عملی قابل بررسی، پروژهٔ متن‌باز [Bedlam](https://github.com/0xSVV/Bedlam) است؛ این پروژه Hysteria 2 را درون فرایند اجرا می‌کند و به پراکسی محلی SOCKS/HTTP متکی نیست.

Bedlam خودش SDK رسمی Hysteria نیست؛ wrapper اندرویدی مستقلی است که از Hysteria core و sing-tun/gVisor استفاده می‌کند. بنابراین API و چرخهٔ عمر آن باید در KING بازطراحی و با معماری برنامه ادغام شود، نه اینکه یک APK یا UI خارجی به برنامه الصاق شود.

## شواهد upstream بررسی‌شده

- مخزن مرجع Android: [0xSVV/Bedlam](https://github.com/0xSVV/Bedlam)، مجوز مخزن GPL-3.0.
- commit مرجع بررسی‌شده: `3d914e9b131d2d82329f82f121dbc2701a0bca56`.
- Hysteria upstream submodule commit ثبت‌شده در Bedlam: `c2b181e0b0e72b077e4b0b7297735af14d1f9929`.
- toolchain اعلام‌شده در Bedlam: Go `1.26.8` و Android NDK `29.0.14206865`.
- نسخه‌های core اعلام‌شده: `app/v2.14.0`, `core/v2.14.0`, `extras/v2.14.0`.
- binding از مسیر `gomobile bind` و با build tag برابر `with_gvisor` ساخته می‌شود.
- وابستگی‌های Go شامل Hysteria core، `sing-tun` و fork سازگار gVisor هستند.

## API و lifecycle مورد نیاز

لایهٔ Kotlin مرجع، عملیات‌های اصلی را به شکل suspend ارائه می‌کند:

- `start(config, tunConfig, protector, tun)`: تا تکمیل handshake و اتصال TUN منتظر می‌ماند.
- `stop(reason)`: توقف هسته و بستن TUN را انجام می‌دهد.
- `updateTun(...)`: امکان جایگزینی TUN در یک نشست را فراهم می‌کند.
- `resetConnections()` و `checkConnection()`: بازیابی اتصال و بررسی زنده‌بودن نشست.
- `state`, `stats()`, `logs()`: وضعیت، شمارنده‌های ترافیک و گزارش رخدادها.

دو callback حیاتی برای Android:

1. **SocketProtector**: هر سوکت خروجی UDP باید پیش از bind با `VpnService.protect(fd)` محافظت شود تا مسیر اتصال QUIC دوباره وارد VPN نشود.
2. **TunFactory**: TUN باید توسط سرویس VPN اندروید ایجاد شود و FD آن به Go منتقل شود. در نمونهٔ مرجع، native core از FD کپی می‌گیرد؛ مالکیت و بستن descriptor باید دقیقاً مشخص باشد.

نمونهٔ مرجع از sing-tun و gVisor برای حمل TCP و UDP روی TUN استفاده می‌کند؛ این مسیر یک موتور واقعی انتقال ترافیک است، نه صرفاً parser لینک Hysteria.

## تصمیم‌های لازم برای KING VPN

1. **مالکیت TUN:** هستهٔ Hysteria باید پیش از ساخت TUN از `KingVpnEngineCoordinator` مالکیت بگیرد و فقط پس از توقف تأییدشدهٔ Go session، بسته‌شدن stack و FD، مالکیت را آزاد کند.
2. **ایزوله‌سازی Go runtime:** Hysteria یک binding مبتنی بر gomobile دیگر وارد می‌کند. پروژه هم‌اکنون Xray/libv2ray، libbox و WireGuard را دارد. اشتراک نام کلاس‌های gomobile یا حذف کلاس‌های تکراری به‌تنهایی سازگاری ABI/runtime را ثابت نمی‌کند. پیش از فعال‌سازی این هسته باید یکی از این معماری‌ها با تست واقعی انتخاب شود:
   - ادغام در یک Go runtime سازگار و واحد، با bindingهای کنترل‌شده؛ یا
   - اجرای موتور در process/service جداگانه و عبور امن FD و پیام‌ها از IPC.
3. **عدم رقابت برای TUN:** هیچ دو هسته‌ای نباید هم‌زمان `VpnService.Builder.establish()` را به‌عنوان مالک فعال فراخوانی کنند.
4. **قابلیت‌ها:** TLS/SNI، CA سفارشی، certificate pinning، احراز هویت، obfuscation، QUIC tuning، congestion control، port hopping، DNS و IPv6 باید بر اساس API و قابلیت واقعی core پیاده شوند؛ parser به‌تنهایی کافی نیست.
5. **ABI و toolchain:** نسخهٔ Go، NDK، gomobile، gVisor و تمام ABIهای مورد پشتیبانی KING باید صریح و قابل بازتولید pin شوند. فهرست ABI نمونهٔ Bedlam نباید به‌عنوان سقف معماری KING استفاده شود.
6. **مجوز:** Bedlam با GPL-3.0 منتشر شده است. اگر کد wrapper آن اقتباس شود، notices، تاریخچه/منبع و تعهدات GPL باید رعایت شوند. استفاده از upstream Hysteria و وابستگی‌های آن نیز نیازمند ثبت مجوز هر dependency و متناظرکردن سورس توزیع‌شده است.

## معیار پذیرش قبل از اعلام «هسته آماده»

- build reproducible برای همهٔ ABIهای پشتیبانی‌شدهٔ KING؛
- unit و integration test برای parser، TLS، احراز هویت، QUIC، DNS، IPv4/IPv6 و TCP/UDP؛
- تست Android واقعی برای permission، foreground service، protect، TUN FD ownership، revoke، network switch، stop timeout و process death؛
- تست handoff رفت‌وبرگشت با Xray، WireGuard و sing-box؛
- اثبات اینکه توقف هر هسته قبل از تحویل مالکیت، native runtime و TUN را واقعاً آزاد کرده است؛
- ثبت لاگ، traffic stats، خطایابی و recovery بدون نمایش وضعیت اتصال جعلی.

**نتیجه:** Hysteria 2 از نظر فنی قابل ادغام است و نمونهٔ Android واقعی دارد؛ اما به دلیل Go runtime و مالکیت TUN، تا عبور از تست‌های بالا نباید آن را هستهٔ آماده یا متصل‌شده اعلام کرد.
