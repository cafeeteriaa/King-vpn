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
