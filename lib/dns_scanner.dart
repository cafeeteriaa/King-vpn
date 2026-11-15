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

/// دامنه‌ی تست: در نت ملی یک دامنه‌ی داخلی (.ir) و در حالت عادی google.com
const List<String> kDnsxNationalProbeDomains = <String>[
  'nic.ir',
  'iran.ir',
  'ac.ir',
];
int _dnsxDomainCursor = 0;
String dnsxProbeDomain() {
  if (!nationalMode) return 'google.com';
  final domain = kDnsxNationalProbeDomains[_dnsxDomainCursor % kDnsxNationalProbeDomains.length];
  _dnsxDomainCursor++;
  return domain;
}

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

/// زمان پاسخ (ms) یا null اگر جواب معتبر نیامد
Future<int?> dnsxProbe(String server,
    {Duration timeout = const Duration(seconds: 3)}) async {
  // NNIE: strict response validation includes transaction ID, QR/opcode,
  // question/type/class, source IP/port, RCODE and usable A answer.
  final result = await NatDnsWireProbe.probe(
    server,
    dnsxProbeDomain(),
    timeout: timeout,
  );
  return result.ok ? result.elapsedMs : null;
}

/// اسکن گروهی (۸ تا ۸ تا). خروجی: فهرست (IP، ms) مرتب شده از سریع به کند
Future<List<MapEntry<String, int>>> dnsxScan(List<String> list,
    {void Function(int done, int total)? onProgress, bool Function()? stop}) async {
  final results = <MapEntry<String, int>>[];
  var done = 0;
  for (var i = 0; i < list.length; i += 8) {
    if (stop != null && stop()) break;
    final batch = list.sublist(i, min(i + 8, list.length));
    await Future.wait(batch.map((server) async {
      final ms = await dnsxProbe(server);
      done++;
      if (ms != null) results.add(MapEntry(server, ms));
      onProgress?.call(done, list.length);
    }));
  }
  results.sort((a, b) => a.value.compareTo(b.value));
  return results;
}

/// بهترین DNSهای پیداشده که در نت ملی اول استفاده می‌شوند (در حافظه)
List<String> dnsxBestCache = [];
bool _dnsxAutoBusy = false;

/// اسکن خودکار: در نت ملی اجرا می‌شود. هر ۶ ساعت یک بار، یا وقتی نتیجه‌ای نداریم.
Future<void> dnsxAutoPick() async {
  if (_dnsxAutoBusy) return;
  _dnsxAutoBusy = true;
  try {
    final p = await SharedPreferences.getInstance();
    final cached = p.get('dnsx_best_v1');
    if (cached is List && dnsxBestCache.isEmpty) {
      dnsxBestCache = [for (final x in cached) x.toString()];
    }
    final at = p.get('dnsx_at_v1');
    final last = at is int ? at : 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    // فاصله‌ی ۶ ساعته همیشه رعایت شود، حتی وقتی نتیجه‌ای نبود (جلوگیری از اسکن تکراری)
    if (now - last < 6 * 3600 * 1000) return;
    final list = nationalMode ? kDnsxNationalDefaults : kDnsxDefaults;
    final r = await dnsxScan(list);
    dnsxBestCache = [for (final e in r.take(4)) e.key];
    await p.setStringList('dnsx_best_v1', dnsxBestCache);
    await p.setInt('dnsx_at_v1', now);
    dbg('DNSX خودکار: ${dnsxBestCache.length} DNS سالم (${nationalMode ? 'نت ملی' : 'عادی'})');
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
    var done = 0;
    var total = 0;
    var results = <MapEntry<String, int>>[];
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
            } catch (_) {}
          }

          Future<void> start() async {
            final extra = extraC.text
                .split(RegExp(r'[\s,]+'))
                .map((s) => s.trim())
                .where((s) =>
                    s.isNotEmpty &&
                    InternetAddress.tryParse(s)?.type ==
                        InternetAddressType.IPv4)
                .toList();
            final list = {...kDnsxDefaults, ...kDnsxNationalDefaults, ...extra}
                .toList();
            upd(() {
              running = true;
              stopFlag = false;
              done = 0;
              total = list.length;
              results = [];
            });
            final r = await dnsxScan(
              list,
              stop: () => stopFlag,
              onProgress: (d, t) => upd(() {
                done = d;
                total = t;
              }),
            );
            upd(() {
              running = false;
              results = r;
            });
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
                  for (final r in results)
                    ListTile(
                      dense: true,
                      title: Text(r.key),
                      trailing: Text('${r.value} ms'),
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: r.key));
                        ScaffoldMessenger.maybeOf(ctx0)?.showSnackBar(
                            SnackBar(content: Text('${r.key} کپی شد')));
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      stopFlag = true;
    });
  }
}
