import 'dart:io';

// ERRJOURNAL (مستقل از main تا فایل‌های جدا هم بتوانند ثبت کنند): دفتر کامل خطاها برای تست ۶۰ دقیقه‌ای.
// هر خطایی که از logError رد شود (حتی خطاهای شبکه‌ای که قبلاً فقط شمرده می‌شدند)
// با زمان، نوع، پیام کامل، جای دقیق در کد (فایل:خط) و بخش فعلی تست ثبت می‌شود.
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

void errJournalAdd(Object e, {String kind = '', StackTrace? st}) {
  try {
    if (errJournal.length >= kErrJournalMax) errJournal.removeAt(0);
    final now = DateTime.now();
    final k = kind.isNotEmpty ? kind : e.runtimeType.toString();
    final where = st != null ? stackHead(st) : _whereHere();
    errJournal.add(ErrEntry(now, k, e.toString(), where, errTag));
    // روی دیسک هم ذخیره می‌شود تا با بسته شدن برنامه از بین نرود
    try {
      final f = File(kErrJournalPath);
      // وقتی فایل خیلی بزرگ شد، نسخه‌ی قبلی نگه داشته می‌شود (چیزی پاک نمی‌شود)
      if (f.existsSync() && f.lengthSync() > 256 * 1024 * 1024) {
        f.renameSync('$kErrJournalPath.old');
      }
      f.writeAsStringSync(
          '${now.toIso8601String()} | $k | بخش: $errTag\nجای خطا: $where\n${e.toString()}\n\n',
          mode: FileMode.append);
    } catch (_) {}
  } catch (_) {}
}


String _whereHere() => stackHead(StackTrace.current);
