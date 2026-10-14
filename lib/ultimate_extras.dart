part of 'main.dart';

// ======================= King Ultimate Extras =======================
// آخرین لایه امکانات رقابتی: آفلاین، صرفه‌جویی دیتا، امتیاز کیفیت،
// پیش‌پرواز، واچ شبکه، حالت اضطراری، گزارش کامل تشخیص.

bool offlineOnly = false; // فقط سرورهای سالم ذخیره‌شده — بدون دانلود لیست
bool dataSaver = false; // workers کمتر، بدون تست سرعت سنگین
bool autoNetReconnect = true; // بعد از تغییر شبکه دوباره وصل شو
bool preflightOn = true; // قبل از وصل یک چک سبک DNS/HTTP
int reconnectCount = 0;
DateTime? pilotSessionStart;
String _lastNetFp = '';
Timer? _netWatchTimer;

// snapshot of numbers when data-saver is toggled on (to restore later)
int? _dsFw, _dsBw, _dsSt;
bool? _dsAs;

int qualityScore() {
  if (!connected || current == null) return 0;
  final s = current!;
  final ping = s.ping ?? 9999;
  final speed = s.speed ?? 0; // MB/s
  // ping: 0ms → 40, 1500ms → 0
  final pScore = (40 * (1 - (ping.clamp(0, 1500) / 1500))).round();
  // speed: 0 → 0, 5 MB/s → 40
  final spScore = (40 * (speed.clamp(0, 5) / 5)).round();
  // stability: fewer recent switches → up to 20
  final stScore = lastWhy.isEmpty ? 20 : 10;
  return (pScore + spScore + stScore).clamp(0, 100);
}

String qualityLabel(int q) {
  if (q >= 80) return 'عالی';
  if (q >= 60) return 'خوب';
  if (q >= 40) return 'متوسط';
  if (q >= 20) return 'ضعیف';
  return 'خیلی ضعیف';
}

void applyDataSaver(bool on) {
  if (on) {
    _dsFw ??= fastWorkers;
    _dsBw ??= bgWorkers;
    _dsSt ??= speedTopN;
    _dsAs ??= autoSpeed;
    fastWorkers = min(fastWorkers, 12);
    bgWorkers = min(bgWorkers, 2);
    speedTopN = min(speedTopN, 1);
    autoSpeed = false;
    dataSaver = true;
  } else {
    if (_dsFw != null) fastWorkers = _dsFw!;
    if (_dsBw != null) bgWorkers = _dsBw!;
    if (_dsSt != null) speedTopN = _dsSt!;
    if (_dsAs != null) autoSpeed = _dsAs!;
    _dsFw = _dsBw = _dsSt = null;
    _dsAs = null;
    dataSaver = false;
  }
}

Future<void> ultimateLoad(SharedPreferences p) async {
  offlineOnly = p.getBool('ult_off') ?? offlineOnly;
  dataSaver = p.getBool('ult_ds') ?? dataSaver;
  autoNetReconnect = p.getBool('ult_anr') ?? autoNetReconnect;
  preflightOn = p.getBool('ult_pf') ?? preflightOn;
  if (dataSaver) applyDataSaver(true);
}

Future<void> ultimateSave() async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setBool('ult_off', offlineOnly);
    await p.setBool('ult_ds', dataSaver);
    await p.setBool('ult_anr', autoNetReconnect);
    await p.setBool('ult_pf', preflightOn);
  } catch (e) {
    logError(e);
  }
}

// lightweight network fingerprint (no extra packages)
Future<String> _netFingerprint() async {
  try {
    final r = await InternetAddress.lookup('one.one.one.one')
        .timeout(const Duration(seconds: 3));
    final ips = r.map((e) => e.address).join(',');
    // also note national mode as part of fingerprint
    return '${nationalMode ? 'N' : 'G'}|$ips';
  } catch (_) {
    return nationalMode ? 'N|down' : 'G|down';
  }
}

extension UltimateExt on _HomePageState {
  void startNetWatch() {
    _netWatchTimer?.cancel();
    if (!autoNetReconnect) return;
    _netWatchTimer = Timer.periodic(const Duration(seconds: 25), (_) async {
      if (!mounted || !wantVpn) return;
      try {
        final fp = await _netFingerprint();
        if (_lastNetFp.isEmpty) {
          _lastNetFp = fp;
          return;
        }
        if (fp != _lastNetFp) {
          _lastNetFp = fp;
          if (wantVpn && !busy && !switching) {
            reconnectCount++;
            lastWhy = 'تغییر شبکه';
            _set('شبکه عوض شد — وصل مجدد خودکار...');
            if (connected) {
              await disconnect();
              wantVpn = true;
            }
            await connect();
          }
        }
      } catch (e) {
        logError(e);
      }
    });
  }

  void stopNetWatch() {
    _netWatchTimer?.cancel();
    _netWatchTimer = null;
  }

  // preflight: quick DNS + HTTP 204 checks before burning full search budget
  Future<bool> runPreflight() async {
    if (!preflightOn) return true;
    _set('پیش‌پرواز: بررسی DNS و دسترسی شبکه...');
    var dnsOk = false;
    try {
      final r = await InternetAddress.lookup('dns.google')
          .timeout(const Duration(seconds: 4));
      dnsOk = r.isNotEmpty;
    } catch (_) {}
    var httpOk = false;
    try {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      try {
        final req = await c
            .getUrl(Uri.parse('http://connectivitycheck.gstatic.com/generate_204'))
            .timeout(const Duration(seconds: 5));
        final res = await req.close().timeout(const Duration(seconds: 5));
        httpOk = res.statusCode == 204 || res.statusCode == 200;
      } finally {
        c.close(force: true);
      }
    } catch (_) {}
    if (!dnsOk && !httpOk) {
      _set('پیش‌پرواز: شبکه خیلی ضعیف است — باز هم تلاش می‌کنم');
      // still allow connect; just warn
      return true;
    }
    _set('پیش‌پرواز OK • DNS:${dnsOk ? '✓' : '✗'} HTTP:${httpOk ? '✓' : '✗'}');
    return true;
  }

  // emergency: stop everything sensitive, keep UI simple
  Future<void> panicNow() async {
    abort = true;
    stopGrokPilot();
    stopNetWatch();
    aiSession = false;
    aiLoop?.cancel();
    if (connected || wantVpn) {
      await disconnect();
    }
    abort = false;
    errorLog.value = '';
    aiText.value = '';
    aiSuggest.value = {};
    _set('حالت اضطراری: اتصال قطع، خلبان و لاگ‌های حساس پاک شد');
  }

  Future<void> connectBestCached() async {
    offlineOnly = true;
    await ultimateSave();
    if (good.isEmpty && _resMap.isEmpty) {
      _set('سرور ذخیره‌شده‌ای نیست — اول یک‌بار عادی وصل شو');
      offlineOnly = false;
      await ultimateSave();
      return;
    }
    _set('اتصال فقط از سرورهای سالم ذخیره‌شده...');
    await connect();
  }

  String fullDiagText() {
    final b = StringBuffer();
    b.writeln('=== King VPN Full Diagnostics ===');
    b.writeln('time: ${DateTime.now().toIso8601String()}');
    b.writeln('connected: $connected wantVpn: $wantVpn');
    b.writeln('national: $nationalMode level: $natLevel op: $natOpKey');
    b.writeln('ultra: $ultraMode indestructible: $indestructibleMode turbo: $turboSpeed');
    b.writeln('offlineOnly: $offlineOnly dataSaver: $dataSaver preflight: $preflightOn');
    b.writeln('autoNetReconnect: $autoNetReconnect reconnects: $reconnectCount');
    b.writeln('quality: ${qualityScore()} (${qualityLabel(qualityScore())})');
    b.writeln('aiProvider: $aiProvider lastAi: $aiLastProvider session: $aiSession');
    b.writeln('mux: $muxEnabled/$muxConc frag: $fragEnabled proxy: $proxyMode');
    b.writeln('servers: total=$total good=${good.length} pending=${pending.length}');
    b.writeln('tests: $totalOk/$totalTested');
    if (current != null) {
      final c = current!;
      b.writeln(
          'current: ${c.name} ping=${c.ping} speed=${c.speed} var=${natVarFor(c)}');
    }
    b.writeln('lastWhy: $lastWhy');
    b.writeln('status: $status');
    b.writeln('--- DNA top ---');
    b.writeln(_plusStats());
    return b.toString();
  }

  Future<void> exportFullDiag() async {
    final t = fullDiagText();
    await Clipboard.setData(ClipboardData(text: t));
    _set('گزارش کامل تشخیص کپی شد');
  }

  List<Widget> ultimateSettingsItems(void Function(void Function()) setS) {
    Widget sw(String t, bool v, void Function(bool) f, {String? sub}) =>
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t),
          subtitle: sub == null ? null : Text(sub),
          value: v,
          onChanged: (x) => setS(() => f(x)),
        );
    return [
      const Padding(
        padding: EdgeInsets.only(top: 14, bottom: 4),
        child: Text('امکانات Ultimate',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Colors.deepPurple)),
      ),
      sw('فقط سرورهای ذخیره‌شده (آفلاین)', offlineOnly, (v) {
        offlineOnly = v;
        ultimateSave();
      }, sub: 'لیست جدید دانلود نمی‌شود — فقط good/cache'),
      sw('صرفه‌جویی دیتا و باتری', dataSaver, (v) {
        applyDataSaver(v);
        ultimateSave();
        _saveSettings();
      }, sub: 'workers کمتر، بدون تست سرعت سنگین'),
      sw('وصل مجدد خودکار بعد از تغییر شبکه', autoNetReconnect, (v) {
        autoNetReconnect = v;
        ultimateSave();
        if (v) {
          startNetWatch();
        } else {
          stopNetWatch();
        }
      }),
      sw('پیش‌پرواز قبل از اتصال', preflightOn, (v) {
        preflightOn = v;
        ultimateSave();
      }, sub: 'چک سبک DNS/HTTP قبل از جستجوی سنگین'),
    ];
  }
}
