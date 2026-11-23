# ممیزی نهایی جامع King VPN — گزارش مرحله‌ای

> وضعیت این سند: **در حال اجرا — فاز ۱ آغاز شده، ممیزی کامل نشده است.**
> این گزارش فقط شواهد قابل مشاهده در مخزن و CI را ثبت می‌کند. مواردی که هنوز بازرسی یا اجرا نشده‌اند صریحاً BLOCKED / NOT TESTED می‌مانند.

## ۱. مشخصات ممیزی

| مورد | مقدار |
|---|---|
| مخزن | cafeeteriaa/King-vpn |
| شاخه ممیزی | audit/final-master |
| شاخه مبنا | codex/continuation-mainline-20261122 |
| شاخه اصلی | main — بدون تغییر |
| PR مرتبط با مبنا | #42 — باز، Draft، ادغام‌نشده |
| commit مبنای کدِ دارای شواهد CI | 0ad29bfe7eb30b13eff2f3949b0b6086bedc6545 |
| commit مستندات checkpoint گزارش‌شده | 25483910a388eecfca7db07aa7bf017e4bf1c913 |
| اجرای CI مبنا | 2130 / 45047539595 — SUCCESS برای commit کد فوق |
| دامنه | VPN، موتورها، Smart Pilot، DNS/Routing، Android Native، King AI، King AI Engineer، ابزارهای تعمیر، امنیت، CI/CD و انتشار |

**محدودیت مبنا:** این ممیزی روی شاخه جداگانه انجام می‌شود. تا زمانی که HEAD دقیق شاخه و همه commitهای بعد از commit دارای شواهد CI بازرسی نشده‌اند، نتایج آن CI به کد فعلی تعمیم داده نمی‌شوند.

## ۲. قواعد پذیرش و گزارش

- هیچ سرعت، پینگ، کاربر آنلاین، نرخ موفقیت یا امتیاز ساختگی پذیرفته نیست؛ مقدار ناموجود باید unknown باشد.
- هیچ موتور فقط به دلیل وجود نام، UI، Parser یا Validator فعال محسوب نمی‌شود.
- فقط موتور دارای عبور ترافیک واقعی تأییدشده روی دستگاه می‌تواند در انتخاب خودکار وارد شود.
- در تعویض موتور، Stop موتور فعلی، تأیید آزادشدن TUN، Start موتور بعدی و آزمون data-plane الزامی است.
- اپ نصب‌شده نباید فایل اجرایی Dart/Native خود را بازنویسی کند.
- قابلیت‌های سالم حفظ می‌شوند؛ تنها سه کاشی مشخص‌شده از UI حذف می‌شوند.
- هر تست باید معیار پذیرش و شواهد اجرای قابل ردیابی داشته باشد.
- وضعیت نهایی کل محصول تا رفع تمام موانع مهم نمی‌تواند FINAL VERIFIED باشد.

## ۳. خط مبنای اندازه و عملکرد

| معیار | مقدار ثبت‌شده | اعتبار و محدودیت |
|---|---:|---|
| APK استخراج‌شده | 122,885,758 bytes | اندازه گزارش‌شده برای artifact اجرای CI 2130؛ مبنای تاریخی، نه هنوز اندازه شاخه ممیزی |
| آرشیو Artifact | 49,011,435 bytes | آرشیو ZIP اجرای CI 2130 |
| SHA-256 آرشیو | 664050952e07aa316530bca4e7c8cc99698b2ba4e7f5b723db42b24de534a816 | با digest گزارش‌شده GitHub تطبیق داده شده |
| SHA-256 APK داخلی | 67828ad04e885675161fcadd66aec5c27106ece2e24abd269abdf45f9c9e4618 | گزارش‌شده برای APK استخراج‌شده |
| CPU / RAM / باتری در حالت idle و اتصال | unknown | اندازه‌گیری دستگاهی ثبت نشده |
| زمان cold start / connect / recovery | unknown | اندازه‌گیری دستگاهی ثبت نشده |

این اندازه‌ها فقط baseline تاریخی‌اند. برای مقایسه معتبر، باید build جدید از HEAD دقیق audit branch با همان ABI، build mode و روش استخراج ساخته شود.

## ۴. ماتریس پوشش اولیه ماژول‌ها

این ماتریس فهرست اولیه حوزه‌های مهم است و هنوز جایگزین inventory کامل فایل‌به‌فایل نیست. هر ردیف تا زمان بازبینی مستقل و اجرای معیار پذیرش وضعیت نهایی نمی‌گیرد.

| ماژول | مسیرها/فایل‌های شناخته‌شده | مسئولیت | شواهد و ریسک‌های باز | سه بازبینی | تست / Build | وضعیت |
|---|---|---|---|---|---|---|
| Flutter UI و نگهداری قابلیت‌ها | lib/، README.md | رابط فارسی، صفحات و ابزارها | تطبیق کامل قابلیت‌ها و سه کاشی هنوز انجام نشده | Pending | تست کامل UI/دستگاه اجرا نشده | NOT TESTED |
| اتصال Xray/V2Ray فعال | lib/main.dart، dependency فعال flutter_v2ray_client:3.5.0 طبق سوابق PR | موتور فعلی و چرخه اتصال | runtime روی گوشی و عبور data-plane تأیید نشده | Pending | CI مبنا build موفق؛ دستگاه BLOCKED | VERIFIED WITH LIMITATIONS |
| Android VPN lifecycle | android_src/KingVpnService.java، android_src/MainActivity.kt | VpnService، TUN، Start/Stop، MethodChannel | مسیر فعال پیش‌فرض plugin-managed است؛ kOwnVpnService=false طبق checkpoint؛ تست واقعی lifecycle لازم است | سه review قبلی برای یک تغییر lifecycle: PASS WITH LIMITATIONS؛ بازبینی مستقل کل ماژول Pending | source guard و CI مبنا موفق؛ دستگاه NOT TESTED | VERIFIED WITH LIMITATIONS |
| Flutter ↔ Native channels | android_src/MainActivity.kt، lib/main.dart | Platform Channels و رویدادها | MissingPluginException تاریخی vpnSettings نیازمند بازتولید روی دستگاه است | Pending | unit/source guards کافی برای runtime نیستند | BLOCKED |
| Smart Pilot / تشخیص ملی و جهانی | lib/network_health.dart، lib/national_engine.dart، lib/main.dart | تشخیص شبکه و انتخاب مسیر | تغییر شبکه وسط probe و evidence gates در PR #43؛ وضعیت فعلی باید روی HEAD ممیزی شود | Pending | تست دستگاه و اپراتور ایران اجرا نشده | VERIFIED WITH LIMITATIONS |
| DNS policy | lib/dns_policy.dart و محل ادغام در lib/national_engine.dart | اولویت DNS داخلی، DoH و deduplication | عبور DNS از هسته و نبود نشت DNS/IP اثبات نشده | Pending | تست‌های واحد گزارش‌شده؛ packet/device test مسدود | BLOCKED |
| IPv4 / IPv6 و Routing | android_src/KingVpnService.java، lib/ | routeهای TUN و خانواده IP | fail-closed برای خطای route IPv6 گزارش شده؛ data-plane هر دو خانواده تأیید نشده | Pending | دستگاه و packet capture انجام نشده | BLOCKED |
| Failover / Reconnect / self-healing | lib/main.dart، lib/self_repair_policy.dart، Android service | generation fencing، cooldown، recovery | raceها و فرایند مرگ پروسه باید روی دستگاه بررسی شوند | Pending | بخشی از source guards و unit tests در CI | VERIFIED WITH LIMITATIONS |
| King AI محلی | lib/king_local_ai.dart | مدل محلی و تحلیل/پژوهش | README مدل Qwen2.5-Coder-1.5B-Instruct Q4_K_M و llama.cpp را توصیف می‌کند؛ ممیزی مدل، sandbox و prompt injection باز است | Pending | عملکرد و امنیت runtime بررسی نشده | NOT TESTED |
| King AI Engineer | docs/KING_AI_SOFTWARE_ENGINEER_FA.md، lib/ و tools/ | تولید Patch و گردش‌کار توسعه | محدودیت مسیر، مالکیت، تأیید Patch، secrets و اجرای کد باید بازبینی شود | Pending | end-to-end automation اثبات نشده | NOT TESTED |
| Patch gate / Repair orchestrator | tools/patch_gate.py، tools/repair_orchestrator.py، tools/diagnose_build.py | اعمال Patch در کپی موقت و اعتبارسنجی | بازبینی کامل traversal، symlink، command execution و rollback لازم است | Pending | تست امنیتی اختصاصی در این مرحله اجرا نشده | NOT TESTED |
| CI/CD و Build | .github/workflows/، prepare_android.py، patch_plugin.py | تولید میزبان Flutter، patch پلاگین و build | permissionها، pull_request_target، pinning، secrets و artifact provenance باز است | Pending | CI run 2130 برای commit مبنا موفق | VERIFIED WITH LIMITATIONS |
| Dependency / License | dependency declarations و plugin_source_reference/ | وابستگی‌ها و مجوزها | inventory کامل مجوز و CVE و GPL/شرایط خاص انجام نشده | Pending | SBOM و vulnerability scan این مرحله موجود نیست | NOT TESTED |
| Logging / Privacy / Storage | lib/errjournal.dart و storageهای lib/ | گزارش، پاک‌سازی داده و تنظیمات | بازبینی جامع secret/UUID/config leakage و retention باز است | Pending | تست نشت داده کامل اجرا نشده | NOT TESTED |
| Performance / Resource | Flutter، Native، مدل محلی و workerها | CPU/RAM/battery/startup | baseline دستگاهی وجود ندارد | Pending | benchmark اجرا نشده | BLOCKED |
| UI theme / display metrics | lib/ | تم تیره و اعداد واقعی | بازبینی تمام ویجت‌ها و منبع اعداد لازم است | Pending | visual/device review اجرا نشده | NOT TESTED |

## ۵. وضعیت موتورهای اتصال

| موتور | وضعیت پیاده‌سازی | Parser/Validator اختصاصی | اتصال به lifecycle واحد | عبور ترافیک واقعی روی گوشی | ورود به انتخاب خودکار | وضعیت ممیزی |
|---|---|---|---|---|---|---|
| Xray/V2Ray | موجود؛ تثبیت کامل هنوز در حال ممیزی | موجودیت و پوشش باید کامل بررسی شود | مسیر plugin-managed فعلی | اثبات دستگاهی در دسترس نیست | تا تأیید دستگاهی ممنوع | BLOCKED برای data-plane |
| sing-box | هنوز در این audit branch پیاده‌سازی/اثبات نشده | NOT TESTED | NOT TESTED | NOT TESTED | خیر | NOT TESTED |
| Mihomo / Clash.Meta | هنوز در این audit branch پیاده‌سازی/اثبات نشده | NOT TESTED | NOT TESTED | NOT TESTED | خیر | NOT TESTED |
| WireGuard | هنوز در این audit branch پیاده‌سازی/اثبات نشده | NOT TESTED | NOT TESTED | NOT TESTED | خیر | NOT TESTED |
| Hysteria2 | هنوز در این audit branch پیاده‌سازی/اثبات نشده | NOT TESTED | NOT TESTED | NOT TESTED | خیر | NOT TESTED |
| Psiphon | امکان‌سنجی فنی/مجوز/توزیع انجام نشده | N/A تا تصمیم امکان‌سنجی | NOT TESTED | NOT TESTED | خیر | NOT TESTED |

**قاعده سخت‌گیرانه:** موتور جدید تا تکمیل پیاده‌سازی واقعی، Parser/Validator، تست، Build، بررسی مجوز و آزمون data-plane روی گوشی BLOCKED/NOT TESTED می‌ماند. هیچ placeholder یا موتور نمایشی در فهرست موتورهای قابل انتخاب قرار نمی‌گیرد.

## ۶. یافته‌های اولیه امنیت و پایداری

| موضوع | شدت اولیه | شواهد فعلی | احتمال/اثر | اقدام لازم | وضعیت |
|---|---|---|---|---|---|
| عبور ترافیک و DNS/IP leak روی دستگاه | Critical | هیچ پذیرش packet/device-level در شواهد مبنا وجود ندارد | نامشخص؛ اثر بالقوه افشای IP/DNS | تست واقعی IPv4/IPv6، DNS، route و packet capture | BLOCKED |
| Platform Channel vpnSettings | High | سابقه MissingPluginException در سوابق پروژه؛ checkpoint می‌گوید handler در MainActivity ثبت شده | در صورت بازگشت خطا، تنظیمات/مسیر وابسته خراب می‌شود | بازتولید، lifecycle engine attach/detach و integration test | BLOCKED |
| Android lifecycle / Stop-Start races | High | اصلاح generation fencing و stop-marker در commitهای قبلی؛ سه review برای تغییر مشخص PASS WITH LIMITATIONS | raceهای باقی‌مانده ممکن است TUN یا session را stale کنند | تست همزمانی قطعی و device process-death/handover | VERIFIED WITH LIMITATIONS |
| اسرار و Tokenها در Git history/Artifacts | High تا زمان اسکن | اسکن جامع تاریخچه و artifact در این فاز انجام نشده | افشای token/API key می‌تواند دسترسی غیرمجاز بدهد | secret scanning روی کل تاریخچه، branchها، artifactها و logs | NOT TESTED |
| Prompt Injection / AI tool execution | High تا زمان ممیزی | README قابلیت تحقیق وب و نوشتن GitHub با token ذخیره‌شده را توصیف می‌کند | محتوای وب/کانفیگ مخرب ممکن است عامل را منحرف کند | جداسازی داده/دستور، allowlist ابزار، مالکیت، patch sandbox و approval gate | NOT TESTED |
| CI/CD permissions و supply chain | High تا زمان ممیزی | workflowهای build/release و patch_plugin.py وجود دارند | اجرای کد ناخواسته یا افشای secrets در PR/Actions | بازبینی permission حداقلی، triggerها، pinning و artifact provenance | NOT TESTED |
| License / GPL / توزیع هسته‌ها | High قبل از ادغام | inventory مجوزهای موتورهای درخواستی تکمیل نشده | ناسازگاری تعهدات توزیع/سورس | بررسی مجوز هر dependency و تأیید مالک پیش از ادغام | BLOCKED |
| CPU/RAM/OOM و مدل محلی | Medium/High | artifact شامل کتابخانه‌های inference است؛ benchmark دستگاهی موجود نیست | مصرف بالا یا افت پایداری | benchmark با سناریوهای مشخص و محدودیت workerها | BLOCKED |

شدت‌ها اولیه‌اند و پس از جمع‌آوری شواهد بازنگری می‌شوند؛ نبود شواهد به معنی نبود آسیب‌پذیری نیست.

## ۷. سه بازبینی مستقل

برای هر ماژول مهم سه نتیجه جداگانه ثبت خواهد شد:
1. **بازبینی فنی/معماری:** صحت طراحی، مالکیت lifecycle، سازگاری و مسیر داده.
2. **بازبینی امنیت/پایداری/عملکرد:** threat model، مرز اعتماد، منابع، race و side effect.
3. **بازبینی نهایی مستقل:** Diff دقیق، معیارهای پذیرش، تست‌های اجراشده و Build دقیق همان commit.

نتایج سه‌گانه برای کل ماژول‌های این گزارش هنوز Pending هستند. سه review ثبت‌شده در PROJECT_STATE.md فقط به تغییر native lifecycle مشخص مربوط‌اند و جایگزین سه بازبینی کل محصول یا موتورهای جدید نیستند.

## ۸. فازبندی و ثبت پیشرفت

| فاز | شرح | وضعیت |
|---|---|---|
| ۱ | ممیزی پایه، inventory کامل، baseline، امنیت و رفع خطاهای بحرانی | IN PROGRESS |
| ۲ | تثبیت Xray و افزودن مرحله‌ای sing-box، Mihomo، WireGuard، Hysteria2 و امکان‌سنجی Psiphon | NOT STARTED |
| ۳ | خلبان هوشمند، انتخاب مبتنی بر شواهد و failover امن | NOT STARTED |
| ۴ | ممیزی جامع VPN، AI، AI Engineer، CI/CD، امنیت و عملکرد | NOT STARTED |
| ۵ | Build نهایی، artifact/hash و پذیرش دستگاه | NOT STARTED |

## ۹. تغییرات ثبت‌شده در این شاخه

- ایجاد شاخه جداگانه audit/final-master؛ main تغییر نکرده است.
- تصمیم مالک برای افزودن/بررسی موتورهای Xray، sing-box، Mihomo/Clash.Meta، WireGuard، Hysteria2 و Psiphon در بخش «محدوده موتور اتصال» سند docs/KING_VPN_INFINITY_ROADMAP_FA.md ثبت شد.
- محدودیت قبلی «فقط Xray» حذف شد؛ بند ۸ مبنی بر ممنوعیت معرفی موتور صرفاً با نام/Parser حفظ شد.
- شروط آزادسازی انحصاری TUN، data-plane acceptance و عدم ورود موتور تأییدنشده به انتخاب خودکار در سند roadmap تصریح شد.
- commit تغییر roadmap: 3f26eeeda59949648d22040b2e7c2dd11027672d.

## ۱۰. محدودیت‌ها و کارهای باز

- هنوز inventory کامل فایل‌به‌فایل و بازبینی کل Diff شاخه مبنا انجام نشده است.
- هنوز ممیزی جامع secret روی تاریخچه Git و Artifactها انجام نشده است.
- هنوز dependency/SBOM/CVE/license scan اجرا نشده است.
- Build دقیق HEAD شاخه audit/final-master در CI Run `45075391129` موفق شد؛ آرشیو APK با اندازه `49,015,078` بایت تولید شد.
- SHA-256 آرشیو APK: `4eb2ebd8188cd23645f1839eb1dc62031cd270fb4798f6d4989ed38e158f48d7` (Artifact: `king-vpn-arm64-release-2142`). این digest، آرشیو Artifact است و به‌تنهایی امضای تولیدی یا اعتبار نصب را اثبات نمی‌کند.
- هنوز هیچ موتور جدیدی اضافه یا روی گوشی تأیید نشده است.
- هیچ اتصال واقعی، DNS leak test، IPv4/IPv6 packet test، اپراتور ایران، failover یا process-death device test در این مرحله ادعا نمی‌شود.

## ۱۱. شرط وضعیت نهایی

تا وقتی هر بخش مهم BLOCKED یا NOT TESTED باشد، وضعیت کل پروژه **FINAL VERIFIED WITH LIMITATIONS** خواهد بود، نه FINAL VERIFIED. هر نتیجه فقط پس از اجرای واقعی معیار پذیرش و ثبت commit، log، artifact و hash قابل ارتقا است.


## ۱۲. یافته و اصلاح افزوده‌شده در ممیزی Smart Pilot

### یافته: latency نامعتبر می‌توانست باعث handover شود

- در نسخه مبنای این شاخه، انتخاب مسیر وقتی هر دو مسیر reachable بودند، فقط non-null بودن latency را بررسی می‌کرد.
- مقدار صفر یا منفی می‌توانست شرط بهبود ۲۰ درصدی/۸۰ میلی‌ثانیه‌ای را پاس کند و باعث انتخاب مسیر اشتباه شود.
- این رفتار با قید مالک که داده صفر یا ناموجود نباید موفقیت/امتیاز محسوب شود ناسازگار بود.

### اصلاح ثبت‌شده

- انتخاب خودکار مبتنی بر latency فقط وقتی مجاز است که هر دو مقدار مثبت و موجود باشند؛ در غیر این صورت استراتژی قبلی حفظ می‌شود.
- شواهد شبکه اکنون شمارنده‌های نمونه/موفقیت را با حد بالای سه نمونه برای هر مسیر اعتبارسنجی می‌کند؛ شمارنده نامعتبر برای تأیید مسیر یا confidence قابل اتکا نیست.
- confidence فقط موفقیت‌های معتبر را می‌شمارد و تأیید TLS را به quorum معتبر گره می‌زند.
- وضعیت نمایشی شبکه و انتخاب استراتژی از دروازه‌های شواهد یکسان استفاده می‌کنند.
- درخواست forced refresh که هنگام probe معمولی برسد، دیگر بی‌صدا حذف نمی‌شود؛ یک refresh اجباری پس از پایان scan جاری صف می‌شود و callerهای بعدی به همان Future می‌پیوندند.
- هویت شبکه قبل و بعد از سه probe داخلی و سه probe جهانی دوباره خوانده می‌شود. اگر شبکه در حین probe تغییر کند، snapshot دور ریخته و فقط یک بار retry می‌شود؛ تغییر مجدد یا identity ناموجود به unknown منجر می‌شود.
- Android از طریق MethodChannel vpn/bg، Network handle و transport/capabilityهای شبکه فعال را به‌صورت transient می‌دهد؛ اگر شبکه فعال VPN باشد یا identity قابل دریافت نباشد، مقدار null برمی‌گردد. Dart فقط hash آن را برای تطبیق کوتاه‌مدت نگه می‌دارد.

### تست‌های افزوده‌شده

- Unit tests برای صفر/منفی/ناموجود بودن latency، quorum و شمارنده‌های نامعتبر، forced refresh و identity/handover policy.
- Source guards برای اطمینان از قبل/بعد identity check، retry محدود، رد VPN به‌عنوان identity پایه و serialization درخواست forced refresh.

### وضعیت اعتبارسنجی

- تغییرات کد در شاخه audit/final-master ثبت شده‌اند.
- اجرای CI دقیق HEAD شاخه audit/final-master در Run `45075391129` برای commit `da2733be49b96497edf166311401271e8d2ef2fb` با نتیجه **SUCCESS** تکمیل شد؛ Source Guard، Flutter Unit Tests، Dart Analysis، ساخت APK بهینه ARM64، بررسی ELF و ZIP alignment برابر 16 KiB و بارگذاری Artifactها همگی موفق بودند.
- آزمون Wi-Fi/mobile handover، VPN فعال، اپراتور ایران و عبور واقعی ترافیک همچنان **BLOCKED** تا اجرای دستگاهی هستند.
- این اصلاحات فقط Smart Pilot evidence/routing را سخت‌گیرانه‌تر می‌کنند؛ خودشان اثبات عبور ترافیک VPN نیستند.

### Commitهای اصلاح

- latency guard اولیه: d72ad54f3f2e07772d16f8dab9262fd93e51d308
- تست latency: cfa902762edc5d62985051ed724f3cc9e7179b3e
- اعتبارسنجی evidence و coordinator: 7fcdd4c1eef470b66c3fec4321da21d673c7ea5d
- تست evidence/quorum: be989c77f40e30be01cd23a483a7a8f2501d86dc
- probe identity و handover fencing: 2af9a0e895891f85f9021fb46bf4e8dfffe38cff
- Android network identity: e226bebb56154f5eaec8098d70992e5b5ab439d8
- source guards: 51e77849cd511c818a3df1bbaadb6d360a152dcc


## ۱۳. بازبینی مرز مالکیت Start/Stop سرویس VPN در Android

### شواهد مستقیم از HEAD ممیزی

- در `lib/own_vpn.dart` مقدار `kOwnVpnService` برابر `false` است؛ بنابراین مسیر اجرایی فعلی باید plugin-managed باقی بماند و سرویس اختصاصی `KingVpnService` هنوز مسیر فعال پیش‌فرض نیست.
- در مسیر شروع `lib/main.dart`، انتخاب بین `ownVpnStart(...)` و `v2ray.startV2Ray(...)` با همین flag انجام می‌شود؛ تغییر flag بدون پذیرش دستگاهی مجاز نیست.
- در مسیر توقف، `_stopV2()` ابتدا در صورت فعال بودن flag، `ownVpnStop()` را فراخوانی می‌کند، اما سپس `v2ray.stopV2Ray()` را بدون شرط اجرا می‌کند.
- در `android_src/MainActivity.kt`، handler فرمان `stop`، متد `KingVpnService.stopFromApp()` را فراخوانی کرده و بلافاصله `result.success(true)` برمی‌گرداند.
- در `android_src/KingVpnService.java`، `stopFromApp()` پاک‌سازی `stopEverything` را به worker صف می‌کند؛ بنابراین پاسخ MethodChannel به‌تنهایی اثبات پایان native core، آزادشدن TUN یا تکمیل توقف نیست.
- سرویس اختصاصی و مسیر plugin-managed از اجزای V2Ray مشترک استفاده می‌کنند؛ در نتیجه ترتیب و هم‌زمانی دو درخواست توقف باید به‌صورت عملی بررسی شود.

### ارزیابی

این بررسی یک **ریسک بالقوه در مسیر غیرفعال custom-service** را مشخص می‌کند، نه یک خرابی اثبات‌شده در مسیر فعلی. هنوز معلوم نیست فراخوانی متوالی توقف پلاگین پس از درخواست توقف سرویس اختصاصی، در تمام interleavingها بی‌خطر است یا می‌تواند با cleanup سرویس اختصاصی رقابت کند.

### اقدام و معیار پذیرش

1. `kOwnVpnService=false` حفظ شود؛ هیچ فعال‌سازی صرفاً بر اساس CI یا تست ایستا انجام نشود.
2. قرارداد توقف native باید میان «درخواست توقف پذیرفته شد» و «هسته متوقف و TUN آزاد شد» تمایز روشن داشته باشد.
3. تست‌های قطعی برای own-service Stop در برابر Start جدید، timeout قدیمی، stop notification و cleanup هم‌زمان با plugin stop اضافه شوند.
4. روی دستگاه واقعی، توقف فقط پس از تأیید پایان core و آزادشدن TUN موفق تلقی شود؛ سپس Start بعدی و عبور واقعی IPv4/IPv6 بررسی شود.
5. تا تکمیل این معیارها، مسیر plugin-managed فعلی حفظ شود و هیچ ادعای تأیید custom service ثبت نشود.

### نتیجه این مرحله

- معماری فعلی تغییر نکرد.
- هیچ قابلیت سالمی حذف نشد.
- هیچ موتور یا سرویس جدیدی فعال نشد.
- این مورد به‌عنوان بررسی باز برای فاز lifecycle ثبت شد؛ وضعیت: **OPEN / DEVICE VALIDATION REQUIRED**.


## ۱۴. ممیزی لایه IP / DNS / SNI / Host / TLS / DPI / Packet

### ۱۴.۱ DNS و مسیر حل نام — یافته‌های ایستا

- `_reliableVpnCfg()` در حالت ملی resolverهای داخلی را در ابتدای فهرست قرار می‌دهد: `178.22.122.100`, `185.51.200.2`, `78.157.42.100`, `78.157.42.101`, `10.202.10.10`, `10.202.10.11`. در صورت Secure DNS، دو DoH به‌عنوان fallback افزوده می‌شوند؛ resolverهای قبلی کانفیگ نیز بعد از این موارد حفظ می‌شوند.
- در حالت جهانی و Secure DNS (به‌جز Ultra)، DoHهای `https://1.1.1.1/dns-query` و `https://8.8.8.8/dns-query` قبل از resolverهای plaintext قرار می‌گیرند و `enableParallelQuery=false` تنظیم می‌شود تا race هم‌زمان به resolver متن‌باز/رمزنگاری‌نشده رخ ندهد.
- در حالت ملی، ترتیب داخلی-first عمداً یک trade-off دسترس‌پذیری است؛ در حالت جهانی نیز plaintext fallback وجود دارد. بنابراین Secure DNS فعلی معادل «اجبار رمزنگاری همه درخواست‌ها» یا تضمین نبود DNS leak نیست.
- `queryStrategy='UseIP'` برای انتخاب IPv4 و IPv6 تنظیم می‌شود؛ این فقط سیاست پاسخ DNS است و ثابت نمی‌کند هر دو خانواده IP از TUN عبور می‌کنند.
- `routing.domainStrategy` فقط در صورت نبود مقدار قبلی روی `AsIs` قرار می‌گیرد؛ سیاست قبلی `withIranRouting` حفظ می‌شود.
- DNS scanner از UDP/53 و پاسخ wire-level با اعتبارسنجی transaction ID، QR/opcode، question/type/class، source IP/port، RCODE و A answer استفاده می‌کند. این آزمون سلامت resolver است، نه اثبات مسیر DNS برنامه‌ها از داخل VPN.
- در کد سیاست DNS، schemeهای `https+local://` و `quic+local://` نیز encrypted شناخته می‌شوند؛ معنای local و احتمال bypass routing باید با نسخه دقیق Xray و packet capture تأیید شود. DoH استاندارد `https://` از نظر طراحی وارد routing هسته می‌شود، اما مسیر واقعی هنوز با capture تأیید نشده است.

**نتیجه:** پیاده‌سازی DNS دارای ترتیب‌دهی و تست واحد است، اما DNS strict-only، DNS leak-free و عبور تضمین‌شده از TUN هنوز اثبات نشده‌اند. وضعیت: **STATIC REVIEWED / PACKET TEST NOT TESTED**.

### ۱۴.۲ IP، IPv4/IPv6، TUN و MTU

- در `android_src/KingVpnService.java`، سرویس اختصاصی TUN با MTU ثابت 1500، آدرس IPv4 برابر `26.26.26.1/30` و آدرس IPv6 برابر `fd00:1:fd00:1:fd00:1:fd00:1/126` می‌سازد و routeهای `0.0.0.0/0` و `::/0` را اضافه می‌کند.
- خطا در ساخت آدرس/route IPv6 در همین سرویس به fail-closed منجر می‌شود تا تونل IPv4-only با احتمال نشت IPv6 برقرار نشود.
- این مسیر custom در `lib/own_vpn.dart` با `kOwnVpnService=false` غیرفعال است؛ پس وجود routeهای کامل در کلاس Java به‌هیچ‌وجه اثبات نمی‌کند مسیر plugin-managed فعلی همین پوشش را دارد.
- MTU=1500 ثابت است؛ PMTU discovery، fragmentation در مسیر واقعی، شبکه‌های موبایل با MTU کمتر، UDP/QUIC و IPv6 هنوز روی دستگاه اندازه‌گیری نشده‌اند.
- اسکن خودکار IP در `lib/ip_auto_scan.dart` برای حالت جهانی از IPهای دقیق کانفیگ‌های شناخته‌شده و در حالت ملی از حافظه/نتایج همان موتور ملی استفاده می‌کند؛ CIDR عمومی خودکار غیرفعال است (`cfIpsBatch=0`, `liveRanges=[]`). این جداسازی باید حفظ شود.
- اسکنر SNI/Port از IPهای پوشه جهانی و نمونه‌های محدود CDN استفاده می‌کند و در صورت VPN فعال/درحال‌راه‌اندازی متوقف می‌شود؛ این تست‌ها برای یافتن endpoint هستند و تست عبور ترافیک VPN نیستند.

**نتیجه:** طراحی fail-closed IPv6 در custom service مشاهده شد، اما مسیر فعال plugin-managed و data-plane هر دو خانواده IP هنوز **NOT TESTED** هستند.

### ۱۴.۳ SNI، Host، TLS fingerprint، ALPN و REALITY

- مسیر `SNIFIX` فقط وقتی `security=tls`، `serverName` خالی و WS Host/header موجود و فاقد colon باشد، Host را به‌عنوان SNI قرار می‌دهد. این fallback محدود به WS است؛ SNI صریح کانفیگ حفظ می‌شود.
- `_reliableVpnCfg()` برای inboundهای محلی، sniffing با `destOverride=['http','tls']` و `routeOnly=true` را فعال/اضافه می‌کند. این قابلیت برای تشخیص مقصد و routing داخلی است؛ SNI واقعی handshake را تغییر نمی‌دهد و به‌تنهایی ضد-DPI نیست.
- ابزارهای SNI/ALPN روی IP مشخص TCP برقرار کرده و TLS handshake را با نام دامنه یا ALPN درخواستی انجام می‌دهند. در probe فعلی `onBadCertificate: (_) => true` است؛ بنابراین موفقیت فقط نشانه برقراری handshake با آن SNI است، نه اعتبار گواهی، تطابق محتوای HTTP، مالکیت دامنه یا عبور از فیلترینگ برای ترافیک عمومی.
- پورت‌های تست‌شده محدود به 443، 8443، 2053، 2083، 2087 و 2096 هستند. باز بودن TCP port به معنی HTTPS سالم یا تونل قابل استفاده نیست.
- در مسیر REALITY، پارامترهای publicKey، shortId و serverName برای سازگاری کانفیگ اهمیت دارند؛ لاگ گواهی واقعی/redirect می‌تواند نشانه mismatch یا دستکاری مسیر باشد، اما تشخیص قطعی MITM بدون شواهد TLS مستقل انجام نمی‌شود.
- تنظیمات TLS fingerprint، ALPN، WebSocket Host/path، gRPC serviceName، REALITY و Fragment/Mux در ماتریس/تبدیل کانفیگ وجود دارند؛ اثر هر variant بر شبکه اپراتور، handshake، throughput و پایداری هنوز در ماتریس دستگاهی مقایسه نشده است.

**نتیجه:** پشتیبانی parsing/normalization و probeهای محدود وجود دارد؛ هیچ نتیجه‌ای درباره عبور قطعی از DPI یا کارکرد SNI/Fragment در اپراتور خاص ثبت نمی‌شود. وضعیت: **IMPLEMENTATION OBSERVED / CIRCUMVENTION NOT PROVEN**.

### ۱۴.۴ DPI، packet shaping و fragmentation

- گزینه‌های Fragment، fingerprint، ALPN، SNI/Host، WebSocket/gRPC، REALITY، Mux و TCP socket options در سورس/ماتریس دیده می‌شوند. اینها پارامترهای سازگاری و transport هستند، نه تضمین عبور از DPI.
- در normalization، برای outboundهای واجد شرایط TCP Fast Open، TCP NoDelay، KeepAlive=15 و TCP MSS=1400 در صورت نبود مقدار از قبل تنظیم می‌شود؛ Worker outbound از این دستکاری مستثنا است.
- Fragment/Noise/Mux می‌توانند در برخی شبکه‌ها latency، CPU، packet overhead یا throughput را بدتر کنند. روشن‌کردن هم‌زمان همه گزینه‌ها بدون آزمون A/B و تأیید data-plane مجاز نیست.
- هیچ packet capture از SYN/TLS ClientHello/SNI، اندازه و مرز packetها، retransmission، fragmentation، PMTU، UDP/QUIC یا رفتار DPI در این ممیزی در دسترس نیست.
- هیچ تکنیک نباید به‌عنوان عبور تضمینی از فیلترینگ یا قطع اینترنت معرفی شود. فقط نتیجه تست زمان‌دار و تکرارپذیر روی اپراتور/منطقه/نسخه سیستم‌عامل مشخص قابل ثبت است.

**نتیجه:** اثر ضد-DPI/Fragmentation هنوز **NOT TESTED**؛ هرگونه ادعای bypass قطعی ممنوع.

### ۱۴.۵ دامنه، Host و میزبانی واقعی

- IP، Host header، SNI و دامنه چهار مفهوم متفاوت‌اند؛ یکی جای دیگری را نمی‌گیرد. دامنه CDN ممکن است به IP مشترک اشاره کند و TLS SNI/HTTP Host باید با سرویس و گواهی مورد انتظار سازگار باشد.
- برچسب کشور، ASN، PTR یا قرار داشتن IP در یک بازه منتسب به ISP، به‌تنهایی میزبانی واقعی در ایران یا عبور ترافیک در شبکه ملی را ثابت نمی‌کند.
- برای پذیرش یک endpoint ملی لازم است DNS resolution در همان اپراتور، ASN/route و مالکیت/میزبانی قابل استناد، TCP/TLS/HTTP response معتبر و در نهایت data-plane از داخل TUN ثبت شوند.
- هیچ سرور یا دامنه‌ای فقط بر اساس geolocation یا نام ارائه‌دهنده به‌عنوان «میزبان داخل ایران» تأیید نمی‌شود.

**نتیجه:** تشخیص میزبانی داخلی و دسترس‌پذیری ملی برای endpointهای واقعی هنوز **NOT TESTED / EVIDENCE REQUIRED** است.

## ۱۵. یافته‌های ممیزی و ریسک‌های قابل پیگیری

| شناسه | یافته | اثر احتمالی | اقدام/معیار پذیرش | وضعیت |
|---|---|---|---|---|
| NET-DNS-01 | DNS ملی plaintext-first و Secure DNS صرفاً fallback است | امکان مشاهده DNS توسط resolver/شبکه محلی | حالت strict encrypted با رفتار fallback صریح و تست packet-level؛ بدون شکستن دسترسی ملی | OPEN |
| NET-DNS-02 | DoH استاندارد و schemeهای local از نظر routing رفتار یکسان ندارند | bypass ناخواسته routing یا شکست bootstrap | capture مقصد DNS و outbound tag برای هر scheme | OPEN |
| NET-IP-01 | IPv6 route در custom service وجود دارد ولی custom service غیرفعال است | اختلاف پوشش IPv6 در مسیر plugin-managed | بررسی plugin builder و تست IPv4/IPv6 روی دستگاه با VPN فعال | OPEN |
| NET-MTU-01 | MTU ثابت 1500 است | blackhole/fragmentation در مسیرهای با MTU کمتر | PMTU/UDP/TCP test و اندازه‌گیری روی Wi-Fi و cellular | OPEN |
| NET-SNI-01 | SNI fallback فقط از WS Host در حالت TLS خالی استفاده می‌کند | کانفیگ‌های غیر-WS یا Host نامعتبر ممکن است شکست بخورند | تست ماتریس پروتکل و جلوگیری از اعتماد به Host بدون validation | OPEN |
| NET-SNI-02 | probe SNI گواهی را نادیده می‌گیرد و HTTP را اعتبارسنجی نمی‌کند | false positive برای TLS reachability | تفکیک TLS handshake، certificate validation و HTTP response | OPEN |
| NET-DPI-01 | اثر Fragment/Mux/fingerprint/ALPN فقط از سورس قابل مشاهده است | احتمال ادعای عملکرد بدون شاهد | A/B روی اپراتورهای مشخص، packet capture و data-plane | OPEN |
| NET-HOST-01 | IP/ASN/geolocation برای اثبات میزبانی داخلی کافی نیست | انتخاب اشتباه سرور ملی | شواهد DNS/ASN/route/hosting و data-plane محلی | OPEN |

## ۱۶. ترتیب ادامه ممیزی شبکه

1. بازیابی build manifest و dependency lockfile واقعی مخزن؛ تولید SBOM و بررسی مجوزها/CVE با نسخه‌های دقیق.
2. بررسی مسیر فعال plugin-managed: IPv4/IPv6 routes، DNS capture، socket protection و lifecycle؛ custom service را فعال نکن.
3. تکمیل ماتریس SNI/Host/TLS/ALPN/REALITY/WS/gRPC با تست‌های unit و config fixtures؛ probeهای TLS را از HTTP/data-plane جدا کن.
4. بررسی دقیق تنظیمات Fragment/Mux/Noise/TFO/MSS و جلوگیری از ترکیب‌های پرهزینه بدون شواهد.
5. اجرای packet/device acceptance برای DNS، IPv4، IPv6، TCP، UDP/QUIC، PMTU و شبکه handover.
6. آزمون جداگانه Wi-Fi و cellular و اپراتورهای هدف؛ نتایج national/global و زمان/منطقه/نسخه Android ثبت شوند.
7. بررسی شواهد میزبانی واقعی دامنه/IPهای داخلی و عدم اعتماد به country label به‌تنهایی.
8. پس از هر تغییر کد، exact-head CI، سه بازبینی مستقل و تکرار تست‌های مرتبط الزامی است.

وضعیت کل پروژه همچنان **IN PROGRESS / VERIFIED WITH LIMITATIONS** است. این فاز صرفاً یافته‌های ایستای سورس را ثبت می‌کند؛ هیچ packet capture، دستگاه واقعی، اپراتور ایران یا bypass موفق DPI ادعا نشده است.


## ۱۷. Dependency و reproducible-build audit — یافته جدید

- مخزن در root فعلی `pubspec.yaml` و `pubspec.lock` نگه نمی‌دارد؛ پروژه Flutter در CI با `flutter create` به‌صورت موقت در `build_app` تولید می‌شود و سورس `lib/` و `test/` به آن کپی می‌شوند.
- workflow وابستگی‌ها را در زمان اجرا با `flutter pub add` اضافه می‌کند. فقط بخشی از وابستگی‌های مستقیم constraint نسخه دارند؛ مواردی مانند `http`, `webview_flutter`, `permission_handler`, `workmanager`, `url_launcher`, `path_provider` و `package_info_plus` در دستور فعلی بدون نسخه دقیق آمده‌اند.
- Flutter action روی channel برابر `stable` تنظیم شده و نسخه SDK در workflow به شماره release ثابت pin نشده است. بنابراین buildهای آینده ممکن است با نسخه Flutter یا dependency graph متفاوتی resolve شوند، حتی اگر commit سورس یکسان باشد.
- AGP و Gradle در `prepare_android.py` به‌ترتیب روی 9.3.1 و 9.5.0 تنظیم می‌شوند؛ این pinها بخشی از toolchain هستند اما جای lockfile و SBOM را نمی‌گیرند.
- workflow پس از `flutter pub get`، سورس plugin دریافت‌شده در Pub cache را با `patch_plugin.py` تغییر می‌دهد. برای provenance کامل باید نسخه/محتوای دقیق plugin، transitive dependencies و patch diff به‌صورت artifact قابل ردیابی ذخیره شوند.
- فایل `NOTICE.md` به‌تنهایی inventory مجوزهای مستقیم/غیرمستقیم نیست. در این مرحله نه Pub lockfile قابل بازبینی وجود داشت و نه SBOM، license report یا CVE scan برای dependency graph دقیق تولید شد.

**ریسک:** build فعلی CI قابل ساخت است، اما dependency resolution به‌طور کامل reproducible و supply-chain inventory کامل نیست. وضعیت: **DEPENDENCY INVENTORY BLOCKED**.

**اقدام لازم:** تثبیت نسخه Flutter SDK؛ تعریف constraint دقیق برای همه dependencyهای مستقیم؛ تولید و commit کردن `pubspec.lock` از build_app واقعی؛ ثبت checksum/source provenance برای plugin patch؛ تولید CycloneDX/SPDX SBOM؛ بررسی مجوزهای transitive و CVE با timestamp؛ سپس build دقیق از lockfile و مقایسه artifact.



## ۱۸. اصلاح مبتنی بر artifact: dependency lockfile واقعاً تولید شده است

این بخش، محدودیت مطرح‌شده در بخش ۱۷ را دقیق‌تر می‌کند:

- Artifact کامل سورس CI Run 2157 با شناسه `14798807054` دانلود و باز شد. SHA-256 آرشیو بیرونی با digest اعلام‌شده GitHub برابر است: `9d65f7ae6f66fd1dbb99c3835b2bd2cf8af97e81edb03d19d79434a86c6c9d15`.
- ZIP داخلی شامل `build_app/pubspec.yaml` و `build_app/pubspec.lock` است؛ بنابراین lockfile برای همان build واقعاً وجود دارد، اما در مخزن commit نشده و در هر اجرای CI دوباره تولید می‌شود.
- نسخه toolchain از log همان Run 2157: Flutter `3.50.1`، Framework revision `ae9b586f34`، Dart `3.14.0`، Java `21.0.13`. Workflow همچنان channel شناور `stable` را درخواست می‌کند.
- lockfile شامل 116 package است: 111 hosted package و 5 SDK package؛ 19 dependency مستقیم main و 2 dependency مستقیم dev. تعداد packageهای hosted دارای SHA-256 در lockfile: 111.
- SHA-256 فایل `pubspec.yaml` در artifact: `d4206ee05eacd3bb3682b8f0f5b62948f110881a3d6ea1291cbe64af334fe5d8`.
- SHA-256 فایل `pubspec.lock` در artifact: `f531c1ac1fcee55851992a6d76bfb3893b7fc4b2508e20e4adb0cedaa0fa159c`.
- این inventory، snapshot دقیق dependency resolution برای commit کد `649147e8a3c96979f1bbab82c14ccff09f6bbf2d) و Flutter 3.50.1 است؛ به commitهای بعدی یا buildهای آینده تعمیم داده نمی‌شود.
- هنوز SBOM استاندارد، license metadata کامل برای تمام packageها، بررسی مجوزهای transitive و CVE scan تولید نشده است. Hashهای lockfile به‌تنهایی گزارش آسیب‌پذیری یا انطباق مجوز نیستند.

**وضعیت اصلاح‌شده:** dependency graph یک build تاریخی قابل بازیابی و hash-verified است؛ اما lockfile در مخزن version-control نشده، reproducibility آینده تضمین نیست، و SBOM/license/CVE review همچنان **OPEN** است.


## ۱۹. اجرای مستقل تست‌های artifact و secret-pattern triage

- Full-source artifact مربوط به CI Run 2157 از GitHub دریافت شد و ZIP داخلی آن استخراج شد. تمام فایل‌های سورس در snapshot artifact با هم بررسی شدند.
- اجرای مستقل مجموعه تست Python از ریشه سورس artifact: **280 passed, 23 subtests passed** در 0.95 ثانیه. این شامل guardها و تست‌های Python موجود در snapshot است؛ معادل اجرای Flutter/Dart یا Android runtime نیست.
- تلاش برای اجرای همان تست‌ها از پوشه `build_app/test` به‌تنهایی به علت کپی نشدن پوشه root-level `tools/` در generated Flutter host با خطای import/collection روبه‌رو شد. اجرای صحیح از root artifact موفق بود؛ این مورد نقص تست‌های root نیست، اما نشان می‌دهد تست‌های Python نباید از مسیر build_app به‌تنهایی اجرا شوند.
- ابزارهای `flutter`, `dart`, `syft`, `trivy`, `osv-scanner`, `gitleaks` و `semgrep` در محیط محلی این ممیزی در دسترس نبودند؛ بنابراین اجرای مجدد Flutter tests، Dart analysis، SBOM، CVE و اسکن استاندارد secrets در این محیط ادعا نمی‌شود. CI قبلی برای commit کد مرجع، test/analyze/build را با موفقیت انجام داده است.
- اسکن regex محدود برای الگوهای کلید خصوصی، GitHub token، Google API key و AWS access key چند match فقط در فایل‌های تست پیدا کرد. بررسی متن نشان داد اینها fixtureهای ساختگی و عمداً برای آزمون redaction/secret detection هستند؛ هیچ مقدار واقعی از آن‌ها در گزارش بازنشر نشد. این اسکن heuristic و محدود است و جایگزین gitleaks/trufflehog و تاریخچه کامل Git نیست.
- شمارش مجدد lockfile artifact: 116 package شامل 111 hosted و 5 SDK؛ هر 111 hosted package دارای SHA-256 در فیلد `description.sha256` است. SHA-256 فایل‌ها در بخش ۱۸ ثبت شده‌اند.

**نتیجه:** Python test snapshot مستقل PASS؛ Flutter/Dart و Android device runtime در این محیط NOT RUN؛ secret scan استاندارد و SBOM/CVE همچنان OPEN. Artifact مبنا همان commit `649147e8a3c96979f1bbab82c14ccff09f6bbf2d) است و این نتایج به کد جدیدتر تعمیم داده نمی‌شوند.


## ۲۰. Smart Pilot، نت ملی و دامنه/پورت — ممیزی عمیق‌تر

### ۲۰.۱ طبقه‌بندی شبکه توسط Smart Pilot

- اسکنر اختصاصی Pilot از سه مقصد داخلی `www.aparat.com`, `www.digikala.com`, `divar.ir` و سه مقصد جهانی `www.cloudflare.com`, `www.google.com`, `github.com` استفاده می‌کند؛ هرکدام فقط TLS روی TCP/443.
- برای تأیید هر مسیر، quorum حداقل ۲ پاسخ موفق از ۳ لازم است؛ برای اعلام domestic-only یا global-only، مسیر مقابل نیز باید حداقل دو شکست معتبر داشته باشد. شواهد ناقص/متناقض حالت قبلی را حفظ می‌کنند.
- هویت شبکه قبل و بعد از probe خوانده می‌شود؛ اگر Wi-Fi/mobile در میانه تغییر کند، snapshot رد و یک بار تکرار می‌شود. cache فقط برای همان identity و حداکثر دو دقیقه معتبر است.
- در دسترس بودن TLS مقصد، اثبات عبور داده از VPN نیست. این probe برای تشخیص مسیر پایه قبل از اتصال و انتخاب راهبرد داخلی/جهانی است، نه health check تونل یا اثبات دسترسی به همه دامنه‌های ایران.
- فهرست ثابت سه‌تایی محدود است؛ اختلال یک دامنه یا DNS resolver می‌تواند طبقه‌بندی را ناقص کند. به همین دلیل quorum و حالت preserve لازم است. گسترش دامنه‌ها باید با تنوع ASN/شبکه و مالکیت قابل اتکا انجام شود، نه صرفاً زیاد کردن تعداد دامنه‌ها.

### ۲۰.۲ پورت، Host و دامنه

- ترتیب اولویت port hopping در موتور ملی: `443, 80, 8443, 2053, 2083, 2087, 2096`. این فهرست برای سازگاری endpoint/CDN است؛ باز بودن پورت به‌تنهایی سرویس VPN سالم یا عبور DPI را ثابت نمی‌کند.
- دامنه‌های probe ملی شامل `nic.ir`, `iran.ir`, `ac.ir`, `www.aparat.com`, `www.digikala.com` هستند؛ در حالت خودکار، دامنه probe محدودتر است. مقصدهای جهانی برای health شامل چند endpoint عمومی و سرویس‌های DoH نیز هستند.
- در نت ملی، IP scanner خودکار فقط از IPهای دقیق منابع/حافظه ملی و hitهای قبلی استفاده می‌کند؛ پیمایش CIDR عمومی ISP/CDN در مسیر خودکار غیرفعال است (`cfIpsBatch=0`, `liveRanges=[]`). این محدودیت برای جلوگیری از اسکن بی‌هدف و اختلاط candidateهای داخلی/جهانی باید حفظ شود.
- تشخیص اپراتور/ASN در بعضی مسیرهای موتور ملی از سرویس‌های ثالث IP metadata استفاده می‌کند. این داده کمکی است و به‌تنهایی مالکیت میزبانی، حضور فیزیکی سرور در ایران یا route واقعی شبکه ملی را ثابت نمی‌کند.
- برای endpointهای داخلی، پذیرش نهایی باید با resolver همان شبکه، ASN/BGP و شواهد میزبانی، TCP/TLS/HTTP معتبر و در نهایت اتصال موفق VPN و data-plane داخل TUN انجام شود. هیچ دامنه/IP فعلی صرفاً بر اساس پسوند `.ir` یا country label تأیید ملی نمی‌شود.

### ۲۰.۳ وضعیت AI Pilot و حاکمیت تغییرات

- Smart Pilot در اتصال اصلی، موتور V2Ray موجود را انتخاب می‌کند؛ طبقه‌بندی داخلی/جهانی با شواهد deterministic انجام می‌شود. مدل محلی نقش مشاور محدود دارد و timeout/نبود مدل نباید حلقه deterministic را متوقف کند.
- سیاست autonomy اجازه مشاهده شبکه، یادگیری از شواهد و تنظیم runtime محدود را با شروط نمونه کافی و rollback می‌دهد؛ آماده‌سازی candidate کد نیازمند نمونه بیشتر و issue تکرارپذیر است. اعمال سورس نیازمند احراز هویت مالک، مجوز کوتاه‌مدت مختص همان candidate و CI سبز است؛ انتشار نیازمند مجوز جداگانه و release validation است.
- پژوهش پس‌زمینه read-only با allowlist رسمی هر ۶ ساعت best-effort است؛ audit روزانه و CI repair با WorkManager زمان‌بندی می‌شوند و تضمین اجرای دقیق ندارند. مدل در پس‌زمینه دانلود نمی‌شود؛ نبود مدل/توکن باعث توقف یا عدم اجرای task می‌شود.
- مالکیت نصب جدید با token حساب GitHub و تطبیق login با owner مخزن `cafeeteriaa` احراز می‌شود؛ رمز محلی با Argon2id و Secure Storage نگهداری می‌شود. session واقعی کد **۲ دقیقه** است.
- **نقص UI اصلاح شد:** متن کنسول اشتباهاً «حداکثر ۱۵ دقیقه» نمایش می‌داد؛ با مقدار واقعی ۲ دقیقه همسان شد و source guard برای جلوگیری از برگشت mismatch اضافه شد. این اصلاح روی شاخه ممیزی است؛ CI مربوط به آن در زمان ثبت این بخش هنوز در حال اجرا بود.

**نتیجه:** Smart Pilot دارای محافظه‌کاری مناسب در انتخاب domestic/global و جداسازی poolها است، اما probe محدود TCP/443 و داده‌های ASN/IP metadata برای اثبات کامل شرایط نت ملی کافی نیست. پذیرش عملیاتی همچنان نیازمند تست چند اپراتور، دستگاه واقعی و data-plane است.

## ۲۱. اعتبارسنجی artifact دقیق HEAD — CI Run 2170

- HEAD بررسی‌شده: `e6ecebe0de842ec3ad1b3794635880bc9c9edea1` روی شاخه `audit/final-master`؛ PR #44 همچنان Draft و باز است و شاخه `main` تغییر نکرده است.
- GitHub Actions Run 2170 با شناسه `45141258460` برای همین SHA با نتیجه **SUCCESS** پایان یافت. تمام مراحل اصلی موفق بودند: source-repair guards، setup toolchain، تولید Flutter host، resolve dependencies، patch plugin، unit tests، Dart analysis، arm64 release APK، بررسی ELF 16 KiB، بررسی APK ZIP alignment و upload artifactها.
- Artifact APK با شناسه `14802108565` دریافت شد. SHA-256 آرشیو ZIP: `ee3cfa82808c6001a897ec9a71a2e2f6da866458cf88640fb9f6d8e305e08c96`؛ با digest اعلام‌شده GitHub Actions برابر است.
- APK داخلی `app-arm64-v8a-release.apk`، اندازه 122,885,758 بایت؛ SHA-256: `eadf5f7e8da0617cee42b772d60abe74067713dc8801aa87d029e971aacdbdc0`.
- بازرسی مستقل ZIP: 330 entry؛ 19 کتابخانه native در ABI برابر `arm64-v8a`؛ هیچ‌یک از entryهای native در offset نامنطبق با مرز 16 KiB قرار نداشتند.
- بازرسی مستقل ELF با `readelf`: 58 عدد LOAD segment از 19 کتابخانه؛ همگی دارای `p_align` برابر 16 KiB یا 64 KiB بودند؛ segment زیر 16 KiB مشاهده نشد.
- این محیط ابزار رسمی `apksigner`/Android Build Tools را نداشت؛ بنابراین امضای APK، گواهی و v2/v3 signing block به‌طور مستقل بررسی نشده‌اند. موفقیت workflow یا وجود APK به‌تنهایی اثبات production signing نیست؛ artifact را release امضاشده یا install-ready اعلام نکنید.
- CI و بازرسی ZIP/ELF، تست روی دستگاه واقعی، رقابت با VPN دیگر، packet capture، نشت DNS، مسیر IPv4/IPv6، اپراتورهای ایران، دسترسی نت ملی و عبور واقعی ترافیک از TUN را اثبات نمی‌کنند.
- متن بخش ۲۰.۳ درباره «CI هنوز در حال اجرا» مربوط به لحظه ثبت قبلی آن بخش است؛ نتیجه نهایی بعدی برای همان HEAD اکنون در Run 2170 با وضعیت SUCCESS ثبت شده است.

**نتیجه این checkpoint:** exact-head CI و بازرسی مستقل ساختار APK/ELF **PASS**؛ بررسی مستقل امضا، دستگاه واقعی و data-plane **NOT VERIFIED / OPEN**.


## ۲۲. اصلاح دامنه اسکن IP در نردبان نت ملی

- بازبینی مسیر `_atIpSweep` نشان داد که علاوه بر بازه‌های منتشرشده Cloudflare، کد بلوک‌های `/24` مجاور IP سرورهای موجود در فهرست `good` را نیز به‌صورت خودکار گسترش می‌داد.
- داشتن یک IP در کانفیگ، به‌تنهایی مجوز یا مالکیت اسکن آدرس‌های مجاور آن بلوک را ثابت نمی‌کند. این رفتار همچنین با اصل محدودسازی اسکن خودکار به منابع شناخته‌شده و مستند ناسازگار بود.
- اصلاح شد: گسترش خودکار بلوک‌های مجاور حذف شد؛ مرحله‌ی IP Sweep فقط از فهرست CIDRهای منتشرشده‌ی ارائه‌دهنده CDN که در `_cfRanges` ثبت شده‌اند استفاده می‌کند. تأیید نهایی هر candidate همچنان نیازمند اتصال واقعی VPN و عبور ترافیک از TUN است.
- Source Guard جدید در `test/test_source_guards.py` نبودن helper و استفاده انحصاری از `_cfRanges` در مسیر `_atIpSweep` را الزام می‌کند.
- این تغییر، اسکن عمومی CIDRهای ISP یا شبکه‌های اشخاص ثالث را اضافه نمی‌کند و هیچ نتیجه‌ای درباره باز بودن پورت یا دور زدن DPI بدون تست end-to-end اعلام نمی‌کند.

**وضعیت:** اصلاح سورس و guard ثبت شد؛ نتیجه‌ی CI روی commit جدید باید جداگانه بررسی شود.


## ۲۳. اعتبارسنجی گواهی در نتایج ذخیره‌شده SNI و ALPN

- ممیزی مسیر اسکن خودکار نشان داد که `_autoSniOk` و `_autoAlpnOk` با `onBadCertificate: (_) => true` گواهی TLS نامعتبر را نیز می‌پذیرفتند؛ در نتیجه صرف موفقیت handshake می‌توانست به‌عنوان SNI/ALPN سالم ذخیره شود.
- اصلاح شد: callback دورزننده‌ی اعتبار گواهی حذف شد تا اعتبارسنجی پیش‌فرض زنجیره و نام میزبان Dart برقرار بماند. نتایج ذخیره‌شده اکنون باید از handshake و اعتبارسنجی گواهی عبور کنند.
- Source Guard اضافه شد تا هیچ‌یک از این دو probe دوباره callback پذیرش گواهی نامعتبر نداشته باشد.
- این اصلاح به معنی اثبات عبور از DPI یا اتصال VPN نیست؛ فقط کیفیت سیگنال TLS ذخیره‌شده را بهتر می‌کند. تست روی دستگاه و شبکه‌های واقعی همچنان لازم است.

**وضعیت:** اصلاح سورس و guard ثبت شد؛ CI باید روی commit جدید نتیجه بدهد.


## ۲۴. همسان‌سازی تشخیص لایه SNI/DPI با اعتبارسنجی واقعی TLS

- در مسیر تشخیص شبکه `lib/net_diag.dart::_diagTls` نیز callback پذیرش همه‌ی گواهی‌ها وجود داشت. این موضوع می‌توانست TLS با گواهی نامعتبر را موفق ثبت کند و در نتیجه طبقه‌بندی SNI/DPI را منحرف سازد.
- callback حذف شد و اعتبارسنجی پیش‌فرض گواهی و hostname فعال ماند؛ Source Guard اختصاصی نیز اضافه شد.
- نتیجه‌ی مثبت این probe فقط موفقیت TLS معتبر تا IP و SNI انتخاب‌شده را نشان می‌دهد؛ به‌تنهایی اثبات عبور از DPI، HTTP سالم یا عبور ترافیک VPN از TUN نیست.
- هیچ تغییر در مسیر واقعی DNS/TUN یا سیاست‌های اتصال در این commit انجام نشده است.

**وضعیت:** اصلاح سورس و guard ثبت شد؛ CI روی commit جدید باید جداگانه تکمیل شود.


## ۲۴. سخت‌سازی parser پاسخ DNS در NNIE

- در parser پاسخ DNS، نام مقصد CNAME از RDATA خوانده می‌شد بدون اینکه طول encoded name با مقدار RDLENGTH رکورد تطبیق داده شود؛ در بسته‌ی بدساخت، parser می‌توانست از مرز RDATA عبور کند.
- اصلاح شد: طول encoding نام CNAME باید دقیقاً با RDLENGTH برابر باشد؛ pointer فشرده‌سازی DNS نیز باید به offset معتبر داخل همان بسته اشاره کند.
- طول نام DNS ورودی برای ساخت query به سقف ۲۵۳ بایت محدود شد.
- تست واحد برای CNAME با RDLENGTH ناسازگار و Source Guard برای سه محدودیت اضافه شد.
- این تغییر صرفاً parser و کیفیت تشخیص DNS را سخت‌گیرانه‌تر می‌کند؛ نتیجه‌ی آن اثبات عدم نشت DNS یا عملکرد resolver در شبکه‌ی واقعی نیست.

**وضعیت:** اصلاح سورس، تست و guard ثبت شد؛ منتظر CI روی commit جدید.


## ۲۵. تکمیل سیاست Secure DNS برای DoQ

- بازبینی سیاست DNS نشان داد که resolverهای `quic://` (DNS-over-QUIC) در کنار `quic+local://` به‌عنوان DNS رمزگذاری‌شده شناسایی نمی‌شدند؛ بنابراین در حالت Secure DNS خاموش، ممکن بود از فهرست resolverهای موجود باقی بمانند.
- اصلاح شد: هر دو scheme مربوط به QUIC در کنار DoH در طبقه‌ی resolver رمزگذاری‌شده قرار گرفتند و در سیاست ملی با Secure DNS خاموش فیلتر می‌شوند.
- تست واحد و Source Guard برای جلوگیری از بازگشت این مورد اضافه شد.
- این تغییر صرفاً policy انتخاب resolver را اصلاح می‌کند؛ اثبات عدم نشت DNS نیازمند packet capture و آزمایش واقعی روی دستگاه است.

**وضعیت:** اصلاح سورس، تست و guard ثبت شد؛ CI روی commit جدید باید بررسی شود.


## ۲۶. حذف پذیرش گواهی نامعتبر از آزمون IP تمیز و سلامت TLS سرور

- در `_cfProbeMs` مسیر IP تمیز Cloudflare و `probe(Server s)` برای سنجش TLS سرور، callback پذیرش همه‌ی گواهی‌ها وجود داشت.
- هر دو مسیر اکنون اعتبارسنجی پیش‌فرض گواهی و تطبیق نام میزبان/SNI را رعایت می‌کنند؛ دو Source Guard برای جلوگیری از بازگشت bypass اضافه شد.
- این کار ممکن است برخی endpointهای دارای گواهی نامعتبر یا SNI اشتباه را از نتایج «سالم» حذف کند؛ این رفتار مطلوب است تا رتبه‌بندی بر پایه TLS قابل‌اعتماد باشد.
- صحت نهایی اتصال همچنان با تست واقعی core و عبور ترافیک TUN سنجیده می‌شود، نه صرفاً probe.

**وضعیت:** اصلاح سورس و guard ثبت شد؛ CI commit جدید باید تأیید کند.


## ۲۶. اصلاح اندیس‌های SNI جایگزین در Smart Pilot نت ملی

- در مولد variantهای SNI، اندیس `10` به فهرست `natFrontSnis` ارجاع داده می‌شد، در حالی که فهرست جاری فقط اندیس‌های `0..7` دارد؛ در نتیجه بخشی از variantهای تولیدشده عملاً بدون تغییر SNI باقی می‌ماندند.
- اندیس نامعتبر با اندیس معتبر دامنه‌ی هشتم جایگزین شد.
- ورودی `1.1.1.1` نیز از فهرست SNI حذف و با نام میزبان `cloudflare-dns.com` جایگزین شد؛ SNI باید نام DNS باشد، نه literal آدرس IP.
- Source Guard برای سازگاری اندیس‌ها و جلوگیری از بازگشت IP literal اضافه شد.
- این اصلاح فقط تولید کانفیگ را درست می‌کند؛ موفقیت اتصال و سازگاری گواهی/Host باید در تست واقعی tunnel بررسی شود.

**وضعیت:** اصلاح سورس و guard ثبت شد؛ منتظر CI.
