part of 'main.dart';

// =============================================================================
// AUTO TEST 20min — تست خودکار سناریوهای واقعی روی گوشی
// هدف: پیدا کردن race condition، گیر کردن busy/switching، ناسازگاری وضعیت
// و قطع‌های پنهان بدون دخالت دستی کاربر.
// =============================================================================

enum _AtPhase {
  idle,
  running,
  done,
}

class _AtFinding {
  final String code; // e.g. BUSY-STUCK, FLAG-MISMATCH
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
  _AtStateSample({
    required this.at,
    required this.connected,
    required this.busy,
    required this.switching,
    required this.watchBusy,
    required this.status,
    required this.lastWhy,
    required this.lastState,
  });
}

final ValueNotifier<String> autoTestText =
    ValueNotifier<String>('تست خودکار آماده است.');
final ValueNotifier<bool> autoTestRunning = ValueNotifier<bool>(false);
final ValueNotifier<double> autoTestProgress = ValueNotifier<double>(0);

extension AutoTestEngine on _HomePageState {
  static const _testDuration = Duration(minutes: 20);
  static const _sampleEvery = Duration(seconds: 3);
  static const _busyStuckLimit = Duration(seconds: 45);
  static const _switchingStuckLimit = Duration(seconds: 25);
  static const _connectHangLimit = Duration(seconds: 90);

  // runtime state (instance-level via private maps would be better, but
  // keep it simple and local to the running test)
  static _AtPhase _phase = _AtPhase.idle;
  static Timer? _sampleT;
  static Timer? _endT;
  static DateTime? _startedAt;
  static DateTime? _busySince;
  static DateTime? _switchingSince;
  static DateTime? _connectingSince;
  static final List<_AtFinding> _findings = [];
  static final List<_AtStateSample> _samples = [];
  static int _scenario = 0;
  static bool _abortRequested = false;

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

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تست خودکار ۲۰ دقیقه‌ای'),
          content: const Text(
            'اپ خودش سناریوهای واقعی (وصل/قطع، تعویض سرور، قطع وسط اتصال، '
            'مانیتور طولانی) را اجرا می‌کند و هر ناسازگاری وضعیت را '
            'با کد دقیق در گزارش ثبت می‌کند.\n\n'
            'در این ۲۰ دقیقه اپ را نبند و صفحه را قفل نکن.\n'
            'می‌توانی وسط کار «توقف تست» را بزنی.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('انصراف')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('شروع تست')),
          ],
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
    _samples.clear();
    _scenario = 0;
    _busySince = null;
    _switchingSince = null;
    _connectingSince = null;
    _startedAt = DateTime.now();
    autoTestRunning.value = true;
    autoTestProgress.value = 0;
    autoTestText.value = 'تست خودکار شروع شد…';
    dbg('🧪 AUTOTEST شروع شد (۲۰ دقیقه)');
    _dbgProb('🧪 تست خودکار ۲۰ دقیقه‌ای شروع شد');

    // continuous sampler
    _sampleT?.cancel();
    _sampleT = Timer.periodic(_sampleEvery, (_) => _atSample());

    // hard end timer
    _endT?.cancel();
    _endT = Timer(_testDuration, () {
      if (_phase == _AtPhase.running) {
        dbg('🧪 AUTOTEST زمان ۲۰ دقیقه تمام شد');
        _atFinish(reason: 'زمان تمام شد');
      }
    });

    try {
      await _atScenarioConnectBasic(); // 1
      if (_abortRequested) return _atFinish(reason: 'توقف دستی');
      await _atScenarioReconnectStorm(); // 2
      if (_abortRequested) return _atFinish(reason: 'توقف دستی');
      await _atScenarioMidConnectAbort(); // 3
      if (_abortRequested) return _atFinish(reason: 'توقف دستی');
      await _atScenarioServerSwap(); // 4
      if (_abortRequested) return _atFinish(reason: 'توقف دستی');
      await _atScenarioLongStable(); // 5
      if (_abortRequested) return _atFinish(reason: 'توقف دستی');
    } catch (e) {
      _atAdd('CRASH', 'استثنای تست: $e');
      logError(e);
    } finally {
      if (_phase == _AtPhase.running) {
        await _atFinish(reason: 'سناریوها تمام شد');
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

    // one last sample
    _atSample();

    final elapsed = _startedAt == null
        ? Duration.zero
        : DateTime.now().difference(_startedAt!);
    final min = elapsed.inMinutes;
    final sec = elapsed.inSeconds % 60;

    final buf = StringBuffer();
    buf.writeln('===== گزارش تست خودکار =====');
    buf.writeln('مدت: ${min}m ${sec}s • دلیل پایان: $reason');
    buf.writeln('نمونه وضعیت: ${_samples.length}');
    buf.writeln('یافته‌ها: ${_findings.length}');
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
          'تست تمام شد • ${_findings.length} مشکل پیدا شد — گزارش خطاها را ببین';
    }

    final report = buf.toString();
    dbg(report);
    errorLog.value = '${errorLog.value}\n$report'.trim();

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
                child: SelectableText(report,
                    style: const TextStyle(fontSize: 13, height: 1.4)),
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
    );
    _samples.add(s);
    if (_samples.length > 500) _samples.removeAt(0);

    // progress
    if (_startedAt != null) {
      final p = now.difference(_startedAt!).inMilliseconds /
          _testDuration.inMilliseconds;
      autoTestProgress.value = p.clamp(0.0, 1.0);
    }

    // --- busy stuck ---
    if (busy) {
      _busySince ??= now;
      if (now.difference(_busySince!) > _busyStuckLimit) {
        _atAdd('BUSY-STUCK',
            'busy بیش از ${_busyStuckLimit.inSeconds}s روشن مانده • status="$status"');
      }
    } else {
      _busySince = null;
    }

    // --- switching stuck ---
    if (switching) {
      _switchingSince ??= now;
      if (now.difference(_switchingSince!) > _switchingStuckLimit) {
        _atAdd('SWITCH-STUCK',
            'switching بیش از ${_switchingStuckLimit.inSeconds}s روشن مانده • status="$status"');
      }
    } else {
      _switchingSince = null;
    }

    // --- connect hang (status looks like connecting but never finishes) ---
    final looksConnecting = !connected &&
        (status.contains('اتصال') ||
            status.contains('جستجو') ||
            status.contains('در حال') ||
            status.contains('تست'));
    if (looksConnecting && busy) {
      _connectingSince ??= now;
      if (now.difference(_connectingSince!) > _connectHangLimit) {
        _atAdd('CONNECT-HANG',
            'بیش از ${_connectHangLimit.inSeconds}s روی وضعیت اتصال گیر کرده • "$status"');
      }
    } else {
      _connectingSince = null;
    }

    // --- flag mismatch patterns (classic race symptoms) ---
    if (connected && !busy && !switching) {
      // healthy connected state — nothing to flag here
    } else if (!connected && lastState.toUpperCase().contains('CONNECTED')) {
      _atAdd('FLAG-MISMATCH',
          'connected=false ولی lastState هنوز CONNECTED است • status="$status"');
    }

    // orphan-ish: connected=true but watch is gone while we expect it
    if (connected &&
        !busy &&
        !switching &&
        watch?.isActive != true &&
        !_abortRequested) {
      // the real self-heal already restarts watch; we just record frequency
      _atAdd('WATCH-MISSING',
          'connected=true ولی واچ‌داگ خاموش است (ممکن است race باشد)');
    }

    autoTestText.value =
        'تست #$_scenario • ${_findings.length} یافته • ${status.length > 40 ? status.substring(0, 40) : status}';
  }

  void _atAdd(String code, String msg) {
    // de-dupe by code+msg skeleton
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
  // Scenarios
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
      _atAdd('TIMEOUT', 'صبر برای «$label» بیش از ${timeout.inSeconds}s طول کشید');
    }
  }

  /// سناریو ۱: اتصال پایه + پایداری کوتاه
  Future<void> _atScenarioConnectBasic() async {
    _scenario = 1;
    autoTestText.value = 'سناریو ۱: اتصال پایه';
    dbg('🧪 سناریو ۱ — اتصال پایه');

    if (connected) {
      await disconnect();
      await _atWaitUntil(() => !connected && !busy,
          timeout: const Duration(seconds: 25), label: 'قطع کامل');
    }

    await connect();
    await _atWaitUntil(() => connected && !busy,
        timeout: const Duration(seconds: 120), label: 'وصل شدن');

    if (connected) {
      await _atWait(const Duration(seconds: 25), note: 'پایداری ۲۵ ثانیه بعد از وصل');
      // quick tunnel liveness hint via existing measure if possible
      try {
        final sp = await measure(url: smallSpeedUrl);
        if (sp == null || sp <= 0) {
          _atAdd('NO-DATA', 'بعد از وصل، تست سرعت کوچک داده برنگرداند');
        } else {
          dbg('🧪 سرعت کوچک ≈ ${(sp * 1024).toStringAsFixed(1)} KB/s');
        }
      } catch (e) {
        _atAdd('MEASURE-FAIL', 'خطا در measure بعد از وصل: $e');
      }
    } else {
      _atAdd('CONNECT-FAIL', 'سناریو ۱: نتوانست وصل شود • status="$status"');
    }
  }

  /// سناریو ۲: طوفان قطع/وصل (۳ بار)
  Future<void> _atScenarioReconnectStorm() async {
    _scenario = 2;
    autoTestText.value = 'سناریو ۲: قطع/وصل سریع';
    dbg('🧪 سناریو ۲ — قطع/وصل سریع ×۳');

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
          timeout: const Duration(seconds: 90), label: 'وصل چرخه $i');

      if (!connected) {
        _atAdd('RECONNECT-FAIL', 'چرخه $i نتوانست دوباره وصل شود');
      }
      await _atWait(const Duration(seconds: 8));
    }
  }

  /// سناریو ۳: قطع وسط اتصال (race کلاسیک)
  Future<void> _atScenarioMidConnectAbort() async {
    _scenario = 3;
    autoTestText.value = 'سناریو ۳: قطع وسط اتصال';
    dbg('🧪 سناریو ۳ — abort وسط اتصال');

    if (connected) {
      await disconnect();
      await _atWaitUntil(() => !connected && !busy,
          timeout: const Duration(seconds: 20), label: 'قطع قبل از mid-abort');
    }

    // start connect without awaiting full completion
    final fut = connect();
    // wait a bit so busy/switching becomes true
    await _atWait(const Duration(seconds: 2), note: 'صبر کوتاه بعد از شروع اتصال');

    // force abort
    abort = true;
    try {
      await disconnect();
    } catch (_) {}
    await _atWaitUntil(() => !busy && !switching,
        timeout: const Duration(seconds: 30), label: 'آزاد شدن بعد از abort');

    // give the original future a chance to settle
    try {
      await fut.timeout(const Duration(seconds: 5));
    } catch (_) {}

    if (busy || switching) {
      _atAdd('ABORT-STUCK',
          'بعد از abort وسط اتصال، busy=$busy switching=$switching مانده');
    }
    if (connected) {
      _atAdd('ABORT-FLAG',
          'بعد از abort، connected هنوز true است (احتمال race در onStatusChanged)');
    }

    // recover cleanly
    abort = false;
    await _atWait(const Duration(seconds: 2));
    if (!connected) {
      await connect();
      await _atWaitUntil(() => connected && !busy,
          timeout: const Duration(seconds: 90), label: 'بازیابی بعد از abort');
    }
  }

  /// سناریو ۴: تعویض سرور موقع وصل بودن
  Future<void> _atScenarioServerSwap() async {
    _scenario = 4;
    autoTestText.value = 'سناریو ۴: تعویض سرور';
    dbg('🧪 سناریو ۴ — تعویض سرور در حالت وصل');

    if (!connected) {
      await connect();
      await _atWaitUntil(() => connected && !busy,
          timeout: const Duration(seconds: 100), label: 'وصل برای تعویض');
    }
    if (!connected) {
      _atAdd('SWAP-SKIP', 'نتوانست برای سناریو تعویض وصل شود');
      return;
    }

    final before = current?.key;
    // trigger failover / swap path that already exists
    try {
      await _failover();
    } catch (e) {
      _atAdd('SWAP-EX', 'استثنا در _failover: $e');
    }

    await _atWaitUntil(() => !busy && !switching,
        timeout: const Duration(seconds: 60), label: 'پایان تعویض');

    await _atWait(const Duration(seconds: 12), note: 'پایداری بعد از تعویض');

    if (!connected) {
      _atAdd('SWAP-DROP', 'بعد از تعویض سرور، اتصال قطع ماند');
    } else if (before != null && current?.key == before) {
      // not always a bug — may have only one good server
      dbg('🧪 تعویض: همان سرور قبلی ماند (احتمالاً فقط یک سرور سالم)');
    } else {
      dbg('🧪 تعویض سرور انجام شد: $before → ${current?.key}');
    }
  }

  /// سناریو ۵: مانیتور طولانی پایدار (باقی‌مانده زمان)
  Future<void> _atScenarioLongStable() async {
    _scenario = 5;
    autoTestText.value = 'سناریو ۵: مانیتور طولانی';
    dbg('🧪 سناریو ۵ — مانیتور پایدار');

    if (!connected) {
      await connect();
      await _atWaitUntil(() => connected && !busy,
          timeout: const Duration(seconds: 100), label: 'وصل برای مانیتور');
    }

    // stay connected and just sample until near the end or ~6 more minutes
    final remain = _startedAt == null
        ? const Duration(minutes: 6)
        : _testDuration - DateTime.now().difference(_startedAt!);
    final watchFor = remain > const Duration(minutes: 6)
        ? const Duration(minutes: 6)
        : (remain.isNegative ? Duration.zero : remain);

    if (watchFor.inSeconds < 10) return;

    final end = DateTime.now().add(watchFor);
    var lastPingCheck = DateTime.now();
    while (DateTime.now().isBefore(end)) {
      if (_abortRequested || _phase != _AtPhase.running) return;

      if (!connected && !busy) {
        _atAdd('STABLE-DROP', 'در فاز مانیتور طولانی، اتصال بی‌دلیل قطع شد');
        // try recover once
        await connect();
        await _atWaitUntil(() => connected && !busy,
            timeout: const Duration(seconds: 80), label: 'بازیابی مانیتور');
      }

      // occasional speed sample every ~40s
      if (DateTime.now().difference(lastPingCheck) > const Duration(seconds: 40)) {
        lastPingCheck = DateTime.now();
        try {
          final sp = await measure(url: smallSpeedUrl);
          if (connected && (sp == null || sp <= 0)) {
            _atAdd('STABLE-NODATA', 'در مانیتور طولانی، داده از تونل نیامد');
          }
        } catch (_) {}
      }

      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }
}
