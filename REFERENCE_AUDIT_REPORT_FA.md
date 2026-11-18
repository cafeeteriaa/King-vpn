# گزارش ممیزی فنی King VPN — نسخه v8.5

**تاریخ بررسی:** 2026-11-17  
**مبنای بررسی:** `King-vpn-v8_5.zip` به‌همراه `src.zip` و `lib.zip` پلاگین  
**نوع بررسی:** تحلیل ایستا و بازبینی مسیرهای بحرانی Dart/Flutter، Android Java/Kotlin، پلاگین V2Ray/Xray، اسکریپت‌های Python و CI  
**وضعیت Build/Runtime:** هیچ Build یا تست روی گوشی انجام نشده است؛ تست دستگاه با کاربر است.

---

## 1. دامنه و محدودیت‌ها

- بسته‌ی اصلی v8.5 شامل **46 فایل واقعی** است. سورس پلاگین جداگانه شامل 16 فایل Java و 11 فایل Dart است؛ در مجموع 73 فایل در مجموعه‌ی بررسی‌شده حضور دارند.
- فایل‌های بحرانی مانند `main.dart`, `nat_ultra.dart`, `nip_scan.dart`, `ip_auto_scan.dart`, `dns_scanner.dart`, `national_engine.dart`, `iran_ai_extras.dart`, `auto_test.dart`, `V2rayCoreManager.java`, `V2rayVPNService.java`, `V2rayProxyOnlyService.java`, `V2rayController.java`, `FlutterV2rayPlugin.java` و اسکریپت‌های ساخت، با تمرکز عمیق بررسی شدند. فایل‌های داده‌ای و UI کم‌ریسک‌تر با مرور ساختاری، جست‌وجوی مسیرهای فراخوانی و بررسی بخش‌های مرتبط پوشش داده شدند؛ **ادعای خواندن انسانیِ تک‌تک خطوط تمام فایل‌های بسیار بزرگ را نمی‌کنم**.
- آرشیو v8.5 شامل `pubspec.yaml`, `pubspec.lock`, پروژه‌ی کامل Gradle و Manifest اصلی Flutter نیست. Workflow یک پروژه‌ی Flutter جدید می‌سازد و سورس‌ها را در آن قرار می‌دهد؛ بنابراین Build مستقل از همین ZIP ممکن نیست.
- محیط بررسی، Flutter/Dart SDK در اختیار نداشت. `python -m py_compile` برای دو اسکریپت Python موفق شد و `patch_plugin.py` روی یک کپی ایزوله از سورس پلاگین اجرا شد و تمام anchorهای پچ را پیدا کرد. این **جایگزین Build Gradle یا تست دستگاه نیست**.
- `kOwnVpnService=false` است؛ مسیر فعال اتصال، سرویس‌های پلاگین `V2rayVPNService` و `V2rayProxyOnlyService` هستند. ایرادهای `android_src/KingVpnService.java` و `MainActivity.kt` که به سرویس اختصاصی مربوط‌اند، در وضعیت فعلی مشروط/غیرفعال محسوب می‌شوند.

## 2. نتیجه‌ی اجرایی

بزرگ‌ترین مشکل نسخه‌ی فعلی، خود Core نیست؛ **عدم تفکیک سلامت اینترنت داخلی و جهانی در مسیر اتصال، واچ‌داگ و خودترمیمی** است. چند قسمت نت ملی، مقصد داخلی دارند، اما مسیر اصلی شروع اتصال و پایش پس از اتصال هنوز به مقصدهای جهانی وابسته است. بنابراین در شرایطی که اینترنت جهانی قطع و اینترنت داخلی برقرار است، برنامه می‌تواند کانفیگ سالم را رد کند یا اتصال داخلی سالم را Failover کند.

دسته‌ی دوم مشکلات، اسکن‌های گسترده و ناعادلانه است: برخی اسکن‌ها از IP یک DNS یا سرور به سه بلوک `/24` همسایه گسترش پیدا می‌کنند، اسکن دامنه‌ها تا پورت‌های بسیار زیاد ادامه دارد، و کرسر ملی در چند مسیر جلو نمی‌رود. علاوه بر ریسک مجوز/عملیات، این طراحی باعث تکرار کار و پوشش ناقص می‌شود.

دسته‌ی سوم، چرخه‌ی عمر سرویس پلاگین است: مسیرهای STOP و خطا در بعضی شرایط سرویس را متوقف نمی‌کنند، خطای شروع Core وضعیت CONNECTING را باقی می‌گذارد، و EventChannel/BroadcastReceiver در چرخه‌ی detach/reattach به‌درستی پاک‌سازی نمی‌شود.

---

## 3. یافته‌های بحرانی — اولویت P0

### P0-1 — تست جهانی در مسیر شروع اتصال، نت ملی را رد می‌کند
**فایل:** `lib/main.dart:8512-8540` و مسیرهای `_connectLoop` / `_pingUrls`  
**علت:** `_startImpl` پس از شروع Core از `pingAny()` استفاده می‌کند که مقصدهایش جهانی‌اند؛ مجموعه‌ی `_tunnelTestUrlsNational` وجود دارد، اما این گیت اولیه در حالت ملی به آن سوئیچ نمی‌کند.  
**اثر:** اگر Google/Cloudflare/Telegram در دسترس نباشند، ولی Aparat/Digikala و ترافیک داخلی از TUN عبور کنند، کانفیگ سالم ممکن است رد شود.  
**اصلاح:** تابع واحد `probeTunnel(mode)` بسازید. در حالت ملی فقط مقصدهای داخلیِ HTTPS با اعتبارسنجی گواهی/کد پاسخ مناسب را در گیت اتصال اولیه استفاده کنید. سلامت جهانی را جداگانه ثبت کنید، نه به‌عنوان شرط لازم اتصال داخلی.

### P0-2 — واچ‌داگ بعد از اتصال فقط پینگ جهانی را ملاک می‌گیرد
**فایل:** `lib/main.dart:13155-13275` و `_pingUrls`  
**علت:** `pingAny()` در چرخه‌ی پایش به مقصدهای جهانی متکی است.  
**اثر:** اتصال داخلی سالم می‌تواند به‌دلیل قطع بین‌الملل Failover شود.  
**اصلاح:** دو سنجه‌ی مستقل بسازید: `domesticTunnelHealth` و `globalTunnelHealth`. در حالت ملی، Failover فقط بر اساس سلامت داخلی/ترافیک واقعی TUN انجام شود؛ قطع جهانی باید وضعیت «داخلی برقرار، جهانی قطع» بسازد.

### P0-3 — تست سرعت Cloudflare باعث Failover اتصال داخلی سالم می‌شود
**فایل:** `lib/main.dart:551-552,13165-13225`  
**علت:** `speedUrl` و `smallSpeedUrl` هر دو روی `speed.cloudflare.com` هستند. واچ‌داگ هر حدود 30 ثانیه تست کوچک انجام می‌دهد و پس از سه پاسخ ناموفق، پیش از بررسی سایت‌های داخلی Failover می‌کند.  
**اثر:** در اینترنت ملی، Cloudflare ممکن است در دسترس نباشد؛ اتصال داخلی سالم بعد از چند چرخه قطع/تعویض می‌شود.  
**اصلاح:** برای حالت ملی، endpoint داخلیِ تحت کنترل/مجوز با payload مشخص، HTTPS معتبر، status و اندازه‌ی معلوم فراهم کنید. تا وقتی چنین endpointی ندارید، شکست تست سرعت جهانی نباید `noData` یا Failover داخلی تولید کند.

### P0-4 — DNS پیش‌فرض پلاگین جهانی است و در حالت ملی حفظ می‌شود
**فایل:** `lib/url/url.dart:117-120` از `lib.zip`; `lib/main.dart:2818-2866`  
**علت:** parser پلاگین برای کانفیگ‌های بدون DNS، `8.8.8.8` و `8.8.4.4` می‌گذارد. `_reliableVpnCfg()` هر DNS غیرخالی را حفظ می‌کند و فقط وقتی DNS خالی باشد DNS ایرانی اضافه می‌کند.  
**اثر:** کانفیگ تولیدشده‌ی معمولی در حالت ملی می‌تواند از همان ابتدا به DNS جهانی وابسته باشد؛ fallback ایرانی اجرا نمی‌شود.  
**اصلاح:** DNS تولیدشده‌ی پیش‌فرض را از DNS صریحِ داخل کانفیگ کاربر جدا کنید. در حالت ملی، فقط defaultهای تولیدشده را به DNS ایرانیِ اعتبارسنجی‌شده تبدیل کنید؛ DNS سفارشی کاربر را بدون دلیل تغییر ندهید.

### P0-5 — کانفیگ اختصاصی Reality با DNS جهانی قبل از کانفیگ ملی امتحان می‌شود
**فایل:** `lib/main.dart:3441-3444,3486-3572,8342-8396`  
**علت:** `useOwnVlessCfg=true` است؛ `vlessRealityOwnCfg()` DNSهای `1.1.1.1` و `8.8.8.8` را hardcode می‌کند و در فهرست تلاش‌ها قبل از کانفیگ معمولی قرار می‌گیرد. در حالت ملی، هر تلاش می‌تواند 18 ثانیه منتظر بماند و سپس حدود 2.5 ثانیه برای توقف/آماده‌سازی مسیر بعدی صرف شود.  
**اثر:** یک تلاش نامناسب می‌تواند بیش از 20 ثانیه تأخیر ایجاد کند و در کانفیگ دامنه‌ای Reality، DNS جهانی ممکن است اصلاً پاسخ ندهد.  
**اصلاح:** این builder باید از همان سیاست DNS mode-aware مسیر اصلی استفاده کند؛ SNI را از `sni`، سپس `host` معتبر و در نهایت hostname مقصد استخراج کند. اگر در حالت ملی پیش‌شرط‌های Reality آماده نیست، این مسیر را پیش از شروع حذف کنید.

### P0-6 — تنظیمات امنیت DNS و مسیر ایران در UI به کانفیگ واقعی وصل نیستند
**فایل‌ها:** `lib/npv_am_extras.dart:941-1110`, `lib/iran_ai_extras.dart:38-90`  
**علت:** `withNpvAmCore()` و `withIranRouting()` تنها محل اعمال چند گزینه‌اند، اما در کل سورس هیچ call-site برای آن‌ها پیدا نشد.  
**گزینه‌های بی‌اثر یا بی‌اتصال:** `secureDns`, `blockQuic`, `lanDirect`, `iranMore`, `iranRoute`, `iranGeoip`; `routeOnly` نیز از preference خوانده نمی‌شود و در `_reliableVpnCfg()` برای inboundهای تازه hardcode شده است.  
**اثر:** گزینه‌ها ذخیره/نمایش داده می‌شوند ولی در JSON نهایی اعمال نمی‌شوند؛ سایت‌های ایرانی ممکن است برخلاف انتخاب کاربر از تونل عبور کنند و DoH/QUIC/LAN-direct هم مطابق UI تغییر نکند.  
**اصلاح:** یک pipeline نهایی واحد بسازید: `parse -> normalize -> applyDnsPolicy -> applyIranRouting -> applyTransportPolicy -> validate -> serialize`. همه‌ی تنظیمات باید فقط در همین مسیر اعمال شوند و برای true/false هر گزینه تست داشته باشید. `geoip:ir` را فقط در صورت وجود و اعتبار فایل GeoIP فعال کنید.

### P0-7 — اسکن ملی از IP یک DNS/سرور، همسایه‌های `/24` را هم اسکن می‌کند
**فایل:** `lib/nat_ultra.dart:1983-2022,2155-2201`  
**علت:** `natSeedBlocks()` از `natIpMemHosts()`, `natDeviceHosts()` و `natIranDnsHosts` برای هر IP چند بلوک `/24` می‌سازد. فهرست DNS شامل IPهای خصوصی `10.202.10.10` و `10.202.10.11` هم هست.  
**اثر:** اسکن آدرس‌های همسایه‌ی ISP/میزبان‌های ثالث و حتی بلوک‌های خصوصی اپراتور، بدون اینکه مالکیت یا مجوز آن بازه معلوم باشد. یک IP DNS یا یک endpoint کانفیگ، مجوز اسکن کل subnet نیست.  
**اصلاح:** گسترش `/24` از DNS، IP رابط دستگاه و endpointهای تک‌سرور حذف شود. فقط endpointهای دقیق استخراج‌شده از کانفیگ‌ها و CIDRهای صریحاً متعلق به کاربر/دارای مجوز تست شوند.

### P0-8 — اسکن دامنه‌های عمومی و پورت‌های بسیار زیاد روی میزبان‌های نامرتبط
**فایل:** `lib/nat_ultra.dart:1931-1980` و `_natRangeAdd`  
**علت:** `_natDomainFirst` دامنه‌های عمومی را resolve می‌کند و روی IPهای به‌دست‌آمده پورت‌های متداول و حتی بازه‌ی 1 تا 65535 را اسکن می‌کند؛ سپس IPها را با credential کانفیگ‌های موجود ترکیب می‌کند.  
**اثر:** ریسک عملیاتی/مجوزی، بار زیاد شبکه و تولید candidateهای بی‌اعتبار.  
**اصلاح:** این مسیر عمومی حذف شود. فقط IP/port موجود در کانفیگ واقعی، endpointهای رسمیِ مستندشده یا بازه‌های دارای مجوز بررسی شوند. TCP-open به‌تنهایی هرگز سرور سالم محسوب نشود.

### P0-9 — اسکن ملی اصلی در هر دور از ابتدای فهرست تکرار می‌شود
**فایل:** `lib/nat_ultra.dart:2180-2184`; فراخوانی `lib/main.dart:10673-10680`  
**علت:** در `nationalMode` مقدار `from=0` ثابت است و `natRangeCursor` جلو نمی‌رود.  
**اثر:** همان اولین slice تا 100,000 آدرس در دورهای بعدی تکرار می‌شود و باقی pool فرصت بررسی پیدا نمی‌کند.  
**اصلاح:** cursor ملی پایدار و cursor مستقل برای هر CIDR پیاده کنید؛ پس از هر slice تکمیل‌شده cursor جلو برود و بلوک‌ها به‌صورت fair interleave شوند.

### P0-10 — اسکنر خودکار IP پشت اسکن DNS برای همیشه starve می‌شود
**فایل:** `lib/main.dart:10168-10170`; `lib/dns_scanner.dart:282-285`; `lib/ip_auto_scan.dart:104-108`  
**علت:** `dnsxAutoPick()` پیش از اولین `await` پرچم `_dnsxAutoBusy=true` را می‌گذارد؛ بلافاصله بعد `ipAutoBackground()` همان پرچم را می‌بیند و خارج می‌شود. در فراخوانی‌های بعدی نیز ترتیب تکرار می‌شود.  
**اثر:** IP-auto ممکن است عملاً هیچ‌وقت شروع نشود.  
**اصلاح:** این دو کار را در scheduler مشترک و ترتیبی قرار دهید؛ پس از اتمام DNS، IP scan اجرا شود یا اولویت/نوبت صریح داشته باشند.

### P0-11 — اسکنر خودکار IP به `kNatIpScanOn` احترام نمی‌گذارد
**فایل:** `lib/ip_auto_scan.dart:104-108,167-206`; فراخوانی `lib/main.dart:10168-10170`  
**علت:** این entry point مستقل هیچ بررسی از `kNatIpScanOn` ندارد.  
**اثر:** خاموش‌کردن اسکن در تنظیم/گیت اصلی، این اسکنر را متوقف نمی‌کند.  
**اصلاح:** تمام entry pointهای اسکن از یک `ScanPolicy` مرکزی عبور کنند؛ UI وضعیت واقعی را نشان دهد.

### P0-12 — IP-auto فقط prefix محدودی از 2,851 CIDR را بارها تکرار می‌کند
**فایل:** `lib/nat_ultra.dart:2098-2115`; `lib/ip_auto_scan.dart:77-95`  
**علت:** `_genAddrsIso()` هر بار از ابتدای `blocks` می‌سازد و با cap متوقف می‌شود؛ `ipAutoPos` فقط داخل همین فهرست محدود می‌چرخد و به cursor بلوک‌ها متصل نیست. با `cfIpsBatch=6000`، حدود 18,000 نمونه‌ی باقی‌مانده برای ISPها (تقریباً 70 بلوک 256تایی) از ابتدای فهرست گرفته می‌شود.  
**اثر:** بخش بزرگی از CIDRهای بعدی هیچ‌وقت نوبت نمی‌گیرند.  
**اصلاح:** `blockCursor` و cursor درون هر CIDR را پایدار ذخیره کنید؛ فهرست capped از ابتدا بازتولید نشود.

---

## 4. یافته‌های High — اولویت P1

### P1-1 — کانفیگ اصلی بدون تغییر در کشف سرور ملی حذف می‌شود
**فایل:** `lib/main.dart:7794-7805`  
در حالت ملی `v==0` از `_delayOf()` حذف می‌شود. `_findGood()` از همین delay برای ورود سرور به فهرست سالم استفاده می‌کند (`7537-7572`). سروری که فقط با کانفیگ اصلی کار می‌کند ممکن است پیش از اتصال واقعی کنار گذاشته شود. اول کانفیگ اصلی را یک بار با مقصد داخلی تست کنید، سپس سراغ variantها بروید.

### P1-2 — DNS auto-pick یک ثانیه فرصت دارد، درحالی‌که probe دو ثانیه طول می‌کشد
**فایل:** `lib/main.dart:11554-11557`; `lib/npv_am_extras.dart:132-139`  
اولین اتصال اغلب با `dnsProvActive` قدیمی ساخته می‌شود و probe تازه در پس‌زمینه تمام می‌شود. بودجه‌ی انتخاب اولیه را 2–3 ثانیه کنید یا در حالت ملی از resolver داخلی شناخته‌شده شروع کنید.

### P1-3 — DNS cache به شبکه/اپراتور/حالت ملی وابسته نیست
**فایل:** `lib/npv_am_extras.dart:20-21,147-150,202-205`  
DNS انتخاب‌شده روی Wi-Fi ممکن است تا 10 دقیقه پس از جابه‌جایی به اپراتور یا حالت ملی حفظ شود. cache باید با network generation، اپراتور و national/global mode کلید بخورد و در تغییر شبکه invalidate شود.

### P1-4 — IP-auto پورت اسکن‌شده را در URI کانفیگ نمی‌نویسد
**فایل:** `lib/ip_auto_scan.dart:228-244`  
`Server` با فیلد `port` اسکن‌شده ساخته می‌شود، اما `_natSetHost()` فقط host را تغییر می‌دهد. `natCfg()` و `buildCoreConfig()` از `s.link` می‌خوانند، پس ممکن است پورت اصلی template تست شود ولی نتیجه با `ip|scannedPort` ذخیره شود. پیش از تست، port را در URI بنویسید و دوباره parse کنید.

### P1-5 — IP-auto نتیجه‌ی Core outbound را به‌عنوان IP سالم ذخیره می‌کند، نه سلامت TUN
**فایل:** `lib/ip_auto_scan.dart:152-164,231-240`  
`getServerDelay()` یک تست outbound با Core موقت است و ترافیک واقعی Android TUN را ثابت نمی‌کند. نتیجه فقط باید `coreReachable` باشد؛ ارتقا به clean/healthy بعد از اتصال واقعی و تست ترافیک داخلی/جهانی TUN انجام شود.

### P1-6 — زمان ذخیره‌شده به‌عنوان ping، مجموع زمان دو تست است
**فایل:** `lib/ip_auto_scan.dart:230-240`  
`Stopwatch` قبل از دو تست شروع می‌شود و کل زمان شامل queue و ساخت config را به‌عنوان `CleanIp.elapsedMs` ذخیره می‌کند. RTT واقعی هر probe را ذخیره کنید؛ زمان کل اسکن را جدا نگه دارید.

### P1-7 — Reality از تغییرات DNS-only هم محروم می‌شود
**فایل:** `lib/nat_ultra.dart:649-653`; `lib/main.dart:7803`  
`_natChangesAddr()` وجود DoH را تغییر endpoint می‌داند و همه‌ی این variantها را برای Reality رد می‌کند. تغییر resolver با تغییر host/port یکی نیست. این دو دسته را جدا کنید و resolver-only را در شرایط امن مجاز کنید.

### P1-8 — SNI matrix یک خانه‌ی no-op دارد و SNI IP literal هم نامعتبر است
**فایل:** `lib/nat_ultra.dart:198,1202-1203`; `lib/nip_scan.dart:246-255,645`  
اندیس 10 درحالی‌که فهرست SNI فقط 0–7 است، به کانفیگ بدون تغییر منتهی می‌شود. همچنین `1.1.1.1` به‌عنوان SNI آمده؛ SNI باید hostname باشد. اندیس را validate کنید و IP literal را حذف کنید.

### P1-9 — Mux و Noise در matrix عملاً غیرفعال‌اند
**فایل:** `lib/nat_ultra.dart:640-641`  
`_natAppliesF()` برای Mux/Noise همیشه false می‌دهد؛ variantهای تعریف‌شده هیچ‌وقت اجرا نمی‌شوند. اگر عمداً غیرفعال‌اند، از UI/نام matrix حذف یا Disabled علامت‌گذاری شوند؛ اگر قرار است فعال شوند، فقط پس از تست سازگاری Core.

### P1-10 — variantهای تکراری در ماتریس
**فایل:** `lib/nat_ultra.dart` بخش `_natBase` و `_natExtra`  
`fp=360` و `fp=qq` در دو مجموعه تکرار شده‌اند. قبل از اجرای matrix با signature پایدار و canonical dedupe کنید.

### P1-11 — نتیجه‌ی delay مثبت، variant را برنده ثبت می‌کند بدون اثبات TUN
**فایل:** `lib/main.dart:7842-7852` و مسیرهای `_delayOnce`, `natVarSet`  
Core outbound delay، TUN traffic و stable tunnel سه مرحله‌ی جدا هستند. موفقیت مرحله‌ی اول نباید به‌عنوان پیروزی نهایی/یادگیری پایدار ثبت شود.

### P1-12 — `natDohUsable` پروتکل DNS کلاسیک را با DoH یکی می‌گیرد
**فایل:** `lib/nat_ultra.dart:1078-1114`  
TCP/443 یا TLS به IP یک DNS resolver، اثبات DoH نیست؛ DNS کلاسیک UDP/TCP 53، DoT روی 853 و DoH با TLS+HTTP+DNS response باید جدا probe شوند.

### P1-13 — parser پاسخ DNS مالک رکورد را بررسی نمی‌کند
**فایل:** `lib/nnie_core.dart:173-189`  
یک A record نامرتبط در پاسخ می‌تواند به‌عنوان جواب دامنه‌ی پرسیده‌شده پذیرفته شود. QNAME و CNAME chain و owner name را validate کنید.

### P1-14 — endpointهای داخلی/جهانی در وضعیت شبکه تفکیک نشده‌اند
**فایل:** `lib/net_state.dart:9-19`; `lib/king_heal.dart:498-506`  
State machine وضعیت «داخلی برقرار، جهانی قطع» ندارد و ممکن است آن را قطعی کامل گزارش کند. حالت `domesticOnly` اضافه شود.

### P1-15 — self-heal بر اساس ping جهانی می‌تواند اتصال ملی سالم را دستکاری کند
**فایل:** `lib/king_heal.dart:230-249`  
سیگنال ping/speed بدون mode و مقصد داخلی/جهانی تفسیر می‌شود. سلامت داخلی و جهانی باید مستقل باشند.

### P1-16 — self-heal می‌تواند بدون اجرای عمل، موفقیت گزارش کند
**فایل:** `lib/king_heal.dart:373-377,388-395,420-434`  
برخی actionها وقتی `busy/switching` هستند هیچ کاری نمی‌کنند ولی `true` برمی‌گردانند. نتیجه را به enum مانند `performed/skipped_busy/failed/verified` تبدیل کنید.

### P1-17 — self-heal mutex واقعی ندارد
**فایل:** `lib/king_heal.dart:65-78,124-137`  
rate limit چهارثانیه‌ای مانع هم‌پوشانی چرخه‌ای که بیش از چهار ثانیه طول می‌کشد نیست. `kingHealBusy` یا Future مشترک به‌عنوان mutex استفاده شود.

### P1-18 — `withNpvAmCore()` و `withIranRouting()` بدون call-site هستند
**فایل‌ها:** `lib/npv_am_extras.dart:941-1110`; `lib/iran_ai_extras.dart:38-90`  
گزینه‌های DNS امن، block QUIC، LAN direct، routeOnly، Iran-more، Iranian direct و geoip:ir به مسیر اصلی config وصل نیستند. یک pipeline واحد ساخت config بسازید و این تبدیل‌ها را آنجا اعمال کنید.

### P1-19 — WebSocket path پیش‌فرض نوع داده‌ی اشتباه دارد
**فایل:** `lib/url/url.dart:247-254` در `lib.zip`  
`wsSettings.path` با `path ?? ['/']` ساخته می‌شود؛ schema آن string است. پیش‌فرض باید `'/'` باشد. H2 path آرایه‌ای است و نباید با WS یکی شود.

### P1-20 — VMess URL-safe Base64 در app پذیرفته می‌شود اما plugin نمی‌تواند decode کند
**فایل‌ها:** `lib/main.dart:3703-3708`; `lib/url/vmess.dart:18-25`  
app `-/_` و padding ناقص را normalize می‌کند؛ plugin فقط `base64Decode` استاندارد دارد. decoder مشترک استاندارد/URL-safe بسازید.

### P1-21 — VMess بدون فیلد `net` در app پذیرفته می‌شود ولی plugin خطا می‌دهد
**فایل‌ها:** `lib/main.dart:3720-3722`; `lib/url/vmess.dart:27-36`  
app مقدار پیش‌فرض tcp می‌گذارد؛ plugin `rawConfig['net']` را مستقیم به پارامتر non-null می‌دهد. در plugin نیز default tcp اعمال شود.

### P1-22 — SNI در parserها fallback مطمئن به hostname مقصد ندارد
**فایل‌ها:** `lib/url/trojan.dart:35-60`, `lib/url/vless.dart:21-45`, `lib/url/vmess.dart:27-47`; `main.dart:3720-3722,3745`; `main.dart:3541`  
در برخی لینک‌های TLS/Reality بدون query `sni`، مقدار خالی می‌ماند؛ fallback باید `sni -> transport host -> endpoint hostname` باشد.

### P1-23 — Shadowsocks parser ممکن است لینک malformed را با method=none/password خالی قبول کند
**فایل:** `lib/url/shadowsocks.dart:23-32`; `main.dart:3697-3705`  
SIP002/legacy باید strict parse شوند؛ method معتبر و password غیرخالی لازم است. Base64 URL-safe هم normalize شود.

### P1-24 — پشتیبانی end-to-end از Hysteria2/SOCKS در app با parser پلاگین هم‌سطح نیست
**فایل:** `lib/main.dart:3697-3705`; parserهای plugin در `lib/url/`  
پلاگین parserهایی دارد اما `Server.parse` آن‌ها را نمی‌پذیرد. یا end-to-end پشتیبانی شود یا UI/مستندات صریحاً unsupported نشان دهد.

### P1-25 — `fetchServers` و حافظه‌ی endpoint، کانفیگ‌های متمایز را با host:port یکی می‌گیرند
**فایل:** `lib/main.dart:4751-4825` و `Server.key`  
UUID، protocol، Reality pbk/sid، SNI، WS path و flow متفاوت ممکن است حذف شوند. دو کلید بسازید: `endpointKey` و `configKey` canonical SHA-256.

### P1-26 — `_natRangeAdd` و IP-auto پورت اسکن‌شده را در URI نمی‌نویسند
**فایل‌ها:** `lib/main.dart:10439-10465`; `lib/ip_auto_scan.dart:213-235`  
Server object ممکن است `port` جدید داشته باشد اما config builder از link خام بخواند. URI را تغییر دهید و دوباره parse کنید.

### P1-27 — `V2rayCoreManager.startCore()` در failure وضعیت CONNECTING و timer را باقی می‌گذارد
**فایل:** `src/.../V2rayCoreManager.java:235-273`  
Timer و CONNECTING پیش از بررسی `isLibV2rayCoreInitialized` شروع می‌شوند؛ early-return/catch آن‌ها را cancel و DISCONNECTED broadcast نمی‌کند. در تمام failureها timer cancel، state reset، broadcast خطا و service cleanup انجام شود.

### P1-28 — STOP وقتی Core از قبل متوقف است، Android Service را متوقف نمی‌کند
**فایل:** `src/.../V2rayCoreManager.java:290-300`; `V2rayVPNService.java:92-95`; `V2rayProxyOnlyService.java:59-62`  
`stopCore()` فقط وقتی Core running باشد `listener.stopService()` را صدا می‌زند. STOP باید مستقل از Core همیشه `stopForeground`، cleanup و `stopSelfResult(startId)` را اجرا کند.

### P1-29 — فراخوانی مستقیم `this.onDestroy()` معادل stopSelf نیست
**فایل‌ها:** `V2rayVPNService.java:52-54,59-62,69-72,81-90,108-111`; `V2rayProxyOnlyService.java:35-39,44-47,54-57,74-77`  
در ProxyOnly، `onDestroy()` فقط super را صدا می‌زند و Core را پاک نمی‌کند. از cleanup helper و `stopSelf(startId)` استفاده شود.

### P1-30 — `onRevoke()` در حالت Core از قبل متوقف، TUN/Service را تضمینی پاک نمی‌کند
**فایل:** `V2rayVPNService.java:297-304`  
`stopAllProcess()` فقط در catch اجرا می‌شود؛ وقتی `stopCore()` بدون exception زود برگردد، cleanup صریح انجام نمی‌شود. `finally` باید cleanup idempotent و stopSelf را اجرا کند.

### P1-31 — شروع Core روی main thread سرویس و قبل از promotion به foreground انجام می‌شود
**فایل‌ها:** `V2rayVPNService.java` و `V2rayProxyOnlyService.java` بخش `onStartCommand`; `V2rayCoreManager.java` بخش `startCore/showNotification`  
Core startup می‌تواند طولانی باشد و promotion دیر شود. ابتدا notification/foreground را در مهلت Android برقرار کنید، سپس Core را روی executor اختصاصی start کنید؛ خطای `startForeground` را fail closed کنید.

### P1-32 — `showNotification()` خطای startForeground را می‌بلعد
**فایل:** `src/.../V2rayCoreManager.java:400-432`  
ادامه‌ی Core بدون foreground ممکن است به kill سیستم منجر شود. خطا باید به caller برگردد و cleanup/retry مشخص انجام شود.

### P1-33 — Connected-delay URL بین دو process با static منتقل نمی‌شود
**فایل‌ها:** `FlutterV2rayPlugin.java:141-147`; `V2rayController.java:87-103`; `V2rayCoreManager.java:438-445`; plugin manifest service process  
`AppConfigs.DELAY_URL` در app process set می‌شود ولی سرویس در `:RunSoLibV2RayDaemon` static جداگانه دارد. URL را در Intent extra بفرستید.

### P1-34 — delay receiver بعد از startService ثبت می‌شود و در timeout unregister نمی‌شود
**فایل:** `V2rayController.java:99-130`  
Broadcast ممکن است قبل از register برسد؛ timeout مسیر unregister ندارد. ابتدا receiver را ثبت کنید، سپس command را بفرستید و در `finally` unregister کنید.

### P1-35 — EventChannel receiver با Context اشتباه unregister می‌شود و در rotation ممکن است دو بار register شود
**فایل:** `FlutterV2rayPlugin.java:61-84,88-101,255-282,285-293`  
Context ثبت‌شده ذخیره نمی‌شود؛ `onDetachedFromActivityForConfigChanges()` خالی است؛ reattach همان receiver را دوباره ثبت می‌کند. `receiverRegisteredContext` و `isRegistered` نگه دارید و از همان context unregister کنید.

### P1-36 — EventSink پس از cancel/detach در static باقی می‌ماند
**فایل:** `FlutterV2rayPlugin.java:88-91,213-226`; `V2rayReceiver.java:13,29-50`  
بعد از `endOfStream()` هر دو reference باید به‌صورت شرطی null شوند تا engine قدیمی نگه داشته نشود و broadcast به sink مرده نرود.

### P1-37 — `V2rayController.init()` BroadcastReceiver را ذخیره/لغو نمی‌کند
**فایل:** `V2rayController.java:23-42`  
هر initialize می‌تواند receiver جدید ثبت کند. receiver را field کنید، init را idempotent و dispose را صریح کنید.

### P1-38 — Logcat filter به‌صورت یک tag با comma فرستاده می‌شود
**فایل:** `src/.../LogcatManager.java:50-60`  
Android logcat filterspecها را whitespace-separated می‌خواهد، نه comma-separated. هر tag را آرگومان جدا بدهید. `getLogs()` نیز تمام logها را برمی‌گرداند، درحالی‌که MAX_LOG_LINES فقط cache داخلی را محدود می‌کند (`90`); خروجی را به 500 خط محدود کنید.

### P1-39 — `clearLogs()` exit code را بررسی نمی‌کند
**فایل:** `LogcatManager.java:98-116`  
در صورت شکست `logcat -c` ممکن است همچنان true برگرداند. exit code و stderr بررسی شوند و «پاک‌شدن cache» از «پاک‌شدن system logcat» جدا باشد.

### P1-40 — `copyAssets()` InputStream ورودی را نمی‌بندد
**فایل:** `Utilities.java:20-27,42-49`  
`CopyFiles` فقط OutputStream را می‌بندد. هر دو stream را try-with-resources کنید. همچنین اگر `getExternalFilesDir("assets")` null شود، مسیر خالی برمی‌گردد و نوشتن relative path ممکن است شکست بخورد (`30-39`).

---

## 5. یافته‌های Medium/Low — اولویت P2/P3

1. **TCP-open به‌عنوان سلامت واقعی کافی نیست** — `national_engine.dart:141-239`, `nnie_core.dart:20-47`. TCP handshake نه TLS را ثابت می‌کند نه HTTP status، captive portal، عبور TUN یا پایداری را.
2. **`NatNetworkDiagnosis.refresh()` Future مشترک ندارد** — `national_engine.dart:43-49`; caller دوم ممکن است snapshot قدیمی را بگیرد. از `_inflight Future` استفاده شود.
3. **`domesticDnsOk` عملاً همیشه false است** — `national_engine.dart:20-47`; DNS probe داخلی به‌درستی وارد evidence نشده است.
4. **DNS parser publicV4 یک شرط dead code دارد** — `nnie_core.dart:...`; `10.10.34.34` قبل از allow بررسی با شرط `10/8` رد می‌شود.
5. **DNS parser پاسخ نامرتبط را می‌پذیرد** — `nnie_core.dart:173-189`; QNAME/CNAME/owner بررسی شود.
6. **`natAdaptiveWorkers` برای موبایل بیش‌ازحد بالا می‌رود** — `main.dart` و `nat_ip_scan.dart`; سقف 4–12 با توجه به RAM/thermal مناسب‌تر است تا 4–32 یا 256 socket.
7. **`nat_ip_scan` cancellation وسط socket connect نیست** — `nat_ip_scan.dart`; cancel token بین probeها چک می‌شود ولی probe فعال تا timeout ادامه دارد.
8. **`natIranDnsHosts` resolver است نه VPN endpoint** — `nat_ultra.dart`; DNS resolver را به‌عنوان candidate server استفاده نکنید.
9. **`natDohUsable` پروتکل‌ها را تفکیک نمی‌کند** — DoH/DoT/UDP53/TCP53 جدا شوند.
10. **`natIpMem` فقط hint باشد، نه اعتماد** — `nat_ultra.dart`; TTL 14 روز و profile باید network-aware و revalidate شوند.
11. **Failure score برای endpoint به‌جای config/variant است** — `main.dart`; شکست یک variant نباید همه‌ی کانفیگ‌های همان IP:port را تنبیه کند.
12. **`_natPrescan` فقط IP اول را می‌گیرد** — `main.dart`; A/AAAA متعدد و IPv4/IPv6 را جداگانه بررسی کند.
13. **Reality نباید با IP graft عمومی تغییر کند** — `nip_scan.dart:111-137`; `nipSwapLink` فقط Shadowsocks را skip می‌کند. Reality را از host/port graft عمومی حذف کنید مگر با matrix معتبر همان provider.
14. **TLS probeهای SNI/ALPN timeout مستقل ندارند و cleanup کامل نیست** — `auto_scanners.dart`; timeout handshake و `finally` برای raw/secure socket لازم است.
15. **چند TLS probe گواهی نامعتبر را می‌پذیرند** — `nip_scan.dart`, `npv_am_extras.dart`, `net_diag.dart`, `main.dart`؛ `onBadCertificate: (_) => true` فقط برای diagnostic بسیار محدود و هرگز برای انتخاب endpoint قابل‌اعتماد نباشد.
16. **Cloudflare probe پاسخ 403 را با متن header می‌تواند موفق حساب کند** — `npv_am_extras.dart`; status و body مورد انتظار `/cdn-cgi/trace` بررسی شود.
17. **`getListMirror()` هر پاسخ HTTP اولیه را معتبر می‌داند** — `iran_ai_extras.dart:851-880`; فقط 200 + محتوای معتبر باید primary success باشد و سپس mirror fallback شود.
18. **Gemini fallback در 429/500 و بعضی exceptionها متوقف می‌شود** — `iran_ai_extras.dart:...`; فقط IO/Timeout catch شده و generic HTTP error می‌تواند مانع مسیر دوم شود. errorها طبقه‌بندی شوند.
19. **AI API key ممکن است در SharedPreferences/Backup باقی بماند** — `iran_ai_extras.dart:199-243`, `backup_restore.dart:8-29`; کلیدهای حساس هرگز وارد backup نشوند و migration امن fail closed باشد.
20. **Backup import allowlist و limit ندارد** — `backup_restore.dart:27-57`; فقط کلیدهای مجاز، سقف حجم/تعداد/طول رشته و import تراکنشی.
21. **Update hash validation fail-open است** — `update_check.dart:122-133`; خطای hash باید نصب را متوقف کند.
22. **دانلود update در RAM محدودیت اندازه ندارد** — `update_check.dart:104-115`; stream با سقف اندازه استفاده شود.
23. **`prefs_store.dart` I/O همگام و XOR را رمزنگاری می‌داند** — I/O به صف async منتقل و secretها با Android Keystore/secure storage نگهداری شوند؛ XOR رمزنگاری نیست.
24. **`conn_specs.dart` ممکن است query/credential را در diagnostics نشان دهد** — `189-203`; allowlist و mask کامل برای token/key/password/secret/privateKey.
25. **خطای DNS در errJournal دوبار ثبت می‌شود** — `conn_specs.dart:209-219`; یک منبع ثبت خطا انتخاب شود.
26. **errJournal ring buffer واقعی ندارد** — `errjournal.dart:37,134-155`; 100k record و `removeAt(0)` پرهزینه است؛ ring buffer و rotation امن‌تر.
27. **Rotation فایل `.old` ممکن است با فایل موجود شکست بخورد** — `errjournal.dart:143-155`; replace/atomic rename.
28. **حجم journal تا 256MB زیاد است** — cap کوچک‌تر و محدودیت تعداد/حجم هر record.
29. **Auto-test بعد از timeout کارهای in-flight را cancel نمی‌کند** — `auto_test.dart:325-334,374-380,2107-2135`; cancellation token و await quiescence لازم است.
30. **Baseline probe در Auto-test await نمی‌شود** — `auto_test.dart:314-317`; `_atFinish()` ممکن است قبل از تکمیل نتیجه را بخواند.
31. **`withNpvAmCore()` اگر بعداً وصل شود، resolverهای جهانی را هم append می‌کند** — `npv_am_extras.dart`; هنگام wiring، DNS list باید mode-aware باشد.
32. **`routeOnly` در `_reliableVpnCfg()` hardcode شده** — `main.dart:2889-2923`; preference باید در یک منبع واحد اعمال شود.
33. **`_natDetect()` شش probe شبکه انجام می‌دهد ولی `world/home` را در تصمیم استفاده نمی‌کند** — `main.dart:10132-10166`; یا evidence را واقعاً مصرف کنید یا از مسیر critical خارج کنید.
34. **ASN detection منتظر هر سه provider می‌ماند** — `nat_ultra.dart:1543-1576`; first-valid result و refresh پس‌زمینه بهتر است.
35. **DNS auto-pick شکست را 10 دقیقه cache می‌کند** — `npv_am_extras.dart:147-150,202-205`; cache failure جدا و کوتاه‌تر از success باشد.
36. **Delayed standby search ممکن است بعد از dispose اجرا شود** — `main.dart:13015` و `_standbyRun()`؛ `mounted` check و cancellable timer لازم است.
37. **`KingDiag.lastExits()` ممکن است exitهای abnormal چاپ‌نشده را برای همیشه skip کند** — `android_src/KingDiag.java:289-321`; cursor فقط از رکوردهای واقعاً پردازش‌شده جلو برود.
38. **سرویس اختصاصی King VPN در وضعیت فعلی غیرفعال است** — `kOwnVpnService=false`; `MainActivity.kt:100-104` در مسیر dormant اگر `instance==null` باشد STOP را drop می‌کند ولی true برمی‌گرداند؛ `MainActivity.kt:78-98` نیز startForegroundService را بدون fallback API24–25 صدا می‌زند. قبل از فعال‌سازی باید اصلاح شوند.
39. **`manageExternalStorage` برای cache خصوصی app لازم نیست** — `nat_ultra.dart:2384-2387`; از internal app storage استفاده کنید و permission گسترده حذف شود.
40. **Cloudflare Worker parser فرض می‌کند VLESS header در اولین WS frame کامل است** — `king_extras2.dart:419-470`; header می‌تواند fragment شود؛ buffer تا parse کامل لازم است.
41. **Cloudflare Worker fallback host ممکن است نامعتبر باشد** — `king_extras2.dart:575-593`; اگر account subdomain lookup fail شد، fail closed کنید.
42. **Cloudflare Worker JS template دارای named-argument شبیه Dart است** — `king_extras2.dart:392-483`; syntax error در `errJournalAdd(e, kind: ...)` باید به JS positional/object syntax تبدیل شود.
43. **Query stringها در `tg_proxy.dart` و Check-host raw concat می‌شوند** — encode/validate پارامترها و IPv6 bracket لازم است.
44. **Online counter timer lifecycle باید owner مشخص داشته باشد** — `online_count.dart:44-48`; اگر app-wide است در service مستقل مدیریت شود.
45. **`_hotBusy` در natHotEnsure به Future مشترک تبدیل نشده** — concurrent caller فوراً برمی‌گردد، نه منتظر عملیات جاری.
46. **dedupe با `hashCode` collision-safe نیست** — `nat_ultra.dart:2443-2445`; canonical SHA-256.
47. **UUID masking/export برای همه‌ی فرمت‌ها کامل نیست** — `nat_ultra.dart:2269-2295`; URL-safe VMess و SS legacy باید parser-based mask شوند.
48. **`natHotEnsure` و `gold`/timerها lifecycle و flush مشخص می‌خواهند** — از Stateهای موقت جدا شوند.
49. **`MainActivity` custom service STOP وقتی instance null است موفقیت کاذب می‌دهد** — dormant؛ نتیجه باید stop-requested/ not-running باشد و وضعیت نهایی تأیید شود.
50. **`V2rayCoreManager` `startCore` و `CoreController.StartLoop` را نباید با «تأیید ترافیک واقعی» یکی دانست** — core running فقط وضعیت Core است؛ TUN و traffic validation جداست.

---

## 6. یافته‌های CI و قابلیت بازتولید Build

1. `King-vpn-v8_5.zip` فاقد `pubspec.yaml`, `pubspec.lock`, Gradle app و Manifest اصلی است؛ Workflow یک Flutter project جدید می‌سازد. این یعنی Build قابل بازتولید فقط از طریق workflow است، نه از ZIP به‌تنهایی.
2. `build.yml` وابستگی‌های زیادی را بدون نسخه‌ی ثابت اضافه می‌کند؛ فقط پلاگین `flutter_v2ray_client:3.5.0` pin شده است. نسخه‌های Flutter stable و پکیج‌های دیگر شناورند؛ خروجی ماه‌های مختلف ممکن است فرق کند.
3. `appBuild=3` در `update_check.dart` با `github.run_number` که برای Android build number استفاده می‌شود، یک منبع واحد ندارد.
4. `flutter analyze` و تست‌ها باید blocking باشند؛ در حال حاضر تست‌ها عمدتاً `nnie_core_test.dart` و منطق pure هستند و تست Android service lifecycle، parserهای پروتکل، TUN traffic، national-only و scan scheduler ندارند.
5. `patch_plugin.py` از اولین مسیر match شده در Pub cache استفاده می‌کند؛ در clean CI معمولاً یک نسخه است، اما در محیط توسعه با چند hosted cache ممکن است پچ روی مسیر اشتباه انجام شود. مسیر واقعی را از `.dart_tool/package_config.json` بگیرید.
6. شبیه‌سازی پچ روی کپی ایزوله‌ی سورس Java موفق شد؛ این فقط anchorها را تأیید می‌کند، نه compile.

---

## 7. مواردی که در بررسی اولیه اصلاح/پس گرفته شدند

برای جلوگیری از گزارش خطای کاذب، موارد زیر به‌عنوان باگ قطعی ثبت نمی‌شوند:

- ادعای shutdown نشدن executor پلاگین نادرست بود؛ `FlutterV2rayPlugin.onDetachedFromEngine()` در `226`، `executor.shutdown()` را دارد.
- ادعای اینکه Proxy-only فقط باز بودن پورت را موفقیت می‌داند نادرست بود؛ مسیر `_connectLoop` تست از طریق local Core proxy هم دارد.
- ادعای fallback مستقیم ping به‌عنوان false-positive در proxy mode نادرست بود؛ `_useCoreProxy()` در proxyMode از local proxy استفاده می‌کند.
- ادعای اینکه `startCore()` طبق پیاده‌سازی upstream به‌طور عادی CONNECTED را بدون running شدن Core برمی‌گرداند، تأیید نشد؛ `CoreController.StartLoop()` در صورت خطا error می‌دهد و `IsRunning` را reset می‌کند. مشکل قطعیِ ثبت‌شده، cleanup ناقص failure و اتکا به state flag به‌جای health check واقعی است.
- `Utilities.copyAssets()` از `V2rayController.init()` فراخوانی می‌شود؛ ادعای فراخوانی‌نشدن آن اصلاح شد. فقط InputStream leak و fallback مسیر خالی مشروط باقی است.
- سه‌argument `Context.registerReceiver(receiver, filter, flags)` از API 26 موجود است؛ ادعای missing-method برای guard API 26 پس گرفته شد. مشکلات واقعی این متد، ترتیب ثبت receiver، unregister در timeout و انتقال URL بین processها هستند.

---

## 8. ترتیب پیشنهادی اصلاحات

### مرحله A — قبل از هر بهینه‌سازی سرعت
1. گیت اتصال و واچ‌داگ را mode-aware کنید: domestic/global جدا.
2. تست سرعت داخلی معتبر اضافه کنید؛ شکست Cloudflare نباید Failover داخلی بسازد.
3. DNS تولیدشده‌ی پیش‌فرض را در حالت ملی ایرانی‌محور کنید؛ DNS صریح کاربر را حفظ کنید.
4. تلاش اختصاصی Reality را از DNS جهانی به DNS mode-aware تغییر دهید و timeout تلاش‌های نامناسب را حذف کنید.
5. کانفیگ اصلی را پیش از matrix یک بار تست کنید.
6. `withNpvAmCore` و `withIranRouting` را به config pipeline واحد وصل کنید؛ گزینه‌های بی‌اثر را تا زمان wiring غیرفعال/حذف کنید.

### مرحله B — ایمنی و عدالت اسکن
1. subnet expansion از DNS/server/device IP را حذف کنید.
2. اسکن all-port دامنه‌های عمومی را حذف کنید.
3. فقط endpointهای دقیق کانفیگ و CIDRهای مجاز را probe کنید.
4. cursor ملی و block cursor را پایدار و fair کنید.
5. DNS scan و IP scan را scheduler ترتیبی بدهید.
6. `kNatIpScanOn` را به تمام entry pointها اعمال کنید.
7. candidate را فقط بعد از Core outbound + TUN traffic + domestic/global stability به healthy ارتقا دهید.

### مرحله C — Android/plugin lifecycle
1. STOP را مستقل از Core state به cleanup + `stopSelfResult(startId)` تبدیل کنید.
2. direct `onDestroy()` calls را حذف کنید.
3. startup را از main thread سرویس خارج کنید و foreground notification را قبل از Core start برقرار کنید.
4. failure start را با timer cancel، DISCONNECTED broadcast و cleanup کامل کنید.
5. receiver registration context را track و EventSink را در cancel/detach پاک کنید.
6. connected-delay URL را Intent extra کنید و receiver را قبل از startService ثبت کنید.
7. Logcat filters را جدا و خروجی را محدود کنید.

### مرحله D — parser, security, diagnostics
1. WS path، VMess URL-safe Base64، missing `net`, SNI fallback و SS parser را اصلاح کنید.
2. endpointKey/configKey را جدا کنید.
3. backup allowlist، secret redaction، secure storage و update hash fail-closed را اعمال کنید.
4. ring buffer و atomic journal rotation پیاده کنید.
5. تست واحد برای parser هر پروتکل و تست instrumented برای Android lifecycle اضافه کنید.

---

## 9. تست‌هایی که کاربر باید بعد از اصلاح اجرا کند

این‌ها تست پیشنهادی‌اند؛ در این ممیزی اجرا نشده‌اند:

1. **Global online:** VLESS Reality/TLS، VMess TCP/WS، Trojan، SS؛ اتصال، TUN traffic، speed و disconnect.
2. **Domestic-only:** DNS داخلی resolve شود، سایت‌های داخلی از TUN باز شوند، Cloudflare/Google unreachable باشد، اما اتصال داخلی نباید رد یا Failover شود.
3. **Domestic up + global down:** واچ‌داگ حداقل 30 دقیقه بدون failover کاذب کار کند.
4. **Global up + domestic down:** وضعیت دقیق گزارش شود؛ داخلی خراب به‌عنوان global down برچسب نخورد.
5. **Network switch:** Wi-Fi به mobile و برعکس؛ DNS cache و operator profile باید invalidate/reselect شوند.
6. **Service lifecycle:** start failure، STOP در حالی که Core از قبل down است، revoke VPN permission، app process death، engine detach/reattach، rotation و proxy-only stop.
7. **Parser fixtures:** VMess Base64 standard/URL-safe، VMess بدون net، WS بدون path، Trojan بدون SNI، Reality بدون SNI، SS SIP002 و malformed SS.
8. **Resource:** اسکن cancel شود؛ socket count، CPU، RAM، battery و تعداد taskهای باقی‌مانده بررسی شود.
9. **Scan fairness:** cursor پس از چند اجرا باید از CIDR اول عبور کند؛ هیچ slice ثابتی نباید تکرار بی‌نهایت داشته باشد.
10. **Security:** backup شامل API key نباشد؛ diagnostics credential را mask کند؛ TLS invalid certificate هیچ‌وقت endpoint سالم نسازد.

---

## 10. جمع‌بندی برای مرحله‌ی بعد: معماری نت ملی

پیش از افزودن اسکن بیشتر یا variant بیشتر، مسیر نت ملی باید بر این ترتیب بازطراحی شود:

`Network Profile -> Domestic/Global Diagnosis -> DNS Policy -> Candidate Configs -> Protocol Validation -> Core Start -> TUN Traffic Validation -> Stability/Hysteresis -> Recovery`

- تشخیص شبکه باید حداقل سه حالت داشته باشد: `globalAndDomestic`, `domesticOnly`, `neither/unknown`.
- DNS باید براساس network generation و اپراتور انتخاب شود؛ DNS جهانی fallback اختیاری باشد، نه پیش‌فرض اجباری در national-only.
- کشف سرور از منابع کانفیگ و endpointهای دقیق شروع شود؛ هیچ subnet عمومی/خصوصی اطراف DNS یا سرور به‌صورت خودکار اسکن نشود.
- معیار موفقیت نهایی باید **عبور ترافیک واقعی از Android TUN** و پایداری آن باشد؛ Core running، TCP-open و outbound delay فقط مراحل میانی‌اند.
- سرعت و ping داخلی/جهانی جدا ذخیره شوند. هیچ عددی از probe نامعتبر یا پاسخ error به‌عنوان سرعت نمایش داده نشود.
- Failover باید hysteresis و circuit breaker داشته باشد تا یک timeout منفرد یا قطع بین‌الملل، تونل داخلی را خراب نکند.

**وضعیت:** ممیزی ایستای این snapshot و تطبیق مسیرهای حساس با سورس پلاگین انجام شد. مرحله‌ی بعد، طراحی معماری اجرایی نت ملی بر اساس همین یافته‌هاست؛ هیچ Build یا تست واقعی ادعا نشده است.
