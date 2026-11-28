part of 'main.dart';

// DNSSCAN: اسکنر DNS. هر resolver با یک پرس‌وجوی UDP به پورت 53 امتحان می‌شود.
// پاسخ فقط وقتی «سالم» است که IP عمومی واقعی بدهد. پاسخ‌های جعلی یا صفحه‌ی بلاک
// (مثل 10.10.34.34 یا آی‌پی خصوصی) رد می‌شوند.
// در نت ملی: دامنه‌ی تست داخلی و DNSهای داخلی؛ اسکن به‌صورت خودکار و در پس‌زمینه انجام می‌شود.
const List<String> kDnsxDefaults = [
  '8.8.8.8',
  '8.8.4.4',
  '1.1.1.1',
  '1.0.0.1',
  '9.9.9.9',
  '149.112.112.112',
  '208.67.222.222',
  '208.67.220.220',
  '94.140.14.14',
  '94.140.15.15',
];

// DNSهای داخلی که از قبل در پروژه (npv_am_extras.dart) آمده‌اند
const List<String> kDnsxNationalDefaults = [
  '178.22.122.100',
  '185.51.200.2',
  '78.157.42.100',
  '10.202.10.10',
];

/// دامنه‌های تست در نت ملی: دامنه‌های داخلی (.ir) و سایت‌های داخلی که خود برنامه
/// برای تشخیص شبکه استفاده می‌کند. هر DNS روی همه‌ی این دامنه‌ها سنجیده می‌شود،
/// تا نتیجه‌ی DNSهای مختلف با هم قابل مقایسه باشد.
const List<String> kDnsxNationalProbeDomains = <String>[
  'nic.ir',
  'iran.ir',
  'ac.ir',
  'www.aparat.com',
  'www.digikala.com',
];

/// دامنه‌های اسکن خودکار پس‌زمینه (کوچک، تا نت ملی بی‌جهت بار نشود)
List<String> dnsxAutoDomains() =>
    nationalMode ? kDnsxNationalProbeDomains : const ['google.com'];

/// تبدیل فهرست‌های پروژه (مثل `domain:divar.ir`) به نام میزبان ساده
List<String> _dnsxHostsFrom(Iterable<String> src) {
  final out = <String>[];
  final okChars = RegExp(r'^[a-z0-9.-]+$');
  for (var s in src) {
    s = s.trim().toLowerCase();
    if (s.startsWith('domain:')) s = s.substring(7);
    if (s.startsWith('full:')) s = s.substring(5);
    // فقط نام دامنه‌ی واقعی؛ TLD تنها (مثل ir) و قانون‌های geoip و کلمه‌ی کلیدی کنار گذاشته می‌شوند
    if (!s.contains('.') || !okChars.hasMatch(s)) continue;
    out.add(s);
  }
  return out;
}

/// سایت‌های خارجی پرکاربرد برای سنجیدن اینکه DNS بین‌المللی را درست جواب می‌دهد یا نه
/// فهرست گسترده‌ی سایت‌های خارجی پرکاربرد، دسته‌بندی‌شده (جستجو، شبکه‌های اجتماعی، پیام‌رسان،
/// ویدیو، خبر، مرجع، فنی و ابری، هوش مصنوعی، خرید و مالی، سفر، بازی).
/// یادآوری: مجموعه‌ی «همه‌ی دامنه‌های خارجی» وجود ندارد؛ این فهرست محبوب‌ترین‌ها را پوشش می‌دهد.
const List<String> kDnsxGlobalDomains = <String>[
  // جستجو و پورتال
  'google.com', 'www.google.com', 'bing.com', 'duckduckgo.com', 'yahoo.com',
  'yandex.ru', 'ecosia.org', 'startpage.com', 'brave.com', 'aol.com',
  // شبکه‌های اجتماعی
  'facebook.com', 'instagram.com', 'twitter.com', 'x.com', 'linkedin.com',
  'reddit.com', 'pinterest.com', 'tumblr.com', 'snapchat.com', 'threads.net',
  'quora.com', 'medium.com', 'vk.com', 'tiktok.com', 'messenger.com',
  // پیام‌رسان
  'telegram.org', 't.me', 'whatsapp.com', 'signal.org', 'discord.com',
  'slack.com', 'line.me', 'viber.com',
  // ویدیو و موسیقی
  'youtube.com', 'youtu.be', 'twitch.tv', 'vimeo.com', 'dailymotion.com',
  'netflix.com', 'hulu.com', 'disneyplus.com', 'primevideo.com', 'spotify.com',
  'soundcloud.com', 'imdb.com', 'rottentomatoes.com',
  // خبر
  'bbc.com', 'bbc.co.uk', 'cnn.com', 'nytimes.com', 'theguardian.com',
  'reuters.com', 'aljazeera.com', 'dw.com', 'france24.com', 'voanews.com',
  'bloomberg.com', 'washingtonpost.com', 'wsj.com', 'economist.com',
  'forbes.com', 'time.com',
  // مرجع و توسعه‌دهندگان
  'wikipedia.org', 'wikimedia.org', 'archive.org', 'britannica.com',
  'stackoverflow.com', 'github.com', 'gitlab.com', 'bitbucket.org', 'npmjs.com',
  'pypi.org', 'python.org', 'mozilla.org', 'ubuntu.com', 'debian.org',
  'kernel.org',
  // فناوری و ابری
  'cloudflare.com', 'microsoft.com', 'office.com', 'live.com', 'outlook.com',
  'apple.com', 'icloud.com', 'android.com', 'gstatic.com', 'googleapis.com',
  'googleusercontent.com', 'gmail.com', 'protonmail.com', 'proton.me',
  'adobe.com', 'oracle.com', 'ibm.com', 'amazonaws.com', 'dropbox.com',
  'box.com', 'notion.so', 'zoom.us', 'trello.com', 'atlassian.com', 'figma.com',
  'canva.com', 'speedtest.net', 'docker.com', 'vercel.com',
  // هوش مصنوعی
  'openai.com', 'chatgpt.com', 'anthropic.com', 'claude.ai', 'perplexity.ai',
  'huggingface.co', 'deepseek.com', 'gemini.google.com', 'mistral.ai',
  'midjourney.com',
  // خرید، پرداخت و مالی
  'amazon.com', 'ebay.com', 'aliexpress.com', 'etsy.com', 'shopify.com',
  'paypal.com', 'stripe.com', 'wise.com', 'visa.com', 'mastercard.com',
  'binance.com', 'coinbase.com', 'kraken.com', 'blockchain.com',
  // سفر و نقشه
  'booking.com', 'airbnb.com', 'tripadvisor.com', 'expedia.com',
  'openstreetmap.org', 'waze.com', 'uber.com', 'skyscanner.com',
  // بازی
  'steampowered.com', 'epicgames.com', 'roblox.com', 'ea.com', 'ubisoft.com',
  'riotgames.com', 'blizzard.com', 'playstation.com', 'xbox.com',
  'nintendo.com', 'minecraft.net', 'chess.com',
];

/// همه‌ی دامنه‌های موجود در پروژه برای اسکن دستی (بدون تکرار): ایرانی و خارجی
List<String> dnsxFullDomains() {
  final all = <String>{
    ...kDnsxNationalProbeDomains,
    ...kDnsxGlobalDomains,
    ...natIrDomains,
    ..._dnsxHostsFrom(iranDomains),
    ..._dnsxHostsFrom(_iranMoreDomains),
  };
  return all.toList();
}

/// متن نمایشی دامنه‌ها در شیت
String dnsxProbeDomain() => '${dnsxFullDomains().length} دامنه (ایرانی و جهانی)';

/// بسته‌ی پرس‌وجوی DNS برای نوع A (RD=1)
List<int> dnsxQuery(String name, int id) {
  final b = <int>[
    (id >> 8) & 0xff, id & 0xff, // ID
    0x01, 0x00, // flags: RD
    0x00, 0x01, // QDCOUNT
    0x00, 0x00, // ANCOUNT
    0x00, 0x00, // NSCOUNT
    0x00, 0x00, // ARCOUNT
  ];
  for (final label in name.split('.')) {
    final bytes = label.codeUnits;
    b.add(bytes.length);
    b.addAll(bytes);
  }
  b.addAll([0x00, 0x00, 0x01, 0x00, 0x01]); // ته‌ی نام، QTYPE=A، QCLASS=IN
  return b;
}

/// آیا این IPv4 عمومی و واقعی است؟ (خصوصی، لوپ‌بک، صفر و بلاک‌پیج رد می‌شوند)
bool dnsxIsPublicV4(int a, int b, int c, int d) {
  if (a == 0 || a == 10 || a == 127 || a >= 224) return false;
  if (a == 169 && b == 254) return false;
  if (a == 172 && b >= 16 && b <= 31) return false;
  if (a == 192 && b == 168) return false;
  if (a == 100 && b >= 64 && b <= 127) return false; // CGNAT
  if (a == 10 && b == 10 && c == 34 && d == 34) return false; // بلاک‌پیج
  return true;
}

/// پاسخ معتبر؟ rcode=0، ID یکسان، و حداقل یک رکورد A عمومی.
bool dnsxAnswerOk(List<int> d, int id) {
  if (d.length < 12) return false;
  final rid = (d[0] << 8) | d[1];
  if (rid != id) return false;
  final rcode = d[3] & 0x0f;
  if (rcode != 0) return false;
  final qd = (d[4] << 8) | d[5];
  final an = (d[6] << 8) | d[7];
  if (an == 0) return false;
  var pos = 12;
  int skipName(int p) {
    while (p < d.length) {
      final len = d[p];
      if (len == 0) return p + 1;
      if ((len & 0xC0) == 0xC0) return p + 2;
      p += len + 1;
    }
    return p;
  }
  for (var i = 0; i < qd; i++) {
    pos = skipName(pos) + 4;
  }
  var goodA = false;
  for (var i = 0; i < an && pos + 10 <= d.length; i++) {
    pos = skipName(pos);
    if (pos + 10 > d.length) break;
    final type = (d[pos] << 8) | d[pos + 1];
    final rdlen = (d[pos + 8] << 8) | d[pos + 9];
    final rd = pos + 10;
    if (type == 1 && rdlen == 4 && rd + 4 <= d.length) {
      if (dnsxIsPublicV4(d[rd], d[rd + 1], d[rd + 2], d[rd + 3])) {
        goodA = true;
      } else {
        return false; // جواب جعلی یا بلاک‌پیج
      }
    }
    pos = rd + rdlen;
  }
  return goodA;
}

/// نتیجه‌ی یک DNS: چند دامنه جواب داد و میانگین زمان آن‌ها
class DnsxHit {
  DnsxHit(this.ip, this.avgMs, this.okCount, this.total,
      {this.ipv4OkCount = 0, this.ipv6OkCount = 0});
  final String ip;
  final int avgMs;
  /// Number of queried names with at least one usable address family.
  final int okCount;
  final int total;
  final int ipv4OkCount;
  final int ipv6OkCount;
}

/// سنجش یک DNS روی فهرست دامنه‌ها. برای جلوگیری از سیل پرس‌وجو، بسته‌به‌بسته (۸ تا ۸ تا) می‌رود.
/// ملاک: حداقل ۲۵٪ دامنه‌ها باید پاسخ معتبر بدهند.
Future<DnsxHit?> dnsxProbe(String server,
    {List<String>? domains,
    Duration timeout = const Duration(seconds: 3),
    Duration gap = Duration.zero,
    bool Function()? stop}) async {
  final list = domains ?? dnsxAutoDomains();
  final times = <int>[];
  var tested = 0;
  var domainHits = 0;
  var ipv4Hits = 0;
  var ipv6Hits = 0;
  const chunk = 8;
  for (var i = 0; i < list.length; i += chunk) {
    if (stop != null && stop()) break;
    if (i > 0 && gap > Duration.zero) await Future.delayed(gap);
    if (stop != null && stop()) break;
    final part = list.sublist(i, min(i + chunk, list.length));
    // Query A and AAAA independently over the same resolver transport.
    // A domain counts once when either family returns a validated address;
    // family counters remain separate so IPv4-only resolvers are not penalized.
    final results = await Future.wait(part.map((domain) async {
      final family = await Future.wait([
        NatDnsWireProbe.probe(
          server,
          domain,
          timeout: timeout,
          cancelled: stop,
          queryType: 1,
        ),
        NatDnsWireProbe.probe(
          server,
          domain,
          timeout: timeout,
          cancelled: stop,
          queryType: 28,
        ),
      ]);
      return (ipv4: family[0], ipv6: family[1]);
    }));
    if (stop != null && stop()) return null;
    tested += part.length;
    for (final result in results) {
      final v4 = result.ipv4;
      final v6 = result.ipv6;
      if (v4.ok) ipv4Hits++;
      if (v6.ok) ipv6Hits++;
      if (v4.ok || v6.ok) {
        domainHits++;
        final samples = <int>[
          if (v4.ok) v4.elapsedMs!,
          if (v6.ok) v6.elapsedMs!,
        ];
        times.add(samples.reduce((a, b) => a + b) ~/ samples.length);
      }
    }
  }
  // One domain is one vote, regardless of whether it has A, AAAA or both.
  if (tested == 0 || domainHits == 0 || domainHits * 4 < tested) return null;
  final avg = times.reduce((a, b) => a + b) ~/ times.length;
  return DnsxHit(
    server,
    avg,
    domainHits,
    tested,
    ipv4OkCount: ipv4Hits,
    ipv6OkCount: ipv6Hits,
  );
}

/// اسکن گروهی (۱۲ تا ۱۲ تا). خروجی: DNSهای سالم؛ اول آن‌که بیشترین دامنه را جواب داده،
/// و در برابر تساوی، آن‌که سریع‌تر است.
Future<List<DnsxHit>> dnsxScan(List<String> list,
    {List<String>? domains,
    Duration gap = Duration.zero,
    void Function(int done, int total)? onProgress,
    bool Function()? stop,
    bool manual = false}) async {
  final results = <DnsxHit>[];
  var done = 0;
  // NATQUOTA: اسکن دستی در نت ملی سهمیه‌ی کم دارد و منتظر جستجوی نت ملی می‌ماند
  final limited = manual && nationalMode;
  final dnsBatch = limited ? kNatManualConc : 12; // DNS در هر دسته‌ی همزمان
  for (var i = 0; i < list.length; i += dnsBatch) {
    if (stop != null && stop()) break;
    if (limited) {
      await natManualYield(shouldAbort: stop);
      if (stop != null && stop()) break;
    }
    final batch = list.sublist(i, min(i + dnsBatch, list.length));
    await Future.wait(batch.map((server) async {
      final hit =
          await dnsxProbe(server, domains: domains, gap: gap, stop: stop);
      done++;
      if (hit != null) results.add(hit);
      onProgress?.call(done, list.length);
    }));
  }
  results.sort((a, b) {
    final domains = b.okCount.compareTo(a.okCount);
    if (domains != 0) return domains;
    final ipv6 = b.ipv6OkCount.compareTo(a.ipv6OkCount);
    if (ipv6 != 0) return ipv6;
    final ipv4 = b.ipv4OkCount.compareTo(a.ipv4OkCount);
    return ipv4 != 0 ? ipv4 : a.avgMs.compareTo(b.avgMs);
  });
  return results;
}

/// بهترین DNSهای پیداشده که در نت ملی اول استفاده می‌شوند (در حافظه)
List<String> dnsxBestCache = [];
bool? _dnsxBestMode; // حالتی که dnsxBestCache برایش پر شده
bool _dnsxAutoBusy = false;
/// اسکن دستی در حال اجراست؛ تا تمام نشده، اسکن خودکار شروع نمی‌شود
bool dnsxManualBusy = false;

/// اسکن خودکار: فقط در نت ملی و وقتی VPN قطع است. هر ۲۴ ساعت (یا ۶ ساعت اگر DNS سالمی نبود)، با همه‌ی دامنه‌های پروژه.
/// اگر وسط کار اتصال برقرار شود (stop=true)، اسکن نیمه‌کاره ذخیره نمی‌شود.
Future<void> dnsxAutoPick({bool Function()? stop, bool force = false, bool coordinatorOwned = false}) async {
  if (_dnsxAutoBusy || (dnsxManualBusy && !coordinatorOwned)) return;
  _dnsxAutoBusy = true;
  // Snapshot the mode before the first await; never mix national/global scan state.
  final scanNationalMode = nationalMode;
  final sfx = scanNationalMode ? 'nat' : 'glob';
  try {
    final p = await SharedPreferences.getInstance();
    if (nationalMode != scanNationalMode) return;
    // DNSMODE: each network mode owns an independent cache and persistence key.
    if (_dnsxBestMode != scanNationalMode) {
      dnsxBestCache = [];
      _dnsxBestMode = scanNationalMode;
    }
    final cached = p.get('dnsx_best_v1_$sfx');
    if (cached is List && dnsxBestCache.isEmpty) {
      dnsxBestCache = [for (final x in cached) x.toString()];
    }
    final at = p.get('dnsx_at_v1_$sfx');
    final last = at is int ? at : 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    // فاصله‌ی ۲۴ ساعته همیشه رعایت شود، حتی وقتی نتیجه‌ای نبود (جلوگیری از اسکن تکراری)
    // اگر DNS سالمی نداریم، زودتر دوباره اسکن می‌شود (۶ ساعت)؛ وگرنه هر ۲۴ ساعت
    final gapMs = dnsxBestCache.isEmpty ? 6 * 3600 * 1000 : 24 * 3600 * 1000;
    if (!force && now - last < gapMs) return;
    final savedDns = await goldDnsList();
    if (nationalMode != scanNationalMode) return;
    final defaults = scanNationalMode ? kDnsxNationalDefaults : kDnsxDefaults;
    final list = <String>{...savedDns, ...defaults}.toList(growable: false);
    // Auto discovery checks the complete saved and mode-specific default resolver inventory.
    // The manual scanner still retains dnsxFullDomains() for user-selected full scans.
    final r = await dnsxScan(
      list,
      domains: dnsxAutoDomains(),
      gap: const Duration(milliseconds: 150),
      stop: () => nationalMode != scanNationalMode || (stop?.call() ?? false),
    );
    // Discard partial or cross-mode results before writing anything.
    bool shouldAbort() =>
        nationalMode != scanNationalMode || (stop?.call() ?? false);
    if (shouldAbort()) return;
    // Persist the shared DNS folder with the same cancellation/mode guard.
    // Await it so a late preferences write cannot outlive this scan's validity.
    if (r.isNotEmpty) {
      final saved = await goldAddDns(r, shouldAbort: shouldAbort);
      if (!saved || shouldAbort()) return;
    }
    // Keep the entire successful resolver inventory; UI/connection ranking
    // may still choose a short fast subset without discarding discoveries.
    final best = [for (final e in r) e.ip];
    await p.setStringList('dnsx_best_v1_$sfx', best);
    if (shouldAbort()) return;
    await p.setInt('dnsx_at_v1_$sfx', now);
    if (!shouldAbort()) {
      dnsxBestCache = best;
      _dnsxBestMode = scanNationalMode;
      dbg('DNSX خودکار: ${best.length} DNS سالم (${scanNationalMode ? 'نت ملی' : 'عادی'})');
    }
  } catch (e, stk) {
    logError(e, stk);
  } finally {
    _dnsxAutoBusy = false;
  }
}

extension DnsxExt on _HomePageState {
  void dnsxSheet(BuildContext ctx0) {
    var running = false;
    var stopFlag = false;
    var sheetOpen = true;
    var done = 0;
    var total = 0;
    var results = <DnsxHit>[];
    var note = ''; // DNSNOTE: پیام داخل خود شیت (SnackBar زیر شیت دیده نمی‌شد)
    final extraC = TextEditingController();

    showModalBottomSheet(
      context: ctx0,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          // اگر کاربر شیت را بسته باشد، setState بی‌صدا نادیده گرفته می‌شود
          void upd(VoidCallback f) {
            try {
              setS(f);
            } catch (e) {
              // شیت بسته شده؛ طبیعی است. فقط با سقف ژورنال ثبت می‌شود
              errJournalAdd(e, kind: 'SILENT-SHEET');
            }
          }

          Future<void> start() async {
            // Acquire the manual-scan lock synchronously before the first await.
            // This closes the race with background DNS scans and repeated taps.
            if (running || dnsxManualBusy || _dnsxAutoBusy) {
              upd(() => note = 'یک اسکن DNS دیگر در حال اجراست؛ کمی صبر کنید.');
              return;
            }
            if (connected) {
              upd(() => note = 'اول VPN را قطع کنید، بعد اسکن دستی را اجرا کنید.');
              return;
            }
            dnsxManualBusy = true;
            stopFlag = false;
            upd(() {
              running = true;
              done = 0;
              total = 0;
              results = [];
              note = 'در حال آماده‌سازی اسکن...';
            });
            List<DnsxHit> r = const <DnsxHit>[];
            try {
              final extra = extraC.text
                  .split(RegExp(r'[\s,]+'))
                  .map((s) => s.trim())
                  .where((s) =>
                      s.isNotEmpty &&
                      InternetAddress.tryParse(s)?.type ==
                          InternetAddressType.IPv4)
                  .toList();
              final saved = await goldDnsList();
              if (!mounted || !sheetOpen) return;
              if (stopFlag) {
                upd(() => note = 'اسکن متوقف شد؛ نتایج ذخیره نشد.');
                return;
              }
              final list = {...saved, ...kDnsxDefaults, ...kDnsxNationalDefaults, ...extra}
                  .toList();
              upd(() => total = list.length);
              r = await dnsxScan(
                list,
                domains: dnsxFullDomains(),
                manual: true,
                stop: () => stopFlag || !sheetOpen,
                onProgress: (d, t) => upd(() {
                  done = d;
                  total = t;
                }),
              );
              if (stopFlag || !sheetOpen) {
                upd(() => note = 'اسکن متوقف شد؛ نتایج ناقص ذخیره نشد.');
              } else if (r.isEmpty) {
                upd(() => note = 'هیچ DNS ای جواب معتبر نداد.');
              } else {
                final saved = await goldAddDns(r, shouldAbort: () => stopFlag || !sheetOpen);
                if (!saved) {
                  upd(() => note = stopFlag || !sheetOpen
                      ? 'اسکن متوقف شد؛ نتایج ناقص ذخیره نشد.'
                      : 'ذخیره نتایج DNS ناموفق بود.');
                } else {
                  upd(() => note = '${r.length} DNS سالم پیدا و ذخیره شد.');
                }
              }
            } catch (e, stk) {
              logError(e, stk);
              upd(() => note = 'خطا در اسکن DNS');
            } finally {
              dnsxManualBusy = false;
              upd(() {
                running = false;
                results = r;
              });
            }
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('اسکنر DNS',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text('دامنه‌ی تست: ${dnsxProbeDomain()}'),
                  const SizedBox(height: 4),
                  const Text(
                      'پاسخ‌های جعلی یا بلاک‌پیج رد می‌شوند. نتیجه از سریع به کند مرتب است. روی هر مورد بزنید تا IP کپی شود.'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: extraC,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'DNS دلخواه (IPv4، با فاصله یا کاما)',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  Text(total == 0 ? 'آماده' : 'انجام شده: $done / $total'),
                  const SizedBox(height: 6),
                  if (note.isNotEmpty) Text(note, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Row(children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: running ? null : () => start(),
                        child: const Text('شروع اسکن'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: running
                            ? () => upd(() {
                                  stopFlag = true;
                                })
                            : null,
                        child: const Text('توقف'),
                      ),
                    ),
                  ]),
                  const Divider(height: 20),
                  if (!running && total > 0 && results.isEmpty)
                    const Text('هیچ DNS ای جواب معتبر نداد.'),
                  if (results.isNotEmpty)
                    OutlinedButton(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(
                            text: results.map((r) => r.ip).join('\n')));
                        upd(() => note = '${results.length} DNS کپی شد');
                      },
                      child: Text('کپی همه‌ی ${results.length} DNS'),
                    ),
                  for (final r in results)
                    ListTile(
                      dense: true,
                      title: Text(r.ip),
                      subtitle: Text('دامنهٔ پاسخ‌گو: ${r.okCount}/${r.total} • IPv4: ${r.ipv4OkCount} • IPv6: ${r.ipv6OkCount}'),
                      trailing: Text('${r.avgMs} ms'),
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: r.ip));
                        upd(() => note = '${r.ip} کپی شد');
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      sheetOpen = false;
      stopFlag = true;
      extraC.dispose();
    });
  }
}
