# ادغام هستهٔ مستقل libbox در KING VPN

## منبع و نسخه‌های پین‌شده
- Flutter plugin: QUSAD-prod/sing_box، نسخه 1.0.0، commit برابر 72f76fb714e07637a560774a7f2fdd3ae11884c4
- هستهٔ بومی: SagerNet/sing-box، نسخه 1.14.4
- Android AAR: آخرین artifact رسمی `libbox-v1.14.4-lx.25`، SHA-256 برابر `8f25b6600b2f1f1104636c9cb92941c756a6322e1f2ce0e5e97b9a6bc41d3bba`
- حجم AAR منتشرشده: 88,694,462 بایت؛ اسکریپت build، `android/libbox.properties` را به آخرین artifact پایدار pin می‌کند و Gradle پیش از استخراج SHA-256 را بررسی می‌کند.

انتشار رسمی Android artifact در زمان ممیزی: [libbox-v1.14.4-lx.25](https://github.com/QUSAD-prod/sing_box/releases/tag/libbox-v1.14.4-lx.25). هستهٔ sing-box همچنان `v1.14.4` است؛ پسوند `lx.25` نسخهٔ انتشار artifact اندروید است، نه نسخهٔ مستقل core.

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
