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
  // Public IPv6 recursive resolvers
  '2001:4860:4860::8888',
  '2001:4860:4860::8844',
  '2606:4700:4700::1111',
  '2606:4700:4700::1001',
  '2620:fe::fe',
  '2620:fe::9',
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

/// اسکن خودکار و دستی DNS هر دو از تمام دامنه‌های موجود در منابع پروژه استفاده می‌کنند.
/// شکست موقت یک دامنه باعث حذف آن از موجودی نمی‌شود؛ چرخه‌های بعدی دوباره آن را می‌آزمایند.
List<String> dnsxAutoDomains() => dnsxFullDomains();

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
    ...kAutoNationalSniDomains,
    ...kAutoSniDomains,
    ...natIrDomains,
    ..._dnsxHostsFrom(iranDomains),
    ..._dnsxHostsFrom(_iranMoreDomains),
    ..._dnsxHostsFrom(natFrontSnis),
    ..._dnsxHostsFrom(natRelayHosts),
  };
  final domains = all.where((value) => value.trim().isNotEmpty).toList()
    ..sort();
  return domains;
}

/// Full project domain inventory with domestic candidates first during national
/// network conditions. The global remainder is retained as a fallback; it is
/// never discarded merely because the current network is domestic-only.
/// [extra] merges scanner discoveries and user-configured hostnames without
/// imposing a fixed inventory ceiling.
List<String> dnsxNationalFirstDomains({
  Iterable<String> extra = const <String>[],
}) {
  final extraHosts = _dnsxHostsFrom(extra);
  final all = <String>{
    ...dnsxFullDomains(),
    ...extraHosts,
  };
  final domestic = <String>{
    ...kDnsxNationalProbeDomains,
    ...natIrDomains,
    ..._dnsxHostsFrom(iranDomains),
    ..._dnsxHostsFrom(_iranMoreDomains),
    ...kAutoNationalSniDomains,
    ...extraHosts.where((host) =>
        host.endsWith('.ir') ||
        host.endsWith('.ac.ir') ||
        host.endsWith('.gov.ir') ||
        host.endsWith('.co.ir') ||
        host.endsWith('.org.ir')),
  };
  final first = domestic.intersection(all).toList()..sort();
  final remaining = all.difference(domestic).toList()..sort();
  return <String>[...first, ...remaining];
}

/// متن نمایشی دامنه‌ها در شیت
String dnsxProbeDomain() => '${dnsxFullDomains().length} دامنه (ایرانی و جهانی)';

/// بسته‌ی پرس‌وجوی DNS برای نوع A (RD=1)
List<int> dnsxQuery(String name, int id, {int recordType = 1}) {
  if (recordType != 1 && recordType != 28) {
    throw ArgumentError.value(recordType, 'recordType');
  }
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
  b.addAll([0x00, (recordType >> 8) & 0xff, recordType & 0xff, 0x00, 0x01]); // root, QTYPE و QCLASS=IN
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

/// پاسخ معتبر برای A یا AAAA؛ حداقل یک رکورد عمومی از همان خانواده لازم است.
/// IPv6 DNS answer validation shares the NNIE global-unicast checks.
bool dnsxIsPublicV6(List<int> bytes, int offset) =>
    NatDnsWireProbe.publicV6(bytes, offset);

bool dnsxAnswerOk(List<int> d, int id, {int recordType = 1}) {
  if (recordType != 1 && recordType != 28) return false;
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
    pos = skipName(pos);
    if (pos + 4 > d.length) return false;
    final qtype = (d[pos] << 8) | d[pos + 1];
    if (qtype != recordType || ((d[pos + 2] << 8) | d[pos + 3]) != 1) return false;
    pos += 4;
  }
  var goodA = false;
  for (var i = 0; i < an && pos + 10 <= d.length; i++) {
    pos = skipName(pos);
    if (pos + 10 > d.length) break;
    final type = (d[pos] << 8) | d[pos + 1];
    final rdlen = (d[pos + 8] << 8) | d[pos + 9];
    final rd = pos + 10;
    if (type == recordType) {
      final valid = recordType == 1
          ? rdlen == 4 && rd + 4 <= d.length &&
              dnsxIsPublicV4(d[rd], d[rd + 1], d[rd + 2], d[rd + 3])
          : rdlen == 16 && rd + 16 <= d.length && dnsxIsPublicV6(d, rd);
      if (valid) {
        goodA = true;
      } else {
        return false; // پاسخ ناقص، جعلی یا خارج از محدوده‌ی آدرس‌دهی عمومی
      }
    }
    pos = rd + rdlen;
  }
  return goodA;
}

/// نتیجه‌ی یک DNS: چند دامنه جواب داد و میانگین زمان آن‌ها
class DnsxHit {
  DnsxHit(this.ip, this.avgMs, this.okCount, this.total);
  final String ip;
  final int avgMs;
  final int okCount;
  final int total;
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
  var tested = 0; // تعداد دامنه‌هایی که واقعاً سنجیده شدند (اگر توقف زده شود، کمتر از کل است)
  const chunk = 8; // دامنه‌ها در هر بسته‌ی همزمان
  for (var i = 0; i < list.length; i += chunk) {
    if (stop != null && stop()) break;
    // فاصله بین بسته‌ها: اسکن پس‌زمینه بار ناگهانی روی اتصال نمی‌گذارد
    if (i > 0 && gap > Duration.zero) await Future.delayed(gap);
    // Cancellation may arrive while waiting between DNS batches.
    if (stop != null && stop()) break;
    final part = list.sublist(i, min(i + chunk, list.length));
    // Query both A and AAAA. A domain counts once when either address
    // family returns a validated usable answer.
    final res = await Future.wait(part.map((d) => Future.wait([
          NatDnsWireProbe.probe(
            server, d, timeout: timeout, cancelled: stop, recordType: 1,
          ),
          NatDnsWireProbe.probe(
            server, d, timeout: timeout, cancelled: stop, recordType: 28,
          ),
        ])));
    if (stop != null && stop()) return null;
    tested += part.length;
    for (final familyResults in res) {
      final successful = familyResults.where((result) => result.ok).toList();
      if (successful.isNotEmpty) {
        times.add(successful.map((result) => result.elapsedMs!).reduce(min));
      }
    }
  }
  // ملاک: حداقل ۲۵٪ از دامنه‌هایی که واقعاً سنجیده شدند باید جواب بدهند
  if (tested == 0 || times.isEmpty || times.length * 4 < tested) return null;
  final avg = times.reduce((a, b) => a + b) ~/ times.length;
  return DnsxHit(server, avg, times.length, tested);
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
    final c = b.okCount.compareTo(a.okCount);
    return c != 0 ? c : a.avgMs.compareTo(b.avgMs);
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
Future<void> dnsxAutoPick({bool Function()? stop}) async {
  if (_dnsxAutoBusy || dnsxManualBusy) return;
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
    if (now - last < gapMs) return;
    final savedDns = await goldDnsList();
    if (nationalMode != scanNationalMode) return;
    final list = {...savedDns, ...(scanNationalMode ? kDnsxNationalDefaults : kDnsxDefaults)}.toList();
    // کامل: همه‌ی دامنه‌های پروژه، با فاصله‌ی ۱۵۰ میلی‌ثانیه بین بسته‌ها
    final r = await dnsxScan(
      list,
      domains: dnsxFullDomains(),
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
    // Keep previously verified resolvers when a later scan is partial or
    // temporarily empty; merge newly verified results without truncating the
    // per-mode inventory. A failed refresh must never erase known-good DNS.
    final best = <String>{
      ...dnsxBestCache,
      for (final e in r) e.ip,
    }.toList(growable: false);
    if (best.isNotEmpty) {
      await p.setStringList('dnsx_best_v1_$sfx', best);
    }
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
                  .where((s) {
                    final parsed = InternetAddress.tryParse(s);
                    return s.isNotEmpty &&
                        parsed != null &&
                        (parsed.type == InternetAddressType.IPv4 ||
                            parsed.type == InternetAddressType.IPv6);
                  })
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
                        labelText: 'DNS دلخواه (IPv4 یا IPv6، با فاصله یا کاما)',
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
                      subtitle: Text('جواب‌داده: ${r.okCount} از ${r.total} دامنه'),
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
