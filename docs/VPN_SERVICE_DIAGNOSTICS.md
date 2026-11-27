# قرارداد تشخیص وضعیت سرویس VPN بین زبان‌ها

## جریان داده

`KingVpnService.java` مالک وضعیت واقعی سرویس Android است. متد `diagnosticSnapshot()` فقط snapshot خواندنی و بدون تغییر وضعیت تولید می‌کند. `MainActivity.kt` آن را از کانال `king/diag` و متد `vpnService` به Flutter تحویل می‌دهد. `lib/main.dart` نتیجه را با نسخه پروتکل بررسی و در ژورنال تشخیصی ثبت می‌کند.

## نسخه و فیلدها

نسخه فعلی قرارداد: `protocolVersion = 1`

فیلدهای عملیاتی:
- وضعیت سرویس: `serviceRunning`, `active`, `stopping`, `retryWaiting`
- وضعیت هسته و بازیابی: `nativeBusy`, `recovering`
- نیت و حالت اتصال: `userStopped`, `nationalMode`
- شمارنده‌ها: `activeAttempt`, `attemptSequence`, `inFlightOperations`
- خطا بدون افشای متن خام: `lastErrorPresent`, `lastErrorCategory`

## حریم خصوصی و ایمنی

- snapshot شامل کانفیگ سرور، آدرس‌ها، شناسه‌ها، رمزها، فهرست پشتیبان یا remark نیست.
- متن خام استثنا یا `lastError` به Flutter ارسال نمی‌شود؛ فقط دسته‌بندی محدود خطا ارائه می‌شود.
- این متد صرفاً خواندنی است و هیچ تغییری در اتصال، watchdog، failover یا چرخه عمر سرویس نمی‌دهد.
- اگر سرویس فعال نباشد، Kotlin یک پاسخ معتبر با `serviceRunning=false` می‌دهد.
- نسخه قدیمی Android که متد را ندارد، در Dart به‌صورت MissingPluginException مدیریت می‌شود و مانع اجرای برنامه نمی‌شود.

## سازگاری

تغییر نام/نوع فیلدها یا معنای آن‌ها باید با افزایش نسخه پروتکل و به‌روزرسانی هم‌زمان Java، Kotlin، Dart و آزمون‌های Python انجام شود. آزمون‌های منبعی فقط سازگاری قرارداد را بررسی می‌کنند؛ اثبات رفتار واقعی دستگاه نیازمند تست روی Android فیزیکی است.
