# قرارداد تشخیص وضعیت سرویس VPN بین زبان‌ها

## جریان داده

`KingVpnService.java` مالک وضعیت واقعی سرویس Android است. متد `diagnosticSnapshot()` فقط snapshot خواندنی و بدون تغییر وضعیت تولید می‌کند. `MainActivity.kt` آن را از کانال `king/diag` و متد `vpnService` به Flutter تحویل می‌دهد. `lib/main.dart` نتیجه را با نسخه پروتکل بررسی و در ژورنال تشخیصی ثبت می‌کند.

## نسخه و فیلدها

نسخه فعلی قرارداد: `protocolVersion = 3` (Dart نسخه‌های ۱ و ۲ را نیز برای سازگاری می‌پذیرد).

فیلدهای عملیاتی:
- وضعیت سرویس: `serviceRunning`, `active`, `stopping`, `retryWaiting`
- وضعیت هسته و بازیابی: `nativeBusy`, `recovering`
- نیت و حالت اتصال: `userStopped`, `nationalMode`
- شمارنده‌های lifecycle: `activeAttempt`, `attemptSequence`, `inFlightOperations`
- سلامت watchdog: `watchdogChecks`, `healthyProbes`, `softProbeFailures`, `hardProbeFailures`
- بازیابی: `failoverCount`, `retryCount`, `currentFailureStreak`, `healthyStreak`
- آخرین probe: `lastProbeResult`, `lastProbeMode`, `lastProbeDurationMs`, `lastProbeAgeMs`
- مدت اجرای سرویس: `serviceUptimeMs`
- خطا بدون افشای متن خام: `lastErrorPresent`, `lastErrorCategory`

## حریم خصوصی و ایمنی

- snapshot شامل کانفیگ سرور، آدرس‌ها، شناسه‌ها، رمزها، فهرست پشتیبان یا remark نیست.
- متن خام استثنا یا `lastError` به Flutter ارسال نمی‌شود؛ فقط دسته‌بندی محدود خطا ارائه می‌شود.
- این متد صرفاً خواندنی است و هیچ تغییری در اتصال، watchdog، failover یا چرخه عمر سرویس نمی‌دهد.
- اگر سرویس فعال نباشد، Kotlin یک پاسخ معتبر با `serviceRunning=false` می‌دهد.
- نسخه قدیمی Android که متد را ندارد، در Dart به‌صورت MissingPluginException مدیریت می‌شود و مانع اجرای برنامه نمی‌شود.

## سازگاری

تغییر نام/نوع فیلدها یا معنای آن‌ها باید با افزایش نسخه پروتکل و به‌روزرسانی هم‌زمان Java، Kotlin، Dart و آزمون‌های Python انجام شود. آزمون‌های منبعی فقط سازگاری قرارداد را بررسی می‌کنند؛ اثبات رفتار واقعی دستگاه نیازمند تست روی Android فیزیکی است.


## مدل سنجش سلامت watchdog — نسخه ۲

سرویس Android مالک شمارنده‌هاست و زمان‌ها با ساعت monotonic اندروید (`SystemClock.elapsedRealtime`) محاسبه می‌شوند؛ تغییر ساعت دیوایس روی مدت‌ها اثر ندارد. شمارنده‌ها در طول عمر همان پردازه تجمعی‌اند و با restart پردازه از صفر آغاز می‌شوند.

- هر چرخهٔ watchdog یک بار در `watchdogChecks` شمرده می‌شود.
- وضعیت نامعلوم core از شکست probe جداست؛ این وضعیت به‌تنهایی failover ایجاد نمی‌کند و در `lastProbeResult=core_state_unknown` ثبت می‌شود.
- نتیجه‌های سالم، شکست نرم، شکست سخت و core خاموش با برچسب‌های محدود ثبت می‌شوند؛ هیچ URL، IP، host، پورت، نام سرور یا محتوای config وارد snapshot نمی‌شود.
- مدت آخرین probe و سن آن با میلی‌ثانیه monotonic گزارش می‌شود؛ مقدار سن `-1` یعنی هنوز probe ثبت نشده است.
- `failoverCount` فقط پس از موفقیت اتصال به سرور جایگزین افزایش می‌یابد؛ `retryCount` تعداد زمان‌بندی retry پس از شکست فهرست را می‌شمارد. منطق تصمیم‌گیری، آستانه‌ها، ترتیب سرورها و رفتار VPN/Proxy تغییر نمی‌کنند.
- snapshot در lock وضعیت سرویس جمع‌آوری می‌شود تا فیلدهای lifecycle و streak از یک تصویر سازگار خوانده شوند؛ شمارنده‌های تجمعی atomic هستند.

Dart نسخه‌های ۱ و ۲ را می‌پذیرد. نسخهٔ ۱ فقط اطلاعات پایه را ثبت می‌کند؛ نسخهٔ ۲ علاوه بر آن، telemetry watchdog را به ژورنال تشخیصی اضافه می‌کند.


## پایش مسیرهای فیزیکی و جابه‌جایی Wi-Fi/Cellular — پروتکل ۳

در نسخهٔ ۳، سرویس Android با `ConnectivityManager.NetworkCallback` فقط شبکه‌هایی را می‌بیند که هم `INTERNET` و هم `NOT_VPN` دارند و از نوع Wi-Fi یا Cellular هستند. این شرط مانع شمردن رابط مجازی VPN به‌عنوان مسیر زیرین می‌شود. در Androidهای دارای قابلیت اعتبارسنجی شبکه، فقط شبکه‌های `VALIDATED` در فهرست مسیرهای زیرین ثبت می‌شوند.

- شبکه‌های Wi-Fi و Cellular معتبر جداگانه شمرده می‌شوند؛ نام اپراتور، SSID، آدرس IP، شناسهٔ Network و مقصدهای ترافیک ثبت یا صادر نمی‌شوند.
- سرویس فهرست شبکه‌های فیزیکی معتبر را با Wi-Fi و سپس Cellular به `VpnService.setUnderlyingNetworks` معرفی می‌کند تا Android از تغییر مسیر زیرین مطلع بماند. این کار به‌تنهایی تضمین نمی‌کند که اتصال TCP هسته بدون وقفه باقی بماند؛ watchdog و health probe موجود همچنان مرجع سلامت تونل هستند.
- `physicalNetworkChangeCount`، `lastPhysicalNetworkChangeAgeMs` و شمارنده‌های شبکه فقط telemetry هستند؛ تغییر شبکه به‌تنهایی باعث تعویض سرور یا ریست هسته نمی‌شود.
- callback هنگام `onDestroy` آزاد می‌شود. خطای ثبت callback یا انتشار underlay نباید مانع راه‌اندازی یا خاموش‌شدن VPN شود.
- فیلدهای جدید: `physicalNetworkProtocolVersion`, `physicalNetworkChangeCount`, `lastPhysicalNetworkChangeAgeMs`, `validatedWifiNetworkCount`, `validatedCellularNetworkCount`, `physicalNetworkTransportSummary`.

Dart نسخه‌های ۱، ۲ و ۳ را می‌پذیرد. نسخهٔ ۳ فیلدهای underlay را به telemetry تشخیصی اضافه می‌کند؛ قرارداد v2 و v1 همچنان معتبرند.
