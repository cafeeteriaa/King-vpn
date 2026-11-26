# ادغام هستهٔ مستقل libbox در KING VPN

## منبع و نسخه‌های پین‌شده
- Flutter plugin: QUSAD-prod/sing_box، نسخه 1.0.0، commit برابر 72f76fb714e07637a560774a7f2fdd3ae11884c4
- هستهٔ بومی: SagerNet/sing-box، نسخه 1.14.4
- Android AAR: libbox.aar، SHA-256 برابر d5511581e6275f10683f57bc8e7263badfa48c720d5d04acc741549fe6a66bae
- حجم AAR منتشرشده: 84,945,706 بایت؛ Gradle پیش از استخراج SHA-256 را بررسی می‌کند.

## معماری اجرا
- libbox از VpnService بومی و CommandServer خودش استفاده می‌کند؛ این parser یا هستهٔ نمایشی نیست.
- KingSingBoxCore پل Dart است و مجوز VPN را پیش از متوقف‌کردن موتور فعلی می‌گیرد.
- کانال king/vpn_engine_owner مالکیت انحصاری TUN را بین Xray، WireGuard و libbox هماهنگ می‌کند.
- handoff تا بستن descriptor و تأیید وضعیت توقف منتظر می‌ماند؛ در صورت ابهام مالکیت آزاد نمی‌شود.
- Xray و WireGuard حفظ شده‌اند و قابلیت‌های اختصاصی آن‌ها با افزودن libbox حذف یا محدود نمی‌شود.

## اعتبارسنجی
- source guards برای dependency pin، مجوزها، مسیر build و handoff اضافه شده‌اند.
- تأیید نهایی نیازمند CI سبز، ساخت APK arm64، نصب روی دستگاه و آزمون عبور ترافیک واقعی است.
- تا آن زمان وضعیت این هسته «ادغام‌شده در سورس؛ هنوز تأییدنشده روی دستگاه» است.

## مجوز و نام‌گذاری
کد plugin و libbox تحت GPL-3.0-or-later هستند و مجوز libbox بند عدم استفاده از نام/القای وابستگی به upstream دارد. متن مجوز و notices در licenses/sing_box نگهداری می‌شود. برنامه با نام KING VPN عرضه می‌شود و نباید خود را برنامهٔ رسمی SagerNet معرفی کند.
