# ممیزی فنی ادغام هستهٔ مستقل AmneziaWG در KING VPN

وضعیت: ممیزی upstream و طراحی adapter؛ **هنوز هسته در KING VPN ادغام یا روی دستگاه آزمایش نشده است.**

## منابع upstream بررسی‌شده

- مخزن Android رسمی: [amnezia-vpn/amneziawg-android](https://github.com/amnezia-vpn/amneziawg-android)، مجوز مخزن Apache-2.0.
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
