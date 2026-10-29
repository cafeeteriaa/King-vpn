part of 'main.dart';

// =============================================================================
// AUTO TEST 60min — تست خودکار شش بخش واقعی + سناریوهای پایداری
// بخش‌ها به ترتیب: اینترنت جهانی | نت ملی (IP اول، بعد تست کانفیگ، همه‌ی سطوح ماتریس)
// | خلبان | خلبان نت ملی | پوشه‌ی منابع تازه | اتصال آفلاین | اتصال آنلاین
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
  static const _testDuration = Duration(minutes: 60); // NATMODES: ۶۰ دقیقه
  static const _sampleEvery = Duration(seconds: 3);
  // آستانه‌ها باید بیشتر از مهلت واقعی اتصال باشند (وگرنه اتصال عادی گزارش گیر می‌دهد)
  static const _busyStuckLimit = Duration(seconds: 120);
  static const _switchingStuckLimit = Duration(seconds: 40);
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
  static DateTime? _switchingSince;
  static DateTime? _connectingSince;
  static final List<_AtFinding> _findings = [];
  static final List<_AtStateSample> _samples = [];
  static int _scenario = 0;
  // FLAG-MISMATCH is reported only when it lasts 3 samples in a row (about 9 s);
  // a state that changes during a normal disconnect is not a bug
  static int _atMismatchTicks = 0;
  static bool _abortRequested = false;
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
  static List<String> get _atActiveNames =>
      [_atItemNames[2], _atItemNames[4]];
  static const List<String> _atItemNames = [
    'اینترنت جهانی (عادی)',
    'پوشه‌ی منابع تازه (ساخت)',
    'نت ملی: IP اول، بعد تست کانفیگ، همه‌ی سطوح',
    'خلبان (بدون نت ملی)',
    'خلبان نت ملی',
    'اتصال آفلاین (فقط پوشه)',
    'اتصال آنلاین (همه‌ی منابع)',
  ];
  // نتیجه‌ی هر بخش، در گزارش پایان نشان داده می‌شود
  static final Map<String, String> _itemResult = {};
  // بیشترین سطح ماتریس نت ملی که در بخش‌های ملی دیده شد
  static int _atMaxNatLevel = 0;
  // NATMODES: نتیجه‌ی هر سطح و اینکه آیا حداقل یک سطح وصل شد
  static final List<String> _atNatRows = [];
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
            title: const Text('تست نت ملی ۶۰ دقیقه‌ای'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('فقط نت ملی تست می‌شود:'),
                  const SizedBox(height: 4),
                  for (final item in [_atItemNames[2], _atItemNames[4]])
                    Text('• $item', style: const TextStyle(fontSize: 13)),
                  const Text(
                    '• هر سطح ماتریس نت ملی (۰ تا ۱۰) جدا تست می‌شود\n'
                    '• برای هر سطح: IP اسکن‌شده، IP باز، تست‌شده، سالم و وصل یا نشدن ثبت می‌شود\n'
                    '• در پایان علت اصلی و راه‌حل گفته می‌شود',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  const SizedBox(height: 6),
                  const Text(
                    'در این ۶۰ دقیقه اپ را نبند و صفحه را قفل نکن.\n'
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
    _abortRequested = false;
    _findings.clear();
    _atNoTraffic = false;
    _samples.clear();
    _atCfgNotes.clear();
    _engineResult.clear();
    _itemResult.clear();
    _atMaxNatLevel = 0;
    _atFailStreak = 0;
    _atVerdict = '';
    _scenario = 0;
    _busySince = null;
    _switchingSince = null;
    _connectingSince = null;
    _currentEngine = 'v2ray';
    _startedAt = DateTime.now();
    _atDomesticProbe(); // DOMESTIC: which sites open on the national network now
    _dbgStartIdx = dbgLines.length;
    autoTestRunning.value = true;
    autoTestProgress.value = 0;
    autoTestText.value = 'تست خودکار شروع شد (${_atSelected.length} VPN)…';
    dbg('🧪 AUTOTEST نت ملی شروع شد (۶۰ دقیقه • ${_atActiveNames.length} بخش)');
    _dbgProb('🧪 تست نت ملی ۶۰ دقیقه‌ای — همه‌ی سطح‌های ماتریس + خلبان نت ملی');

    _sampleT?.cancel();
    _sampleT = Timer.periodic(_sampleEvery, (_) => _atSample());

    _endT?.cancel();
    _endT = Timer(_testDuration, () {
      if (_phase == _AtPhase.running) {
        dbg('🧪 AUTOTEST زمان ۶۰ دقیقه تمام شد');
        _atFinish(reason: 'زمان تمام شد');
      }
    });

    try {
      // پوشه‌ی منابع تازه از همین اول در پس‌زمینه ساخته می‌شود تا بخش آفلاین آماده باشد
      if (!natHotReady()) unawaited(natHotEnsure(force: true));

      // بخش‌های اصلی: هر کدام فقط اگر وقت باقی‌مانده‌ی کافی داشته باشد اجرا می‌شود
      // NATONLY: فقط نت ملی (جستجو) و خلبان نت ملی؛ بقیه‌ی بخش‌ها حذف شدند
      // NATMODES: هر سطح ماتریس نت ملی (۰ تا ۱۰) جداگانه تست می‌شود، سپس خلبان نت ملی
      final steps = <(String, Duration, Future<void> Function())>[
        (_atItemNames[2], const Duration(minutes: 50), _atItemNatModes),
        (_atItemNames[4], const Duration(minutes: 8),
            () => _atItemPilot(national: true)),
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
    buf.writeln('===== گزارش تست خودکار ۶۰ دقیقه‌ای =====');
    buf.writeln('مدت: ${min}m ${sec}s • دلیل پایان: $reason');
    buf.writeln('نمونه وضعیت: ${_samples.length}');
    buf.writeln('یافته‌ها: ${_findings.length}');
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

    if (_findings.isEmpty) {
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
    if (_samples.length > 500) _samples.removeAt(0);

    if (_startedAt != null) {
      final p = now.difference(_startedAt!).inMilliseconds /
          _testDuration.inMilliseconds;
      autoTestProgress.value = p.clamp(0.0, 1.0);
    }

    if (busy) {
      _busySince ??= now;
      if (now.difference(_busySince!) > _busyLimitNow()) {
        _atAdd('BUSY-STUCK',
            'busy بیش از ${_busyStuckLimit.inSeconds}s مانده • موتور=$_currentEngine • $status');
        _busySince = now;
      }
    } else {
      _busySince = null;
    }

    if (switching && !busy) {
      _switchingSince ??= now;
      if (now.difference(_switchingSince!) > _switchingStuckLimit) {
        _atAdd('SWITCH-STUCK',
            'switching بیش از ${_switchingStuckLimit.inSeconds}s • موتور=$_currentEngine');
        _switchingSince = now;
      }
    } else {
      _switchingSince = null;
    }

    if (busy && !connected) {
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
      case 'PILOT-NOCOUNT':
        return [
          'lib/iran_ai_extras.dart → localPilotTick و lib/nat_ultra.dart → natLiveBox',
          'کادر خلبان در نت ملی شمارنده‌ی IP را نشان نداد',
          'کادر خلبان هنگام جستجو باید با natLiveBox زنده شود',
        ];
      case 'HOT-NOTREADY':
        return [
          'lib/nat_ultra.dart → natHotEnsure',
          'پوشه‌ی منابع تازه بعد از ۱۰ دقیقه ساخته نشد',
          'دسترسی به منابع را بررسی کن؛ بدون پوشه، اتصال آفلاین ممکن نیست',
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
        'اگر وصل نشدی، مشکل از خلبان است؛ بخش «خلبان نت ملی» را ببین.';
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
      final r = await Process.run('logcat', ['-d', '-t', '800', '-v', 'brief']);
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
    final ipDiag = _atIpNoTestDiag(funBefore, foundBefore, testedBefore);
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
    // NATCHOICE: بدون این، تشخیص خودکار شبکه (وقتی اینترنت جهانی هست) نت ملی را خاموش می‌کند
    // و جستجوی ملی اصلاً اجرا نمی‌شود (NAT-LEVEL 0 / NAT-NOIP). همان انتخاب دکمه‌ی نت ملی است.
    userModeChoice = true;
    offlineOnly = false;
    await ultimateSave();

    final s0 = natIpScanned;
    final f0 = natIpFound;
    final t0 = natIpTested;
    final o0 = natIpOk;
    var ipSeen = false;
    var testedBeforeIp = false;
    var done = false;
    final fut = _atConnectItem(name, timeout: const Duration(minutes: 10))
        .whenComplete(() {
      done = true;
    });
    final t = DateTime.now();
    while (!done &&
        _phase == _AtPhase.running &&
        !_abortRequested &&
        DateTime.now().difference(t) < const Duration(minutes: 11)) {
      if (natIpScanned > s0) ipSeen = true;
      if (!ipSeen && natIpTested > t0) testedBeforeIp = true;
      if (natLevel > _atMaxNatLevel) _atMaxNatLevel = natLevel;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    await fut;

    if (!ipSeen) {
      _atAdd('NAT-NOIP',
          'نت ملی: شمارنده‌ی اسکن IP صفر ماند؛ یا IP در صف نبود یا TCP اجرا نشد');
    }
    if (testedBeforeIp) {
      _atAdd('NAT-ORDER', 'نت ملی: سرور قبل از تست IP به تست کانفیگ رسید');
    }
    if (_atMaxNatLevel < 4) {
      _atAdd('NAT-LEVEL',
          'نت ملی: بیشترین سطح ماتریس $_atMaxNatLevel بود؛ انتظار ۴ یا بیشتر');
    }
    _itemResult[name] =
        '${_itemResult[name] ?? ''} • IP اسکن +${natIpScanned - s0}'
        ' • باز +${natIpFound - f0} • تست هسته +${natIpTested - t0}'
        ' • سالم +${natIpOk - o0} • بیشترین سطح $_atMaxNatLevel';
    await _atEnsureDisconnected();
  }

  /// NATMODES: هر سطح ماتریس نت ملی جدا با سقف ۴ دقیقه؛ نتیجه‌ی هر سطح ثبت می‌شود
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
    if (!_atNatWorking) {
      _atAdd('NAT-NOCONNECT',
          'نت ملی: هیچ سطحی وصل نشد (${_atNatRows.length} سطح تست شد)');
    }
  }

  /// بخش ۴ و ۵: خلبان محلی؛ بدون نت ملی و با نت ملی (دکمه‌ی خلبان نت ملی)
  Future<void> _atItemPilot({required bool national}) async {
    _scenario = national ? 5 : 4;
    final name = _atItemNames[national ? 4 : 3];
    errTag = name;
    await _atEnsureDisconnected();
    if (localPilotOn) stopLocalPilot();
    natForce = national;
    if (!national) nationalMode = false;

    final tick0 = _localTickN;
    autoTestText.value = 'بخش «$name»: روشن کردن خلبان…';
    dbg('🧪 بخش «$name» — روشن کردن خلبان');
    // PILOTCHOICE: تست باید همان انتخاب کاربر را داشته باشد (بدون نت ملی = جهانی)،
    // وگرنه خلبان خودش به نت ملی می‌رود و سناریو درست سنجیده نمی‌شود
    userModeChoice = national;
    startLocalPilot(national: national);
    // PILOTWAIT: اتصال نت ملی با ماتریس کامل چند دقیقه طول می‌کشد؛ مهلت متناسب با آن
    await _atWaitUntil(() => connected && !busy,
        timeout: Duration(minutes: national ? 15 : 8), label: name);

    if (!connected) {
      _itemResult[name] = '❌ خلبان وصل نکرد • status="$status" • lastFail="$lastFail"';
      _atAdd('ITEM-FAIL', '$name وصل نشد • status="$status" • lastFail="$lastFail"');
      stopLocalPilot();
      await _atEnsureDisconnected();
      return;
    }

    // خلبان باید حداقل یک تیک بزند؛ کادر خلبان از همان تیک پر می‌شود
    // PILOTFIX: تیک خلبان وقتی busy باشد برنمی‌گردد؛ اول صبر کن آزاد شود، بعد تیک را اجبار کن
    final bEnd = DateTime.now().add(const Duration(seconds: 30));
    while (busy && DateTime.now().isBefore(bEnd) && !_abortRequested) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (!_abortRequested && _localTickN <= tick0) {
      unawaited(localPilotTick(force: true));
    }
    final tEnd = DateTime.now().add(const Duration(seconds: 240));
    while (_localTickN <= tick0 &&
        DateTime.now().isBefore(tEnd) &&
        !_abortRequested) {
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    userModeChoice = null; // پایان بخش: خلبان دوباره خودکار (بدون قفل تست)
    if (_localTickN <= tick0) {
      _atAdd('PILOT-NOTICK', '$name وصل شد ولی خلبان تیکی نزد');
    }

    if (nationalMode && !localPilotText.value.contains('IP اسکن')) {
      _atAdd('PILOT-NOCOUNT',
          '$name در نت ملی بود ولی کادر خلبان شمارنده‌ی IP را نشان نداد');
    }
    if (natLevel > _atMaxNatLevel) _atMaxNatLevel = natLevel;

    final detail = national
        ? ' • IP اسکن کل $natIpScanned / باز $natIpFound / تست هسته $natIpTested / سالم $natIpOk'
        : '';
    final mode = nationalMode ? 'ملی' : 'جهانی';
    _itemResult[name] =
        '✅ خلبان وصل • حالت: $mode • تیک‌ها: ${_localTickN - tick0}$detail';

    await _atWait(const Duration(seconds: 15), note: 'پایداری $name');
    stopLocalPilot();
    await _atEnsureDisconnected();
  }

  /// بخش ۶: اتصال آفلاین؛ فقط از پوشه‌ی منابع تازه، بدون دانلود لیست
  Future<void> _atItemOffline() async {
    _scenario = 6;
    final name = _atItemNames[5];
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
    final name = _atItemNames[6];
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

    abort = true;
    try {
      await disconnect();
    } catch (e, stk) { logError(e, stk); }
    await _atWaitUntil(() => !busy && !switching,
        timeout: const Duration(seconds: 30), label: 'آزاد شدن بعد از abort');

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
  const pubDir = '/storage/emulated/0/Download/King-VPN';
  String saved = '';
  for (final d in const [privDir, pubDir]) {
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
  return saved;
}
