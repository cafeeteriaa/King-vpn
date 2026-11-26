# ممیزی فنی ادغام هستهٔ مستقل AmneziaWG در KING VPN

وضعیت: ممیزی upstream و طراحی adapter؛ **هنوز هسته در KING VPN ادغام یا روی دستگاه آزمایش نشده است.**

## آخرین نسخهٔ پایدار upstream بررسی‌شده (ممیزی 2026-11-26)

- آخرین release رسمی Android: `v3.1.20260814`؛ وضعیت GitHub: Latest stable.
- commit دقیق این tag: `5c16489e2cd9ed3a0a7a27c7445bba5238132f86`.
- API JNI در همین release با wrapper فعلی `AmneziaWgNative.java` تطبیق داده شد.
- Go module در این release روی `amneziawg-go/v3 v3.1.20260814` و Go `1.25.0` است؛ Makefile upstream هنوز Go `1.24.2` pin کرده و این ناسازگاری باید پیش از ساخت native رفع و checksum ابزار ثبت شود.

## منابع upstream بررسی‌شده

- مخزن Android رسمی: [amnezia-vpn/amneziawg-android](https://github.com/amnezia-vpn/amneziawg-android)، مجوز مخزن Apache-2.0.
- commit بررسی‌شدهٔ مخزن: `5c16489e2cd9ed3a0a7a27c7445bba5238132f86`.
- API JNI در `tunnel/src/main/java/org/amnezia/awg/GoBackend.java`:
  - `awgTurnOn(ifName, tunFd, settings)`
  - `awgTurnOff(handle)`
  - `awgGetSocketV4(handle)`
  - `awgGetSocketV6(handle)`
  - `awgGetConfig(handle)`
  - `awgVersion()`
- پیاده‌سازی Go در `tunnel/tools/libwg-go/api-android.go` بر پایهٔ `github.com/amnezia-vpn/amneziawg-go/v3` است.
- نسخهٔ اعلام‌شده در go.mod: `amneziawg-go/v3 v3.1.20260814` و Go language version برابر `1.25.0`.
- موتور Go از CGo/JNI export استفاده می‌کند؛ API بالا gomobile `go.Seq` نیست.

## معماری صحیح برای KING

کلاس `GoBackend.java` در upstream، یک Backend کامل متصل به چرخهٔ عمر اپ Amnezia است. متد `setStateInternal` خودش سرویس VPN مربوط به Amnezia را راه‌اندازی می‌کند و `VpnService.Builder.establish()` را صدا می‌زند. استفادهٔ مستقیم از آن Backend در KING، مالک دوم TUN می‌سازد و با coordinator ناسازگار است.

راه ادغام مناسب، ساخت adapter مستقل KING روی JNI API است:

1. اعتبارسنجی و تبدیل پیکربندی AmneziaWG به قالب IPC مورد انتظار `awgTurnOn`.
2. گرفتن مالکیت از `KingVpnEngineCoordinator` پیش از ساخت TUN.
3. ساخت TUN با سرویس/Builder متعلق به KING و تحویل FD به `awgTurnOn`.
4. گرفتن سوکت‌های IPv4/IPv6 با `awgGetSocketV4/V6` و محافظت آن‌ها با `VpnService.protect(fd)` مطابق lifecycle هسته.
5. نگهداری handle و وضعیت واقعی موتور؛ توقف با `awgTurnOff(handle)` و تأیید پایان native worker قبل از بستن descriptor و آزادکردن مالکیت.
6. جمع‌آوری handshake، TX/RX، نسخه، خطاها و وضعیت از backend، بدون جعل حالت Connected.

## تداخل کتابخانه با WireGuard موجود

هر دو پروژهٔ WireGuard و AmneziaWG از کتابخانهٔ بومی با نام متداول `wg-go` استفاده می‌کنند. بسته‌بندی هم‌زمان دو فایل متفاوت با نام `libwg-go.so` در یک APK می‌تواند باعث انتخاب/بارگذاری کتابخانهٔ اشتباه شود.

برای جلوگیری از برخورد نام، در adapter اختصاصی KING باید خروجی AmneziaWG با نام مجزایی مانند `libawg-go.so` بسته‌بندی شود و loader فقط همان نام را بارگذاری کند. JNI exportهای کلاس `org.amnezia.awg.GoBackend` نیز باید با package/class دقیق هماهنگ بمانند. قبل از پذیرش نهایی، وجود هر دو کتابخانه در APK و بارگذاری هم‌زمان آن‌ها روی دستگاه واقعی باید آزمایش شود.

این تغییر نام به‌تنهایی سازگاری native symbolها، ABI یا رفتار دو Go runtime را اثبات نمی‌کند؛ تست runtime و در صورت مشاهدهٔ برخورد، جداسازی process لازم است.

## مجوز و زنجیرهٔ وابستگی

مخزن Android رسمی Apache-2.0 است، اما مجوز `amneziawg-go` و همهٔ وابستگی‌های CGo باید جداگانه از فایل‌های LICENSE و metadata همان commit استخراج و در `THIRD_PARTY_NOTICES.md` ثبت شود. مجوز مخزن میزبان به‌تنهایی مجوز تمام dependencyها را تعیین نمی‌کند.

## معیار پذیرش

- build قابل بازتولید Go/CGo و NDK برای تمام ABIهای مورد پشتیبانی KING؛
- آزمون import/export JNI، بارگذاری هم‌زمان `libwg-go.so` و `libawg-go.so` و نسخه‌های ABI؛
- تست config parsing، handshake، socket protection، IPv4/IPv6، DNS، MTU و آمار؛
- تست permission/revoke، توقف، crash، network change و بازیابی؛
- handoff رفت‌وبرگشت با Xray، WireGuard و sing-box؛
- اثبات اینکه فقط یک هسته در هر لحظه مالک TUN است و مالکیت پیش از توقف تأییدشده آزاد نمی‌شود.

**نتیجه:** AmneziaWG از نظر فنی قابل ادغام است، اما Backend upstream به‌صورت مستقیم قابل استفاده در KING نیست؛ adapter مبتنی بر JNI و TUN coordinator لازم است. WireGuard فعلی حفظ می‌شود و AmneziaWG جایگزین آن نخواهد شد.


## تکمیل ممیزی ABI و build (بازبینی 2026-11-26)

### API واقعی JNI و انتقال مالکیت FD

در commit upstream بالا، کلاس `org.amnezia.awg.GoBackend` صرفاً declaration متدهای native را ارائه می‌کند. فایل `tunnel/tools/libwg-go/jni.c` این JNI exportها را پیاده‌سازی می‌کند و به توابع Go متصل است:

- `awgTurnOn(ifName, tunFd, settings)` یک TUN FD از قبل ایجادشده را با `tun.CreateUnmonitoredTUNFromFD` می‌پذیرد.
- `awgTurnOff(handle)` موتور و TUN تحت مالکیت آن را می‌بندد.
- `awgGetSocketV4/V6(handle)` FD سوکت‌های outbound را برای `VpnService.protect(fd)` برمی‌گرداند.
- `awgGetConfig(handle)` وضعیت UAPI و شمارنده‌ها را می‌دهد.
- `awgVersion()` نسخهٔ موتور را برمی‌گرداند.

در نتیجه KING می‌تواند JNI wrapper باریک و اختصاصی خود را داشته باشد؛ لازم نیست کلاس Backend یا سرویس VPN upstream را وارد چرخهٔ اجرای اپ کند. پس از موفقیت `awgTurnOn`، مالکیت FD به موتور native منتقل می‌شود؛ مسیر خطا و توقف باید فقط پس از تأیید `awgTurnOff` منابع را آزاد کند. از آزادکردن زودهنگام PFD/FD جلوگیری شود.

### سه برخورد نام باینری، نه فقط یکی

در upstream commit `5c16489e2cd9ed3a0a7a27c7445bba5238132f86`، فایل `tunnel/tools/CMakeLists.txt` سه خروجی native تعریف می‌کند:

- `libwg-go.so`
- `libwg.so`
- `libwg-quick.so`

هر سه نام در بسته‌بندی WireGuard موجود KING استفاده می‌شوند یا با آن هم‌نام‌اند. بنابراین باید برای هر سه خروجی AmneziaWG نام مستقل تعیین شود؛ برای نمونه:

- `libawg-go.so`
- `libawg-tools.so`
- `libawg-quick.so`

تغییر باید به‌صورت هماهنگ در CMake targetها، Makefile target و SONAME، مسیر خروجی، JNI loader و تمام ارجاعات اجرایی انجام شود. صرف rename فایل نهایی بدون هماهنگی SONAME و loader کافی نیست. نام JNI exportهای `Java_org_amnezia_awg_GoBackend_*` باید با کلاس wrapper انتخابی دقیقاً تطبیق داشته باشد. هیچ‌یک از سه فایل WireGuard فعلی نباید overwrite یا حذف شود.

### ناسازگاری نسخهٔ Go در upstream

در همین commit، `tunnel/tools/libwg-go/go.mod` مقدار `go 1.25.0` را اعلام می‌کند، اما `tunnel/tools/libwg-go/Makefile` مقدار `GO_VERSION := 1.24.2` را pin کرده است. این دو مقدار ناسازگارند و نباید با فرض auto-download یا toolchain تصادفی نادیده گرفته شوند.

پیش از ادغام باید یکی از این دو مسیر با شواهد build انتخاب شود:
1. پین‌کردن Go 1.25.0 و ثبت SHA-256 رسمی آرشیوهای میزبان مورد استفاده، همراه با `GOTOOLCHAIN=local`؛ یا
2. اثبات سازگاری یک نسخهٔ دیگر با go.mod و ثبت همان نسخه و checksum به‌شکل reproducible.

نسخهٔ Go، NDK، CMake، submodule commitها و dependency graph باید همگی pin و در CI قابل‌تکرار باشند. submoduleهای upstream شامل `amneziawg-tools` و `termux-elf-cleaner` هستند و باید با commit دقیق دریافت شوند؛ دریافت branch شناور `master` در زمان build پذیرفته نیست.

### الزامات TUN coordinator در KING

- هستهٔ AmneziaWG باید پیش از `Builder.establish()` مالکیت `amneziawg` را از coordinator بگیرد.
- خود `KingVpnService` باید TUN را با تنظیمات Interface و AllowedIPs پروفایل بسازد؛ آدرس‌ها، routeهای IPv4/IPv6، DNS، MTU، excluded/included apps و kill-switch باید با semantics پیکربندی سازگار باشند.
- سپس FD جداشده به JNI داده و هر دو socket descriptor با `protect(fd)` محافظت شوند.
- توقف باید شامل native shutdown تأییدشده، بسته‌شدن handle، تأیید DOWN و سپس آزادسازی coordinator باشد.
- اگر shutdown یا آزادسازی TUN تأیید نشد، مالکیت باید حفظ شود و موتور بعدی اجازهٔ start نگیرد.
- مسیرهای crash، revoke permission، network change، service recreation و process death باید بازیابی یا پاک‌سازی امن داشته باشند.

### نتیجهٔ بازبینی

این ممیزی طراحی را دقیق‌تر کرده، اما هنوز هیچ فایل native از AmneziaWG وارد پروژه نشده و هیچ اتصال AmneziaWG روی دستگاه تأیید نشده است. مرحلهٔ بعدی، ساخت adapter و pipeline بومی با نام‌های مستقل و تست‌های ABI/ownership است؛ تا آن زمان نباید AmneziaWG در UI به‌عنوان هستهٔ آماده نمایش داده شود.
