# وضعیت Psiphon در KING VPN

وضعیت: **ردشده برای ادغام در KING VPN؛ استفاده فقط از اپ رسمی مستقل Psiphon توسط کاربر.**

## تصمیم قطعی

Psiphon دیگر جایگزین یا هستهٔ قابل‌ادغام KING VPN محسوب نمی‌شود. کاربر ترجیح داده است اپ رسمی Psiphon را جداگانه نصب کند؛ بنابراین هیچ کتابخانه، AAR، سرویس، wrapper، SOCKS bridge، server entry یا تنظیمات شبکهٔ Psiphon نباید وارد APK عملیاتی KING VPN شود.

## علت

شرایط رسمی استفادهٔ Psiphon دسترسی به شبکهٔ Psiphon را به client appهایی محدود می‌کند که خود Psiphon منتشر کرده است و استفاده از third-party یا modified client ممکن است مسدود شود. این شرط حتی برای استفادهٔ شخصی نیز مسئله‌ساز است.

مجوز GPL-3.0 هستهٔ متن‌باز Psiphon فقط حقوق نرم‌افزار را پوشش می‌دهد و مجوز استفاده از شبکه و سرویس Psiphon را اعطا نمی‌کند. رایگان‌بودن یا شخصی‌بودن استفاده این شرط سرویس را برطرف نمی‌کند.

## سیاست اجرایی

- از Psiphon فقط از طریق اپ رسمی مستقل آن استفاده شود.
- هیچ بخشی از Psiphon برای دورزدن شرط client رسمی در KING VPN بازبسته‌بندی یا تغییر داده نشود.
- هیچ وابستگی یا منبع Psiphon در build عملیاتی KING VPN اضافه نشود.
- Xray، WireGuard و سایر هسته‌های KING بدون تغییر و مستقل باقی بمانند.
- جایگزین KING VPN در سند `docs/RISEUPVPN_CORE_INTEGRATION_FA.md` ثبت شده است.

## منابع رسمی

- شرایط استفاده: https://psiphon.ca/en/license.html
- هستهٔ متن‌باز: https://github.com/Psiphon-Labs/psiphon-tunnel-core
- کتابخانهٔ Android: https://github.com/Psiphon-Labs/psiphon-tunnel-core-Android-library

نسخه‌های قبلی Psiphon که در پیش‌نویس پژوهشی ثبت شده‌اند صرفاً سابقهٔ ممیزی هستند و نباید به‌عنوان نسخهٔ انتخاب‌شده یا تأییدشده برای KING تفسیر شوند.
