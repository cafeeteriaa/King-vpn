part of 'main.dart';

// =============================================================================
// AUTO TEST 20min — تست خودکار هر ۶ نوع VPN + سناریوهای واقعی
// هدف: پیدا کردن race، گیر کردن busy/switching، شکست اتصال هر موتور،
// و قطع‌های پنهان بدون دخالت دستی.
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
  static const _testDuration = Duration(minutes: 20);
  static const _sampleEvery = Duration(seconds: 3);
  // آستانه‌ها باید بیشتر از مهلت واقعی اتصال باشند (وگرنه اتصال عادی گزارش گیر می‌دهد)
  static const _busyStuckLimit = Duration(seconds: 120);
  static const _switchingStuckLimit = Duration(seconds: 40);
  static const _connectHangLimit = Duration(seconds: 110);
  // قابلیت‌های هسته‌ای که کانفیگ‌های ناموفق لازم داشتند
  static final List<String> _atCfgNotes = [];

  /// هر ۶ نوع VPN که در دیالوگ اتصال هستند
  static const List<(String id, String label)> _engines = [
    ('v2ray', 'V2Ray'),
    ('ovpn', 'OpenVPN'),
    ('wg', 'WireGuard'),
    ('am', 'AM Tunnel'),
    ('npv', 'NPV Tunnel'),
    ('injector', 'HTTP Injector'),
  ];

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
  static String _currentEngine = 'v2ray';
  // موتورهایی که کاربر برای این تست انتخاب کرده (پیش‌فرض: همه)
  static Set<String> _atSelected = {for (final e in _engines) e.$1};
  static final Map<String, String> _engineResult = {}; // ok / fail / skip

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
            title: const Text('تست خودکار ۲۰ دقیقه‌ای'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('موتورهایی که می‌خواهی تست شوند:'),
                  const SizedBox(height: 4),
                  for (final e in _engines)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(e.$2),
                      value: sel.contains(e.$1),
                      onChanged: (v) => setD(() {
                        if (v == true) {
                          sel.add(e.$1);
                        } else {
                          sel.remove(e.$1);
                        }
                      }),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'سناریوهای ۲ تا ۵ فقط روی V2Ray اجرا می‌شوند؛ '
                    'اگر V2Ray انتخاب نشود، اجرا نمی‌شوند.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'در این ۲۰ دقیقه اپ را نبند و صفحه را قفل نکن.\n'
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
    _samples.clear();
    _atCfgNotes.clear();
    _engineResult.clear();
    _scenario = 0;
    _busySince = null;
    _switchingSince = null;
    _connectingSince = null;
    _currentEngine = 'v2ray';
    _startedAt = DateTime.now();
    autoTestRunning.value = true;
    autoTestProgress.value = 0;
    autoTestText.value = 'تست خودکار شروع شد (${_atSelected.length} VPN)…';
    dbg('🧪 AUTOTEST شروع شد (۲۰ دقیقه • ${_atSelected.length} VPN)');
    _dbgProb('🧪 تست خودکار ۲۰ دقیقه‌ای — ۶ موتور VPN');

    _sampleT?.cancel();
    _sampleT = Timer.periodic(_sampleEvery, (_) => _atSample());

    _endT?.cancel();
    _endT = Timer(_testDuration, () {
      if (_phase == _AtPhase.running) {
        dbg('🧪 AUTOTEST زمان ۲۰ دقیقه تمام شد');
        _atFinish(reason: 'زمان تمام شد');
      }
    });

    try {
      await _atScenarioAllEngines(); // 1 — هر ۶ VPN
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

    _atSample();

    final elapsed = _startedAt == null
        ? Duration.zero
        : DateTime.now().difference(_startedAt!);
    final min = elapsed.inMinutes;
    final sec = elapsed.inSeconds % 60;

    final buf = StringBuffer();
    buf.writeln('===== گزارش تست خودکار (۶ VPN) =====');
    buf.writeln('مدت: ${min}m ${sec}s • دلیل پایان: $reason');
    buf.writeln('نمونه وضعیت: ${_samples.length}');
    buf.writeln('یافته‌ها: ${_findings.length}');
    buf.writeln('');
    buf.writeln('--- نتیجه هر موتور ---');
    for (final e in _engines) {
      final r = _engineResult[e.$1] ?? 'تست نشد';
      buf.writeln('• ${e.$2}: $r');
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

    buf.write(_atDiagnosis());

    // privacy: keep only the first three octets of IPv4 addresses in the copied report
    final report = buf.toString().replaceAllMapped(
        RegExp(r'\b(\d{1,3}\.\d{1,3}\.\d{1,3})\.\d{1,3}\b'),
        (m) => '${m.group(1)}.x');
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
      if (now.difference(_busySince!) > _busyStuckLimit) {
        _atAdd('BUSY-STUCK',
            'busy بیش از ${_busyStuckLimit.inSeconds}s مانده • موتور=$_currentEngine • $status');
        _busySince = now;
      }
    } else {
      _busySince = null;
    }

    if (switching) {
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
      if (now.difference(_connectingSince!) > _connectHangLimit) {
        _atAdd('CONNECT-HANG',
            'اتصال بیش از ${_connectHangLimit.inSeconds}s طول کشید • موتور=$_currentEngine');
        _connectingSince = now;
      }
    } else {
      _connectingSince = null;
    }

    if (connected && !wantVpn && !busy) {
      _atAdd('FLAG-MISMATCH',
          'connected=true ولی wantVpn=false • موتور=$_currentEngine');
    }
    if (connected && !watchBusy && !busy && !switching) {
      // informational only when watchdog should be running — not always a bug
    }

    autoTestText.value =
        'تست #$_scenario • $_currentEngine • ${_findings.length} یافته';
  }

  void _atAdd(String code, String msg) {
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
          'صبر برای «$label» بیش از ${timeout.inSeconds}s • موتور=$_currentEngine');
    }
  }

  /// اعمال موتور بدون دیالوگ UI (مسیر تست)
  Future<void> _atApplyEngine(String id) async {
    _currentEngine = id;
    applyPilotEngine(id);
    // injector/am/npv در UI صفحه باز می‌کنند؛ در تست مستقیم connect می‌کنیم
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  Future<void> _atEnsureDisconnected() async {
    if (connected || busy || wantVpn) {
      abort = true;
      try {
        await disconnect();
      } catch (e) { logError(e); }
      await _atWaitUntil(() => !connected && !busy && !switching,
          timeout: const Duration(seconds: 25), label: 'قطع کامل');
      abort = false;
    }
  }

  /// وصل با یک موتور مشخص + تست سرعت کوتاه
  Future<bool> _atConnectEngine(String id, String label) async {
    await _atApplyEngine(id);
    await _atEnsureDisconnected();
    if (_abortRequested) return false;

    autoTestText.value = 'اتصال با $label…';
    dbg('🧪 اتصال موتور: $label ($id)');
    await connect();
    // اپ قبل از وصل نهایی جستجو و تست سرعت سرورها را انجام می‌دهد که چند دقیقه طول می‌کشد؛
    // پس مهلت باید بیشتر از آن باشد تا «نرسیدن» با «هنوز در جستجو» اشتباه نشود
    await _atWaitUntil(() => connected && !busy,
        timeout: const Duration(seconds: 300), label: 'وصل $label');

    if (!connected) {
      _engineResult[id] = '❌ وصل نشد';
      _atAdd('ENG-FAIL',
          '$label نتوانست وصل شود • status="$status" • lastFail="$lastFail" • lastWhy="$lastWhy"');
      return false;
    }

    await _atWait(const Duration(seconds: 12), note: 'پایداری $label');
    try {
      final sp = await measure(url: smallSpeedUrl);
      if (sp == null || sp <= 0) {
        _engineResult[id] = '⚠️ وصل شد ولی سرعت صفر';
        _atAdd('ENG-NODATA', '$label وصل شد ولی تست سرعت داده نداد');
      } else {
        final kb = (sp * 1024).toStringAsFixed(0);
        _engineResult[id] = '✅ وصل • ≈$kb KB/s';
        dbg('🧪 $label سرعت ≈ $kb KB/s');
      }
    } catch (e) {
      _engineResult[id] = '⚠️ وصل • خطا در measure';
      _atAdd('ENG-MEASURE', '$label خطا در measure: $e');
    }
    return true;
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
          'lib/auto_test.dart → _atConnectEngine',
          'موتور وصل نشد؛ status آخر اپ در همان خط آمده',
          'lastFail و lastWhy داخل همان خط علت دقیق شکست اپ را می‌گویند. اگر برای همه‌ی کانفیگ‌ها تکرار شد، مشکل از شروع هسته در حالت VPN است؛ مشخصات کانفیگ‌ها در بخش E-CONFIG-FAIL گزارش اصلی است',
        ];
      case 'RECONNECT-FAIL':
        return [
          'lib/auto_test.dart → _atScenarioReconnectStorm',
          'بعد از قطع و وصل مجدد، اتصال برنگشت',
          'ناپایداری روی همان سرور. ENG-FAIL و بخش هسته را ببین',
        ];
      case 'ENG-NODATA':
        return [
          'lib/auto_test.dart → _atConnectEngine',
          'وصل شد ولی تست سرعت داده نداد',
          'تونل بالا آمده ولی ترافیک رد نمی‌شود. DNS و مسیریابی TUN را بررسی کن (در ۳.۵.۰ TUN بومی شده)',
        ];
      case 'ENG-MEASURE':
        return [
          'lib/auto_test.dart → _atConnectEngine',
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

  /// سناریو ۱: تست تک‌تک هر ۶ موتور VPN
  Future<void> _atScenarioAllEngines() async {
    _scenario = 1;
    autoTestText.value = 'سناریو ۱: تست ۶ VPN';
    dbg('🧪 سناریو ۱ — هر ۶ موتور VPN');

    final list = _engines.where((e) => _atSelected.contains(e.$1)).toList();
    for (var i = 0; i < list.length; i++) {
      if (_abortRequested) return;
      final e = list[i];
      autoTestText.value = 'سناریو ۱: ${e.$2} (${i + 1}/${list.length})';
      final ok = await _atConnectEngine(e.$1, e.$2);
      if (ok) {
        await _atEnsureDisconnected();
        await _atWait(const Duration(seconds: 2));
      } else {
        // اگر سرور آن نوع نبود، ادامه بده
        await _atEnsureDisconnected();
        await _atWait(const Duration(seconds: 1));
      }
    }
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
          timeout: const Duration(seconds: 90), label: 'وصل چرخه $i');

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
    } catch (e) { logError(e); }
    await _atWaitUntil(() => !busy && !switching,
        timeout: const Duration(seconds: 30), label: 'آزاد شدن بعد از abort');

    try {
      await fut.timeout(const Duration(seconds: 5));
    } catch (e) { logError(e); }

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
          timeout: const Duration(seconds: 90), label: 'بازیابی بعد از abort');
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
          timeout: const Duration(seconds: 100), label: 'وصل برای تعویض');
    }
    if (!connected) {
      _atAdd('SWAP-SKIP', 'نتوانست برای سناریو تعویض وصل شود');
      return;
    }

    final before = current?.key;
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
          timeout: const Duration(seconds: 100), label: 'وصل برای مانیتور');
    }

    final remain = _startedAt == null
        ? const Duration(minutes: 5)
        : _testDuration - DateTime.now().difference(_startedAt!);
    final watchFor = remain > const Duration(minutes: 5)
        ? const Duration(minutes: 5)
        : (remain.isNegative ? Duration.zero : remain);

    if (watchFor.inSeconds < 10) return;

    final end = DateTime.now().add(watchFor);
    var lastPingCheck = DateTime.now();
    while (DateTime.now().isBefore(end)) {
      if (_abortRequested || _phase != _AtPhase.running) return;

      if (!connected && !busy) {
        _atAdd('STABLE-DROP', 'در مانیتور طولانی، اتصال بی‌دلیل قطع شد');
        await connect();
        await _atWaitUntil(() => connected && !busy,
            timeout: const Duration(seconds: 80), label: 'بازیابی مانیتور');
      }

      if (DateTime.now().difference(lastPingCheck) >
          const Duration(seconds: 40)) {
        lastPingCheck = DateTime.now();
        try {
          final sp = await measure(url: smallSpeedUrl);
          if (connected && (sp == null || sp <= 0)) {
            _atAdd('STABLE-NODATA', 'در مانیتور طولانی، داده از تونل نیامد');
          }
        } catch (e) { logError(e); }
      }

      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }
}
