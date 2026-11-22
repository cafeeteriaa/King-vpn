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
- هنوز build دقیق HEAD شاخه audit/final-master اجرا نشده است.
- هنوز اندازه APK بعد از تغییرات این شاخه اندازه‌گیری نشده است.
- هنوز هیچ موتور جدیدی اضافه یا روی گوشی تأیید نشده است.
- هیچ اتصال واقعی، DNS leak test، IPv4/IPv6 packet test، اپراتور ایران، failover یا process-death device test در این مرحله ادعا نمی‌شود.

## ۱۱. شرط وضعیت نهایی

تا وقتی هر بخش مهم BLOCKED یا NOT TESTED باشد، وضعیت کل پروژه **FINAL VERIFIED WITH LIMITATIONS** خواهد بود، نه FINAL VERIFIED. هر نتیجه فقط پس از اجرای واقعی معیار پذیرش و ثبت commit، log، artifact و hash قابل ارتقا است.
