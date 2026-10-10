part of 'main.dart';

// ======================= مسیریابی هوشمند ایران =======================
// سایت‌های ایرانی مستقیم می‌روند (بدون تانل)، بقیه از VPN.
bool iranRoute = true;
// قانون IP (geoip:ir) به فایل geoip داخل هسته نیاز دارد؛ پیش‌فرض خاموش.
bool iranGeoip = false;

const iranDomains = <String>[
  'domain:ir',
  'domain:digikala.com',
  'domain:aparat.com',
  'domain:filimo.com',
  'domain:telewebion.com',
  'domain:torob.com',
  'domain:eitaa.com',
  'domain:bale.ai',
  'domain:tapsi.cab',
];

// فقط روی اتصال واقعی VPN اعمال می‌شود (تست‌ها دست‌نخورده می‌مانند)
String withIranRouting(String cfg) {
  if (!iranRoute) return cfg;
  try {
    final j = jsonDecode(cfg);
    if (j is! Map<String, dynamic>) return cfg;
    final outs = (j['outbounds'] as List?) ?? <dynamic>[];
    var tag = '';
    for (final o in outs) {
      if (o is Map && o['protocol'] == 'freedom' && o['tag'] != null) {
        tag = o['tag'].toString();
        break;
      }
    }
    if (tag.isEmpty) {
      tag = 'ir-direct';
      outs.add({
        'tag': tag,
        'protocol': 'freedom',
        'settings': <String, dynamic>{}
      });
    }
    j['outbounds'] = outs;
    // قانون دامنه فقط وقتی کار می‌کند که sniffing روشن باشد
    for (final ib in (j['inbounds'] as List?) ?? <dynamic>[]) {
      if (ib is Map) {
        final sn = ib['sniffing'];
        if (sn is! Map || sn['enabled'] != true) {
          ib['sniffing'] = {
            'enabled': true,
            'destOverride': ['http', 'tls']
          };
        }
      }
    }
    final routing =
        (j['routing'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final rules = <dynamic>[
      {'type': 'field', 'outboundTag': tag, 'domain': iranDomains},
      if (iranGeoip)
        {
          'type': 'field',
          'outboundTag': tag,
          'ip': ['geoip:ir']
        },
    ];
    routing['rules'] = [
      ...rules,
      ...((routing['rules'] as List?) ?? <dynamic>[])
    ];
    if (iranGeoip) routing['domainStrategy'] = 'IPIfNonMatch';
    j['routing'] = routing;
    return jsonEncode(j);
  } catch (e) {
    logError(e);
    return cfg;
  }
}

List<Widget> iranSettingsItems(
  Widget Function(String) head,
  Widget Function(String, bool, void Function(bool), {String? sub}) sw,
) =>
    [
      head('🇮🇷 مسیریابی هوشمند ایران'),
      sw('سایت‌های ایرانی مستقیم بروند', iranRoute, (v) => iranRoute = v,
          sub: 'دامنه‌های .ir و چند سایت پرکاربرد بدون VPN باز می‌شوند'),
      sw('قانون IP ایران (geoip، تجربی)', iranGeoip, (v) => iranGeoip = v,
          sub: 'اگر با روشن کردنش اتصال برقرار نشد، خاموشش کن'),
    ];

// ======================= Gemini =======================
String geminiKey = '';
String geminiModel = 'gemini-flash-latest';

class GeminiLocationError implements Exception {
  @override
  String toString() => 'Gemini روی IP این سرور مسدود است (منطقه/آی‌پی)';
}

final aiText = ValueNotifier<String>('');
final aiLoading = ValueNotifier<bool>(false);
// تنظیمات پیشنهادی دستیار (کلید → عدد). با دکمه‌ی «اعمال» روی اپ اعمال می‌شود.
final aiSuggest = ValueNotifier<Map<String, int>>(<String, int>{});
DateTime _lastAutoAi = DateTime.fromMillisecondsSinceEpoch(0);
String aiActionName = '';

Future<void> loadGeminiPrefs(SharedPreferences p) async {
  geminiKey = p.getString('gem_key') ?? '';
  geminiModel = p.getString('gem_model') ?? geminiModel;
}

Future<void> saveGeminiPrefs() async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString('gem_key', geminiKey);
    await p.setString('gem_model', geminiModel);
  } catch (e) {
    logError(e);
  }
}

// true = API روی این سرور باز است، false = منطقه پشتیبانی نمی‌شود، null = نامعلوم
Future<bool?> geminiApiStatus({bool direct = true}) async {
  if (geminiKey.isEmpty) return null;
  final c = HttpClient()
    ..findProxy =
        ((_) => direct ? 'DIRECT' : 'PROXY 127.0.0.1:$httpProxyPort')
    ..connectionTimeout = const Duration(seconds: 6);
  try {
    return await () async {
      final req = await c.getUrl(Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models?pageSize=1'));
      req.headers.set('x-goog-api-key', geminiKey);
      final res = await req.close();
      final body = (await res
              .transform(const Utf8Decoder(allowMalformed: true))
              .join())
          .toLowerCase();
      if (res.statusCode == 200) return true;
      if (body.contains('location is not supported') ||
          body.contains('not supported for the api use')) {
        return false;
      }
      return null;
    }()
        .timeout(const Duration(seconds: 10));
  } catch (_) {
    return null;
  } finally {
    c.close(force: true);
  }
}

// پاسخ HTML با کد 403 یعنی خودِ گوگل درخواست را (بر اساس IP/منطقه) بلاک کرده
bool _geminiHtmlBlock(int code, String body) {
  final b = body.trimLeft().toLowerCase();
  return code == 403 && (b.startsWith('<!doctype') || b.startsWith('<html'));
}

// null = بلاک HTML (مسیر بعدی امتحان شود)
Future<String?> _geminiTry(String route, String prompt) async {
  final c = HttpClient()
    ..findProxy = ((_) => route)
    ..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await c
        .postUrl(Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent'))
        .timeout(const Duration(seconds: 10));
    req.headers.set('content-type', 'application/json');
    req.headers.set('x-goog-api-key', geminiKey);
    req.add(utf8.encode(jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ]
    })));
    final res = await req.close().timeout(const Duration(seconds: 40));
    final body = await res
        .transform(const Utf8Decoder(allowMalformed: true))
        .join()
        .timeout(const Duration(seconds: 40));
    if (res.statusCode == 200) {
      try {
        final j = jsonDecode(body);
        final parts = j['candidates'][0]['content']['parts'] as List;
        final t = parts.map((p) => (p['text'] ?? '').toString()).join('\n');
        return t.trim().isEmpty ? 'پاسخ خالی بود.' : t.trim();
      } catch (_) {
        throw Exception('پاسخ Gemini قابل خواندن نبود');
      }
    }
    final low = body.toLowerCase();
    if (low.contains('location is not supported') ||
        low.contains('not supported for the api use')) {
      throw GeminiLocationError();
    }
    if (_geminiHtmlBlock(res.statusCode, body)) return null;
    final cut = body.length > 160 ? body.substring(0, 160) : body;
    throw Exception('Gemini ${res.statusCode}: $cut');
  } finally {
    c.close(force: true);
  }
}

Future<String> geminiAsk(String prompt) async {
  // حالت پروکسی: اول پورت محلی؛ حالت VPN: اول تونل، بعد پورت محلی
  final routes = proxyMode
      ? <String>['PROXY 127.0.0.1:$httpProxyPort', 'DIRECT']
      : <String>['DIRECT', 'PROXY 127.0.0.1:$httpProxyPort'];
  var blocked = false;
  Object? lastErr;
  for (final r in routes) {
    try {
      final t = await _geminiTry(r, prompt);
      if (t != null) return t;
      blocked = true;
    } on IOException catch (e) {
      lastErr = e;
    } on TimeoutException catch (e) {
      lastErr = e;
    }
  }
  if (blocked) throw GeminiLocationError(); // یعنی IP این سرور مسدود است
  throw lastErr ?? Exception('Gemini بدون پاسخ');
}

// پاسخ Gemini را به «متن» و «تنظیمات پیشنهادی» جدا می‌کند
void aiShow(String raw) {
  var text = raw;
  aiActionName = '';
  final sug = <String, int>{};
  final i = raw.lastIndexOf('SETTINGS:');
  if (i >= 0) {
    text = raw.substring(0, i).trim();
    try {
      final tail = raw.substring(i + 9);
      final a = tail.indexOf('{'), b = tail.lastIndexOf('}');
      if (a >= 0 && b > a) {
        final j = jsonDecode(tail.substring(a, b + 1)) as Map;
        const okKeys = {
          'proto_vless',
          'proto_vmess',
          'proto_trojan',
          'proto_ss',
          'autoSpeed',
          'savedFirst',
          'smartOrder',
          'autoCycle',
          'autoUpgrade',
          'fastDelay',
          'badPingSwitch',
          'ipMode',
          'iranRoute',
          'fastWorkers',
          'bgWorkers',
          'timeout',
          'batch',
          'minSpeedKB',
          'badPingMs',
          'speedTopN'
        };
        if (j['action'] is String) aiActionName = j['action'] as String;
        j.forEach((k, v) {
          if (okKeys.contains(k) || (k is String && k.startsWith('num_'))) {
            if (v is num) {
              sug[k as String] = v.toInt();
            } else if (v is bool) {
              sug[k as String] = v ? 1 : 0;
            }
          }
        });
      }
    } catch (_) {}
  }
  text = text.replaceAll('```json', '').replaceAll('```', '').trim();
  aiText.value = text.isEmpty ? raw : text;
  aiSuggest.value = sug;
}

// ======================= آینه‌ی لیست‌ها (jsDelivr) =======================
// اگر raw.githubusercontent.com باز نشد، همان فایل از jsDelivr گرفته می‌شود.
int _rawFail = 0, _rawOk = 0;

String? _mirrorOf(String u) {
  if (!u.startsWith(_gh)) return null;
  final p = u.substring(_gh.length).split('/');
  if (p.length < 4) return null;
  var rest = p.sublist(2);
  if (rest.length >= 3 && rest[0] == 'refs' && rest[1] == 'heads') {
    rest = rest.sublist(2);
  }
  if (rest.length < 2) return null;
  return 'https://cdn.jsdelivr.net/gh/${p[0]}/${p[1]}@${rest.first}/${rest.sublist(1).join('/')}';
}

Future<http.Response> getListMirror(String u) async {
  final m = _mirrorOf(u);
  // raw کاملاً بسته است: مستقیم سراغ آینه برو
  final skipRaw = m != null && _rawOk == 0 && _rawFail >= 6;
  if (!skipRaw) {
    try {
      final r =
          await http.get(Uri.parse(u)).timeout(const Duration(seconds: 8));
      _rawOk++;
      return r;
    } catch (_) {
      _rawFail++;
    }
  }
  if (m != null) {
    try {
      return await http
          .get(Uri.parse(m))
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }
  return http.Response('', 599);
}

// ======================= لینک اشتراک (subscription) =======================
Future<List<Server>> fetchSubscription(String url) async {
  try {
    final r =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) return [];
    var body = r.body.trim();
    if (!body.contains('://')) {
      try {
        body = utf8.decode(base64
            .decode(base64.normalize(body.replaceAll(RegExp(r'\s'), ''))));
      } catch (_) {
        return [];
      }
    }
    final out = <Server>[];
    final seen = <String>{};
    for (final l in npvSplit(body)) {
      final s = Server.parse(l);
      if (s != null && seen.add(s.key)) out.add(s);
    }
    return out;
  } catch (e) {
    logError(e);
    return [];
  }
}

// ======================= بخش‌های رابط و منطق (روی State) =======================
extension HomeExtras on _HomePageState {
  Future<void> importSubscription(BuildContext ctx, String url) async {
    Navigator.pop(ctx);
    _set('دریافت اشتراک...');
    final list = (await fetchSubscription(url)).take(300).toList();
    if (list.isEmpty) {
      _set('اشتراک خالی بود یا دریافت نشد');
      return;
    }
    for (final s in list) {
      favs[s.key] = s.link;
    }
    _saveFavs();
    pending.insertAll(0, list);
    _set('${list.length} کانفیگ از اشتراک اضافه شد');
  }

  void subDialog() {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('🔗 افزودن لینک اشتراک'),
          content: TextField(
            controller: c,
            maxLines: 3,
            minLines: 1,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(hintText: 'https://...'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('لغو')),
            FilledButton(
              onPressed: () {
                final u = c.text.trim();
                if (!u.startsWith('http')) return;
                importSubscription(ctx, u);
              },
              child: const Text('دریافت'),
            ),
          ],
        ),
      ),
    );
  }

  // فقط آمار کلی؛ آدرس سرور، لینک و UUID هرگز ارسال نمی‌شود
  String aiPrompt() {
    final sb = StringBuffer();
    final c = current;
    sb.writeln('Connected: $connected');
    if (c != null) {
      sb.writeln('Current kind: ${_profKey(c)} ping=${c.ping}ms '
          'speed=${(c.speed ?? 0).toStringAsFixed(2)}MB/s');
    }
    sb.writeln(
        'Servers: list=$total queue=${pending.length} healthy=${_usable().length}');
    sb.writeln('Tests: total=$totalTested ok=$totalOk '
        'fast=$fastOk/$fastTested standby=$bgOk/$bgTested');
    final pk = profTested.keys.toList()
      ..sort((a, b) => profTested[b]!.compareTo(profTested[a]!));
    sb.writeln(
        'Success by kind (protocol|transport|security|port443): ok/tested');
    for (final k in pk.take(8)) {
      sb.writeln(' $k: ${profOk[k] ?? 0}/${profTested[k]}');
    }
    final byOwner = <String, List<int>>{};
    srcTested.forEach((u, t) {
      final o =
          u.startsWith(_gh) ? u.substring(_gh.length).split('/').first : u;
      final e = byOwner.putIfAbsent(o, () => [0, 0]);
      e[0] += t;
      e[1] += srcOkN[u] ?? 0;
    });
    final owners = byOwner.entries.toList()
      ..sort((a, b) => b.value[0].compareTo(a.value[0]));
    sb.writeln('Sources (ok/tested):');
    for (final e in owners.take(8)) {
      sb.writeln(' ${e.key}: ${e.value[1]}/${e.value[0]}');
    }
    sb.writeln('Settings: fastWorkers=$fastWorkers bgWorkers=$bgWorkers '
        'timeout=${delayTimeout.inSeconds}s batch=$batchSize '
        'minSpeedKB=$minSpeedKB badPingMs=$badPingMs speedTopN=$speedTopN '
        'iranRoute=$iranRoute geoip=$iranGeoip '
        'protocols=${protoSel.isEmpty ? "all" : protoSel.join("+")} '
        'autoSpeed=$autoSpeed savedFirst=$savedFirst smartOrder=$smartOrder '
        'autoCycle=$autoCycle autoUpgrade=$autoUpgrade fastDelay=$fastDelay '
        'badPingSwitch=$badPingSwitch ipMode=$ipMode');
    sb.writeln('Last switch reason: ${lastWhy.isEmpty ? '-' : lastWhy}');
    for (final s in _usable().take(5)) {
      sb.writeln(' standby: ${_profKey(s)} ping=${s.ping}ms '
          'speed=${(s.speed ?? 0).toStringAsFixed(2)}MB/s');
    }
    sb.writeln('Last error: ${errorLog.value.isEmpty ? '-' : errorLog.value}');
    sb.writeln('Numeric options (num_<id>=value [range] default): ' +
        numOpts.map((o) => 'num_${o.id}=${o.get()} [${o.lo}-${o.aiHi}] def ${o.def}').join(', '));
    return 'You are a network assistant inside a censorship-circumvention VPN '
        'client used in Iran. Using ONLY the stats below, answer in Persian, '
        'max 12 short lines: (1) which protocol/transport kinds and sources '
        'work best on this network and how the app can find servers faster '
        'and better, (2) which settings to change and to what values, '
        '(3) likely reasons for drops or slowness. Do not invent data.\n'
        'At the very end add ONE last line exactly in this format (only the '
        'keys you want to change, integers only, no markdown):\n'
        'SETTINGS: {"fastWorkers":4,"bgWorkers":4,"timeout":8,"batch":200,'
        '"minSpeedKB":200,"badPingMs":3000,"speedTopN":3}\n'
        'Allowed keys and ranges: fastWorkers 1-1000, bgWorkers 1-1000, timeout 1-1000, '
        'batch 1-1000, minSpeedKB 0-1000, badPingMs 70-7000, speedTopN 1-1000.\n'
        'Every numeric option can also be set with key num_<id> (integer inside the range shown in the stats). Change one or two at a time.\n'
        'Also allowed, 1 = on and 0 = off: proto_vless, proto_vmess, '
        'proto_trojan, proto_ss (protocols to test; all 0 = every protocol), '
        'autoSpeed, savedFirst, smartOrder, autoCycle, autoUpgrade, '
        'fastDelay, badPingSwitch, ipMode, iranRoute.\n'
        'You may also put ONE string key "action" inside the same SETTINGS '
        'JSON: "switch_best" (move now to the fastest standby server), '
        '"refresh_lists" (download new lists and search again), '
        '"reset_blacklist" (give failed servers another chance), or "none".\n'
        'Be proactive: if the current speed or ping is poor and faster '
        'standby servers exist, use switch_best; if few servers are healthy '
        'or the success rate is very low, use refresh_lists.\n\n'
        '$sb';
  }

  // auto = بعد از اتصال به‌صورت خودکار (هیچ‌وقت سرور را عوض نمی‌کند)
  Future<void> aiAnalyze({bool auto = false}) async {
    if (aiLoading.value) return;
    if (geminiKey.isEmpty) {
      if (!auto) aiText.value = 'اول کلید API را وارد و ذخیره کن.';
      return;
    }
    if (!connected) {
      if (!auto) {
        aiText.value =
            'اول به VPN وصل شو (ترجیحاً با دکمه‌ی «اتصال به سرور مخصوص AI»)، چون Gemini بدون سرور مناسب باز نمی‌شود.';
      }
      return;
    }
    aiLoading.value = true;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        if (!auto) {
          aiText.value = attempt == 0
              ? 'در حال ارسال آمار به Gemini...'
              : 'این سرور برای Gemini جواب نداد؛ تعویض به سرور مخصوص AI...';
        }
        try {
          aiShow(await geminiAsk(aiPrompt()));
          applyAiSuggest();
          if (auto && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('🤖 تحلیل دستیار آماده شد'),
              duration: const Duration(seconds: 8),
              action: SnackBarAction(
                  label: 'نمایش', onPressed: () => this.aiSheet()),
            ));
          }
          return;
        } on GeminiLocationError {
          current?.ai = false;
          if (auto) return; // خودکار: اتصال را به‌هم نمی‌زنیم
          final has =
              _usable().any((s) =>
              s.ai == true && s.ping != null && !identical(s, current));
          if (attempt == 1 || !has) {
            aiText.value =
                'Gemini روی این سرور باز نمی‌شود و سرور AI سالمی هم آماده نیست. ردیف «🤖 سرورهای مخصوص هوش مصنوعی» را بزن تا جستجو کند، بعد دوباره امتحان کن.';
            return;
          }
          await connectRow('r:ai');
          if (!connected) {
            aiText.value = 'اتصال به سرور AI انجام نشد.';
            return;
          }
        }
      }
    } catch (e) {
      if (!auto) {
        aiText.value = 'خطا: ${e.toString().replaceFirst('Exception: ', '')}';
      }
    } finally {
      aiLoading.value = false;
    }
  }

  // چند ثانیه بعد از اتصال، دستیار خودش اتصال را بررسی می‌کند (حداکثر هر ۲۰ دقیقه)
  void autoAiAfterConnect() {
    if (geminiKey.isEmpty || !aiSession) return;
    if (DateTime.now().difference(_lastAutoAi) < const Duration(minutes: 20)) {
      return;
    }
    Future.delayed(const Duration(seconds: 40), () {
      if (!mounted || !connected || aiLoading.value) return;
      _lastAutoAi = DateTime.now();
      aiAnalyze(auto: true);
    });
  }

  // پیشنهادهای دستیار را روی تنظیمات اپ اعمال می‌کند
  void aiAutopilotStart() {
    aiLoop?.cancel();
    aiLoop =
        Timer.periodic(const Duration(minutes: 3), (_) => aiAutopilotTick());
    Future.delayed(const Duration(seconds: 45), aiAutopilotTick);
  }

  Future<void> aiAutopilotTick() async {
    if (!aiSession ||
        !mounted ||
        !connected ||
        busy ||
        switching ||
        aiLoading.value ||
        geminiKey.isEmpty) {
      return;
    }
    aiLoading.value = true;
    try {
      aiShow(await geminiAsk(aiPrompt()));
      applyAiSuggest();
      await aiRunAction();
    } on GeminiLocationError {
      current?.ai = false;
      if (_usable().any((s) => s.ai == true && !identical(s, current))) {
        await connectRow('r:ai');
      }
    } catch (e) {
      logError(e);
    } finally {
      aiLoading.value = false;
    }
  }

  Future<void> aiRunAction() async {
    final a = aiActionName;
    aiActionName = '';
    if (a == 'switch_best') {
      final l = _pickList();
      if (l.isNotEmpty && !busy && !switching) {
        lastWhy = 'تصمیم دستیار';
        await _swapTo(l.first);
      }
    } else if (a == 'refresh_lists') {
      listTime = null;
      pending = [];
      failed.clear();
      lastFetchTry = DateTime.fromMillisecondsSinceEpoch(0);
      await _loadPending(bg: true, exhausted: true);
    } else if (a == 'reset_blacklist') {
      failed.clear();
      for (final g in good) {
        g.badAt = null;
      }
    }
  }

  void applyAiSuggest() {
    final m = aiSuggest.value;
    if (m.isEmpty) return;
    int g(String k, int d, int lo, int hi) =>
        (m.containsKey(k) ? m[k]!.clamp(lo, hi).toInt() : d);
    fastWorkers = g('fastWorkers', fastWorkers, 1, 1000);
    bgWorkers = g('bgWorkers', bgWorkers, 1, 1000);
    delayTimeout =
        Duration(seconds: g('timeout', delayTimeout.inSeconds, 1, 1000));
    batchSize = g('batch', batchSize, 1, 1000);
    minSpeedKB = g('minSpeedKB', minSpeedKB, 0, 1000);
    badPingMs = g('badPingMs', badPingMs, 70, 7000);
    speedTopN = g('speedTopN', speedTopN, 1, 1000);
    applyNumSuggest(m);
    const protoKeys = ['vless', 'vmess', 'trojan', 'ss'];
    if (protoKeys.any((p) => m.containsKey('proto_$p'))) {
      protoSel.clear();
      for (final p in protoKeys) {
        if (m['proto_$p'] == 1) protoSel.add(p);
      }
      pending = [];
    }
    if (m.containsKey('autoSpeed')) autoSpeed = m['autoSpeed'] == 1;
    if (m.containsKey('savedFirst')) savedFirst = m['savedFirst'] == 1;
    if (m.containsKey('smartOrder')) smartOrder = m['smartOrder'] == 1;
    if (m.containsKey('autoCycle')) autoCycle = m['autoCycle'] == 1;
    if (m.containsKey('autoUpgrade')) autoUpgrade = m['autoUpgrade'] == 1;
    if (m.containsKey('fastDelay')) fastDelay = m['fastDelay'] == 1;
    if (m.containsKey('badPingSwitch')) {
      badPingSwitch = m['badPingSwitch'] == 1;
    }
    if (m.containsKey('ipMode')) ipMode = m['ipMode'] == 1;
    if (m.containsKey('iranRoute')) iranRoute = m['iranRoute'] == 1;
    aiSuggest.value = <String, int>{};
    _saveSettings();
    _set('✅ تنظیمات پیشنهادی دستیار اعمال شد');
  }

  // دکمه‌ی دستیار روی صفحه‌ی اصلی (زیر پنل سرعت)
  Widget aiBar() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => this.aiSheet(),
            icon: const Icon(Icons.smart_toy_outlined, size: 18),
            label: const Text('🤖 دستیار هوشمند (Gemini)'),
          ),
        ),
      );

  void aiSheet() {
    final k = TextEditingController(text: geminiKey);
    final m = TextEditingController(text: geminiModel);
    Future<void> save() async {
      geminiKey = k.text.trim();
      final mm = m.text.trim().replaceFirst(RegExp(r'^models/'), '');
      geminiModel = mm.isEmpty ? 'gemini-flash-latest' : mm;
      for (final g in good) {
        g.ai = null; // با API دوباره سنجیده می‌شوند
      }
      await saveGeminiPrefs();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🤖 دستیار هوشمند (Gemini)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 6),
                    const Text(
                        'کلید رایگان را از aistudio.google.com بگیر. کلید فقط روی همین گوشی ذخیره می‌شود (رمزنگاری‌شده نیست). '
                        'فقط آمار کلی اتصال ارسال می‌شود، نه آدرس سرور یا لینک. '
                        'بعد از هر اتصال، دستیار خودش اتصال را بررسی می‌کند و می‌گوید چطور سرور بهتر پیدا شود؛ '
                        'با دکمه‌ی «اعمال» تنظیمات پیشنهادی‌اش را روی اپ می‌گذاری. '
                        'Gemini با هر سروری باز نمی‌شود؛ برنامه خودش سرور مناسب را انتخاب می‌کند.',
                        style: TextStyle(fontSize: 12, color: Color(0xFFCDD1D8))),
                    TextField(
                        controller: k,
                        obscureText: true,
                        textDirection: TextDirection.ltr,
                        decoration:
                            const InputDecoration(labelText: 'کلید API')),
                    TextField(
                        controller: m,
                        textDirection: TextDirection.ltr,
                        decoration:
                            const InputDecoration(labelText: 'نام مدل')),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      FilledButton(
                          onPressed: () async {
                            await save();
                            _set('تنظیمات Gemini ذخیره شد');
                          },
                          child: const Text('ذخیره')),
                      FilledButton.tonal(
                          onPressed: () async {
                            await save();
                            aiAnalyze();
                          },
                          child: const Text('📊 تحلیل اتصال')),
                      OutlinedButton(
                          onPressed: () async {
                            await save();
                            if (ctx.mounted) Navigator.pop(ctx);
                            aiSession = true;
                            aiAutopilotStart();
                            connectRow('r:ai');
                          },
                          child: const Text('اتصال به سرور مخصوص AI')),
                    ]),
                    ValueListenableBuilder<bool>(
                        valueListenable: aiLoading,
                        builder: (_, l, __) => l
                            ? const Padding(
                                padding: EdgeInsets.only(top: 10),
                                child: LinearProgressIndicator())
                            : const SizedBox.shrink()),
                    ValueListenableBuilder<String>(
                        valueListenable: aiText,
                        builder: (_, t, __) => t.isEmpty
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: SelectableText(t))),
                    ValueListenableBuilder<Map<String, int>>(
                        valueListenable: aiSuggest,
                        builder: (_, sg, __) => sg.isEmpty
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          'تنظیمات پیشنهادی: ${sg.entries.map((e) => '${e.key}=${e.value}').join(' • ')}',
                                          textDirection: TextDirection.ltr,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFFCDD1D8))),
                                      const SizedBox(height: 6),
                                      FilledButton(
                                          onPressed: () {
                                            applyAiSuggest();
                                            Navigator.pop(ctx);
                                          },
                                          child: Text(
                                              '✅ اعمال تنظیمات پیشنهادی (${sg.length})')),
                                    ]),
                              )),
                  ]),
            ),
          ),
        ),
      ),
    );
  }
}


// NUMPATCH ======================= عددهای قابل تنظیم =======================
// first search (used by patch_fast.py): it stops at the FIRST healthy server
// (for the Gemini row: the first Gemini server). Safety: after [firstCapSec]
// seconds it goes on with the ones found.
int firstCapSec = 120;

// the AI assistant must not change these
const aiLockedNums = {'firstCapSec'};

class NumOpt {
  final String id, title;
  final int lo, hi, def, aiHi; // aiHi = the highest value the AI may set
  final bool extra; // shown in the extra section
  final int Function() get;
  final void Function(int) set;
  NumOpt(this.id, this.title, this.lo, this.hi, this.def, this.aiHi,
      this.extra, this.get, this.set);
}

final List<NumOpt> numOpts = [
  NumOpt('fastWorkers', 'تست همزمان (جستجوی اول)', 1, 1000, 50, 50, false,
      () => fastWorkers, (v) => fastWorkers = v),
  NumOpt('bgWorkers', 'تست همزمان (وقتی وصل است)', 1, 1000, 2, 2, false,
      () => bgWorkers, (v) => bgWorkers = v),
  NumOpt('timeout', 'تایم‌اوت هر تست (ثانیه)', 1, 1000, 8, 20, false,
      () => delayTimeout.inSeconds, (v) => delayTimeout = Duration(seconds: v)),
  NumOpt('batch', 'اندازه دسته', 1, 1000, 300, 1000, false,
      () => batchSize, (v) => batchSize = v),
  NumOpt('minPingMs', 'حداقل پینگ معتبر', 0, 1000, 0, 300, false,
      () => minPingMs, (v) => minPingMs = v),
  NumOpt('speedTopN', 'تعداد سرور برای تست سرعت', 1, 1000, 3, 10, false,
      () => speedTopN, (v) => speedTopN = v),
  NumOpt('badPingMs', 'پینگ بد از', 70, 7000, 3000, 7000, false,
      () => badPingMs, (v) => badPingMs = v),
  NumOpt('minSpeedKB', 'تعویض اگر سرعت کمتر از', 0, 50000, 300, 1000, false,
      () => minSpeedKB, (v) => minSpeedKB = v),
  NumOpt('listRefreshMin', 'هر چند دقیقه لیست جدید', 1, 1000, 30, 240, false,
      () => listRefreshMin, (v) => listRefreshMin = v),
  NumOpt('failMin', 'سرور خراب تا چند دقیقه تست نشود', 1, 1000, 20, 240, false,
      () => failMin, (v) {
    failMin = v;
    failWindow = Duration(minutes: v);
  }),
  NumOpt('recheckMin', 'بررسی دوباره سرورهای سالم (دقیقه)', 1, 1000, 3, 60,
      false, () => recheckMin, (v) {
    recheckMin = v;
    recheckAfter = Duration(minutes: v);
  }),
  // ----- 12 new options -----
  NumOpt('tcpWorkers', 'پیش‌فیلتر TCP همزمان', 1, 1000, 150, 500, true,
      () => tcpWorkers, (v) => tcpWorkers = v),
  NumOpt('tcpTimeout', 'تایم‌اوت TCP (دهم ثانیه)', 1, 1000, 25, 40, true,
      () => tcpTimeout.inMilliseconds ~/ 100,
      (v) => tcpTimeout = Duration(milliseconds: v * 100)),
  NumOpt('maxPerSource', 'حداکثر سرور از هر منبع', 1, 1000, 500, 1000, true,
      () => maxPerSource, (v) => maxPerSource = v),
  NumOpt('fetchWorkers', 'دانلود همزمان لیست‌ها', 1, 1000, 24, 48, true,
      () => fetchWorkers, (v) => fetchWorkers = v),
  NumOpt('fetchDeadline', 'مهلت دانلود لیست‌ها (ثانیه)', 1, 1000, 25, 120, true,
      () => fetchDeadline.inSeconds,
      (v) => fetchDeadline = Duration(seconds: v)),
  NumOpt('firstBatchSize', 'اندازه دسته‌ی اول', 1, 1000, 100, 300, true,
      () => firstBatchSize, (v) => firstBatchSize = v),
  NumOpt('standbyBatchSize', 'اندازه دسته (وقتی وصل است)', 1, 1000, 100, 600,
      true, () => standbyBatchSize, (v) => standbyBatchSize = v),
  NumOpt('maxBatches', 'حداکثر تعداد دسته در هر جستجو', 1, 1000, 15, 100, true,
      () => maxBatches, (v) => maxBatches = v),
  NumOpt('watchFailLimit', 'تعداد پینگ ناموفق تا تعویض', 1, 1000, 3, 6, true,
      () => watchFailLimit, (v) => watchFailLimit = v),
  NumOpt('badPingLimit', 'تعداد پینگ بد تا تعویض', 1, 1000, 3, 6, true,
      () => badPingLimit, (v) => badPingLimit = v),
  NumOpt('missLimit', 'تعداد شکست تا حذف سرور سالم', 1, 1000, 3, 8, true,
      () => missLimit, (v) => missLimit = v),
  NumOpt('watchEvery', 'فاصله‌ی چک اتصال (ثانیه)', 1, 1000, 5, 30, true,
      () => watchEvery.inSeconds, (v) => watchEvery = Duration(seconds: v)),
  // ----- first search: time cap -----
  NumOpt('firstCapSec', 'سقف زمان جستجوی اول (ثانیه)', 1, 1000, 120, 120, true,
      () => firstCapSec, (v) => firstCapSec = v),
];

// one-time: an old saved batch size (e.g. 150) is replaced by 300, so the new
// default also takes effect on phones that already saved their numbers.
// After that, whatever the user types is kept.
Future<void> loadNumPrefs(SharedPreferences p) async {
  await _loadNumPrefs0(p);
  if (p.getBool('batch300') != true) {
    batchSize = 300;
    await p.setBool('batch300', true);
    saveNumPrefs();
  }
}

Future<void> _loadNumPrefs0(SharedPreferences p) async {
  final str = p.getString('numx');
  if (str == null) {
    for (final o in numOpts) {
      o.set(o.def);
    }
    return;
  }
  try {
    final j = jsonDecode(str) as Map;
    for (final o in numOpts) {
      final v = j[o.id];
      if (v is num) o.set(v.toInt().clamp(o.lo, o.hi).toInt());
    }
  } catch (e) {
    logError(e);
  }
}

Future<void> saveNumPrefs() async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        'numx', jsonEncode({for (final o in numOpts) o.id: o.get()}));
  } catch (e) {
    logError(e);
  }
}

List<Widget> numSettingsItems(
  Widget Function(String) head,
  Widget Function(
          String, String, double, double, double, int, void Function(double))
      row,
) =>
    [
      head('🔧 تنظیمات عددی بیشتر (هر عدد را می‌توانی تایپ کنی)'),
      for (final o in numOpts.where((o) => o.extra))
        row(
            o.title,
            '${o.get()}',
            o.get().toDouble(),
            o.lo.toDouble(),
            (o.def * 4).clamp(o.lo + 10, o.hi).toDouble(),
            0,
            (x) => o.set(x.round())),
    ];

extension NumHomeExtras on _HomePageState {
  void resetNumbers() {
    for (final o in numOpts) {
      o.set(o.def);
    }
    saveNumPrefs();
    _saveSettings();
    autoTune = false; // AUTOTUNEPATCH: reset = manual numbers
    autoTuneSave();
    _set('✅ همه‌ی عددها به پیش‌فرض برگشتند');
  }

  Widget resetNumButton(StateSetter setS) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => setS(resetNumbers),
            icon: const Icon(Icons.restart_alt),
            label: const Text('↩️ برگرداندن همه‌ی عددها به پیش‌فرض'),
          ),
        ),
      );

  // the AI may only move a number inside [lo, aiHi]
  void applyNumSuggest(Map<String, int> m) {
    for (final o in numOpts) {
      if (aiLockedNums.contains(o.id)) continue;
      final v = m['num_${o.id}'];
      if (v != null) o.set(v.clamp(o.lo, o.aiHi).toInt());
    }
    saveNumPrefs();
  }
}


// TUNEDPATCH ===================== مقدارهای بهینه (یک‌بار) =====================
const Map<String, dynamic> _tunedSettings = {
  't': 8,
  'bw2': 2,
  'st': 3,
  'bp': 3000,
  'ms': 300,
  'lr': 30,
  'fm': 20,
  'rm': 3,
  'a2': true,
  'i': true,
  'cip': true,
  'sdns': true,
  'sf': true,
  'so': true,
  'ac': true,
  'o': true,
  'u': true,
  'fd': true,
  'bps': true,
  'npv': true,
  'irm': true,
  'bq': true,
  'lan': true,
  'ro': false,
  'frg': false,
  'mux': false,
  'ig': false,
};
const Map<String, int> _tunedNums = {
  'bgWorkers': 2,
  'timeout': 8,
  'speedTopN': 3,
  'badPingMs': 3000,
  'minSpeedKB': 300,
  'listRefreshMin': 30,
  'failMin': 20,
  'recheckMin': 3,
  'tcpWorkers': 150,
  'tcpTimeout': 25,
  'maxPerSource': 500,
  'fetchDeadline': 25,
  'firstBatchSize': 100,
  'standbyBatchSize': 100,
  'watchFailLimit': 3,
  'badPingLimit': 3,
};

// settings saved by an older build get the tuned values ONCE; after that the
// user's own changes are kept. Auto tune, proxy mode and the parallel test of
// the first search (fastWorkers) are never touched.
Future<String?> tunedSettings(SharedPreferences p) async {
  try {
    if (p.getBool('tuned_v1') != true) {
      final st = p.getString('settings');
      if (st != null) {
        final j = jsonDecode(st);
        if (j is Map) {
          final m = Map<String, dynamic>.from(j);
          _tunedSettings.forEach((k, v) => m[k] = v);
          await p.setString('settings', jsonEncode(m));
        }
      }
      final nx = p.getString('numx');
      if (nx != null) {
        final j = jsonDecode(nx);
        if (j is Map) {
          final m = Map<String, dynamic>.from(j);
          _tunedNums.forEach((k, v) => m[k] = v);
          await p.setString('numx', jsonEncode(m));
        }
      }
      await p.setBool('tuned_v1', true);
    }
  } catch (e) {
    logError(e);
  }
  return p.getString('settings');
}
