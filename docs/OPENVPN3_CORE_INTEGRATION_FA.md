# ممیزی فنی ادغام هستهٔ مستقل OpenVPN 3 در KING VPN

وضعیت: ممیزی upstream و طرح ادغام؛ **هنوز کد OpenVPN 3 در KING VPN ساخته یا اجرا نشده است.**

## مرجع و مجوز

- upstream رسمی: [OpenVPN/openvpn3](https://github.com/OpenVPN/openvpn3)
- commit بررسی‌شده: `ff9dd3cdb9b993002d46bd3152ecc153b5cc03bd`
- فایل API عمومی: `client/ovpncli.hpp`
- پیاده‌سازی: `client/ovpncli.cpp`
- رابط SWIG: `client/ovpncli.i`
- TUN builder: `openvpn/tun/builder/base.hpp`
- مجوز بالادستی: `MPL-2.0 OR AGPL-3.0-only WITH openvpn3-openssl-exception`.

برای KING VPN باید شاخهٔ MPL-2.0 به‌صورت روشن انتخاب و notices آن حفظ شود؛ مجوز همهٔ dependencyها، از جمله OpenSSL/mbedTLS، Asio، LZO، LZ4 و xxHash، جداگانه بررسی شود. انتخاب MPL، مجوزهای وابستگی‌ها را خودکار حل نمی‌کند.

## API واقعی کلاینت

کلاس `openvpn::ClientAPI::OpenVPNClient` یک API کلاینت C++ واقعی است و از این interfaceها ارث می‌برد:

- `TunBuilderBase`: ساخت TUN، تنظیم آدرس‌ها، routeها، DNS، MTU و teardown؛
- `LogReceiver`: دریافت گزارش‌ها؛
- `ExternalTun::Factory` و `ExternalTransport::Factory`: مسیرهای توسعهٔ transport/TUN؛
- `ExternalPKIBase`: callbackهای مربوط به PKI خارجی.

چرخهٔ اصلی:

1. ساخت شیء client و فراخوانی `eval_config()` برای بررسی profile؛
2. فراخوانی `provide_creds()` در صورت نیاز؛
3. اجرای `connect()` روی worker اختصاصی؛ این تابع تا قطع نشست برنمی‌گردد؛
4. دریافت رخدادها از `event()`، پیام‌های کانال سفارشی از `acc_event()` و لاگ‌ها از `log()`؛
5. توقف از thread دیگر با `stop()`؛
6. خواندن آمار از `stats_n()`, `stats_name()`, `stats_value()` و جزئیات اتصال از `connection_info()`.

بنابراین wrapper نباید `connect()` را روی Android main thread اجرا کند. رویداد `CONNECTED` نیز باید از callback واقعی هسته بیاید، نه از موفقیت ساخت شیء یا شروع worker.

## اتصال TUN اندروید

در `openvpn/tun/builder/base.hpp` خود OpenVPN 3، `TunBuilderBase` به‌عنوان abstraction مشابه Android `VpnService.Builder` تعریف شده است. core این callbackها را فراخوانی می‌کند:

- `tun_builder_new()`
- `tun_builder_set_layer()`
- `tun_builder_set_remote_address()`
- `tun_builder_add_address()`
- `tun_builder_add_route()` و `tun_builder_exclude_route()`
- `tun_builder_reroute_gw()`
- `tun_builder_set_dns_options()`
- `tun_builder_set_mtu()`
- `tun_builder_set_session_name()`
- `tun_builder_set_allow_family()`
- `tun_builder_establish()`
- `tun_builder_teardown()`

طبق contract هدر upstream، `tun_builder_establish()` باید FD رابط را برگرداند و مالکیت FD به caller منتقل می‌شود. در KING، callbackهای JNI باید تنظیمات را به `VpnService.Builder` متعلق به سرویس KING منتقل کنند؛ هیچ VpnService یا TUN مستقل دیگری برای OpenVPN ساخته نشود.

callback `socket_protect(socket, remote, ipv6)` در `OpenVPNClient` باید هر سوکت خروجی transport را با `VpnService.protect(fd)` از loop تونل خارج کند. شکست protect باید به هسته گزارش شود؛ نادیده‌گرفتن آن می‌تواند loop اتصال بسازد.

## معماری پیشنهادی KING

1. `KingOpenVpnCore` در Kotlin مالک session و lifecycle باشد.
2. یک JNI/C++ adapter محدود و version-pinned، `OpenVPNClient` و subclass callbackها را نگهداری کند.
3. پیش از هر `tun_builder_new/establish`، مالکیت از `KingVpnEngineCoordinator` گرفته شود.
4. تمام callbackهای TUN به یک `VpnService.Builder` متعلق به KING متصل شوند.
5. `connect()` در native worker اجرا شود؛ `stop()` از thread دیگر فراخوانی شود و join/exit واقعی worker و teardown TUN تأیید گردد.
6. coordinator فقط پس از پایان connect loop، callback teardown و بسته‌شدن FD مالکیت را آزاد کند.
7. callbackهای credentials، static/dynamic challenge، external PKI، SSO و app custom control به‌صورت رویدادهای قابل مدیریت در Flutter bridge شوند.
8. رویدادها، status، traffic stats، خطاها و reconnect/pause/resume باید از API واقعی OpenVPN 3 بیایند.

## build و ABI

OpenVPN 3 هستهٔ C++ است؛ باید CMake و NDK را برای ABIهای مورد پشتیبانی KING به‌کار برد. `client/CMakeLists.txt` نمونهٔ upstream، SWIG را برای Python تنظیم کرده و به‌تنهایی Android JNI آمادهٔ KING نیست. `javacli/android/cpu.cpp` نیز فقط helper مربوط به CPU usage است و adapter کامل VPN محسوب نمی‌شود.

پس باید یک JNI bridge اختصاصی و کمینه ساخته شود، نه اینکه وجود فایل `ovpncli.i` یا `cpu.cpp` به‌اشتباه به‌عنوان پشتیبانی کامل Android فرض شود. پیکربندی CMake، نسخهٔ NDK، toolchain، OpenSSL/mbedTLS، symbol visibility، exception boundary و ABIها باید pin و در CI بازتولید شوند.

## معیار پذیرش

- build release و debug برای هر ABI پشتیبانی‌شده؛
- تست parser/profile، TLS، UDP و TCP، احراز هویت، challenge، reconnect و certificate validation؛
- تست تمام callbackهای TUN، route، DNS، MTU، IPv4/IPv6 و socket protect؛
- تست Android VPN permission/revoke، network switch، foreground service، process death و stop timeout؛
- تست handoff رفت‌وبرگشت با Xray، WireGuard و sing-box؛
- اثبات آزادسازی TUN فقط پس از توقف قطعی native worker و تأیید teardown؛
- ثبت notices و سورس متناظر dependencyها و انتخاب مجوز MPL-2.0.

**نتیجه:** OpenVPN 3 یک هستهٔ مستقل C++ با API رسمی قابل استفاده است؛ ولی Android integration آمادهٔ کپی در مخزن upstream دیده نشد. برای KING یک JNI adapter و TUN builder اختصاصی لازم است. استفاده از `openvpn_flutter` به‌تنهایی جایگزین این ادغام نیست، زیرا lifecycle سرویس و مالکیت TUN باید با coordinator KING یکپارچه باشد.
