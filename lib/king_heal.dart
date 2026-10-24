part of 'main.dart';

// =============================================================================
// KING HEAL ENGINE — خودترمیمی نسل آخر (بدون API)
// لایه‌ها: حسگر → تشخیص → پیش‌بینی → اقدام → تأیید → یادگیری → آپدیت
// هدف: قبل از اینکه کاربر بفهمد مشکل بوده، ترمیم شده باشد.
// =============================================================================

enum _HealPhase { idle, sense, diagnose, act, verify, learn }

class _HealSignal {
  final String id;
  final int severity; // 1..10
  final String note;
  _HealSignal(this.id, this.severity, this.note);
}

class _HealMemory {
  final Map<String, int> wins = {};
  final Map<String, int> fails = {};
  final List<String> recent = [];
  void remember(String action, bool ok) {
    if (ok) {
      wins[action] = (wins[action] ?? 0) + 1;
    } else {
      fails[action] = (fails[action] ?? 0) + 1;
    }
    recent.add('${ok ? "✓" : "✗"}$action');
    if (recent.length > 40) recent.removeAt(0);
  }

  int score(String action) =>
      (wins[action] ?? 0) - (fails[action] ?? 0);
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
    if (!mounted) return;
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
      final ok = await _healAct(plan.$1, plan.$3);
      _healMem.remember(plan.$1, ok);
      _healActStreak = ok ? 0 : _healActStreak + 1;

      // ----- ۴) تأیید -----
      _healPhase = _HealPhase.verify;
      await Future.delayed(const Duration(seconds: 2));
      final stillBad = await _healSense();
      final fixed = stillBad.every((s) => s.severity < 5) ||
          (wantVpn && connected && lastState == 'CONNECTED');

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
    if (connected && cp != null && cp > badPingMs) {
      _hBadPing++;
      if (_hBadPing >= 2) {
        out.add(_HealSignal('bad_ping', 5, 'پینگ ${cp}ms'));
      }
    } else {
      _hBadPing = 0;
    }

    // سرعت نزدیک صفر (زیر ~۴۰ KB/s) — فقط بعد از پایداری کافی
    final sp = current?.speed;
    if (connected &&
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
      if (ids.contains('blacklist') || failed.length > 50) {
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

    // انتخاب از حافظه: اقدامی که قبلاً بیشتر برد داشته
    final candidates = [
      'connect_now',
      'failover',
      'soft_clear_and_search',
      'restart_tunnel'
    ];
    candidates.sort((a, b) => _healMem.score(b).compareTo(_healMem.score(a)));
    if (_healMem.score(candidates.first) > 0 && top.first.severity >= 7) {
      return (
        candidates.first,
        'از حافظه: ${candidates.first} قبلاً موفق‌تر بوده',
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
          if (!busy) await connect();
          return true;

        case 'connect_now':
          abort = false;
          wantVpn = true;
          turboSpeed = true;
          muxEnabled = true;
          muxConc = max(muxConc, 28);
          if (!busy && !switching) await connect();
          return connected || busy;

        case 'search_connect':
          abort = false;
          wantVpn = true;
          listTime = null;
          lastFetchTry = DateTime.fromMillisecondsSinceEpoch(0);
          if (!busy) await connect();
          return true;

        case 'soft_clear_blacklist':
        case 'soft_clear_and_search':
          // تهاجمی‌تر: سرورهای قدیمی‌تر از ۱۰ دقیقه آزاد می‌شوند
          final cut =
              DateTime.now().subtract(const Duration(minutes: 10));
          failed.removeWhere((_, t) => t.isBefore(cut));
          // اگر هنوز شلوغ است، ۷۰٪ قدیمی‌ها را آزاد کن
          if (failed.length > 60) {
            final keys = failed.keys.toList();
            final removeCount = (keys.length * 0.7).round();
            for (var i = 0; i < removeCount && i < keys.length; i++) {
              failed.remove(keys[i]);
            }
          }
          dbg('خودترمیمی تهاجمی: سیاه‌لیست → ${failed.length}');
          if (action == 'soft_clear_and_search') {
            abort = false;
            wantVpn = true;
            listTime = null;
            lastFetchTry = DateTime.fromMillisecondsSinceEpoch(0);
            if (!busy) await connect();
          }
          return true;

        case 'failover':
        case 'failover_soft':
          if (!busy && !switching) {
            lastWhy = 'خودترمیمی: $action';
            await _failover();
          }
          return true;

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
          _localTgFail = 0;
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
          turboSpeed = true;
          muxEnabled = true;
          muxConc = max(muxConc, 32);
          if (!nationalMode) fragEnabled = false;
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
    final mem = _healMem.recent.reversed.take(5).join(' ');
    final st = _netStateNow(
      connected: connected,
      national: nationalMode,
      tunBadNow: tunBad,
      pingRounds: badPingRounds,
    );
    return 'فاز: $_healPhase • چرخه: $_healCycle • شبکه: ${_netStateLabel(st)} • اخیر: $mem';
  }
}
