part of 'main.dart';

// =============================================================================
// KING HEAL ENGINE — خودترمیمی نسل آخر (بدون API)
// لایه‌ها: حسگر → تشخیص → پیش‌بینی → اقدام → تأیید → یادگیری → آپدیت
// هدف: قبل از اینکه کاربر بفهمد مشکل بوده، ترمیم شده باشد.
// =============================================================================

// STABLE2: زمان آخرین تقویت Mux توسط خودترمیمی
DateTime _kingTurboAt = DateTime.fromMillisecondsSinceEpoch(0);

enum _HealPhase { idle, sense, diagnose, act, verify, learn }

class _HealSignal {
  final String id;
  final int severity; // 1..10
  final String note;
  _HealSignal(this.id, this.severity, this.note);
}

class _HealMemory {
  static const Set<String> _knownActions = <String>{
    'clear_abort_connect',
    'connect_now',
    'search_connect',
    'soft_clear_blacklist',
    'soft_clear_and_search',
    'restart_tunnel',
    'failover',
    'failover_soft',
    'force_turbo',
    'calm_pilot',
  };
  final Map<String, int> wins = {};
  final Map<String, int> fails = {};
  final Map<String, int> contextualWins = {};
  final Map<String, int> contextualFails = {};
  Future<void>? _loadTask;
  Future<void> _writeQueue = Future<void>.value();

  // Event journal is append-only: no fixed lifetime limit and no full-file
  // materialization. It survives process death and is replayed incrementally.
  Future<void> load() => _loadTask ??= _loadJournal();

  Future<void> _loadJournal() async {
    try {
      final root = await getApplicationSupportDirectory();
      final file = File('${root.path}/king_heal_learning.jsonl');
      if (!await file.exists()) return;
      await for (final line in file.openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        try {
          final row = jsonDecode(line);
          if (row is! Map || row['v'] != 1) continue;
          final action = row['action'];
          final ok = row['ok'];
          if (action is! String || !_knownActions.contains(action) || ok is! bool) continue;
          final context = row['context'];
          _apply(action, ok, context: context is String ? context : '');
        } catch (_) {
          // Ignore a torn/corrupt journal row; later rows remain recoverable.
        }
      }
    } catch (_) {
      // Learning storage is best-effort and must never block VPN recovery.
    }
  }

  String _contextKey(String context, String action) => '${context}::$action';

  void _apply(String action, bool ok, {String context = ''}) {
    if (ok) {
      wins[action] = (wins[action] ?? 0) + 1;
    } else {
      fails[action] = (fails[action] ?? 0) + 1;
    }
    if (context.isNotEmpty) {
      final key = _contextKey(context, action);
      if (ok) {
        contextualWins[key] = (contextualWins[key] ?? 0) + 1;
      } else {
        contextualFails[key] = (contextualFails[key] ?? 0) + 1;
      }
    }
  }

  Future<void> remember(String action, bool ok, {String context = ''}) async {
    if (!_knownActions.contains(action)) return;
    await load();
    final previous = _writeQueue;
    final release = Completer<void>();
    _writeQueue = release.future;
    await previous;
    try {
      final root = await getApplicationSupportDirectory();
      final file = File('${root.path}/king_heal_learning.jsonl');
      final lockFile = await File('${file.path}.lock')
          .open(mode: FileMode.append);
      var locked = false;
      try {
        await lockFile.lock(FileLock.exclusive);
        locked = true;
        await file.writeAsString(
          jsonEncode(<String, Object>{
            'v': 1,
            'action': action,
            'ok': ok,
            if (context.isNotEmpty) 'context': context,
            'at': DateTime.now().toUtc().toIso8601String(),
          }) + '\n',
          mode: FileMode.append,
          flush: true,
        );
      } finally {
        try {
          if (locked) await lockFile.unlock();
        } finally {
          await lockFile.close();
        }
      }
    } catch (_) {
      // Keep current-session adaptation alive even if storage is unavailable.
    } finally {
      _apply(action, ok, context: context);
      release.complete();
    }
  }

  double score(String action, {String context = ''}) {
    final totalWins = wins[action] ?? 0;
    final totalFails = fails[action] ?? 0;
    final globalRate = (totalWins + 1) / (totalWins + totalFails + 2);
    if (context.isEmpty) return globalRate;
    final key = _contextKey(context, action);
    final localWins = contextualWins[key] ?? 0;
    final localFails = contextualFails[key] ?? 0;
    final localRate = (localWins + 1) / (localWins + localFails + 2);
    final evidenceWeight = (localWins + localFails) /
        (localWins + localFails + 4);
    return globalRate * (1 - evidenceWeight) + localRate * evidenceWeight;
  }
}

final _healMem = _HealMemory();
_HealPhase _healPhase = _HealPhase.idle;
DateTime? _healLastRun;
DateTime? _healLastAct;
DateTime? _healStableSince;
int _healCycle = 0;
int _healActStreak = 0;
String _healLastAction = '';
final ValueNotifier<String> kingHealText =
    ValueNotifier<String>('موتور خودترمیمی King آماده است.');
final ValueNotifier<bool> kingHealBusy = ValueNotifier<bool>(false);

// شمارنده‌های حسگر
int _hOrphan = 0;
int _hNoHealthy = 0;
int _hCoreDrop = 0;
int _hNoTun = 0;
int _hBadPing = 0;
int _hNoData = 0;
int _hPilotThrash = 0;
int _hConfigFail = 0;
int _hSyncFix = 0;

extension KingHealEngine on _HomePageState {
  /// نقطهٔ ورود اصلی — از واچ‌داگ، خلبان، و بعد از خطا
  /// نسخهٔ تهاجمی: سریع‌تر حس می‌کند، زودتر وارد عمل می‌شود، کمتر صبر می‌کند
  Future<void> kingSelfHeal({String reason = ''}) async {
    if (!mounted || kingHealBusy.value) return; // حقیقی: جلوگیری از هم‌پوشانی چرخه‌های ترمیم
    final now = DateTime.now();
    // فاصلهٔ بین چرخه‌ها کمتر شد (۸ → ۴ ثانیه)
    if (_healLastRun != null &&
        now.difference(_healLastRun!) < const Duration(seconds: 4)) {
      return;
    }
    // اگر مشغول یا در حال تعویض است، دخالت نکن (قبلاً فقط وقتی هر دو true بود)
    if ((busy || switching) && reason != 'force') return;
    _healLastRun = now;
    _healCycle++;
    kingHealBusy.value = true;
    _healPhase = _HealPhase.sense;

    try {
      // ----- ۱) حسگر -----
      await _healMem.load();
      final signals = await _healSense();
      if (signals.isEmpty) {
        _healPhase = _HealPhase.idle;
        if (connected) {
          _healStableSince ??= now;
          final up = now.difference(_healStableSince!).inSeconds;
          if (up > 60) {
            kingHealText.value =
                '🛡 پایدار ${up}s • چرخه #$_healCycle • هیچ تهدیدی نیست';
          }
        }
        return;
      }

      // ----- ۲) تشخیص -----
      _healPhase = _HealPhase.diagnose;
      signals.sort((a, b) => b.severity.compareTo(a.severity));
      final top = signals.take(3).toList();
      final plan = _healPlan(top);

      kingHealText.value =
          '🩺 تشخیص: ${top.map((s) => s.id).join(" + ")}\n'
          '🎯 اقدام: ${plan.$1}\n'
          '📝 ${plan.$2}';

      // ----- ۳) اقدام (با حداقل فاصله بین اقدامات سنگین) -----
      if (plan.$1 == 'none') {
        _healPhase = _HealPhase.idle;
        return;
      }
      // فاصلهٔ بین اقدامات تکراری کمتر شد (۲۰ → ۱۰ ثانیه)
      if (_healLastAct != null &&
          now.difference(_healLastAct!) < const Duration(seconds: 10) &&
          plan.$1 == _healLastAction) {
        kingHealText.value = '⏳ همان اقدام اخیراً انجام شد — صبر کوتاه';
        return;
      }

      _healPhase = _HealPhase.act;
      _healLastAct = now;
      _healLastAction = plan.$1;
      healActive = true; // ADAUTO: کار خودکار خلبان، تبلیغ نشان نمی‌دهد
      final bool ok;
      try {
        ok = await _healAct(plan.$1, plan.$3);
      } finally {
        healActive = false;
      }
      // ----- ۴) تأیید -----
      _healPhase = _HealPhase.verify;
      await Future.delayed(const Duration(seconds: 2));
      final stillBad = await _healSense();
      // Core CONNECTED is not proof of repair. Require traffic through the
      // active tunnel, using domestic endpoints in nationalMode and global
      // endpoints otherwise. Proxy-only mode has no TUN data-plane to verify.
      final bool dataPlaneOk;
      if (!wantVpn) {
        dataPlaneOk = true;
      } else if (proxyMode) {
        dataPlaneOk = connected && lastState == 'CONNECTED';
      } else {
        dataPlaneOk = connected &&
            await _tunnelTrafficOk().timeout(
              const Duration(seconds: 10),
              onTimeout: () => false,
            );
      }
      final fixed = dataPlaneOk && stillBad.every((s) => s.severity < 5);
      // Learn from verified tunnel recovery, not merely an action's return
      // value (which may report CONNECTED while no traffic passes).
      final learningContext = (top.map((signal) => signal.id).toList()..sort()).join('+');
      await _healMem.remember(plan.$1, fixed, context: learningContext);
      _healActStreak = fixed ? 0 : _healActStreak + 1;

      // ----- ۵) یادگیری + پیشنهاد آپدیت اگر ترمیم کافی نبود -----
      _healPhase = _HealPhase.learn;
      if (fixed) {
        _healStableSince = DateTime.now();
        _healActStreak = 0;
        kingHealText.value =
            '✅ ترمیم موفق: ${plan.$1}\n'
            'حافظه: برد ${_healMem.wins[plan.$1] ?? 0} / باخت ${_healMem.fails[plan.$1] ?? 0}';
        dbg('خودترمیمی✓ ${plan.$1} ($reason)');
        _shProb('heal:ok:${plan.$1}',
            'خودترمیمی موفق: ${plan.$1} • ${plan.$2}');
      } else {
        kingHealText.value =
            '⚠ ترمیم ناقص: ${plan.$1}\n'
            'اقدام بعدی در چرخه بعد • streak=$_healActStreak';
        dbg('خودترمیمی✗ ${plan.$1} ($reason)');
        _shProb('heal:fail:${plan.$1}',
            'خودترمیمی ناقص: ${plan.$1} • ${plan.$2}');
        // اگر چند بار پشت‌سرهم شکست → آپدیت نسخه را پیشنهاد بده
        if (_healActStreak >= 4) {
          _healActStreak = 0;
          unawaited(_healOfferUpdate(
              'چند ترمیم محلی کافی نبود. نسخه‌ی جدید ممکن است ریشه‌ی مشکل را بسته باشد.'));
        }
      }
    } catch (e, stk) {
      logError(e, stk);
      kingHealText.value = 'خطای موتور ترمیم: $e';
    } finally {
      _healPhase = _HealPhase.idle;
      kingHealBusy.value = false;
    }
  }

  Future<List<_HealSignal>> _healSense() async {
    final out = <_HealSignal>[];
    // Stability age belongs to the current connected session only.
    if (connected) {
      _healStableSince ??= DateTime.now();
    } else {
      _healStableSince = null;
    }

    // همگام‌سازی هسته
    try {
      if (_syncCore()) {
        out.add(_HealSignal('sync', 6, 'ناهمگامی اپ/هسته اصلاح شد'));
        _hSyncFix++;
      }
    } catch (e, stk) { logError(e, stk); }

    // یتیم: می‌خواهد وصل باشد ولی بیکار است
    if (wantVpn && !connected && !busy && !switching && !searching) {
      _hOrphan++;
      if (_hOrphan >= 1) {
        out.add(_HealSignal(
            'orphan', 9, 'wantVpn=1 ولی هیچ کار اتصالی در جریان نیست'));
      }
    } else {
      _hOrphan = 0;
    }

    // بدون سرور سالم
    if (wantVpn && !connected && good.isEmpty) {
      _hNoHealthy++;
      out.add(_HealSignal(
          'no_healthy',
          good.isEmpty && pending.isEmpty ? 8 : 6,
          'سالم=${good.length} صف=${pending.length} سیاه=${failed.length}'));
    } else {
      _hNoHealthy = 0;
    }

    // لیست سیاه متورم — حساس‌تر
    if (failed.length > 40 && good.length < 5) {
      out.add(_HealSignal(
          'blacklist', 8, 'لیست سیاه ${failed.length} — ممکن است سرورهای خوب قفل شده باشند'));
    }

    // علت آخرین تعویض / وضعیت
    final why = lastWhy;
    if (why.contains('هسته/اندروید') || why.contains('CORE')) {
      _hCoreDrop++;
      out.add(_HealSignal('core_drop', 8, why));
    } else {
      _hCoreDrop = 0;
    }

    // تونل
    if (connected && !proxyMode && tunWarn) {
      _hNoTun++;
      out.add(_HealSignal('no_tun', 9, 'تونل هشدار دارد'));
    } else {
      _hNoTun = 0;
    }

    // پینگ بد — فقط بعد از ۲ بار متوالی (تعویض نمی‌کند، فقط Mux تقویت می‌شود)
    final cp = current?.ping;
    if (connected && !nationalMode && cp != null && cp > badPingMs) {
      _hBadPing++;
      if (_hBadPing >= 2) {
        out.add(_HealSignal('bad_ping', 5, 'پینگ ${cp}ms'));
      }
    } else {
      _hBadPing = 0;
    }

    // سرعت نزدیک صفر (زیر ~۴۰ KB/s) — فقط بعد از پایداری کافی
    final sp = current?.speed;
    if (connected && !nationalMode &&
        (sp == null || sp < 0.04) &&
        _healStableSince != null &&
        DateTime.now().difference(_healStableSince!).inSeconds > 35) {
      _hNoData++;
      if (_hNoData >= 2) {
        out.add(_HealSignal('no_data', 7, 'سرعت نزدیک صفر'));
      }
    } else {
      _hNoData = 0;
    }

    // خلبان thrash
    if (why.contains('خلبان') && why.contains('switch')) {
      _hPilotThrash++;
      if (_hPilotThrash >= 2) {
        out.add(_HealSignal(
            'pilot_thrash', 7, 'تعویض مکرر خلبان — باید آرام شود'));
      }
    } else if (connected) {
      _hPilotThrash = 0;
    }

    // صف خالی + wantVpn
    if (wantVpn && pending.isEmpty && good.isEmpty && !searching) {
      out.add(_HealSignal('empty_queue', 7, 'صف و سالم هر دو خالی'));
    }

    // توربو/Mux خاموش در اتصال
    if (connected && turboSpeed && (!muxEnabled || muxConc < 8)) {
      out.add(_HealSignal('turbo_off', 3, 'توربو باید Mux داشته باشد'));
    }

    // abort گیر کرده
    if (abort && wantVpn && !connected) {
      out.add(_HealSignal('abort_stuck', 8, 'abort=1 ولی هنوز میخواهیم وصل باشیم'));
    }

    return out;
  }

  /// (action, explain, params)
  (String, String, Map<String, int>) _healPlan(List<_HealSignal> top) {
    final ids = top.map((s) => s.id).toSet();
    final params = <String, int>{};

    // اولویت مطلق
    if (ids.contains('abort_stuck')) {
      return (
        'clear_abort_connect',
        'abort گیر کرده — رهاسازی و اتصال',
        params
      );
    }
    if (ids.contains('no_tun')) {
      return ('restart_tunnel', 'تونل نیست — ریستارت همان سرور', params);
    }
    if (ids.contains('orphan')) {
      return ('connect_now', 'اتصال یتیم — اتصال فوری', params);
    }
    if (ids.contains('empty_queue') || ids.contains('no_healthy')) {
      if (ids.contains('blacklist')) {
        return (
          'soft_clear_and_search',
          'سیاه‌لیست بزرگ + بدون سالم — پاک‌سازی نرم و جستجو',
          params
        );
      }
      return ('search_connect', 'بدون سرور سالم — جستجو و اتصال', params);
    }
    if (ids.contains('core_drop')) {
      return ('failover', 'قطع هسته — تعویض سرور', params);
    }
    if (ids.contains('pilot_thrash')) {
      return (
        'calm_pilot',
        'خلبان زیاد تعویض می‌کند — آرام‌سازی و نگه‌داری اتصال',
        params
      );
    }
    if (ids.contains('blacklist')) {
      return (
        'soft_clear_blacklist',
        'لیست سیاه متورم — آزادسازی سرورهای قدیمی',
        params
      );
    }
    if (ids.contains('no_data')) {
      // فقط سرعت نزدیک صفر → بعد از پایداری کافی تعویض
      final up = _healStableSince == null
          ? 999
          : DateTime.now().difference(_healStableSince!).inSeconds;
      if (up >= 45 && good.isNotEmpty) {
        return ('failover_soft', 'سرعت نزدیک صفر — تعویض نرم', params);
      }
      return ('force_turbo', 'سرعت ضعیف — تقویت Mux', params);
    }
    if (ids.contains('bad_ping')) {
      // پینگ بد به تنهایی تعویض نمی‌کند؛ فقط Mux را تقویت می‌کند
      // مگر اینکه سرور ۵۰٪ بهتر در صف باشد (منطق betterSwitch در واچ‌داگ)
      return ('force_turbo', 'پینگ بالا — تقویت Mux بدون تعویض', params);
    }
    if (ids.contains('turbo_off')) {
      return ('force_turbo', 'اعمال Mux/توربو بدون قطع', params);
    }
    if (ids.contains('sync')) {
      return ('none', 'همگام‌سازی انجام شد', params);
    }

    // Context-aware learning: the same repair may behave differently for
    // no-healthy, core-drop, no-data and pilot-thrash incidents.
    final context = ids.toList()..sort();
    final contextKey = context.join('+');
    final candidates = <String>[
      'connect_now',
      'search_connect',
      'failover',
      'failover_soft',
      'soft_clear_and_search',
      'restart_tunnel',
      'force_turbo',
      'calm_pilot',
    ];
    candidates.sort((a, b) => _healMem
        .score(b, context: contextKey)
        .compareTo(_healMem.score(a, context: contextKey)));
    if (top.first.severity >= 7 &&
        (_healMem.wins[candidates.first] ?? 0) +
                (_healMem.fails[candidates.first] ?? 0) >
            0) {
      return (
        candidates.first,
        'تصمیم تطبیقی برای [$contextKey] • احتمال موفقیت تاریخی: '
            '${(_healMem.score(candidates.first, context: contextKey) * 100).round()}%',
        params
      );
    }
    return ('none', 'سیگنال خفیف — اقدام لازم نیست', params);
  }

  Future<bool> _healAct(String action, Map<String, int> params) async {
    try {
      switch (action) {
        case 'clear_abort_connect':
          abort = false;
          wantVpn = true;
          if (busy || switching) return false;
          await connect();
          return connected;

        case 'connect_now':
          abort = false;
          wantVpn = true;
          turboSpeed = true;
          muxEnabled = true;
          muxConc = max(muxConc, 32);
          if (!busy && !switching) await connect();
          return connected || busy;

        case 'search_connect':
          abort = false;
          wantVpn = true;
          listTime = null;
          lastFetchTry = DateTime.fromMillisecondsSinceEpoch(0);
          if (busy || switching) return false;
          await connect();
          return connected;

        case 'soft_clear_blacklist':
        case 'soft_clear_and_search':
          // تهاجمی‌تر: سرورهای قدیمی‌تر از ۱۰ دقیقه آزاد می‌شوند
          final cut =
              DateTime.now().subtract(const Duration(minutes: 10));
          failed.removeWhere((_, t) => t.isBefore(cut));
          // Never mass-delete recent failures to force a search. Only
          // entries whose recorded cooldown has actually expired are released.
          dbg('خودترمیمی تهاجمی: سیاه‌لیست → ${failed.length}');
          if (action == 'soft_clear_and_search') {
            abort = false;
            wantVpn = true;
            listTime = null;
            lastFetchTry = DateTime.fromMillisecondsSinceEpoch(0);
            if (busy || switching) return false;
            await connect();
            return connected;
          }
          return true;

        case 'failover':
        case 'failover_soft':
          if (busy || switching) return false;
          lastWhy = 'خودترمیمی: $action';
          await _failover();
          return connected;

        case 'restart_tunnel':
          if (current != null && connected) {
            await _restartTunnel();
            return true;
          }
          if (!busy) await connect();
          return true;

        case 'calm_pilot':
          // نگه‌داری: تعویض را قفل زمانی کن
          _healStableSince = DateTime.now();
          _localSlowStreak = 0;
          _localPhase = 'stable';
          if (localPilotOn) {
            localPilotText.value =
                '🛡 خودترمیمی: خلبان آرام شد — حداقل ۳ دقیقه بدون تعویض';
          }
          if (connected && turboSpeed) {
            muxEnabled = true;
            muxConc = max(muxConc, 24);
          }
          return true;

        case 'force_turbo':
          // STABLE2: force_turbo قبلاً mux را هر بار روی ۳۲ می‌گذاشت و CPU گوشی
          // را بالا می‌برد. الان فقط اگر muxConc پایین‌تر از ۳۲ بود بالا می‌بره
          // (هرگز پایین نمی‌کشه). حداکثر یک بار در ۵ دقیقه اجرا می‌شود.
          if (DateTime.now().difference(_kingTurboAt) <
              const Duration(minutes: 5)) {
            return false;
          }
          _kingTurboAt = DateTime.now();
          turboSpeed = true;
          muxEnabled = true;
          // HEALMUX: بالا ببر تا ۳۲، هرگز پایین نکش (هدف کاربر ۳۲ است).
          // کامنت قدیمی از ۳۲ به‌عنوان "CPU spike" یاد کرده بود؛ حالا
          // Fragment خاموش و SNI جعل اضافه شده، پس ۳۲ قابل تحمل‌تر است.
          if (muxConc < 32) muxConc = 32;
          try {
            await _saveSettings();
          } catch (e, stk) { logError(e, stk); }
          // اگر وصل نیست، فوراً وصل شو
          if (wantVpn && !connected && !busy) {
            await connect();
          }
          return true;

        default:
          return false;
      }
    } catch (e, stk) {
      logError(e, stk);
      return false;
    }
  }

  Future<void> _healOfferUpdate(String why) async {
    if (!mounted) return;
    try {
      kingHealText.value =
          '🚀 پیشنهاد آپدیت: $why\nدر حال بررسی نسخه‌ی جدید...';
      // اجازه‌ی چک مجدد آپدیت
      _updateChecked = false;
      await checkForUpdate();
    } catch (e, stk) {
      logError(e, stk);
    }
  }

  /// وضعیت انسانی برای UI
  String kingHealStatusLine() {
    final mem = 'برد ${_healMem.wins.values.fold<int>(0, (a, b) => a + b)} / '
        'باخت ${_healMem.fails.values.fold<int>(0, (a, b) => a + b)}';
    final st = _netStateNow(
      connected: connected,
      tunBadNow: tunBad,
      pingRounds: badPingRounds,
      nationalMode: nationalMode,
    );
    return 'فاز: $_healPhase • چرخه: $_healCycle • شبکه: ${_netStateLabel(st)} • اخیر: $mem';
  }
}
