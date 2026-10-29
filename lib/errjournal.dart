import 'dart:io';

// ERRJOURNAL (مستقل از main تا فایل‌های جدا هم بتوانند ثبت کنند): دفتر خطاها برای تست ۶۰ دقیقه‌ای.
// هر خطایی که از logError رد شود با زمان، نوع، پیام، جای دقیق در کد (فایل:خط) و بخش فعلی تست ثبت می‌شود.
//
// ERRFIX: خطاهای شبکه‌ای عادی (دامنه‌ی مرده، timeout، connection refused، …) حالا همه با یک نوع
// SILENT-NET شمرده می‌شوند و فقط ۳۰۰ بار ثبت می‌شوند. قبلاً هر خطا با نوع خالی می‌آمد و دفتر را
// تا ۱۰۰ هزار مورد پر می‌کرد و باگ‌های واقعی گم می‌شدند.
class ErrEntry {
  final DateTime at;
  final String type;
  final String msg;
  final String where;
  final String tag;
  ErrEntry(this.at, this.type, this.msg, this.where, this.tag);
}

final List<ErrEntry> errJournal = [];

// محل دقیق خطا: چند خط اول پشته (فایل:خط) از همان catch که خطا را گرفته
String stackHead(StackTrace st) {
  try {
    final re = RegExp(r'#\d+\s+(.+?)\s+\(.*?(\w+\.dart):(\d+)');
    final out = <String>[];
    for (final ln in st.toString().split('\n')) {
      final mm = re.firstMatch(ln);
      if (mm == null) continue;
      out.add('${mm.group(2)}:${mm.group(3)} (${mm.group(1)})');
      if (out.length >= 4) break;
    }
    return out.isEmpty ? st.toString().split('\n').take(3).join(' | ') : out.join(' <- ');
  } catch (_) {
    return '';
  }
}

const int kErrJournalMax = 100000;
const String kErrJournalPath =
    '/data/data/com.kingvpn.king_vpn/cache/errjournal.log';
String errTag = ''; // نام بخش فعلی تست، تا معلوم شود خطا در کدام بخش افتاده

final Map<String, int> _journalKindCount = {};
// FREEZEFIX: writes are queued one after another (never blocking the UI)
Future<void> _journalWrite = Future<void>.value();

// ERRFIX: تشخیص خطاهای شبکه‌ای عادی از روی متن خطا
String netNoiseKind(Object e) {
  final m = e.toString();
  const marks = [
    'Failed host lookup',
    'Connection timed out',
    'Connection refused',
    'No route to host',
    'Network is unreachable',
    'Connection reset',
    'Connection failed',
    'TLS handshake timeout',
    'closed pipe',
    'TimeoutException',
  ];
  for (final k in marks) {
    if (m.contains(k)) return 'SILENT-NET';
  }
  // NOISE2: هر خطای اتصال/سوکت/TLS از جنس شبکه است و هم‌ردیف بقیه‌ی نویز شمرده می‌شود.
  // (قبلاً SocketException و HandshakeException بدون محدودیت ثبت می‌شدند و ۲۰۰+ مورد می‌شدند)
  if (m.startsWith('SocketException') ||
      m.startsWith('HandshakeException') ||
      m.startsWith('HttpException') ||
      m.startsWith('TimeoutException')) {
    return 'SILENT-NET';
  }
  // ERRFIX2: فایل موقت که قبلاً پاک شده (مثلاً xray_err.log) خطای مهمی نیست
  if (m.contains('PathNotFoundException')) return 'SILENT-FILE';
  return '';
}

// ERRFIX: دسته‌ی هر خطا برای خلاصه‌ی گزارش: باگ واقعی جدا از خطای عادی شبکه
String errCategory(ErrEntry e) {
  final t = e.type;
  final m = e.msg;
  if (m.contains('PathExistsException') || m.contains('FileSystemException') ||
      m.contains('PathAccessException')) {
    return 'باگ فایل (باید رفع شود)';
  }
  // LATIN1-FIX: this message comes from our own http.Response(String) call,
  // not from a bad config, so it is a bug to fix (it used to be hidden)
  if (m.contains('Contains invalid characters')) return 'باگ کد (باید رفع شود)';
  if (m.contains('Illegal percent encoding')) return 'داده‌ی نامعتبر (مدیریت‌شده)';
  if (m.contains('FormatException') ||
      m.contains('TypeError') ||
      m.contains('RangeError') ||
      m.contains('Null check') ||
      m.contains('cannot unmarshal')) {
    return 'باگ کد (باید رفع شود)';
  }
  if (t.startsWith('SILENT-NET') || t.startsWith('SILENT-DNS')) {
    return 'شبکه / دامنه‌ی مرده (عادی)';
  }
  if (t.startsWith('SILENT-FILE')) return 'فایل موقت (بی‌اهمیت)';
  // ERRFIX2: ArgumentError روی نام کانفیگ همیشه داخل try گرفته و مدیریت می‌شود
  if (m.contains('ArgumentError')) return 'داده‌ی نامعتبر (مدیریت‌شده)';
  if (m.contains('Socket') || m.contains('Timeout') || m.contains('Handshake')) {
    return 'شبکه (عادی)';
  }
  return 'سایر';
}

// ERRFIX: هر جستجوی DNS از این تابع می‌گذرد. host های نامعتبر (مثل دامنه‌ی درصد‌کدشده) قبل از lookup
// کنار گذاشته می‌شوند و خطا هرگز به بیرون پرت نمی‌شود.
Future<List<InternetAddress>> safeLookup(String host,
    {Duration timeout = const Duration(seconds: 3)}) async {
  final h = host.trim();
  if (h.isEmpty || h == '-' || h.contains('%') || h.contains(' ') || h.contains('/')) {
    return const <InternetAddress>[];
  }
  try {
    return await InternetAddress.lookup(h).timeout(timeout);
  } catch (e) {
    errJournalAdd(e, kind: 'SILENT-DNS');
    return const <InternetAddress>[];
  }
}

void errJournalAdd(Object e, {String kind = '', StackTrace? st}) {
  try {
    // NOISE: خطاهای تکراری و قابل‌انتظار فقط ۳۰۰ بار در هر نوع ثبت می‌شوند
    final kk = kind.isNotEmpty ? kind : netNoiseKind(e);
    if (kk.startsWith('SILENT-')) {
      final c = (_journalKindCount[kk] ?? 0) + 1;
      _journalKindCount[kk] = c;
      if (c > 300) return;
    }
    if (errJournal.length >= kErrJournalMax) errJournal.removeAt(0);
    final now = DateTime.now();
    final k = kk.isNotEmpty ? kk : e.runtimeType.toString();
    final where = st != null ? stackHead(st) : _whereHere();
    errJournal.add(ErrEntry(now, k, e.toString(), where, errTag));
    // روی دیسک هم ذخیره می‌شود تا با بسته شدن برنامه از بین نرود
    // FREEZEFIX: disk write is async. The old sync version (existsSync /
    // lengthSync / writeAsStringSync) blocked the UI thread on every error.
    final line =
        '${now.toIso8601String()} | $k | بخش: $errTag\nجای خطا: $where\n${e.toString()}\n\n';
    _journalWrite = _journalWrite.then((_) async {
      try {
        final f = File(kErrJournalPath);
        if (await f.exists() && await f.length() > 256 * 1024 * 1024) {
          await f.rename('$kErrJournalPath.old');
        }
        await f.writeAsString(line, mode: FileMode.append, flush: false);
      } catch (_) {}
    });
  } catch (_) {}
}

String _whereHere() => stackHead(StackTrace.current);
