part of 'main.dart';
// TESTNOAD: true only while the 20-minute test runs; the ad gate lets connects through
bool autoTestAdFree = false;

// =============================================================================
// AUTO TEST 60min — تست خودکار شش بخش واقعی + سناریوهای پایداری
// بخش‌ها به ترتیب: اینترنت جهانی | نت ملی (IP اول، بعد تست کانفیگ، همه‌ی سطوح ماتریس)
// | خلبان | پوشه‌ی منابع تازه | اتصال آفلاین | اتصال آنلاین
// بعد از آن‌ها قطع/وصل، قطع وسط اتصال، تعویض سرور و مانیتور طولانی با باقی‌مانده‌ی وقت اجرا می‌شوند.
// هدف: پیدا کردن race، گیر کردن busy/switching، و اینکه هر حالت واقعاً کار می‌کند.
// =============================================================================

enum _AtPhase {
  idle,
  running,
  done,
}

class _AtFinding {
  final String code; // e.g. BUSY-STUCK, FLAG-MISMATCH, ENG-FAIL
  final String msg;
  final DateTime at;
  int n = 1;
  _AtFinding(this.code, this.msg) : at = DateTime.now();
}

class _AtStateSample {
  final DateTime at;
  final bool connected;
  final bool busy;
  final bool switching;
  final bool watchBusy;
  final String status;
  final String lastWhy;
  final String lastState;
  final String engine;
  _AtStateSample({
    required this.at,
    required this.connected,
    required this.busy,
    required this.switching,
    required this.watchBusy,
    required this.status,
    required this.lastWhy,
    required this.lastState,
    required this.engine,
  });
}

final ValueNotifier<String> autoTestText =
    ValueNotifier<String>('تست خودکار آماده است.');
final ValueNotifier<bool> autoTestRunning = ValueNotifier<bool>(false);
final ValueNotifier<double> autoTestProgress = ValueNotifier<double>(0);

extension AutoTestEngine on _HomePageState {
  /// LOGFIX: lines of the debug log written since this test started (HH:MM:SS sorted)
  List<String> _atLogSince() {
    final start = _startedAt == null ? '00:00:00' : _dbgHms(_startedAt!);
    return dbgLines.where((l) => l.compareTo(start) >= 0).toList();
  }

  /// سناریو ۶: تشخیص شبکه (جهانی یا ملی) و ثبت آن در گزارش
  Future<void> _atScenarioNational() async {
    _scenario = 6;
    autoTestText.value = 'سناریو ۶: تشخیص شبکه';
    if (busy || switching || connected) return;
    try {
      await _natDetect();
    } catch (e) {
      _atAdd('NAT-DETECT', 'تشخیص شبکه خطا داد: $e');
      return;
    }
    dbg('🧪 تشخیص شبکه: ${nationalMode ? 'نت ملی' : 'نت جهانی'}');
  }

  // ALLPATHS: تست کامل همه‌ی مسیرها؛ مدت مهم نیست، بخش‌ها همه اجرا می‌شوند
  // SIX-HOUR: تست کامل همه‌ی مسیرها ۶ ساعت است (وقت کافی برای همه‌ی بخش‌ها)
  // STEST60: کل تست ۶۰ دقیقه و فقط نت ملی است (جهانی، پوشه، آفلاین، آنلاین، پروتکل‌ها، کشور و خلبان هوش مصنوعی حذف شدند)
  static const _testDuration = Duration(hours: 5); // V14: 5-hour national test
  static const _sampleEvery = Duration(seconds: 3);
  // آستانه‌ها باید بیشتر از مهلت واقعی اتصال باشند (وگرنه اتصال عادی گزارش گیر می‌دهد)
  static const _busyStuckLimit = Duration(seconds: 240); // TESTUPGRADE
  static const _switchingStuckLimit = Duration(seconds: 90); // TESTUPGRADE
  static const _connectHangLimit = Duration(seconds: 110);
  // قابلیت‌های هسته‌ای که کانفیگ‌های ناموفق لازم داشتند
  static final List<String> _atCfgNotes = [];

  /// only V2Ray: the other engines are removed from this build
  static const List<(String id, String label)> _engines = [
    ('v2ray', 'V2Ray'),
  ];

  static _AtPhase _phase = _AtPhase.idle;
  static Timer? _sampleT;
  static Timer? _endT;
  static DateTime? _startedAt;
  static int _dbgStartIdx = 0; // KNOWN-ISSUES: only this run's debug lines
  static DateTime? _busySince;
  // TESTFIX2: true only while _atConnectEngine is waiting for a connect
  static bool _atConnecting = false;
  static DateTime? _switchFlagSince;
  static String? _busyStatus; // PROGRESS: آخرین وضعیت وقتی busy بود
  static DateTime? _busyStatusAt; // PROGRESS: از کی وضعیت عوض نشده
  static DateTime? _noHealthySince; // NOHEALTHY: از کی بدون سرور سالم جستجو می‌کنیم
  static bool _noHealthyReported = false;
  static const _busyQuietLimit = Duration(seconds: 90);
  static const _noHealthyLimit = Duration(minutes: 10);
  static DateTime? _switchingSince;
  static DateTime? _connectingSince;
  static final List<_AtFinding> _findings = [];
  static final List<_AtStateSample> _samples = [];
  static int _scenario = 0;
  // PLUGIN-SWALLOW: where this run's log starts inside errorLog
  static int _atLogStart = 0;
  // PILOT-FLAP: how many times the pilot switched the server during this run
  static int _atPilotSwitches = 0;
  // FLAG-MISMATCH is reported only when it lasts 3 samples in a row (about 9 s);
  // a state that changes during a normal disconnect is not a bug
  static int _atMismatchTicks = 0;
  static bool _abortRequested = false;
static bool get autoTestAbortRequested => _abortRequested;
  // CORE-DEAD: how many times in a row the core did not open its local port
  static int _atCoreDeadStreak = 0;
static void _resetCoreDeadStreak() { _atCoreDeadStreak = 0; }
  // EARLY-STOP: consecutive engine failures with the same cause end the test early
  static int _atFailStreak = 0;
  static String _atVerdict = ''; // one plain-language cause, printed first in the report
  static String _atLastFail = ''; // lastFail of the last failed connect (facts, not guesses)
  static bool _atLastCoreUp = false; // was the local core port open at that failure
  static String _currentEngine = 'v2ray';
  // موتورهایی که کاربر برای این تست انتخاب کرده (پیش‌فرض: همه)
  static Set<String> _atSelected = {for (final e in _engines) e.$1};
  static final Map<String, String> _engineResult = {}; // ok / fail / skip
  // بخش‌های تست با ترتیب اجرا (نام نمایشی)
  // NATONLY2: فقط این دو بخش در تست و گزارش دیده می‌شوند
  // FIVE-HOUR: همه‌ی مسیرهای اتصال در گزارش دیده می‌شوند
  static List<String> get _atActiveNames =>
      [_atItemNames[2], _atSubstName]; // STEST60: فقط نت ملی
  static const List<String> _atItemNames = [
    'اینترنت جهانی (عادی)',
    'پوشه‌ی منابع تازه (ساخت)',
    'نت ملی: همه‌ی سطوح ماتریس',
    'اتصال آفلاین (فقط پوشه)',
    'اتصال آنلاین (همه‌ی منابع)',
    'VMess (فقط vmess)',
    'VLESS (فقط vless)',
    'Trojan (فقط trojan)',
    'Shadowsocks (فقط ss)',
    'کشور (پرتکرارترین کشور)',
    'خلبان هوش مصنوعی (کلید)',
  ];
  // نتیجه‌ی هر بخش، در گزارش پایان نشان داده می‌شود
  static final Map<String, String> _itemResult = {};
  // بیشترین سطح ماتریس نت ملی که در بخش‌های ملی دیده شد
  static int _atMaxNatLevel = 0;
  // NATMODES: نتیجه‌ی هر سطح و اینکه آیا حداقل یک سطح وصل شد
  static final List<String> _atNatRows = [];
  static final List<String> _atSubstFailed = []; // NOTWORK

  static final List<String> _atSubstUntried = []; // NOTWORK

  /// NOTWORK: هر چیزی که جواب نداده یا تست نشده، یک خط گزارش می‌شود
  List<String> _atFailList() {
    final out = <String>[];
    for (final r in _atNatRows) {
      if (r.contains('وصل نشد')) out.add('نت ملی • $r');
    }
    for (final f in _atSubstFailed) {
      out.add('جایگزین «$f»');
    }
    final timeoutNames = <String>[];
    final noServerNames = <String>[];
    for (final u in _atSubstUntried) {
      if (u.endsWith('تست نشد (وقت تمام شد)')) {
        timeoutNames.add(u.replaceAll(': تست نشد (وقت تمام شد)', ''));
      } else if (u.contains('با هیچ سرور تست‌شده سازگار نبود')) {
        noServerNames.add(u.split(':').first);
      } else {
        out.add('جایگزین «$u»');
      }
    }
    // GROUPED: به‌جای هزاران خط، یک خط خلاصه با چند نمونه
    if (timeoutNames.isNotEmpty) {
      out.add('${timeoutNames.length} حالت به‌خاطر پایان زمان تست امتحان نشد '
          '(مدت تست کوتاه بود). نمونه: ${timeoutNames.take(8).join('، ')}');
    }
    if (noServerNames.isNotEmpty) {
      out.add('${noServerNames.length} حالت با هیچ‌کدام از سرورهای تست‌شده سازگار نبود '
          '(مثلاً ${noServerNames.take(5).join('، ')})');
    }
    for (final n in _atActiveNames) {
      if (n == _atItemNames[2] || n == _atSubstName) continue;
      final r = _itemResult[n] ?? 'تست نشد';
      if (r.contains('❌') || r.contains('اجرا نشد') || r.contains('تست نشد') ||
          r.contains('رد شد') || r.contains('⚠️')) {
        out.add('$n: $r');
      }
    }
    return out;
  }
  static bool _atNatWorking = false;

  bool get isAutoTesting => _phase == _AtPhase.running;

  /// نقطهٔ ورود از UI
  Future<void> startAutoTest20() async {
    if (_phase == _AtPhase.running) {
      _set('تست خودکار همین الان در حال اجراست');
      return;
    }
    if (busy || switching) {
      _set('صبر کن تا عملیات فعلی تمام شود، بعد تست را شروع کن');
      return;
    }

    final sel = Set<String>.from(_atSelected);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: const Text('تست نت ملی (۴ ساعت)'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('فقط نت ملی تست می‌شود:'),
                  const SizedBox(height: 4),
                  for (final item in _atActiveNames)
                    Text('• $item', style: const TextStyle(fontSize: 13)),
                  const Text(
                    '• هر سطح ماتریس نت ملی (۰ تا ۱۰) جدا تست می‌شود\n'
    '• برای هر سطح: تست‌شده، سالم و وصل یا نشدن ثبت می‌شود\n'
                    '• در پایان علت اصلی و راه‌حل گفته می‌شود',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  const SizedBox(height: 6),
                  const Text(
                    'در این ۴ ساعت اپ را نبند و صفحه را قفل نکن.\n'
                    'می‌توانی وسط کار «توقف تست» را بزنی.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('انصراف')),
              FilledButton(
                  onPressed: sel.isEmpty
                      ? null
                      : () {
                          _atSelected = Set<String>.from(sel);
                          Navigator.pop(ctx, true);
                        },
                  child: const Text('شروع تست')),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;

    await _atRun();
  }

  Future<void> stopAutoTest() async {
    if (_phase != _AtPhase.running) return;
    _abortRequested = true;
    _set('در حال توقف تست خودکار…');
  }

  Future<void> _atRun() async {
    _phase = _AtPhase.running;
    autoTestAdFree = true; // TESTNOAD
    _abortRequested = false;
    _applyModePreset(true, offlineOnly, false); // BESTDEF: تست ۴ ساعته = تنظیمات نت ملی
    _findings.clear();
    _atNoTraffic = false;
    _samples.clear();
    _atCfgNotes.clear();
    _engineResult.clear();
    _itemResult.clear();
    _atMaxNatLevel = 0;
    _atSubstFailed.clear();
    _atSubstUntried.clear();
    _atFailStreak = 0;
    _atVerdict = '';
    _scenario = 0;
    _atPilotSwitches = 0;
    _atLogStart = errorLog.value.length;
    _busySince = null;
    _busyStatus = null;
    _busyStatusAt = null;
    _noHealthySince = null;
    _noHealthyReported = false;
    _switchingSince = null;
    _connectingSince = null;
    _currentEngine = 'v2ray';
    _startedAt = DateTime.now();
    _atDomesticProbe(); // DOMESTIC: which sites open on the national network now
    _dbgStartIdx = dbgLines.length;
    autoTestRunning.value = true;
    autoTestProgress.value = 0;
    autoTestText.value = 'تست خودکار شروع شد (${_atSelected.length} VPN)…';
    dbg('🧪 AUTOTEST نت ملی شروع شد (۴ ساعت • ${_atActiveNames.length} بخش)');
    _dbgProb('🧪 تست نت ملی — ۴ ساعت');

    _sampleT?.cancel();
    _sampleT = Timer.periodic(_sampleEvery, (_) => _atSample());

    _endT?.cancel();
    _endT = Timer(_testDuration, () {
      if (_phase == _AtPhase.running) {
        dbg('🧪 AUTOTEST زمان ۴ ساعت تمام شد');
        _atFinish(reason: 'زمان تمام شد');
      }
    });

    try {
      // پوشه‌ی منابع تازه از همین اول در پس‌زمینه ساخته می‌شود تا بخش آفلاین آماده باشد
      if (!natHotReady()) unawaited(natHotEnsure(force: true));

      // بخش‌های اصلی: هر کدام فقط اگر وقت باقی‌مانده‌ی کافی داشته باشد اجرا می‌شود
      // NATONLY: فقط نت ملی (جستجو)؛ بقیه‌ی بخش‌ها حذف شدند
      // NATMODES: هر سطح ماتریس نت ملی (۰ تا ۱۰) جداگانه تست می‌شود
      // ALLPATHS: همه‌ی مسیرهای اصلی به ترتیب؛ هر بخش اگر وقت داشت اجرا می‌شود
      // SUBST-ONLY: فقط تست جایگزینی روی سرورهای سالم اجرا می‌شود
      // AUTOFULL: اول نت ملی (جستجو تا ۱۵ سرور سالم)، بعد جایگزینی روی همان سالم‌ها
      // FIVE-HOUR: همه‌ی مسیرها به ترتیب؛ هر بخش اگر وقت کافی داشته باشد اجرا می‌شود
      // STEST60: فقط بخش‌های نت ملی، در مجموع ۶۰ دقیقه:
      //  ۱) همه‌ی سطوح ماتریس نت ملی (تا ۱۱ دقیقه)
      //  ۲) همه‌ی حالت‌های جایگزین روی سرورهای سالم (تا ۲۵ دقیقه)
      // V14: only run the national test for the full 5 hours.
      final steps = <(String, Duration, Future<void> Function())>[
        (_atItemNames[2], const Duration(hours: 5), _atItemNational),
      ];
      for (final s in steps) {
        if (_abortRequested) return _atFinish(reason: 'توقف دستی');
        if (_atCanRun(s.$1, s.$2)) await s.$3();
      }

      // NATONLY: سناریوهای پایداری حذف شدند
    } catch (e) {
      _atAdd('CRASH', 'استثنای تست: $e');
      logError(e);
    } finally {
      if (_phase == _AtPhase.running) {
        await _atFinish(reason: 'تست نت ملی تمام شد');
      }
    }
  }

  Future<void> _atFinish({required String reason}) async {
    if (_phase == _AtPhase.done) return;
    _phase = _AtPhase.done;
    _sampleT?.cancel();
    _endT?.cancel();
    _sampleT = null;
    _endT = null;
    autoTestRunning.value = false;
    autoTestProgress.value = 1.0;

    _atSample();

    // PLUGIN-SWALLOW: platform errors the app caught silently during this run
    final logWin = _atLogSince().join('\n'); // LOGFIX
    final swallowed = RegExp('بلعیده|MissingPluginException').allMatches(logWin).length;
    if (swallowed > 0) {
      _atAdd('PLUGIN-SWALLOW', 'خطای بخش native اندروید $swallowed بار بلعیده شد (مثلاً کانال vpn/bg)');
    }
    // XRAY-NOLOG: the core starts without its error file, so its own errors are invisible
    final noLog = RegExp('فایل خطای هسته ساخته نشد').allMatches(logWin).length;
    if (noLog > 0) {
      _atAdd('XRAY-NOLOG', 'هسته $noLog بار بدون فایل خطا شروع شد؛ این فقط یک نشانه است؛ اگر اتصال برقرار شده بی‌اهمیت است');
    }
    final elapsed = _startedAt == null
        ? Duration.zero
        : DateTime.now().difference(_startedAt!);
    final min = elapsed.inMinutes;
    final sec = elapsed.inSeconds % 60;

    _atKnownIssues(); // KNOWN-ISSUES: the problems still open in this build
    if (_atDomesticResult.isNotEmpty) {
      final domOpen = _atDomesticOk.length;
      if (domOpen <= 2) {
        _atAdd('NAT-CLOSED',
            'نت ملی بیشتر سایت‌های داخلی را هم رد می‌کند ($_atDomesticResult)');
      }
      dbg('DOMESTIC-REPORT: $_atDomesticResult • باز: ${_atDomesticOk.join(' ، ')}');
    }
    _atVerdict = _atNatDiagnosis(); // NATONLY
    final buf = StringBuffer();
    buf.writeln('===== گزارش تست خودکار نت ملی (۴ ساعت) =====');
    buf.writeln('مدت: ${min}m ${sec}s • دلیل پایان: $reason');
    buf.writeln('نمونه وضعیت: ${_samples.length}');
    // TOPACTIONS: the three most important findings first, each with its first action
    const atPriority = ['ABORT-STUCK', 'TIMEOUT', 'SWITCH-FLAG-STUCK', 'SWITCH-STUCK', 'BG-BUSY',
        'BUSY-STUCK', 'CONNECT-HANG', 'STABLE-NODATA', 'PLUGIN-SWALLOW', 'XRAY-NOLOG', 'PILOT-FLAP'];
    int atRank(String c) {
      final i = atPriority.indexOf(c);
      return i < 0 ? 99 : i;
    }
    final ranked = [..._findings]..sort((a, b) => atRank(a.code).compareTo(atRank(b.code)));
    if (ranked.isNotEmpty) {
      buf.writeln('🎯 اول این‌ها را حل کن:');
      for (final f in ranked.take(3)) {
        buf.writeln('  • [${f.code}] ${_atHelpOf(f.code)[2]}');
      }
    }
    buf.writeln('🧭 سناریوی رسیده‌شده: $_scenario از ۶ • تعویض‌های خلبان: $_atPilotSwitches');
    buf.writeln('یافته‌ها: ${_findings.length}');
    buf.writeln('🌐 شبکه: ${nationalMode ? 'نت ملی' : 'نت جهانی'} • خلبان: ${localPilotOn ? 'روشن' : 'خاموش'}');
    buf.writeln('⚙ تنظیمات: IP تمیز=${cleanIpMode ? 'روشن' : 'خاموش'} • DoH=${ipMode ? 'روشن' : 'خاموش'} • Fragment=${fragEnabled ? 'روشن' : 'خاموش'} • ماتریس=${ultraMode ? 'روشن' : 'خاموش'} • شکست‌ناپذیر=${indestructibleMode ? 'روشن' : 'خاموش'}');
    if (_atVerdict.isNotEmpty) {
      buf.writeln('🎯 علت اصلی و راه حل: $_atVerdict');
    }
    buf.writeln('');
    buf.writeln('--- نتیجه هر موتور ---');
    for (final e in _engines) {
      final r = _engineResult[e.$1] ?? 'تست نشد';
      buf.writeln('• ${e.$2}: $r');
    }
    buf.writeln('');
    buf.writeln('--- نتیجه هر بخش ---');
    for (final n in _atActiveNames) {
      buf.writeln('• $n: ${_itemResult[n] ?? 'تست نشد'}');
    }
    buf.writeln('');

    final failList = _atFailList();
    if (failList.isEmpty) {
      buf.writeln('✅ همه‌ی سطوح و حالت‌های جایگزین تست‌شده جواب دادند.');
    } else {
      buf.writeln('❌ جواب نداد (${failList.length} مورد):');
      for (final f in failList) {
        buf.writeln('• $f');
      }
    }
    buf.writeln('');

    if (_findings.isEmpty && !_abortRequested) {
      buf.writeln('✅ هیچ ناسازگاری جدی در این اجرا پیدا نشد.');
      autoTestText.value = 'تست تمام شد • مشکلی پیدا نشد';
    } else {
      buf.writeln('❌ یافته‌ها:');
      for (final f in _findings) {
        buf.writeln(
            '• [${f.code}] ${f.msg} (اولین ${_dbgHms(f.at)} • ${f.n} بار)');
        _dbgProb('[AUTOTEST ${f.code}] ${f.msg}');
      }
      autoTestText.value =
          'تست تمام شد • ${_findings.length} مشکل — گزارش را ببین';
    }

    buf.write(_atJournalSection());
    buf.write(_atXrayTail());
    buf.write(await _atLogcatTail());
    buf.write(_atDiagnosis());

    // کامل: آدرس IP و جزئیات بدون پوشش (برای پیدا کردن دقیق مشکل)
    final report = buf.toString();
    dbg(report);
    errorLog.value = '${errorLog.value}\n$report'.trim();
    // REPORTSAVE: گزارش داخل فایل هم ذخیره می‌شود تا بعداً بتوانی کپی یا بفرستی
    final savedPath = await atSaveReport(report);

    if (mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(_findings.isEmpty
                ? 'تست خودکار تمام شد ✅'
                : 'تست خودکار تمام شد — ${_findings.length} مشکل'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                          savedPath.isNotEmpty
                              ? 'ذخیره شد در:\n$savedPath'
                              : 'ذخیره در پوشه‌ی Download انجام نشد. در تنظیمات برنامه، دسترسی «همه‌ی فایل‌ها» را روشن کن و دوباره تست بگیر.',
                          style: const TextStyle(fontSize: 12)),
                    ),
                    SelectableText(report,
                        style: const TextStyle(fontSize: 13, height: 1.4)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: report));
                  Navigator.pop(ctx);
                },
                child: const Text('کپی گزارش'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('باشه'),
              ),
            ],
          ),
        ),
      );
    }

    _phase = _AtPhase.idle;
    autoTestAdFree = false; // TESTNOAD
    if (_pilotSnap != null && !localPilotOn && !aiSession) { // MODESNAP
      _restorePilotSnap();
    }
  }

  // ---------------------------------------------------------------------------
  // Sampler + detectors
  // ---------------------------------------------------------------------------

  void _atSample() {
    if (_phase != _AtPhase.running) return;
    final now = DateTime.now();
    final s = _AtStateSample(
      at: now,
      connected: connected,
      busy: busy,
      switching: switching,
      watchBusy: watchBusy,
      status: status,
      lastWhy: lastWhy,
      lastState: lastState,
      engine: _currentEngine,
    );
    _samples.add(s);
    // PILOT-FLAP: a server change caused by the pilot, counted once per change
    if (_samples.length >= 2) {
      final prevWhy = _samples[_samples.length - 2].lastWhy;
      if (lastWhy != prevWhy && lastWhy.contains('خلبان')) {
        _atPilotSwitches++;
      }
      if (_atPilotSwitches == 6) {
        _atAdd('PILOT-FLAP', 'خلبان ۶ بار سرور را عوض کرد؛ شاید بیش از حد تعویض می‌کند');
      }
    }
    if (_samples.length > 500) _samples.removeAt(0);

    if (_startedAt != null) {
      final p = now.difference(_startedAt!).inMilliseconds /
          _testDuration.inMilliseconds;
      autoTestProgress.value = p.clamp(0.0, 1.0);
    }

    // SWITCH-FLAG-STUCK: switching stays true while connected and idle (blocks later actions)
    if (switching && connected && !busy) {
      _switchFlagSince ??= now;
      if (now.difference(_switchFlagSince!) > const Duration(seconds: 40)) {
        _atAdd('SWITCH-FLAG-STUCK', 'switching=true با اتصال برقرار و بدون کار، بیش از 40s • موتور=$_currentEngine');
        switching = false; // release it so later actions are not blocked
        _switchFlagSince = null;
      }
    } else {
      _switchFlagSince = null;
    }
    if (busy) {
      _busySince ??= now;
      // PROGRESS: جستجوی طولانی که وضعیتش هنوز عوض می‌شود گیر نیست
      if (status != _busyStatus) {
        _busyStatus = status;
        _busyStatusAt = now;
      }
      final quietFor = now.difference(_busyStatusAt ?? now);
      if (now.difference(_busySince!) > _busyLimitNow() &&
          quietFor > _busyQuietLimit) {
        _atAdd(connected ? 'BG-BUSY' : 'BUSY-STUCK',
            'busy بیش از ${_busyStuckLimit.inSeconds}s مانده • موتور=$_currentEngine • $status');
        _busySince = now;
      }
    } else {
      _busySince = null;
    }

    // NOHEALTHY: ده دقیقه‌ی پیاپی جستجو بدون هیچ سرور سالم
    if (!connected && searching && _ready() == 0) {
      _noHealthySince ??= now;
      if (!_noHealthyReported &&
          now.difference(_noHealthySince!) > _noHealthyLimit) {
        _noHealthyReported = true;
        _atAdd('NO-HEALTHY-LONG',
            '${_noHealthyLimit.inMinutes} دقیقه بدون سرور سالم • تست سریع $fastOk/$fastTested • وضعیت: $status');
      }
    } else if (connected || _ready() > 0) {
      _noHealthySince = null;
      _noHealthyReported = false;
    }

    if (switching && !busy) {
      _switchingSince ??= now;
      if (!busy && now.difference(_switchingSince!) > _switchingStuckLimit) { // TESTUPGRADE
        _atAdd('SWITCH-STUCK',
            'switching بیش از ${_switchingStuckLimit.inSeconds}s • موتور=$_currentEngine');
        _switchingSince = now;
      }
    } else {
      _switchingSince = null;
    }

    if (_atConnecting && busy && !connected) {
      _connectingSince ??= now;
      if (now.difference(_connectingSince!) > _connectHangNow()) {
        _atAdd('CONNECT-HANG',
            'اتصال بیش از ${_connectHangLimit.inSeconds}s طول کشید • موتور=$_currentEngine');
        _connectingSince = now;
      }
    } else {
      _connectingSince = null;
    }

    if (connected && !wantVpn && !busy) {
      _atMismatchTicks++;
      if (_atMismatchTicks >= 3) {
        _atAdd('FLAG-MISMATCH',
            'connected=true ولی wantVpn=false برای ${_atMismatchTicks * 3}s • موتور=$_currentEngine');
      }
    } else {
      _atMismatchTicks = 0;
    }
    if (connected && !watchBusy && !busy && !switching) {
      // informational only when watchdog should be running — not always a bug
    }

    autoTestText.value =
        'تست #$_scenario • $_currentEngine • ${_findings.length} یافته';
  }

  // وصل شد ولی ترافیک رد نشد: اطلاعاتی است و خطا حساب نمی‌شود
  static const _atInfoCodes = {'ENG-NODATA', 'STABLE-NODATA'};
  static bool _atNoTraffic = false;

  void _atAdd(String code, String msg) {
    // NOTEONLY: وضعیت داده است (نه خطای برنامه) → فقط در دفتر و لاگ ثبت می‌شود، یافته حساب نمی‌شود
    if (code == 'SUBST-NODEAD' || code == 'SUBST-NOCLEAN') {
      errJournalAdd('[$code] $msg', kind: 'INFO-$code');
      dbg('ℹ [$code] $msg (اطلاعاتی، خطا نیست)');
      return;
    }
    if (_atInfoCodes.contains(code)) {
      _atNoTraffic = true;
      errJournalAdd('[$code] $msg', kind: 'INFO-$code');
      dbg('ℹ [$code] $msg (اطلاعاتی، خطا نیست)');
      return;
    }
    final key = '$code|${msg.replaceAll(RegExp(r'\d+'), '#')}';
    for (final f in _findings) {
      final fk = '${f.code}|${f.msg.replaceAll(RegExp(r'\d+'), '#')}';
      if (fk == key) {
        f.n++;
        return;
      }
    }
    _findings.add(_AtFinding(code, msg));
    dbg('🧪 یافته: [$code] $msg');
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<void> _atWait(Duration d, {String? note}) async {
    if (note != null) {
      autoTestText.value = 'تست #$_scenario • $note';
      dbg('🧪 $note');
    }
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      if (_abortRequested || _phase != _AtPhase.running) return;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  Future<void> _atWaitUntil(
    bool Function() pred, {
    required Duration timeout,
    String label = '',
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (_abortRequested || _phase != _AtPhase.running) return;
      if (pred()) return;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    if (!pred()) {
      _atAdd('TIMEOUT',
          'صبر برای «$label» بیش از ${timeout.inSeconds}s • موتور=$_currentEngine • ${_atStateSnap()}');
    }
  }

  /// وضعیت لحظه‌ای برنامه؛ تا گزارش همیشه بگوید «گیر در کجاست»
  String _atStateSnap() =>
      'وضعیت: وصل=${connected ? 1 : 0} مشغول=${busy ? 1 : 0} '
      'تعویض=${switching ? 1 : 0} جستجو=${searching ? 1 : 0} '
      'صف=${pending.length} • status="$status" • lastFail="$lastFail"';

  /// اعمال موتور بدون دیالوگ UI (مسیر تست)
  Future<void> _atApplyEngine(String id) async {
    _currentEngine = id;
    applyPilotEngine(id);
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  Future<void> _atEnsureDisconnected() async {
    if (connected || busy || wantVpn) {
      abort = true;
      try {
        await disconnect();
      } catch (e, stk) { logError(e, stk); }
      await _atWaitUntil(() => !connected && !busy && !switching,
          timeout: const Duration(seconds: 25), label: 'قطع کامل');
      abort = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Scenarios
  // ---------------------------------------------------------------------------

  /// آیا V2Ray در همین اجرا وصل شده؟ اگر نه، سناریوهای فقط-V2Ray را رد می‌کنیم
  /// تا ۲۰ دقیقه پشت‌سرهم صرف یک موتور خراب نشود و موتورهای بعدی تست شوند.
  bool _atV2rayUsable() {
    if (!_atSelected.contains('v2ray')) return false;
    final r = _engineResult['v2ray'] ?? '';
    final ok = r.startsWith('✅') || r.startsWith('⚠️');
    if (!ok) dbg('🧪 V2Ray وصل نشده؛ سناریوهای V2Ray-only رد شد');
    return ok;
  }

  /// چه قابلیتی از هسته این کانفیگ لازم دارد (فقط قوانین قطعی یا آنچه در changelog نسخه‌ی ۳.۵.۰ آمده)
  String _atCfgNeeds(Server? s) {
    if (s == null) return 'کانفیگ ثبت نشد';
    final l = s.link;
    final notes = <String>[];
    if (l.contains('allowInsecure=1') ||
        l.contains('allowInsecure=true') ||
        l.contains('insecure=1')) {
      notes.add('allowInsecure دارد؛ هسته‌ی ۳.۵.۰ (Xray v26.9.9) این گزینه را حذف کرده → با نسخه‌ی ۳.۴.۱ امتحان کن');
    }
    if (l.startsWith('vless://') && !s.tls && s.isIp) {
      notes.add('VLESS بدون TLS به IP عمومی؛ هسته‌ی ۳.۵.۰ این را رد می‌کند');
    }
    if (s.reality) {
      notes.add('REALITY دارد؛ فقط در هسته‌ی Xray کار می‌کند');
    }
    if (l.contains('type=xhttp') || l.contains('type=splithttp')) {
      notes.add('transport xhttp/splithttp دارد؛ فقط در Xray کار می‌کند');
    }
    if (notes.isEmpty) {
      return 'قابلیت خاصی لازم ندارد؛ علت احتمالاً سرور یا شبکه است';
    }
    return notes.join(' | ');
  }

  /// راهنمای هر کد: [کجا، علت، راه حل]
  List<String> _atHelpOf(String code) {
    if (code.startsWith('SUBST-USELESS')) {
      return [
        'lib/nat_ultra.dart → _natSpecs (لیست حالت‌های پروژه)',
        'این حالت روی چند تلاش با اتصال واقعی ترافیک تونل نداد',
        'اگر تست دوباره همین را گفت، حالت را در _natRetiredNames (nat_ultra.dart) بگذار؛ کار دیگری لازم نیست',
      ];
    }
    switch (code) {
      case 'NAT-CLOSED':
        return [
          'lib/auto_test.dart → _atDomesticProbe (تست سایت‌های داخلی بدون تونل)',
          'در این لحظه فقط تعداد کمی از سایت‌های داخلی باز بودند؛ مسیر نت ملی تنگ است',
          'خط DOMESTIC-REPORT را بفرست؛ دامنه‌هایی که باز شده‌اند را برای مسیر مجاز امتحان می‌کنیم',
        ];
      case 'ORPHAN-LOOP':
        return [
          'lib/main.dart → _inspect (بخش orph) و _runBusy (abort) و _failover',
          'جستجو لغو شد ولی wantVpn روشن ماند؛ واچ‌داگ _failover را صدا زد و جستجو از اول شروع شد',
          'بعد از لغو، جستجوی باقی‌مانده را ادامه بده و _failover را صدا نزن. این اصلاح بزرگ‌تر است؛ گزارش را بفرست',
        ];
      case 'BUSY-CAP':
        return [
          'lib/main.dart → _runBusy (سقف زمان)',
          'کار طولانی‌تر از سقف بود و وسط راه abort شد',
          'سقف نت ملی ۲۰ دقیقه است؛ اگر هنوز رخ داد، کار را به مراحل کوچک‌تر با سقف جدا تقسیم کن',
        ];
      case 'BATCH-SLOW':
        return [
          'lib/main.dart → WATCHDOG دسته‌ی نت ملی و اندازه‌ی دسته (BATCHFIT)',
          'تست‌های یک دسته یکی‌یکی از یک هسته رد می‌شوند؛ دسته‌ی بزرگ در ۴ دقیقه تمام نمی‌شود',
          'اندازه‌ی دسته‌ی نت ملی را کمتر کن (مثلاً ۸) یا حالت‌های ماتریس را برای سرورهای بی‌پاسخ کوتاه‌تر کن',
        ];
      case 'NO-TRAFFIC':
        return [
          'lib/main.dart → pingAny و مسیر iranRoute / DNS',
          'سرور وصل می‌شود ولی بسته‌ها از تونل برنمی‌گردند (سرور فیلتر، مسیر یا DNS)',
          'اگر همه‌ی سرورها همین‌اند مسیر DNS و iranRoute را بررسی کن؛ وگرنه این گروه سرور را لیست سیاه کن',
        ];
      case 'TLS-MISMATCH':
        return [
          'lib/nat_ultra.dart → ساخت کانفیگ IP (security و SNI بعد از جایگزینی IP)',
          'سرور روی پورتی که TLS ندارد جواب می‌دهد ولی کانفیگ security=tls دارد؛ یا SNI بعد از جایگزینی IP درست نمانده',
          'یک کانفیگ را با v2rayNG مقایسه کن (serverName، Host و security). اگر فقط کانفیگ‌های IP-جایگزین خطا دارند، SNI را حفظ کن',
        ];
      case 'DIALER-PROXY':
        return [
          'lib/main.dart → sanitizeCfg (پاک‌سازی dialerProxy)',
          'یک outbound با dialerProxy به outbound ناموجود ارجاع داده',
          'اگر در نسخه‌ی جدید هم هست، sanitizeCfg را روی مسیری که این کانفیگ را می‌سازد اعمال کن',
        ];
      case 'PATH-ACCESS':
        return [
          'lib/nat_ultra.dart → نوشتن فایل‌های بخشی (PARTSPRIV)',
          'نوشتن در Download رد شد؛ معمولاً nat_ultra.dart قدیمی در build است',
          'nat_ultra.dart جدید را جایگزین کن و دوباره بساز',
        ];
      case 'SWITCH-STUCK':
        return [
          'lib/main.dart → _swapTo / _stableSwap (فلگ switching)',
          'تعویض سرور بیش از حد طول کشید؛ معمولاً اتصال قبلی هنوز بسته نشده',
          'قطع کامل را قبل از وصل جدید منتظر بمان. اگر همراه ENG-FAIL است، مشکل از هسته است',
        ];
      case 'BUSY-STUCK':
        return [
          'lib/auto_test.dart → _atSample (آستانه ۱۲۰ ثانیه)',
          'اتصال یا تست سرعت بیش از حد مانده',
          'اگر همراه ENG-FAIL یا CONNECT-HANG است، هسته به CONNECTED نرسیده؛ بخش قابلیت‌های هسته را ببین',
        ];
      case 'NO-HEALTHY-LONG':
        return [
          'lib/main.dart → _findGood / _acquireInner (حلقه‌ی جستجو)',
          'منابع تست شدند ولی هیچ سرور سالمی پیدا نشد',
          'خط‌های «TRACE batch» و «تست سریع» را ببین؛ اگر تست‌ها فوری با closed pipe شکست می‌خورند، مشکل از اجرای تست هسته است نه از منابع',
        ];
      case 'CONNECT-HANG':
        return [
          'lib/auto_test.dart → _atSample (آستانه ۱۱۰ ثانیه)',
          'اتصال بیش از ۱۱۰ ثانیه طول کشید',
          'کانفیگ یا سرور پاسخ نمی‌دهد. اگر برای همه‌ی کانفیگ‌ها تکرار شد، نسخه‌ی هسته (flutter_v2ray_client) را بررسی کن',
        ];
      case 'TIMEOUT':
        return [
          'lib/auto_test.dart → _atWaitUntil',
          'منتظر وصل شدن موتور ماندیم و نشد',
          'اگر ENG-FAIL هم هست، اتصال واقعاً برقرار نشده؛ علت را در بخش قابلیت‌های هسته ببین',
        ];
      case 'ENG-FAIL':
        return [
          'lib/auto_test.dart → _atConnectItem',
          'موتور وصل نشد؛ status آخر اپ در همان خط آمده',
          'lastFail و lastWhy داخل همان خط علت دقیق شکست اپ را می‌گویند. اگر برای همه‌ی کانفیگ‌ها تکرار شد، مشکل از شروع هسته در حالت VPN است؛ مشخصات کانفیگ‌ها در بخش E-CONFIG-FAIL گزارش اصلی است',
        ];
      case 'RECONNECT-FAIL':
        return [
          'lib/auto_test.dart → _atScenarioReconnectStorm',
          'بعد از قطع و وصل مجدد، اتصال برنگشت',
          'ناپایداری روی همان سرور. ENG-FAIL و بخش هسته را ببین',
        ];
      case 'VERDICT':
        return [
          'lib/auto_test.dart → _atConnectItem (تست‌های پشت‌سرهم)',
          'سه سرور پشت‌سرهم با یک علت وصل نشدند؛ تست برای صرفه‌جویی زودتر تمام شد',
          'علت احتمالی بالای گزارش را بخوان؛ بعد از رفع، تست را دوباره اجرا کن',
        ];
      case 'ABORT-STUCK':
        return [
          'lib/main.dart → _runBusy و تابع‌هایی که abort را چک می‌کنند (_doConnect / _failover / _swapTo)',
          'بعد از توقف، busy یا switching هنوز true است؛ یعنی کاری که به abort جواب نمی‌دهد هنوز در جریان است',
          'در آن تابع، بعد از هر await یک if (abort) return بگذار و در finally پرچم‌ها را پاک کن (busy=false، switching=false)',
        ];
      case 'ABORT-FLAG':
        return [
          'lib/main.dart → disconnect و شنونده‌ی onStatusChanged',
          'بعد از توقف، connected هنوز true است؛ یعنی وضعیت DISCONNECTED از هسته نرسیده',
          'مسیر disconnect را بررسی کن که منتظر رویداد DISCONNECTED بماند و بعد از timeout connected را خودش false کند',
        ];
      case 'SWAP-SKIP':
        return [
          'lib/auto_test.dart → _atScenarioServerSwap',
          'سناریوی تعویض سرور بدون اتصال اولیه شروع شد، چون اتصال اول برقرار نشد',
          'ریشه‌ی آن ENG-FAIL / VERDICT است؛ اول آن را رفع کن',
        ];
      case 'SWAP-EX':
        return [
          'lib/main.dart → _failover',
          'استثنا هنگام تعویض سرور',
          'متن استثنا در همان خط را بفرست؛ جای دقیق آن در stack trace مشخص می‌شود',
        ];
      case 'SWAP-DROP':
        return [
          'lib/main.dart → _failover / _swapTo (بعد از وصل جدید)',
          'بعد از تعویض سرور، اتصال قطع ماند',
          'بعد از وصل جدید، شنونده‌ی onStatusChanged باید connected را true نگه دارد؛ مسیر قطع را با رویداد DISCONNECTED ناخواسته مقایسه کن',
        ];
      case 'STABLE-DROP':
        return [
          'lib/main.dart → شنونده‌ی onStatusChanged (dropTimer) و _startWatch',
          'در مانیتور طولانی، اتصال بدون درخواست کاربر قطع شد',
          'همان شنونده‌ی DISCONNECTED؛ خطوط «هسته:» و «V2RAY-STATE» همان ساعت را در گزارش اصلی ببین',
        ];
      case 'STABLE-NODATA':
        return [
          'lib/auto_test.dart → _atScenarioLongStable',
          'در مانیتور طولانی، تونل بالا بود ولی داده‌ای نرسید',
          'DNS و مسیریابی TUN؛ در ۳.۵.۰ TUN بومی است، پس نسخه‌ی پلاگین را بررسی کن (build.yml)',
        ];
      case 'ITEM-FAIL':
        return [
          'lib/auto_test.dart → _atConnectItem',
          'این بخش به CONNECTED نرسید',
          'status و lastFail داخل همان خط علت را می‌گویند؛ اگر فقط در این بخش است، لیست یا حالت همان بخش را بررسی کن',
        ];
      case 'NAT-NOCONNECT':
        return [
          'lib/auto_test.dart → _atItemNational (پایان بخش نت ملی)',
          'هیچ سطحی از ماتریس نت ملی به اتصال سالم نرسید',
          'خط «سطح N» هر سطح و «علت» بالای همین گزارش را بخوان؛ اگر لیست خالی بود سرور نیست، اگر هندشیک قطع بود Fragment/سطح بالاتر',
        ];
      case 'SUBST-NOHEALTHY':
        return [
          'lib/auto_test.dart → _atItemSubst (شروع)',
          'پوشه‌ی سرورهای سالم خالی بود، پس تست جایگزینی اجرا نشد',
          'یک بار جستجوی جهانی یا ملی کامل کن تا سرور سالم ذخیره شود، بعد تست را دوباره بزن',
        ];
      case 'SUBST-NOCLEAN':
        return [
          'lib/nat_ultra.dart → cleanIps (IP تمیز)',
          'لیست IP تمیز خالی بود؛ حالت‌های «IP تمیز» عملاً همان حالت پایه بودند',
          'IP تمیز را در تنظیمات وارد کن یا یک بار با نت عادی جستجو کن تا ساخته شود',
        ];
      case 'SUBST-NONE':
        return [
          'lib/nat_ultra.dart → _natLinkFor / _natApplyTweaks (جایگزینی پورت، IP، DNS، SNI)',
          'هیچ‌کدام از حالت‌های جایگزینی روی سرورهای سالم جواب نداد',
          'خط «پورت/IP تمیز/DNS/SNI» همین گزارش را ببین؛ اگر پایه هم شکست خورد، سرورها امروز مرده‌اند',
        ];
      case 'SUBST-NORESCUE':
        return [
          'lib/auto_test.dart → _atItemSubst (ستون «وقتی پایه شکست خورد»)',
          'جایگزینی بعضی حالت‌ها جواب داد، ولی برای سروری که پایه شکست خورد هیچ‌کدام کمک نکرد',
          'جایگزینی روی سرورهای دیگر کمک کرد؛ اگر این الگو همیشگی است، ترتیب حالت‌ها را عوض کن',
        ];
      case 'IP-NOTEST':
        return [
          'lib/main.dart → _testBatchFast / _loadPending / _findGood (مسیر IP نت ملی)',
          'IP باز پیدا شد ولی به تست هسته (natIpTested) نرسید',
          'مسیر دقیق و راه حل در همین متن است (خط «راه حل:» را بخوان)',
        ];
      case 'ITEM-DLZERO':
        return [
          'lib/auto_test.dart → _atConnectItem (measure ۳ بار + _siteOpens)',
          'تونل و سایت کنترل جواب دادند ولی دانلود حجمی smallSpeedUrl داده نگرفت',
          'تونل سالم است؛ آدرس دانلود (speed.cloudflare.com) از این شبکه بسته یا کند است. آدرس دوم بگذار یا روی سرور دیگری تست کن',
        ];
      case 'ITEM-NODATA':
      case 'ITEM-MEASURE':
        return [
          'lib/auto_test.dart → _atConnectItem',
          'وصل شد ولی تست سرعت و کنترل سایت هر دو داده نگرفتند',
          'تونل بالا آمده ولی ترافیک رد نشده؛ DNS و مسیریابی را بررسی کن',
        ];
      case 'NAT-NOIP':
        return [
          'lib/main.dart → _testBatchFast و _natPrescan (اسکن IP نت ملی)',
          'شمارنده‌ی اسکن IP در این بخش تکان نخورد؛ IPها قبل از تست کانفیگ بررسی نشدند',
          'بازه‌های IP را در «بازه‌های IP برای جستجو» وارد کن، یا یک بار با نت عادی وصل شو تا IPهای حافظه ساخته شوند',
        ];
      case 'NAT-ORDER':
        return [
          'lib/main.dart → _testBatchFast',
          'سرور قبل از تست TCP روی IP به تست کانفیگ رسید',
          'ترتیب IP اول را در _testBatchFast بررسی کن؛ ULTRA غیرنت‌ملی نباید این مسیر را دور بزند',
        ];
      case 'NAT-LEVEL':
        return [
          'lib/main.dart → _natEscalate و _doConnect (natFloor)',
          'نت ملی همه‌ی سطوح ماتریس را امتحان نکرد',
          'natFloor دکمه‌ی نت ملی باید ۱۰ باشد و natLevel نباید پایین‌تر از آن بماند',
        ];
      case 'PILOT-NOTICK':
        return [
          'lib/iran_ai_extras.dart → localPilotTick',
          'خلبان وصل شد ولی تیکی نزد',
          'اگر busy یا switching مانده، شرط شروع تیک را بررسی کن',
        ];
      case 'HOT-NOTREADY':
        return [
          'lib/nat_ultra.dart → natHotEnsure',
          'پوشه‌ی منابع تازه بعد از ۱۰ دقیقه ساخته نشد',
          'دسترسی به منابع را بررسی کن؛ بدون پوشه، اتصال آفلاین ممکن نیست',
        ];
      case 'PILOT-FLAP':
        return [
          'lib/iran_ai_extras.dart → localPilotTick / _localApply',
          'خلبان بیش از حد سرور را عوض کرد',
          'قانون مدت ماندن روی سرور در خلبان وجود ندارد؛ باید در تصمیم تعویض (localPilotTick / _localDecide) اضافه شود',
        ];
      case 'NAT-DETECT':
        return [
          'lib/main.dart → _natDetect',
          'تشخیص شبکه (جهانی یا ملی) خطا داد',
          'متن خطا را بفرست؛ معمولاً به دسترسی سایت‌های تست یا لغو زودهنگام مربوط است',
        ];
      case 'PLUGIN-SWALLOW':
        return [
          'lib/main.dart → _startWatch (کانال vpn/bg)',
          'بخش native اندروید متد alive را ندارد؛ هر دقیقه خطا می‌دهد ولی اتصال قطع نمی‌شود',
          'متد alive در کد اندروید پیاده‌سازی نشده (فقط در Dart تعریف شده). اپ کار می‌کند، ولی یا باید در MainActivity اضافه شود یا این فراخوانی حذف شود',
        ];
      case 'SWITCH-FLAG-STUCK':
        return [
          'lib/main.dart → _swapTo / _failover / _doConnect (هر جایی که switching=true می‌شود)',
          'پرچم switching بعد از وصل شدن آزاد نشده؛ اپ را در حالت «تعویض» نگه می‌دارد و کارهای بعدی را مسدود می‌کند',
          'در finally همان تابع switching = false بگذار؛ تست همین الان آن را آزاد می‌کند و کد آن را نشان می‌دهد',
        ];
      case 'BG-BUSY':
        return [
          'lib/main.dart → _runBusy (جستجوی پس‌زمینه / ردیف همه)',
          'اتصال برقرار است ولی جستجوی پس‌زمینه پرچم busy را نگه داشته؛ کارهای دیگر (تعویض، قطع، تست) مسدود می‌شوند',
          'وقتی connected=true است جستجوی پس‌زمینه را محدود کن (worker کمتر یا توقف) و قبل از هر کار دستی آن را متوقف کن',
        ];
      case 'XRAY-NOLOG':
        return [
          'lib/main.dart → _start (نوشتن کانفیگ هسته، کلید log.error)',
          'هسته قبل از ساختن فایل خطا بسته شد؛ دلیل واقعی فقط در logcat اندروید است و این در تقریباً همه‌ی شکست‌ها تکرار شد',
          'logcat را هنگام اتصال بگیر (فیلتر: xray یا V2RAY) و خطای اولین خط هسته را بفرست',
        ];
      case 'ABORT-CONTEXT':
        return [
          'lib/main.dart → همان مرحله‌ای که در «status» نوشته شده (مثلاً _start یا _preSocialCheck)',
          'این مرحله وقتی توقف رسید هنوز در حال انتظار بود',
          'در همان تابع بعد از هر await یک if (abort) return بگذار؛ اسم تابع را از status بگیر و برای من بفرست',
        ];
      case 'CRASH':
        return [
          'lib/auto_test.dart → _atRun',
          'استثنای داخل تست خودکار',
          'stack trace همین خط را بفرست؛ این باگ کد است',
        ];
      case 'ENG-NODATA':
        return [
          'lib/auto_test.dart → _atConnectItem',
          'وصل شد ولی تست سرعت داده نداد',
          'تونل بالا آمده ولی ترافیک رد نمی‌شود. DNS و مسیریابی TUN را بررسی کن (در ۳.۵.۰ TUN بومی شده)',
        ];
      case 'ENG-MEASURE':
        return [
          'lib/auto_test.dart → _atConnectItem',
          'خطا هنگام تست سرعت',
          'متن خطای measure در همان خط را ببین',
        ];
      case 'FLAG-MISMATCH':
        return [
          'lib/auto_test.dart → _atSample',
          'وضعیت داخلی ناسازگار: connected ولی wantVpn=false',
          'باگ state. این را باید در کد اصلاح کرد',
        ];
      default:
        return [
          'نامشخص',
          'این کد در راهنما تعریف نشده',
          'متن پیام را برای بررسی بفرست',
        ];
    }
  }

  /// بخش «تشخیص و راه‌حل» گزارش
  /// علت احتمالی یک شکست اتصال، از روی چیزهایی که واقعاً ثبت شده
  String _atCauseOfFail() {
    if (_atLastFail.contains('uuid')) {
      return 'کانفیگ uuid ندارد (لینک سرور ناقص است). '
          'راه حل: لینک سرور را دوباره از منبع بگیر.';
    }
    if (_atLastCoreUp) {
      return 'هسته روی پورت محلی بالا است ولی وضعیت CONNECTED از پلاگین نمی‌رسد؛ '
          'پس مشکل از سرور نیست. راه حل: خطوط V2RAY-STATE و V2RAY-START همین گزارش '
          'را بفرست تا بررسی شود که شنونده‌ی onStatusChanged در lib/main.dart وضعیت را می‌گیرد.';
    }
    return 'هسته روی پورت محلی بالا نمی‌آید؛ هسته قبل از شروع متوقف شده است. '
        'راه حل: خط XRAY-ERR و بلوک E-CONFIG-FAIL همین گزارش را بفرست؛ '
        'علت معمولاً کانفیگ (پروتکل، امنیت یا ترنسپورت) یا نبود مجوز VPN است.';
  }

  /// جمع‌بندی پایان تست: یک علت اصلی و یک کار مشخص
  /// NATONLY: تشخیص مشکل اصلی نت ملی از شمارنده‌های واقعی همان اجرا
  /// DOMESTIC: در شروع تست بدون تونل نگاه می‌کند کدام سایت‌های داخلی و کدام
  /// سایت‌های خارجی باز می‌شوند. نتیجه نشان می‌دهد نت ملی چه چیزهایی را رد
  /// می‌کند و کدام دامنه‌ها را برای مسیر مجاز امتحان کنیم.
  Future<void> _atDomesticProbe() async {
    const domestic = [
      'https://www.aparat.com/',
      'https://www.digikala.com/',
      'https://divar.ir/',
      'https://www.snapp.ir/',
      'https://www.iranserver.com/',
      'https://www.bale.ai/',
      'https://eitaa.com/',
      'https://www.zarinpal.com/',
    ];
    const global = [
      'https://www.google.com/generate_204',
      'https://www.youtube.com/',
      'https://www.instagram.com/',
      'https://web.telegram.org/',
    ];
    try {
      final domOk = <String>[];
      final globOk = <String>[];
      for (final u in domestic) {
        if (await _siteOpens(u, viaCore: false)) domOk.add(u);
      }
      for (final u in global) {
        if (await _siteOpens(u, viaCore: false)) globOk.add(u);
      }
      _atDomesticResult = 'داخلی باز: ${domOk.length}/${domestic.length} • '
          'خارجی باز: ${globOk.length}/${global.length}';
      dbg('DOMESTIC: $_atDomesticResult');
      _atDomesticOk = domOk;
    } catch (e, stk) {
      errJournalAdd(e, kind: 'DOMESTIC', st: stk);
    }
  }

  static String _atDomesticResult = '';
  static List<String> _atDomesticOk = [];

  /// KNOWN-ISSUES: هر مشکل باقی‌مانده را از لاگ همین اجرا پیدا می‌کند و
  /// با محل و راه حل گزارش می‌دهد (به‌جای اینکه کاربر حدس بزند).
  void _atKnownIssues() {
    try {
      final since = _dbgStartIdx.clamp(0, dbgLines.length);
      final lines = dbgLines.sublist(since);
      int cnt(bool Function(String) test) => lines.where(test).length;

      String xrayText = '';
      try {
        final f = File(kXrayErrPath);
        if (f.existsSync()) {
          final all = f.readAsLinesSync();
          xrayText = (all.length > 400 ? all.sublist(all.length - 400) : all).join('\n');
        }
      } catch (_) {}

      final journalMsgs = errJournal
          .where((e) => _startedAt == null || !e.at.isBefore(_startedAt!))
          .map((e) => e.msg)
          .toList();

      final orphan = cnt((l) => l.contains('خودترمیمی: اتصال یتیم'));
      if (orphan >= 2) {
        _atAdd('ORPHAN-LOOP',
            'اتصال یتیم $orphan بار: بعد از لغو جستجو اپ بدون کار ماند و جستجو از اول شروع شد');
      }
      final busyCap = cnt((l) => l.contains('کار متوقف شد'));
      if (busyCap >= 1) {
        _atAdd('BUSY-CAP', 'سقف زمان کار $busyCap بار قطع کرد (کار وسط راه متوقف شد)');
      }
      final slow = cnt((l) => l.contains('WATCHDOG: دسته‌ی نت ملی'));
      if (slow >= 3) {
        _atAdd('BATCH-SLOW',
            'دسته‌های نت ملی $slow بار از ۴ دقیقه گذشتند و سرورهای باقی‌مانده کنار رفتند');
      }
      final noTraffic = cnt((l) =>
          l.contains('اینترنت از تونل هنوز رد نشد') || l.contains('ترافیک تونل صفر'));
      if (noTraffic >= 3) {
        _atAdd('NO-TRAFFIC', '$noTraffic بار وصل شد ولی ترافیک از تونل رد نشد');
      }
      const tlsBad = 'tls: first record does not look like a TLS handshake';
      final tlsN = tlsBad.isEmpty ? 0 : xrayText.split(tlsBad).length - 1;
      if (tlsN >= 5) {
        _atAdd('TLS-MISMATCH',
            'سرورهایی با security=tls روی پورتی که TLS ندارد ($tlsN خطا در لاگ هسته)');
      }
      if (xrayText.contains('no outbound handler for dialerProxy')) {
        _atAdd('DIALER-PROXY', 'کانفیگی به یک outbound نامعتبر dialerProxy ارجاع می‌دهد');
      }
      final pa = journalMsgs.where((m) => m.contains('PathAccessException')).length;
      if (pa > 0) {
        _atAdd('PATH-ACCESS', 'نوشتن فایل در پوشه‌ی Download رد شد ($pa بار)');
      }
    } catch (e, stk) {
      errJournalAdd(e, kind: 'KNOWN-ISSUES', st: stk);
    }
  }

  String _atNatDiagnosis() {
    // NATTEST2: اسکن IP خاموش است (تنظیم عمدی)؛ تشخیص فقط روی ماتریس سطوح و اتصال انجام می‌شود
    if (!kNatIpScanOn) {
      final lf = _atLastFail;
      final stuckNow = _findings.any((f) =>
          f.code == 'BUSY-STUCK' || f.code == 'SWITCH-STUCK' || f.code == 'ABORT-STUCK');
      if (natIpOk > 0 || _atNatWorking) {
        return 'نت ملی کار کرد: سطح $_atMaxNatLevel وصل شد.';
      }
      if (stuckNow) {
        return 'مشکل: اتصال نت ملی گیر کرد (busy/switching بیش از حد). '
            'راه حل: همین گزارش را بفرست؛ زمان هر سطح در خط‌های «سطح» دیده می‌شود.';
      }
      if (lf.contains('EOF') || lf.contains('reset') || lf.contains('TLS') || lf.contains('handshake')) {
        return 'مشکل از فیلترینگ پروتکل است: هندشیک ($lf) قطع می‌شود. '
            'راه حل: Fragment را روشن کن و سطوح بالاتر ماتریس را امتحان کن.';
      }
      return 'هیچ سطحی از ماتریس وصل نشد. '
          'راه حل: لیست سرورهای نت ملی را بررسی کن (شاید خالی یا مرده باشد) و سطوح خط «سطح» را بفرست.';
    }
    final scanned = natIpScanned;
    final found = natIpFound;
    final tested = natIpTested;
    final ok = natIpOk;
    final lastFail = _atLastFail;
    final codes = _findings.map((f) => f.code).toSet();
    final stuck = codes.contains('BUSY-STUCK') ||
        codes.contains('SWITCH-STUCK') ||
        codes.contains('ABORT-STUCK');
    final protoBlocked = lastFail.contains('EOF') ||
        lastFail.contains('reset') ||
        lastFail.contains('TLS') ||
        lastFail.contains('handshake');

    if (scanned == 0) {
      return 'مشکل: اسکن IP اجرا نشد. '
          'راه حل: در ابزارها «بازه‌های IP برای جستجو» را خالی نگذار و یک بازه‌ی معتبر (مثلاً 5.160.0.0/16) وارد کن.';
    }
    if (found == 0) {
      return 'مشکل از شبکه است: روی $scanned آدرس هیچ IP با پورت باز پیدا نشد. '
          'راه حل: بازه‌ی IP دیگری اضافه کن (CDN یا ابر داخلی)، یا از حالت «اینترنت ضعیف / نت ملی» با IP تمیز استفاده کن.';
    }
    if (tested == 0) {
      return 'مشکل از کد است: $found IP باز پیدا شد ولی هیچ‌کدام به تست هسته نرسید '
          '(صف گیر کرد). راه حل: همین گزارش و خط‌های TRACE / WATCHDOG را بفرست؛ این باگ باید در کد رفع شود.';
    }
    if (ok == 0 && protoBlocked) {
      return 'مشکل از فیلترینگ پروتکل است: TCP به $found IP وصل می‌شود ولی هندشیک VPN ($lastFail) قطع می‌شود. '
          'راه حل: در تنظیمات نت ملی «Fragment» و «DNS ایرانی» را روشن کن، SNI را با دامنه‌ی واقعی یکی کن، '
          'و سرورهایی با پروتکل دیگر (مثلاً ws روی 443 یا TLS با SNI معتبر) را امتحان کن.';
    }
    if (ok == 0) {
      return 'مشکل: $tested سرور تست شد ولی هیچ‌کدام سالم نشد (علت آخر: ${lastFail.isEmpty ? 'نامشخص' : lastFail}). '
          'راه حل: کانفیگ‌های این IPها را با منبع اصلی مقایسه کن و Fragment را روشن کن.';
    }
    if (stuck) {
      return 'سرور سالم پیدا شد ($ok) ولی اتصال قفل شد (busy/switching آزاد نشد). '
          'راه حل: همین گزارش را بفرست؛ این باگ کد است.';
    }
    return 'نت ملی کار کرد: $ok سرور سالم از $found IP باز پیدا شد. '
        'اگر وصل نشدی، همین گزارش را بفرست.';
  }

  String _atRootCause() {
    final codes = _findings.map((f) => f.code).toSet();
    final anyUp = _engineResult.values.any((r) =>
        r.startsWith('✅') || r.contains('وصل شد') || r.contains('measure'));
    final anyFail = _engineResult.values.any((r) => r.contains('وصل نشد'));
    if (!anyUp && anyFail) return _atCauseOfFail();
    if (codes.contains('ENG-NODATA') || codes.contains('ENG-MEASURE')) {
      return 'وصل شد ولی از تونل داده‌ای رد نشد (ترافیک صفر). '
          'راه حل: سرور دیگری را امتحان کن؛ اگر همه‌ی سرورها همین‌طور بودند، '
          'اینترنت یا DNS گوشی/اپراتور را بررسی کن.';
    }
    if (codes.contains('ABORT-STUCK') || codes.contains('SWITCH-STUCK') ||
        codes.contains('BUSY-STUCK') || codes.contains('TIMEOUT')) {
      return 'بعد از توقف یا تعویض، قفل‌های برنامه (busy/switching) آزاد نشدند. '
          'این ممکن است نتیجه‌ی شکست شروع هسته باشد؛ اول خطوط XRAY-ERR و CORE-PORT را ببین. '
          'اگر هسته بالا نیامده، logcat را هنگام اتصال بگیر و بفرست. '
          'اگر هسته بالا آمده ولی قفل ماند، خطوط ABORT-CONTEXT و BUSY-STUCK را بفرست (lib/main.dart → _runBusy).';
    }
    if (codes.contains('RECONNECT-FAIL')) {
      return 'قطع و وصل پشت‌سرهم شکست خورد. '
          'راه حل: خط RECONNECT-FAIL و چند خط قبل از آن را بفرست.';
    }
    if (codes.contains('CRASH')) {
      return 'خود تست با خطا متوقف شد (CRASH). راه حل: متن CRASH را بفرست.';
    }
    if (codes.isEmpty && _atNoTraffic) {
      return 'هیچ خطایی نیست. فقط اطلاع: بعضی سرورها وصل شدند ولی ترافیک از تونل رد نشد؛ '
          'این خطا حساب نمی‌شود و سرور بعدی امتحان شد.';
    }
    if (codes.isEmpty) return 'هیچ مشکلی در این اجرا دیده نشد.';
    return 'مشکل‌های غیرمنتظره: ${codes.join('، ')}. '
        'راه حل: همین گزارش را برای بررسی بفرست.';
  }

  /// logcat اندروید: خط‌های هسته (GoLog/xray/V2Ray) که خود برنامه ثبت کرده
  Future<String> _atLogcatTail() async {
    try {
      final r = await Process.run(
          'logcat', ['-d', '-t', '800', '-v', 'brief', '--pid=$pid']);
      final all = (r.stdout as String).split('\n');
      final lines = all.where((l) {
        final low = l.toLowerCase();
        return low.contains('golog') ||
            low.contains('xray') ||
            low.contains('v2ray') ||
            low.contains('proxyerror') ||
            low.contains('[error]') ||
            low.contains('[warning]');
      }).toList();
      final tail = lines.length > 300 ? lines.sublist(lines.length - 300) : lines;
      return '\n📱 logcat (خطوط هسته) — ${tail.length} خط:\n${tail.join('\n')}\n';
    } catch (e, stk) {
      errJournalAdd(e, kind: 'LOGCAT-READ', st: stk);
      return '\n(گرفتن logcat ممکن نشد)\n';
    }
  }

  /// خط‌های آخر لاگ هسته‌ی V2Ray (xray_err.log): خطای واقعی اتصال اغلب همین‌جاست
  String _atXrayTail() {
    try {
      final f = File(kXrayErrPath);
      if (!f.existsSync()) {
        return '\n(فایل لاگ هسته پیدا نشد: $kXrayErrPath)\n';
      }
      final lines = f.readAsLinesSync();
      final tail = lines.length > 400 ? lines.sublist(lines.length - 400) : lines;
      return '\n📡 لاگ هسته V2Ray — ${tail.length} خط آخر از ${lines.length} خط:\n'
          '${tail.join('\n')}\n';
    } catch (jex, jstk) {
      errJournalAdd(jex, kind: 'XRAY-READ', st: jstk);
      return '\n(خواندن لاگ هسته ناموفق بود)\n';
    }
  }

  /// دفتر کامل خطاها: خطاهای مشابه گروه می‌شوند ولی هیچ‌کدام حذف نمی‌شود
  String _atJournalSection() {
    final out = StringBuffer();
    out.writeln('');
    out.writeln('📜 دفتر کامل خطاها (${errJournal.length} ثبت):');
    if (errJournal.isEmpty) {
      out.writeln('• هیچ خطایی ثبت نشد.');
      return out.toString();
    }
    // فقط خطاهای همین اجرای تست (از وقتی که شروع شد)
    final since = _startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final runEntries = errJournal.where((e) => !e.at.isBefore(since)).toList();
    out.writeln('(این اجرا: ${runEntries.length} • کل دفتر: ${errJournal.length})');
    // ERRREPORT: خلاصه‌ی دسته‌ها: باگ واقعی جدا از خطای عادی شبکه
    final cats = <String, int>{};
    for (final e in runEntries) {
      final c = errCategory(e);
      cats[c] = (cats[c] ?? 0) + 1;
    }
    out.writeln('خلاصه بر اساس نوع:');
    final catKeys = cats.keys.toList()
      ..sort((a, b) => cats[b]!.compareTo(cats[a]!));
    for (final c in catKeys) {
      out.writeln('• $c: ${cats[c]}');
    }
    // گروه‌بندی بر اساس محل خطا در کد (نه متن کامل که برای هر دامنه فرق دارد)
    final groups = <String, List<ErrEntry>>{};
    for (final e in runEntries) {
      final key = '${errCategory(e)}|${e.type}|${e.where}';
      (groups[key] ??= <ErrEntry>[]).add(e);
    }
    // اول باگ‌ها، بعد بقیه؛ داخل هر دسته پرتکرارترها اول
    final keys = groups.keys.toList()
      ..sort((a, b) {
        final ba = a.startsWith('باگ') ? 0 : 1;
        final bb = b.startsWith('باگ') ? 0 : 1;
        if (ba != bb) return ba.compareTo(bb);
        return groups[b]!.length.compareTo(groups[a]!.length);
      });
    // ERRREPORT2: خطاهای عادی شبکه (دامنه‌ی مرده، timeout) در لیست نمی‌آیند؛ فقط شمارششان نشان داده می‌شود
    bool noisy(String k) => k.startsWith('شبکه') ||
        k.startsWith('فایل موقت') ||
        k.startsWith('داده‌ی نامعتبر');
    final important = keys.where((k) => !noisy(k)).toList();
    final noiseCount = keys.length - important.length;
    if (noiseCount > 0) {
      out.writeln('(خطاهای عادی شبکه‌ی ${noiseCount} گروه نادیده گرفته شد؛ نیازی به کار نیست)');
    }
    if (important.isEmpty) {
      out.writeln('• هیچ باگ واقعی‌ای در این اجرا ثبت نشد.');
      return out.toString();
    }
    var i = 0;
    for (final k in important.take(40)) {
      final g = groups[k]!;
      final first = g.first;
      final last = g.last;
      i++;
      out.writeln('#$i ×${g.length}  ${k.split('|')[0]}  نوع: ${first.type}');
      out.writeln(
          '   اولین: ${_dbgHms(first.at)}  •  آخرین: ${_dbgHms(last.at)}');
      out.writeln('   بخش تست: ${first.tag.isEmpty ? '-' : first.tag}');
      out.writeln('   جای خطا در کد: ${first.where}');
      final m = first.msg;
      out.writeln('   نمونه‌ی پیام: ${m.length > 300 ? '${m.substring(0, 300)}…' : m}');
    }
    if (important.length > 40) out.writeln('… و ${important.length - 40} گروه دیگر');
    return out.toString();
  }

  String _atDiagnosis() {
    final out = StringBuffer();
    if (_findings.isNotEmpty) {
      out.writeln('');
      out.writeln('🔧 تشخیص و راه‌حل:');
      final seen = <String>{};
      for (final f in _findings) {
        if (!seen.add(f.code)) continue;
        final r = _atHelpOf(f.code);
        out.writeln('• [${f.code}]');
        out.writeln('   📍 کجا: ${r[0]}');
        out.writeln('   🔎 علت: ${r[1]}');
        out.writeln('   🛠 راه حل: ${r[2]}');
      }
    }
    if (_atCfgNotes.isNotEmpty) {
      out.writeln('');
      out.writeln('🧩 کانفیگ‌های ناموفق و قابلیت هسته‌ای که لازم داشتند:');
      final seen = <String>{};
      for (final n in _atCfgNotes) {
        if (seen.add(n)) out.writeln('• $n');
      }
    }
    return out.toString();
  }

  // ---------------------------------------------------------------------------
  // بخش‌های تست ۶۰ دقیقه‌ای؛ هر کدام یک حالت واقعی برنامه را تست می‌کند
  // ---------------------------------------------------------------------------

  /// آیا این بخش وقت دارد؟ اگر نه، با دلیل ثبت و رد می‌شود
  bool _atCanRun(String name, Duration need) {
    if (_abortRequested || _phase != _AtPhase.running) return false;
    if (_atLeft() < need) {
      _itemResult[name] = '⏭ رد شد: وقت باقی‌مانده کافی نبود';
      dbg('🧪 بخش «$name» رد شد (وقت کم)');
      return false;
    }
    return true;
  }

  /// STEST60: هر بودجه‌ای (IP، خلبان) فقط از وقت باقی‌مانده استفاده می‌کند
  Duration _atCap(Duration want, {Duration reserve = Duration.zero}) {
    final room = _atLeft() - reserve;
    if (room <= const Duration(seconds: 30)) return const Duration(seconds: 30);
    return room < want ? room : want;
  }

  Duration _atLeft() {
    if (_startedAt == null) return _testDuration;
    final l = _testDuration - DateTime.now().difference(_startedAt!);
    return l.isNegative ? Duration.zero : l;
  }

  /// نت ملی جستجوی طولانی دارد؛ حد گیر کردن برای آن بیشتر است
  Duration _busyLimitNow() => (nationalMode || natForce)
      ? const Duration(minutes: 15)
      : _busyStuckLimit;

  Duration _connectHangNow() => (nationalMode || natForce)
      ? const Duration(minutes: 12)
      : _connectHangLimit;

  /// برگشت به حالت عادی جهانی؛ بین بخش‌ها و قبل از سناریوهای پایداری
  Future<void> _atResetToGlobal() async {
    if (localPilotOn) stopLocalPilot();
    natForce = false;
    nationalMode = false;
    natFloor = 0;
    userModeChoice = null;
    offlineOnly = false;
    await ultimateSave();
    await _atEnsureDisconnected();
  }

  /// IP-NOTEST: IP باز پیدا شد ولی به تست هسته نرسید → کجای مسیر از بین رفت + راه حل
  String? _atIpNoTestDiag(
      Map<String, int> before, int foundBefore, int testedBefore) {
    final found = natIpFound - foundBefore;
    final tested = natIpTested - testedBefore;
    if (found <= 0 || tested > 0) return null;
    int d(String k) => (natIpFunnel[k] ?? 0) - (before[k] ?? 0);
    const keys = [
      'reload_dropped_ip',
      'ip_untrusted',
      'ip_batched',
      'ip_tcp_open',
      'ip_tcp_closed',
      'skip_enough',
      'skip_srcdead',
      'skip_recent_or_bad',
      'skip_abort',
      'skip_watchdog',
      'skip_slow',
      'empty_batch_with_ip_pending',
      'loop_calls',
      'loop_enough_at_start',
      'loop_pending_ip',
      'loop_zero_batches',
      'skip_searching',
    ];
    final path = keys.map((k) => '$k=${d(k)}').join(' • ');
    String fix;
    if (d('skip_searching') > 0) {
      fix = 'جستجوی دیگری (پس‌زمینه یا قبلی) قفل بود و این جستجو کنار گذاشته شد. '
          'راه حل: در _findGood نسخه‌ی IPWAIT را بگذار (جستجوی اصلی منتظر می‌ماند)';
    } else if (d('loop_calls') == 0) {
      fix = 'حلقه‌ی جستجوی IP اصلاً شروع نشد؛ بعد از اسکن، _findGood صدا زده نشد '
          'یا زودتر برگشت. راه حل: مسیر اسکن → _search → _findGood را در main.dart بررسی کن';
    } else if (d('loop_enough_at_start') > 0 && d('ip_batched') == 0) {
      fix = 'قبل از شروع، enough() درست بود و حلقه تست را نگرفت. راه حل: '
          'در نت ملی، IPهای تازه‌ی اسکن را از شرط enough() معاف کن';
    } else if (d('loop_zero_batches') > 0 && d('ip_batched') == 0) {
      fix = 'حلقه اجرا شد ولی هیچ دسته‌ای ساخته نشد (فیلتر cand). راه حل: '
          'IPهای تازه را قبل از فیلترهای نرم به دسته بفرست';
    } else if (d('reload_dropped_ip') > 0) {
      fix = 'فهرست صف دوباره ساخته شد و IPهای پیداشده از آن افتادند. '
          'راه حل: در _loadPending (main.dart) IPهای صف را نگه دار و فقط '
          'آن‌هایی را که دیگر لازم نیستند حذف کن';
    } else if (d('ip_untrusted') > 0 && d('ip_batched') == 0) {
      fix = 'همه‌ی IPها به فیلتر «ناشناخته» خوردند. راه حل: IPهای اسکن‌شده '
          'را قبل از _testBatchFast در natScanHits ثبت کن';
    } else if (d('ip_batched') == 0) {
      fix = 'IPها هرگز به دسته‌ی تست نرسیدند. راه حل: فیلتر cand در '
          '_findGood (_recentFail / _bad / _srcDead) را برای IPهای تازه بررسی کن';
    } else if (d('ip_tcp_closed') >= d('ip_batched')) {
      fix = 'همه‌ی IPها در بررسی TCP بسته بودند. راه حل: پورت‌ها و probe '
          'را بررسی کن، یا بازه‌ی IP را عوض کن';
    } else if (d('skip_enough') > 0) {
      fix = 'تست IP قبل از شروع، با «کافی بودن سرورهای سالم» (enough) رد شد. '
          'راه حل: در نت ملی، IPهای تازه را از enough() معاف کن';
    } else if (d('skip_recent_or_bad') > 0) {
      fix = 'IPها به خاطر شکست یا بد بودن قبلی رد شدند. راه حل: '
          'failed/badAt را برای IPهای تازه‌ی اسکن پاک کن';
    } else if (d('skip_srcdead') > 0) {
      fix = 'منبع IPها مرده حساب شد. راه حل: _srcDead را برای IPهای اسکن نادیده بگیر';
    } else if (d('skip_watchdog') > 0) {
      fix = 'دسته بیش از ۴ دقیقه طول کشید و IPها به دور بعد رفتند. '
          'راه حل: IPها را اول تست کن یا WATCHDOG را کوتاه‌تر کن';
    } else if (d('skip_slow') > 0) {
      fix = 'IPها پینگ بد داشتند و کنار گذاشته شدند. راه حل: آستانه‌ی badPingMs را برای نت ملی بالا ببر';
    } else {
      fix = 'مسیر مشخص نشد. همین خط مسیر را بفرست';
    }
    return 'IP باز پیداشده $found • به تست هسته $tested\n'
        'مسیر: $path\n'
        'راه حل: $fix';
  }

  /// وصل با تنظیمات فعلی برنامه تا CONNECTED یا مهلت؛ نتیجه در _itemResult[name]
  Future<bool> _atConnectItem(String name,
      {Duration timeout = const Duration(minutes: 6)}) async {
    errTag = name;
    final funBefore = Map<String, int>.from(natIpFunnel);
    final foundBefore = natIpFound;
    final testedBefore = natIpTested;
    await _atEnsureDisconnected();
    if (_abortRequested) return false;

    autoTestText.value = 'بخش «$name»: اتصال…';
    dbg('🧪 بخش «$name» — اتصال');
    await connect();
    // اتصال در نت ملی چند دقیقه طول می‌کشد؛ مهلت باید از همه‌ی جستجو بیشتر باشد
    await _atWaitUntil(() => connected && !busy,
        timeout: timeout, label: name);

    // IP-NOTEST: اگر IPهای باز پیدا شد ولی هیچ‌کدام به تست هسته نرسید، علت و راه حل را ثبت کن
    final ipDiag = kNatIpScanOn
        ? _atIpNoTestDiag(funBefore, foundBefore, testedBefore)
        : null; // NATTEST2: بدون اسکن IP این هشدار معنی ندارد
    if (ipDiag != null) _atAdd('IP-NOTEST', '$name: $ipDiag');

    if (!connected) {
      // "لغو شد" یعنی توقف دستی یا پایان تست، نه خطای اتصال؛ علت خالی نماند
      final cancelled = status.contains('لغو') && lastFail.isEmpty;
      _atLastFail = lastFail;
      if (cancelled) {
        _itemResult[name] = '⏹ لغو شد (توقف دستی یا پایان تست)';
        return false;
      }
      _itemResult[name] = '❌ وصل نشد • status="$status" • lastFail="$lastFail"';
      _atAdd('ITEM-FAIL',
          '$name وصل نشد • status="$status" • '
          'علت: ${lastFail.isEmpty ? 'ثبت نشد → ${_atStateSnap()}' : lastFail} • lastWhy="$lastWhy"');
      return false;
    }

    _itemResult[name] = '✅ وصل';
    await _atWait(const Duration(seconds: 10), note: 'پایداری $name');
    try {
      // ITEM-NODATA fix: one failed download is not "no data". The download
      // is tried up to 3 times; only when all of them fail the tunnel itself
      // is checked (a plain 204 request through the same core proxy).
      double? sp;
      for (var attempt = 1; attempt <= 3; attempt++) {
        sp = await measure(
            url: smallSpeedUrl, total: const Duration(seconds: 12));
        if (sp != null && sp > 0) break;
        if (attempt < 3) {
          await _atWait(const Duration(seconds: 4),
              note: 'تکرار تست سرعت $name ($attempt/3)');
        }
      }
      if (sp != null && sp > 0) {
        _itemResult[name] =
            '✅ وصل • ≈${(sp * 1024).toStringAsFixed(0)} KB/s';
      } else {
        final reach = await _siteOpens(
            'https://www.gstatic.com/generate_204', viaCore: true);
        if (reach) {
          _itemResult[name] =
              '⚠️ وصل • تونل جواب می‌دهد؛ دانلود حجمی ۳ بار داده نگرفت';
          _atAdd('ITEM-DLZERO',
              '$name: تونل و سایت کنترل جواب دادند ولی دانلود حجمی ۳ بار داده نگرفت');
        } else {
          _itemResult[name] = '⚠️ وصل • تست سرعت داده نگرفت';
          _atAdd('ITEM-NODATA',
              '$name وصل شد ولی از تونل داده نرسید (دانلود و کنترل سایت هر دو ناموفق)');
        }
      }
    } catch (e, jstk) { errJournalAdd(e, st: jstk);
      _itemResult[name] = '⚠️ وصل • خطا در تست سرعت';
      _atAdd('ITEM-MEASURE', '$name خطا در measure: $e');
    }
    return true;
  }

  /// ALLPATHS: پروتکل تکی (فقط همان پروتکل از فیلتر برنامه)
  Future<void> _atItemProto(int idx, String proto) async {
    _scenario = 6;
    final name = _atItemNames[idx];
    await _atResetToGlobal();
    final has = fetchedAll
        .any((s) => s.link.toLowerCase().startsWith('$proto://'));
    if (!has) {
      _itemResult[name] = '⏭ در لیست هیچ سرور $proto نبود';
      _atAdd('PROTO-NONE', '$name: هیچ سرور $proto در لیست دریافتی نیست');
      return;
    }
    protoSel
      ..clear()
      ..add(proto);
    pending = [];
    try {
      await _atConnectItem(name);
    } finally {
      protoSel.clear();
      pending = [];
    }
  }

  /// ALLPATHS: پرتکرارترین کشور در لیست، با فیلتر کشور
  Future<void> _atItemCountry(int idx) async {
    _scenario = 6;
    final name = _atItemNames[idx];
    await _atResetToGlobal();
    final cnt = <String, int>{};
    for (final s in fetchedAll) {
      final c = s.country;
      if (c != null) cnt[c] = (cnt[c] ?? 0) + 1;
    }
    if (cnt.isEmpty) {
      _itemResult[name] = '⏭ کشور سرورها هنوز معلوم نیست';
      return;
    }
    final top = cnt.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    selCountry = top;
    pending = [];
    try {
      final ok = await _atConnectItem(name);
      if (ok) {
        _itemResult[name] = '${_itemResult[name]} • کشور: $top';
      }
    } finally {
      selCountry = null;
      pending = [];
    }
  }

  /// ALLPATHS: خلبان هوش مصنوعی با کلیدی که کاربر ذخیره کرده؛ ۱۰ دقیقه پایش
  Future<void> _atItemAiPilot(int idx) async {
    _scenario = 7;
    final name = _atItemNames[idx];
    if (!_hasAnyAiKey) {
      _itemResult[name] = '⏭ هیچ کلید هوش مصنوعی ذخیره نشده';
      return;
    }
    await _atResetToGlobal();
    errTag = name;
    autoTestText.value = 'بخش «$name»: روشن کردن خلبان AI…';
    startGrokPilot();
    await _atWaitUntil(() => connected && !busy,
        timeout: const Duration(minutes: 15), label: name);
    if (!connected) {
      _itemResult[name] =
          '❌ خلبان AI وصل نکرد • status="$status" • lastFail="$lastFail"';
      _atAdd('ITEM-FAIL', '$name وصل نشد • lastFail="$lastFail"');
      stopGrokPilot();
      await _atEnsureDisconnected();
      return;
    }
    await _atWait(const Duration(minutes: 10), note: 'پایش $name');
    if (connected) {
      _itemResult[name] = '✅ خلبان AI ۱۰ دقیقه وصل ماند • ${_connStatus()}';
    } else {
      _itemResult[name] = '⚠️ خلبان AI بعد از وصل شدن قطع شد • status="$status"';
      _atAdd('AI-DROP', '$name بعد از وصل شدن قطع شد • status="$status"');
    }
    stopGrokPilot();
    await _atEnsureDisconnected();
  }

  /// بخش ۱: اینترنت جهانی (حالت عادی)
  Future<void> _atItemGlobal() async {
    _scenario = 1;
    final name = _atItemNames[0];
    await _atResetToGlobal();
    await _atApplyEngine('v2ray');
    final ok = await _atConnectItem(name);
    if (ok) {
      // این نتیجه، مبنای تست‌های V2Ray در سناریوهای پایداری است
      _engineResult['v2ray'] = _itemResult[name] ?? '✅';
      _itemResult[name] =
          '${_itemResult[name]} • حالت شناسایی‌شده: '
          '${nationalMode ? 'ملی' : 'جهانی'}';
    }
  }

  /// بخش ۲: پوشه‌ی منابع تازه باید ساخته شود تا بخش آفلاین کار کند
  Future<void> _atItemFolder() async {
    _scenario = 2;
    final name = _atItemNames[1];
    if (natHotReady()) {
      _itemResult[name] = '✅ از قبل ساخته شده بود';
      return;
    }
    autoTestText.value = 'در انتظار ساخت پوشه‌ی منابع تازه…';
    final t = DateTime.now();
    final end = t.add(const Duration(minutes: 10));
    while (!natHotReady() &&
        DateTime.now().isBefore(end) &&
        !_abortRequested &&
        _phase == _AtPhase.running) {
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    if (natHotReady()) {
      _itemResult[name] =
          '✅ ساخته شد • ${DateTime.now().difference(t).inSeconds}s';
    } else {
      _itemResult[name] = '❌ بعد از ۱۰ دقیقه ساخته نشد';
      _atAdd('HOT-NOTREADY', 'پوشه‌ی منابع تازه بعد از ۱۰ دقیقه ساخته نشد');
    }
  }

  /// بخش ۳: نت ملی. اول IPها TCP بررسی می‌شوند، بعد تست کانفیگ روی IPهای باز.
  /// همه‌ی سطوح ماتریس (تا ۱۰) باید در این جستجو امتحان شوند.
    Future<void> _atItemNational() async {
    _scenario = 3;
    final name = _atItemNames[2];
    natForce = true;
    nationalMode = true;
    userModeChoice = true;
    offlineOnly = false;
    natRound = 1; // V14: force pass 1
    await ultimateSave();

    _set('نت ملی: پاک‌سازی صف برای تست کامل ۵ ساعته');
    good.clear();
    pending.clear();
    failed.clear();
    fetchedAll.clear();
    listTime = null;

    _set('نت ملی: شروع اتصال اولیه...');
    await connect(); // Triggers V13 logic, returns on first server

    final tStart = DateTime.now();
    final testDuration = const Duration(hours: 5);

    while (_phase == _AtPhase.running && !_abortRequested) {
      final elapsed = DateTime.now().difference(tStart);
      if (elapsed > testDuration) break;

      final progress = elapsed.inSeconds / testDuration.inSeconds;
      autoTestProgress.value = progress.clamp(0.0, 1.0);
      autoTestText.value = 'نت ملی ۵ ساعته • ${elapsed.inHours}h ${elapsed.inMinutes % 60}m • '
          'دور: $natRound • سالم: ${good.length} • صف: ${pending.length} • '
          'IP تست‌شده: $natIpTested • IP باز: $natIpFound';

      if (natRound >= 2 && pending.isEmpty && !searching && !busy) {
        _atAdd('NAT-EXHAUSTED', 'کل صف در هر دو دور تست شد و صف خالی است.');
        break;
      }

      if (!searching && !busy && connected && pending.isNotEmpty) {
        unawaited(_standbyRun());
      }

      await Future<void>.delayed(const Duration(seconds: 3));
    }

    _itemResult[name] = '✅ تست ۵ ساعته تمام شد • '
        'سالم: ${good.length} • تست‌شده: $natIpTested • باز: $natIpFound';
  }

  /// NATMODES: هر سطح ماتریس نت ملی جدا با سقف ۴ دقیقه؛ نتیجه‌ی هر سطح ثبت می‌شود
  // SUBST: تست فقط برای جایگزینی پورت / IP تمیز / DNS / SNI روی سرورهای سالم
  static const String _atSubstName =
      'نت ملی: جایگزینی پورت/هاست/DNS روی سرورهای سالم';
  static const int _atSubstServers = 20; // سرورهای سالم (سریع‌ترین‌ها)
  static const int _atSubstPerServer = 12; // سقف حالت جایگزینی برای هر سرور (SUBSTFAST)
  static const Duration _atSubstTimeout = Duration(seconds: 5); // مهلت هر تست

  List<String> _atSubstDims(int v) {
    final x = _natSpecs[v];
    return [
      if (x.port) 'پورت',
      if (x.clean) 'IP تمیز',
      if (x.doh != null) 'DNS',
      if (x.sniHost) 'SNI',
      if (x.mode?.startsWith('kcp:') ?? false) 'UDP (kcp)',
    ];
  }

  // MULTIHOP: زنجیره‌ی exit ← relay؛ دلیل اینکه ورودی‌های relay حذف می‌شوند این است که فقط خروجی‌اش لازم است
  Future<int?> _atChainDelay(Server exit, Server relay) async {
    try {
      final merged = natChainCfg(natCfg(exit, 0), natCfg(relay, 0));
      if (merged == null) return null;
      final rr = await v2ray
          .getServerDelay(config: _testCfg(merged), url: delayTestUrl)
          .timeout(Duration(seconds: _atSubstTimeout.inSeconds + 8),
              onTimeout: () => -1);
      final int r = rr is int ? rr : (int.tryParse('$rr') ?? -1);
      return r > 0 ? r : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _atItemSubst() async {
    // SUBST-REAL2: تست هر جایگزین را با اتصال واقعی و بررسی ترافیک تونل امتحان می‌کند.
    // همان حالت‌هایی که در پروژه هستند. هر حالت که ترافیک را رد نکند، در گزارش «بی‌اثر» می‌شود.
    _scenario = 3;
    final name = _atSubstName;
    natForce = true;
    nationalMode = true;
    userModeChoice = true;
    offlineOnly = false;
    await ultimateSave();

    // HEALTHYFIRST: تا پوشه‌ی سرورهای سالم پر نشده، تست شروع نمی‌شود.
    // اگر خالی بود، همان جستجوی نت ملی برنامه اجرا می‌شود تا سرور سالم پیدا شود.
    var healthy = _usable().take(_atSubstServers).toList();
    if (healthy.isEmpty && !_abortRequested) {
      _set('پوشه‌ی سرورهای سالم خالی است؛ جستجو از پوشه‌ی منابع تازه...');
      try {
        // FRESHFIRST: اول پوشه‌ی منابع تازه (اگر نیست یا قدیمی است) به‌روز می‌شود، بعد جستجو
        if (!natHotReady()) {
          await natHotEnsure(force: true).timeout(const Duration(minutes: 5));
        } else {
          await natHotEnsure().timeout(const Duration(minutes: 5));
        }
        await _findGood(3).timeout(const Duration(minutes: 8));
      } catch (e, stk) {
        logError(e, stk);
      }
      healthy = _usable().take(_atSubstServers).toList();
    }
    if (healthy.isEmpty) {
      _atAdd('SUBST-NOHEALTHY',
          'تست شروع نشد: پوشه‌ی سرورهای سالم خالی ماند و جستجو هم سرور سالمی پیدا نکرد');
      _itemResult[name] = 'اجرا نشد: سرور سالمی پیدا نشد';
      return;
    }
    final healthySet = _usable().toSet();
    final dead = good
        .where((x) => !healthySet.contains(x) &&
            (x.badAt != null || x.checkedAt != null))
        .take(_atSubstServers)
        .toList();
    // IPSWEEP: IP‌ها اول با ترافیک تونل سنجیده می‌شوند؛ فقط IP‌های ترافیک‌دار در پروژه می‌مانند
    autoTestText.value = 'سنجش IP تمیز با تونل...';
    final ipWin = await _atIpSweep(
        healthy, _atCap(const Duration(minutes: 30))); // جدید: رزرو ۶۰ دقیقه‌ای مال خلبان بود و حذف شد
    if (ipWin.isNotEmpty) {
      cleanIps = List<CleanIp>.of(ipWin);
      cleanIpsAt = DateTime.now();
      await _saveCleanIps();
    }
    dbg('IPSWEEP: ${ipWin.length} IP ترافیک‌دار');
    if (cleanIps.isEmpty) {
      _atAdd('SUBST-NOCLEAN',
          'IP تمیز: از ${healthy.length} سرور سالم هیچ IP ای ترافیک نداد؛ حالت‌های IP تمیز در این اجرا تست نشدند (نتیجه‌ی شبکه است، خطای برنامه نیست)');
    }
    if (dead.isEmpty) {
      _atAdd('SUBST-NODEAD',
          'سرور خراب (تست‌شده و ناسالم) برای آزمایش پیدا نشد؛ زنده کردن امتحان نشد');
    }

    // ALLMODES: هر حالت پروژه (همه‌ی _natSpecs) حداقل یک بار روی یک سرور واقعی امتحان می‌شود.
    // هیچ حالتی بی‌صدا رد نمی‌شود: یا تست می‌شود، یا با دلیل مشخص در گزارش «جواب نداد» / «تست نشد» می‌آید.
    final allVars = [
      for (var v = 1; v < _natSpecs.length; v++)
        if (!natDisabled.contains(v) && !natRetired(v)) v
    ];
    final untried = <int>[...allVars]; // هنوز روی هیچ سروری امتحان نشده
    final failedOnce = <int>{}; // یک بار امتحان شده و ترافیک نداده (برای دور دوم)
    final perTry = <int, int>{}; // هر حالت: چند بار امتحان شد
    final perWin = <int, int>{}; // هر حالت: چند بار ترافیک تونل را رد کرد
    final noDoh = <int>{}; // DNS این حالت از گوشی باز نبود
    final order = <(String, Server)>[
      for (final s in healthy) ('سالم', s),
      for (final s in dead) ('خراب', s),
    ];
    final rows = <String>[];
    var total = 0, baseOk = 0, substServers = 0, brokenServers = 0;
    final t0 = DateTime.now();
    // جایگزینی فقط با توقف دستی یا پایان وقت متوقف می‌شود (جدید)
    bool stop() => _abortRequested || _phase != _AtPhase.running;

    Future<bool> tryVar(Server s, String key, int v) async {
      natVar[key] = v; // _start() خواندن حالت را از natVarFor می‌گیرد
      var ok = false;
      try {
        if (await _start(s)) {
          await Future.delayed(const Duration(seconds: 2));
          ok = await _tunnelTrafficOk();
        }
      } catch (e, stk) {
        logError(e, stk);
      } finally {
        await _stopV2();
      }
      return ok;
    }

    wantVpn = true;
    // دور اول: همه‌ی سرورها، هر کدام تا ۱۲ حالت از فهرست «هنوز امتحان نشده» که با آن سازگارند
    // دور دوم (اگر وقت بود): فقط سرورهای سالم، برای حالت‌هایی که یک بار جواب ندادند
    for (var pass = 0; pass < 2; pass++) {
      final list = pass == 0
          ? order
          : [for (final e in order) if (e.$1 == 'سالم') e];
      if (pass == 1 && failedOnce.isEmpty) break;
      rows.add(pass == 0
          ? '— دور اول: ${order.length} سرور —'
          : '— دور دوم: تکرار حالت‌هایی که جواب ندادند (${failedOnce.length}) —');
      for (var i = 0; i < list.length; i++) {
        if (stop()) break;
        final g = list[i].$1;
        final s = list[i].$2;
        final key = _nk(s);
        final f = _NatFacts(s);
        if (pass == 0) total++;
        autoTestProgress.value = i / (list.isEmpty ? 1 : list.length);
        autoTestText.value =
            'حالت‌ها (${g}) ${i + 1}/${list.length} • ${s.name} • مانده: ${untried.length}';

        var baseTun = false;
        if (pass == 0) {
          // (الف) پایه با اتصال واقعی
          natVar.remove(key);
          try {
            if (await _start(s)) {
              await Future.delayed(const Duration(seconds: 2));
              baseTun = await _tunnelTrafficOk();
            }
          } catch (e, stk) {
            logError(e, stk);
          } finally {
            await _stopV2();
          }
          if (baseTun) baseOk++;
        }

        // (ب) حالت‌های این سرور
        final cands = pass == 0
            ? untried.where((v) => _natAppliesF(f, v)).take(_atSubstPerServer).toList()
            : failedOnce.where((v) => _natAppliesF(f, v)).take(_atSubstPerServer).toList();
        final passed = <String>[];
        int? winner;
        for (final v in cands) {
          if (stop()) break;
          final name2 = v < _natSpecs.length ? _natSpecs[v].name : '#$v';
          if (pass == 0) untried.remove(v);
          if (!await natDohUsable(v)) {
            noDoh.add(v);
            failedOnce.remove(v);
            continue;
          }
          perTry[v] = (perTry[v] ?? 0) + 1;
          final ok = await tryVar(s, key, v);
          if (ok) {
            perWin[v] = (perWin[v] ?? 0) + 1;
            failedOnce.remove(v);
            passed.add(name2);
            winner ??= v;
          } else if ((perWin[v] ?? 0) == 0) {
            failedOnce.add(v);
          }
        }
        // APPLY: جایگزینی که ترافیک داد، برای همین سرور ذخیره می‌شود
        if (winner != null) {
          natVarSet(s, winner);
        } else {
          natVar.remove(key);
        }

        if (pass == 0) {
          if (passed.isNotEmpty) substServers++;
          if (!baseTun && passed.isEmpty) brokenServers++;
          rows.add('${s.name}: '
              '${baseTun ? 'پایه ✅' : 'پایه ❌'}'
              ' • حالت‌های تست‌شده: ${cands.length}'
              ' • ترافیک‌دار: ${passed.length}'
              '${passed.isEmpty ? '' : ' (${passed.take(2).join('، ')})'}');
        }
      }
    }
    wantVpn = false;

    // گزارش هر حالت: یا «جواب نداد» (امتحان شد و ترافیک نداد) یا «تست نشد» با دلیل
    _atSubstFailed.clear();
    _atSubstUntried.clear();
    final noServerVars = [
      for (final v in untried)
        if (!order.any((e) => _natAppliesF(_NatFacts(e.$2), v))) v
    ];
    for (final v in allVars) {
      final nm = v < _natSpecs.length ? _natSpecs[v].name : '#$v';
      final tries = perTry[v] ?? 0;
      if (perWin[v] != null) continue;
      if (tries > 0) {
        _atSubstFailed.add('$nm (روی $tries تلاش ترافیک نداد)');
      } else if (noDoh.contains(v)) {
        _atSubstUntried.add('$nm: DNS آن از گوشی باز نیست');
      } else if (noServerVars.contains(v)) {
        _atSubstUntried.add('$nm: با هیچ سرور تست‌شده سازگار نبود');
      } else {
        _atSubstUntried.add('$nm: تست نشد (وقت تمام شد)');
      }
    }
    final tested = perTry.keys.length;
    final won = perWin.keys.length;
    final perLine = <String>[];
    final keys = perTry.keys.toList()..sort();
    for (final v in keys) {
      final tries = perTry[v] ?? 0;
      final wins = perWin[v] ?? 0;
      final nm = v < _natSpecs.length ? _natSpecs[v].name : '#$v';
      perLine.add('$nm: ترافیک‌دار $wins از $tries');
      if (tries >= 3 && wins == 0) {
        _atAdd('SUBST-USELESS-$nm',
            'حالت «$nm» روی $tries تلاش با اتصال واقعی ترافیک تونل نداد؛ از پروژه حذف شود');
      }
    }
    final mins = DateTime.now().difference(t0).inMinutes;
    rows.insert(
        0,
        'حالت‌ها: کل ${allVars.length} • امتحان شد $tested • جواب داد $won • '
        'جواب نداد ${_atSubstFailed.length} • تست نشد ${_atSubstUntried.length}');
    rows.insert(
        1,
        'خلاصه: سرور $total • پایه ترافیک‌دار $baseOk • '
        'سرورهایی با جایگزین ترافیک‌دار $substServers • '
        'بدون هیچ‌کدام $brokenServers • $mins دقیقه');
    if (perLine.isNotEmpty) rows.insert(2, perLine.join(' • '));
    _itemResult[name] = rows.join('\n');
    autoTestProgress.value = 1;
  }

  Future<void> _atItemNatModes() async {
    _scenario = 3;
    final name = _atItemNames[2];
    natForce = true;
    nationalMode = true;
    userModeChoice = true;
    offlineOnly = false;
    await ultimateSave();
    final rows = <String>[];
    _atNatRows.clear();
    _atNatWorking = false;
    for (var lvl = 0; lvl <= 10; lvl++) {
      if (_abortRequested || _phase != _AtPhase.running) break;
      natFloor = lvl;
      natLevel = lvl;
      final s0 = natIpScanned, f0 = natIpFound, t0 = natIpTested, o0 = natIpOk;
      final connected = await _atConnectItem('$name • سطح $lvl',
          timeout: const Duration(minutes: 4));
      final ownOk = natIpOk - o0; // سالم‌هایی که همین سطح پیدا کرده
      final viaSaved = connected && ownOk == 0; // وصل شده ولی از سرور ذخیره‌شده، نه از این سطح
      // WORKOK: اتصال واقعی موفق است، حتی اگر از سرور ذخیره‌شده‌ی جستجوی قبلی باشد
      final status = connected && !viaSaved
          ? 'وصل شد ✅ (از همین سطح)'
          : viaSaved
              ? 'وصل شد ✅ (سرور ذخیره‌شده‌ی قبلی؛ جستجوی این سطح سالم پیدا نکرد)'
              : 'وصل نشد ❌';
      final reason = connected
          ? ''
          : (_atLastFail.isEmpty ? ' • علت: ثبت نشد' : ' • علت: $_atLastFail');
      final row = 'سطح $lvl: اسکن +${natIpScanned - s0} • باز +${natIpFound - f0}'
          ' • تست +${natIpTested - t0} • سالم +$ownOk • $status$reason';
      rows.add(row);
      _atNatRows.add(row);
      if (connected) _atNatWorking = true; // WORKOK
      await _atEnsureDisconnected();
    }
    natFloor = 0;
    _itemResult[name] = rows.isEmpty ? 'اجرا نشد' : rows.join('\n');
    // NATSTOP: توقف دستی وسط ماتریس خطای نت ملی نیست؛ فقط وقتی همه‌ی سطوح امتحان شده ثبت شود
    if (!_atNatWorking && !_abortRequested && _atNatRows.length >= 11) {
      _atAdd('NAT-NOCONNECT',
          'نت ملی: هیچ سطحی وصل نشد (${_atNatRows.length} سطح تست شد)');
    }
  }

  /// بخش ۶: اتصال آفلاین؛ فقط از پوشه‌ی منابع تازه، بدون دانلود لیست
  Future<void> _atItemOffline() async {
    _scenario = 6;
    final name = _atItemNames[3];
    if (!natHotReady()) {
      _itemResult[name] = '❌ پوشه‌ی منابع تازه آماده نیست؛ تست نشد';
      return;
    }
    natForce = false;
    offlineOnly = true;
    await ultimateSave();
    await _atConnectItem(name);
    offlineOnly = false;
    await ultimateSave();
    await _atEnsureDisconnected();
  }

  /// بخش ۷: اتصال آنلاین؛ از همه‌ی منابع
  Future<void> _atItemOnline() async {
    _scenario = 7;
    final name = _atItemNames[4];
    natForce = false;
    offlineOnly = false;
    await ultimateSave();
    await _atConnectItem(name);
  }

  /// سناریو ۲: طوفان قطع/وصل روی V2Ray (موتور اصلی)
  Future<void> _atScenarioReconnectStorm() async {
    if (!_atV2rayUsable()) return; // فقط V2Ray، و فقط اگر V2Ray در تست ۱ وصل شده
    _scenario = 2;
    autoTestText.value = 'سناریو ۲: قطع/وصل سریع';
    dbg('🧪 سناریو ۲ — قطع/وصل ×۳ روی V2Ray');
    await _atApplyEngine('v2ray');

    for (var i = 1; i <= 3; i++) {
      if (_abortRequested) return;
      autoTestText.value = 'سناریو ۲: چرخه $i/3';

      if (connected) {
        await disconnect();
        await _atWaitUntil(() => !connected && !busy,
            timeout: const Duration(seconds: 20), label: 'قطع چرخه $i');
      }

      await _atWait(const Duration(milliseconds: 600));
      await connect();
      await _atWaitUntil(() => connected && !busy,
          timeout: const Duration(minutes: 4), label: 'وصل چرخه $i');

      if (!connected) {
        _atAdd('RECONNECT-FAIL', 'چرخه $i نتوانست دوباره وصل شود');
      }
      await _atWait(const Duration(seconds: 8));
    }
  }

  /// سناریو ۳: قطع وسط اتصال
  Future<void> _atScenarioMidConnectAbort() async {
    if (!_atV2rayUsable()) return; // فقط V2Ray، و فقط اگر V2Ray در تست ۱ وصل شده
    _scenario = 3;
    autoTestText.value = 'سناریو ۳: قطع وسط اتصال';
    dbg('🧪 سناریو ۳ — abort وسط اتصال');
    await _atApplyEngine('v2ray');
    await _atEnsureDisconnected();

    final fut = connect().catchError((e) { logError(e); });
    await _atWait(const Duration(seconds: 2), note: 'صبر بعد از شروع اتصال');

    // ABORTCTX: snapshot what the app was doing at the moment of the stop
    dbg('🧪 توقف وسط اتصال (اطلاعات، نه خطا): status="$status" • آخرین رویداد: $lastState • lastWhy="$lastWhy"');
    abort = true;
    try {
      await disconnect();
    } catch (e, stk) { logError(e, stk); }
    await _atWaitUntil(() => !busy && !switching,
        timeout: const Duration(seconds: 100), label: 'آزاد شدن بعد از abort'); // TIMEOUTFIX: app waits up to 90s

    try {
      await fut.timeout(const Duration(seconds: 5));
    } catch (e, stk) { logError(e, stk); }

    if (busy || switching) {
      _atAdd('ABORT-STUCK',
          'بعد از abort، busy=$busy switching=$switching مانده');
    }
    if (connected) {
      _atAdd('ABORT-FLAG',
          'بعد از abort، connected هنوز true است');
    }

    abort = false;
    await _atWait(const Duration(seconds: 2));
    if (!connected) {
      await connect();
      await _atWaitUntil(() => connected && !busy,
          timeout: const Duration(minutes: 4), label: 'بازیابی بعد از abort');
    }
  }

  /// سناریو ۴: تعویض سرور
  Future<void> _atScenarioServerSwap() async {
    if (!_atV2rayUsable()) return; // فقط V2Ray، و فقط اگر V2Ray در تست ۱ وصل شده
    _scenario = 4;
    autoTestText.value = 'سناریو ۴: تعویض سرور';
    dbg('🧪 سناریو ۴ — تعویض سرور');
    await _atApplyEngine('v2ray');

    if (!connected) {
      await connect();
      await _atWaitUntil(() => connected && !busy,
          timeout: const Duration(minutes: 5), label: 'وصل برای تعویض');
    }
    if (!connected) {
      _atAdd('SWAP-SKIP', 'نتوانست برای سناریو تعویض وصل شود');
      return;
    }

    final before = current?.key;
    try {
      await _failover();
    } catch (e, jstk) { errJournalAdd(e, st: jstk);
      _atAdd('SWAP-EX', 'استثنا در _failover: $e');
    }

    await _atWaitUntil(() => !busy && !switching,
        timeout: const Duration(seconds: 60), label: 'پایان تعویض');
    await _atWait(const Duration(seconds: 12), note: 'پایداری بعد از تعویض');

    if (!connected) {
      _atAdd('SWAP-DROP', 'بعد از تعویض سرور، اتصال قطع ماند');
    } else if (before != null && current?.key == before) {
      dbg('🧪 تعویض: همان سرور قبلی ماند');
    } else {
      dbg('🧪 تعویض: $before → ${current?.key}');
    }
  }

  /// سناریو ۵: مانیتور طولانی
  Future<void> _atScenarioLongStable() async {
    if (!_atV2rayUsable()) return; // فقط V2Ray، و فقط اگر V2Ray در تست ۱ وصل شده
    _scenario = 5;
    autoTestText.value = 'سناریو ۵: مانیتور طولانی';
    dbg('🧪 سناریو ۵ — مانیتور پایدار');
    await _atApplyEngine('v2ray');

    if (!connected) {
      await connect();
      await _atWaitUntil(() => connected && !busy,
          timeout: const Duration(minutes: 5), label: 'وصل برای مانیتور');
    }

    final remain = _startedAt == null
        ? const Duration(minutes: 5)
        : _testDuration - DateTime.now().difference(_startedAt!);
    // تا پایان ۶۰ دقیقه روی اتصال می‌ماند (همه‌ی باقی‌مانده‌ی وقت)
    final watchFor = remain.isNegative ? Duration.zero : remain;

    if (watchFor.inSeconds < 10) return;

    final end = DateTime.now().add(watchFor);
    var lastPingCheck = DateTime.now();
    while (DateTime.now().isBefore(end)) {
      if (_abortRequested || _phase != _AtPhase.running) return;

      if (!connected && !busy) {
        _atAdd('STABLE-DROP', 'در مانیتور طولانی، اتصال بی‌دلیل قطع شد');
        await connect();
        await _atWaitUntil(() => connected && !busy,
            timeout: const Duration(minutes: 4), label: 'بازیابی مانیتور');
      }

      if (DateTime.now().difference(lastPingCheck) >
          const Duration(seconds: 40)) {
        lastPingCheck = DateTime.now();
        try {
          final sp = await measure(url: smallSpeedUrl);
          if (connected && (sp == null || sp <= 0)) {
            _atAdd('STABLE-NODATA', 'در مانیتور طولانی، داده از تونل نیامد');
          }
        } catch (e, stk) { logError(e, stk); }
      }

      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }
}


// REPORTSAVE: گزارش تست ۶۰ دقیقه‌ای را در پوشه‌ی Download/King-VPN ذخیره می‌کند
// (و یک نسخه‌ی ثابت به اسم last_auto_test_report.txt). مسیر ذخیره را برمی‌گرداند.
Future<String> atSaveReport(String report) async {
  try {
    final st = Permission.manageExternalStorage;
    if (!await st.isGranted) await st.request();
  } catch (_) {}
  final stamp = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .split('.')
      .first;
  final name = 'auto_test_report_$stamp.txt';
  // REPORTSAVE-FIX: اول پوشه‌ی خصوصی برنامه (همیشه قابل نوشتن)، بعد Download (اختیاری، بدون خطا)
  const privDir = '/data/data/com.kingvpn.king_vpn/files/reports';
  // V14: save to multiple public directories
  const pubDir1 = '/storage/emulated/0/King-VPN';
  const pubDir2 = '/storage/emulated/0/Documents/KingVPN';
  const pubDir3 = '/storage/emulated/0/Download/KingVPN';
  String saved = '';
  for (final d in const [privDir, pubDir1, pubDir2, pubDir3]) {
    try {
      final dir = Directory(d);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final f = File('${dir.path}/$name');
      await f.writeAsString(report, flush: true);
      await File('${dir.path}/last_auto_test_report.txt')
          .writeAsString(report, flush: true);
      if (saved.isEmpty) saved = f.path;
    } catch (_) {}
  }
  // XRAYCOPY: کپی کامل خطای هسته (xray_err.log) کنار گزارش، بدون نیاز به کامپیوتر
  try {
    final src = File(kXrayErrPath);
    if (src.existsSync()) {
      // فیکس ۳: ماسک UUID قبل از ذخیره در Download
      final txt = _maskUuidsForExport(await src.readAsString());
      // XRAYCOPY-FIX: pubDir فقط داخل حلقه‌ی بالا تعریف شده بود؛ همان مسیرها را این‌جا امتحان می‌کنیم
      for (final d in const [privDir, pubDir1, pubDir2, pubDir3]) {
        try {
          final dir = Directory(d);
          if (!dir.existsSync()) dir.createSync(recursive: true);
          await File('${dir.path}/xray_err_last.log').writeAsString(txt, flush: true);
        } catch (_) {}
      }
    }
  } catch (_) {}
  return saved;
}
