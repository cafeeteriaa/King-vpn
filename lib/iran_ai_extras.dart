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
  'domain:snapp.ir',
  'domain:snapp.site',
  'domain:divar.ir',
  'domain:sheypoor.com',
  'domain:bankmellat.ir',
  'domain:bmi.ir',
  'domain:shaparak.ir',
  'domain:myket.ir',
  'domain:cafebazaar.ir',
  'domain:rubika.ir',
  'domain:soroush-app.ir',
  'domain:irancell.ir',
  'domain:mci.ir',
  'domain:rightel.ir',
  'domain:shatel.ir',
  'domain:asiatech.ir',
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
  } catch (e, stk) {
    logError(e, stk);
    return cfg;
  }
}

List<Widget> iranSettingsItems(
  Widget Function(String) head,
  Widget Function(String, bool, void Function(bool), {String? sub}) sw,
) =>
    [
      head('🇮🇷 مسیریابی هوشمند ایران'),
      sw('سایت‌های ایرانی مستقیم بروند', iranRoute, (v) { _markUserTouched(const ['iranRoute']); iranRoute = v; },
          sub: 'دامنه‌های .ir و چند سایت پرکاربرد بدون VPN باز می‌شوند'),
      sw('قانون IP ایران (geoip، تجربی)', iranGeoip, (v) => iranGeoip = v,
          sub: 'اگر با روشن کردنش اتصال برقرار نشد، خاموشش کن'),
      sw('جعل SNI', sniSpoofAll, (v) => sniSpoofAll = v, // SNIDEF
          sub: 'فقط روی کانفیگ‌های CDN+TLS؛ برای سرورهای مستقیم بی‌اثر است'),
    ];

// ======================= Local-only King AI =======================
DateTime? _aiApplyAt; // زمان آخرین اعمال تنظیمات خلبان
String aiProvider = 'local';
String aiLastProvider = '';

const _secure = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

String? _nz(String? value) => (value == null || value.isEmpty) ? null : value;

Future<Map<String, String?>> _secReadMany(List<String> keys) async {
  final result = <String, String?>{};
  try {
    await Future.wait(keys.map((key) async {
      result[key] = await _secure.read(key: key);
    })).timeout(const Duration(seconds: 3));
  } catch (error) {
    errJournalAdd(error, kind: 'SILENT-FILE');
  }
  return result;
}

Future<void> _secApply(Map<String, String?> values) async {
  try {
    await Future.wait(values.entries.map((entry) => entry.value == null
        ? _secure.delete(key: entry.key)
        : _secure.write(key: entry.key, value: entry.value!)))
        .timeout(const Duration(seconds: 3));
  } catch (error) {
    errJournalAdd(error, kind: 'SILENT-FILE');
  }
}

final aiText = ValueNotifier<String>('');
final aiLoading = ValueNotifier<bool>(false);
final aiSuggest = ValueNotifier<Map<String, int>>(<String, int>{});
DateTime _lastAutoAi = DateTime.fromMillisecondsSinceEpoch(0);
String aiActionName = '';

bool get _hasAnyAiKey => KingLocalAi.instance.isLoaded;
bool get _selectedAiKeyAvailable => KingLocalAi.instance.isLoaded;

/// Remove credentials and provider selections left by older builds. King now
/// uses only the on-device model; no paid API, API key, or remote LLM is used.
Future<void> loadLocalAiPrefs(SharedPreferences prefs) async {
  aiProvider = 'local';
  const legacyKeys = <String>[
    'gem_key', 'grok_key', 'claude_key', 'openai_key', 'deepseek_key',
    'gem_model', 'grok_model', 'claude_model', 'openai_model',
    'deepseek_model', 'ai_prov',
  ];
  try {
    await Future.wait(legacyKeys.map((key) => prefs.remove(key)));
  } catch (error, stack) {
    logError(error, stack);
  }
  try {
    await Future.wait(legacyKeys.map((key) => _secure.delete(key: key)))
        .timeout(const Duration(seconds: 5));
  } catch (error, stack) {
    logError(error, stack);
  }
}

Future<String> aiAsk(String prompt) async {
  aiProvider = 'local';
  aiLastProvider = 'King Local AI (on-device)';
  return KingLocalAi.instance.ask(prompt);
}

// پاسخ محلی King را به متن و تنظیمات پیشنهادی جدا می‌کند
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
        const allowedActions = {
          'switch_best', 'refresh_lists', 'reset_blacklist', 'connect',
          'enable_turbo', 'none'
        };
        if (j['action'] is String &&
            allowedActions.contains(j['action'])) {
          aiActionName = j['action'] as String;
        }
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
    } catch (e, stk) { logError(e, stk); }
  }
  text = text.replaceAll('```json', '').replaceAll('```', '').trim();
  aiText.value = text.isEmpty ? raw : text;
  aiSuggest.value = sug;
}

// ======================= آینه‌ی لیست‌ها (jsDelivr) =======================
// اگر raw.githubusercontent.com باز نشد، همان فایل از jsDelivr گرفته می‌شود.
int _rawFail = 0, _rawOk = 0;

// hosts that serve the same GitHub files; when one is blocked another may work
const _mirrorHosts = [
  'cdn.jsdelivr.net',
  'fastly.jsdelivr.net',
  'gcore.jsdelivr.net',
  'testingcf.jsdelivr.net',
  'quantil.jsdelivr.net',
  'originfastly.jsdelivr.net',
  'jsdelivr.b-cdn.net',
  'cdn.statically.io',
];

// proxies that fetch a raw GitHub URL for us (the whole URL is appended)
const _mirrorProxies = [
  'https://ghproxy.net/',
  'https://gh-proxy.com/',
  'https://ghfast.top/',
  'https://mirror.ghproxy.com/',
  'https://gh.llkk.cc/',
];

List<String> _mirrorsOf(String u) {
  if (!u.startsWith(_gh)) return const [];
  final p = u.substring(_gh.length).split('/');
  if (p.length < 4) return const [];
  var rest = p.sublist(2);
  if (rest.length >= 3 && rest[0] == 'refs' && rest[1] == 'heads') {
    rest = rest.sublist(2);
  }
  if (rest.length < 2) return const [];
  final path = rest.sublist(1).join('/');
  return [
    for (final h in _mirrorHosts)
      if (h == 'cdn.statically.io')
        'https://$h/gh/${p[0]}/${p[1]}/${rest.first}/$path'
      else
        'https://$h/gh/${p[0]}/${p[1]}@${rest.first}/$path',
    'https://raw.githack.com/${p[0]}/${p[1]}/${rest.first}/$path',
    'https://rawcdn.githack.com/${p[0]}/${p[1]}/${rest.first}/$path',
    'https://raw.gitmirror.com/${p[0]}/${p[1]}/${rest.first}/$path',
    for (final h in _mirrorProxies) '$h$u',
  ];
}

int _mirrorBest = 0; // index of the mirror host that worked last

// FORMAT-FIX: strict utf8 threw "FormatException: Unexpected extension byte"
// when a list was cut mid-character. Decode leniently instead.
http.Response _safeResp(http.Response r) => http.Response.bytes(
      // re-encode the lenient text as valid UTF-8; http.Response(String) would
      // encode it as latin1 and throw "Contains invalid characters"
      utf8.encode(utf8.decode(r.bodyBytes, allowMalformed: true)),
      r.statusCode,
      request: r.request,
      headers: r.headers,
    );

// asks every url at the same time, the first good (200) answer wins
Future<http.Response?> _raceGet(List<String> urls, Duration t) {
  final c = Completer<http.Response?>();
  var left = urls.length;
  if (left == 0) return Future.value(null);
  for (final u in urls) {
    http.get(Uri.parse(u)).timeout(t).then((r0) {
      final r = _safeResp(r0);
      if (r.statusCode == 200 && r.body.isNotEmpty && !c.isCompleted) {
        c.complete(r);
      }
    }).catchError((e) { logError(e); }).whenComplete(() {
      if (--left == 0 && !c.isCompleted) c.complete(null);
    });
  }
  return c.future;
}

Future<http.Response> getListMirror(String u) async {
  final ms = _mirrorsOf(u);
  // raw is completely blocked: go straight to the mirrors
  final skipRaw = ms.isNotEmpty && _rawOk == 0 && _rawFail >= 6;
  if (!skipRaw) {
    try {
      final r =
          await http.get(Uri.parse(u)).timeout(const Duration(seconds: 8));
      _rawOk++;
      return _safeResp(r);
    } catch (e, stk) {
      logError(e, stk);
      _rawFail++;
    }
  }
  // the mirror that worked last goes first; they are asked 4 at a time
  final order = [
    for (var k = 0; k < ms.length; k++) ms[(_mirrorBest + k) % ms.length]
  ];
  for (var i = 0; i < order.length; i += 4) {
    final grp = order.sublist(i, min(i + 4, order.length));
    final r = await _raceGet(grp, Duration(seconds: i == 0 ? 10 : 8));
    if (r != null) {
      final w = ms.indexOf(r.request?.url.toString() ?? '');
      if (w >= 0) _mirrorBest = w;
      return r;
    }
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
      } catch (e, stk) {
        logError(e, stk);
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
  } catch (e, stk) {
    logError(e, stk);
    return [];
  }
}

// ======================= بخش‌های رابط و منطق (روی State) =======================
// ======================= هشدار مصرف بالا =======================
// قبل از روشن شدن قابلیت‌های پرمصرف (دستیارها، خلبان‌ها، نت ملی، مداد جادویی) هشدار می‌دهد.
// فقط موقع روشن شدن نشان داده می‌شود، نه موقع خاموش کردن.
// true = ادامه بده، false = لغو شد
Future<bool> confirmHeavyFeature(BuildContext context, String featureName) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text('⚠️ $featureName'),
        content: const Text(
          'این قابلیت حجم اینترنت زیادی مصرف می‌کند، چون مدام سرورها را تست و جستجو می‌کند.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('متوجه شدم، ادامه')),
        ],
      ),
    ),
  );
  return ok == true;
}

extension HomeExtras on _HomePageState {
  Future<void> importSubscription(BuildContext ctx, String url) async {
    Navigator.pop(ctx);
    _set('دریافت اشتراک...');
    final list = (await fetchSubscription(url)).take(300).toList();
    if (!mounted) return;
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
    ).whenComplete(c.dispose);
  }

  // فقط آمار کلی؛ آدرس سرور، لینک و UUID هرگز ارسال نمی‌شود
  String aiPrompt() {
    final sb = StringBuffer();
    final c = current;
    sb.writeln('Connected: $connected');
    sb.writeln('Ultra=$ultraMode turbo=$turboSpeed '
        'indestructible=$indestructibleMode');
    sb.writeln('Operator: $natOpKey provider=$aiProvider lastAi=$aiLastProvider');
    sb.writeln('Mux=$muxEnabled conc=$muxConc frag=$fragEnabled');
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
    final evidence = PilotNetworkProbe.current;
    sb.writeln('Independent TLS route evidence (not proof of VPN data-plane): '
        'domestic=${evidence.domestic.name} ${evidence.domesticSuccesses}/${evidence.domesticSamples} '
        'verified=${evidence.domesticTlsReachabilityVerified} '
        'latency=${evidence.domesticLatencyMs ?? -1}ms; '
        'global=${evidence.global.name} ${evidence.globalSuccesses}/${evidence.globalSamples} '
        'verified=${evidence.globalTlsReachabilityVerified} '
        'latency=${evidence.globalLatencyMs ?? -1}ms '
        'confidence=${evidence.confidence.toStringAsFixed(2)}');
    sb.writeln('National diagnosis: ${natNetworkClassLabel(NatNetworkDiagnosis.current)}');
    if (c != null) {
      final history = NationalNetworkIntelligence.memoryFor(
          NationalNetworkIntelligence.keyOfServer(c));
      sb.writeln('Current endpoint history: success=${history.successes}/${history.attempts} '
          'failStreak=${history.failStreak} stable=${history.stableSuccesses} '
          'score=${NationalNetworkIntelligence.scoreFor(NationalNetworkIntelligence.keyOfServer(c)).toStringAsFixed(1)}');
    }
    return 'You are a network assistant inside a censorship-circumvention VPN '
        'client used in Iran. Use only the measured statistics and the independent domestic/global TLS evidence above. '
        'A TLS handshake is reachability evidence, not proof that VPN tunnel traffic works. '
        'Never infer network class from one endpoint or one failed probe; preserve the current strategy when evidence is incomplete. '
        'Do not use Telegram, YouTube, or Instagram availability as a universal health gate. '
        'Using ONLY the stats below, answer in Persian, '
        'max 12 short lines: (1) which protocol/transport kinds and sources '
        'work best on this network and how the app can find servers faster '
        'and better, (2) which settings to change and to what values, '
        '(3) likely reasons for drops or slowness. Do not invent data.\n'
        'At the very end add ONE last line exactly in this format (only the '
        'keys you want to change, integers only, no markdown):\n'
        'SETTINGS: {"fastWorkers":3,"bgWorkers":1,"timeout":8,"batch":200,'
        '"minSpeedKB":200,"badPingMs":3000,"speedTopN":3}\n'
        'Allowed keys and ranges: fastWorkers 1-20, bgWorkers 1-3, timeout 3-45, '
        'batch 1-300, minSpeedKB 0-1000, badPingMs 70-7000, speedTopN 1-10.\n'
        'Every numeric option can also be set with key num_<id> (integer inside the range shown in the stats). Change one or two at a time.\n'
        'Also allowed, 1 = on and 0 = off: proto_vless, proto_vmess, '
        'proto_trojan, proto_ss (protocols to test; all 0 = every protocol), '
        'autoSpeed, savedFirst, smartOrder, autoCycle, autoUpgrade, '
        'fastDelay, badPingSwitch, ipMode, iranRoute.\n'
        'You may also put ONE string key "action" inside the same SETTINGS '
        'JSON: "switch_best" (move now to the fastest standby server), '
        '"refresh_lists" (download new lists and search again), '
        '"reset_blacklist" (give failed servers another chance), '
        '"connect" (start full server search and connect), '
        '"enable_turbo" (max throughput levers), '
        'or "none".\n'
        'Be proactive: if not connected use connect; if speed is poor use '
        'switch_best; if few healthy servers use refresh_lists; otherwise use connect.\n'
        'Suggest only the allowlisted settings and toggles, changing one or two at a time. '
        'Prefer higher throughput (Mux on, Fragment off) only when '
        'the tunnel already works; prefer low data when searching lists.\n\n'
        '$sb';
  }

  // auto = بعد از اتصال به‌صورت خودکار (هیچ‌وقت سرور را عوض نمی‌کند)
  Future<void> aiAnalyze({bool auto = false}) async {
    if (aiLoading.value) return;
    if (!_hasAnyAiKey) {
      if (!auto) {
        aiText.value = 'ابتدا مدل هوش مصنوعی داخلی را از تنظیمات دانلود و بارگذاری کن.';
      }
      return;
    }
    if (!connected) {
      if (!auto) {
        aiText.value = 'برای تحلیل زنده اتصال، ابتدا VPN را وصل کن؛ تحلیل کد محلی به VPN نیاز ندارد.';
      }
      return;
    }
    aiLoading.value = true;
    try {
      aiText.value = 'در حال تحلیل محلی وضعیت اتصال...';
      final answer = await aiAsk(aiPrompt());
      if (auto && (!aiSession || !localPilotOn)) return;
      aiShow(answer);
      if (aiLastProvider.isNotEmpty && !auto) {
        aiText.value = '[$aiLastProvider]\n${aiText.value}';
      }
      // Manual analysis only proposes changes; the user presses Apply.
      if (auto && aiSession && localPilotOn) applyAiSuggest();
      if (auto && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('🤖 تحلیل ${aiLastProvider} آماده شد'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'نمایش',
            onPressed: () => this.aiSheet(),
          ),
        ));
      }
    } catch (e, st) {
      errJournalAdd(e, st: st);
      if (!auto) aiText.value = 'خطای هوش مصنوعی محلی: $e';
    } finally {
      aiLoading.value = false;
    }
  }

  // چند ثانیه بعد از اتصال، دستیار خودش اتصال را بررسی می‌کند (حداکثر هر ۲۰ دقیقه)
  void autoAiAfterConnect() {
    if (!_hasAnyAiKey || !aiSession) return;
    if (DateTime.now().difference(_lastAutoAi) < const Duration(minutes: 20)) {
      return;
    }
    Future.delayed(const Duration(seconds: 40), () {
      if (!mounted || !connected || aiLoading.value ||
          !aiSession || !localPilotOn) return;
      _lastAutoAi = DateTime.now();
      aiAnalyze(auto: true);
    });
  }

  // پیشنهادهای دستیار را روی تنظیمات اپ اعمال می‌کند
  void aiAutopilotStart() {
    aiLoop?.cancel();
    // A small on-device coder is expensive; the deterministic pilot handles fast network events.
    aiLoop =
        Timer.periodic(const Duration(minutes: 10), (_) => aiAutopilotTick());
    Future.delayed(const Duration(seconds: 8), aiAutopilotTick);
  }

  /// امتیاز و دلیل پیشنهاد هر موتور VPN (عدد بالاتر = قوی‌تر برای شرایط فعلی)
  List<({String id, String title, String sub, IconData icon, int score, String why})>
      _rankVpnEngines() {
    // تعداد سرورهای سالم فعلی (تقریبی برای رتبه‌بندی)
    // Only V2Ray remains as an engine; every good server is a V2Ray server.
    final nV2 = good.length;

    // امتیاز پایه + شرایط شبکه + موجودی سرور
    final items = <({String id, String title, String sub, IconData icon, int score, String why})>[
      (
        id: 'v2ray',
        title: 'V2Ray',
        sub: 'VLESS / VMess / Trojan / SS',
        icon: Icons.flash_on,
        score: 70 + (nV2 > 0 ? 15 : 0) + 10,
        why: 'بهترین گزینه عمومی — سرور زیاد و پایدار',
      ),
    ];
    items.sort((a, b) => b.score.compareTo(a.score));
    return items;
  }

  /// Ask which VPN engine/mode to use — مرتب از قوی‌ترین با پیشنهاد.
  /// Returns null if user cancels.
  Future<String?> pickVpnEngineDialog() async {
    if (!mounted) return null;
    final ranked = _rankVpnEngines();
    final best = ranked.first;
    return showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('پیشنهاد VPN (از قوی‌ترین)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Color(0xFF352919).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFD9AE55)),
                  ),
                  child: Text(
                    'پیشنهاد الان: ${best.title}\n${best.why}',
                    style: const TextStyle(fontSize: 13, height: 1.35),
                  ),
                ),
                for (var i = 0; i < ranked.length; i++)
                  Builder(builder: (_) {
                    final e = ranked[i];
                    final isBest = i == 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Material(
                        color: isBest
                            ? Color(0xFF352919).withValues(alpha: 0.35)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isBest
                                  ? const Color(0xFFD9AE55)
                                  : Colors.grey.shade700,
                            ),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: isBest
                                ? const Color(0xFF66512D)
                                : Colors.grey.shade800,
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                          title: Row(
                            children: [
                              Icon(e.icon, size: 18),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  e.title,
                                  style: TextStyle(
                                    fontWeight: isBest
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (isBest)
                                const Text(
                                  '★ بهتر',
                                  style: TextStyle(
                                    color: Color(0xFFD9AE55),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            '${e.sub}\n${e.why}',
                            style: const TextStyle(fontSize: 11.5, height: 1.3),
                          ),
                          isThreeLine: true,
                          onTap: () => Navigator.pop(ctx, e.id),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, best.id),
              child: Text('همین پیشنهاد (${best.title})'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
          ],
        ),
      ),
    );
  }

  void applyPilotEngine(String e) {
    // این نسخه فقط runtime واقعی V2Ray دارد؛ موتور فرضی انتخاب نمی‌شود.
    // فهرست پیشنهادها نیز فقط V2Ray را نمایش می‌دهد.
    pilotEngine = 'v2ray';
    proto = 'all';
    connRow = null;
    // _set owns the throttled UI refresh; extension methods must not call setState.
    _set(e == 'v2ray'
        ? 'موتور اجرایی V2Ray انتخاب شد.'
        : 'در این نسخه فقط موتور اجرایی V2Ray فعال است.');
  }

  String _engineLabel(String e) => 'V2Ray';

  /// Dialog then start; returns false if cancelled.
  /// اتصال آنلاین (همه‌ی منابع) یا آفلاین (فقط پوشه، بدون دانلود)
  Future<String?> _pickOnlineOffline() async {
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('نوع اتصال'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.public),
                title: const Text('🌐 اتصال آنلاین'),
                subtitle: const Text('در تمام منابع کانفیگ می‌گردد و سرور پیدا می‌کند'),
                onTap: () => Navigator.pop(ctx, 'online'),
              ),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('📦 اتصال آفلاین'),
                subtitle: const Text('فقط از پوشه‌ی منابع تازه (۳۰ هزار کانفیگ)؛ مصرف اینترنت کم'),
                onTap: () => Navigator.pop(ctx, 'offline'),
              ),
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('🏠 سرور شخصی'),
                subtitle: const Text(
                    'برای ساخت سرور رایگان نامحدود، ساخت خودکار سرور کلودفلر را بزنید'),
                onTap: () => Navigator.pop(ctx, 'personal'),
              ),
              ListTile(
                leading: const Icon(Icons.radar),
                title: const Text('🔎 اسکنر'),
                subtitle: const Text('تشخیص شبکه، اسکن هدفمند DNS/IP/SNI و انتخاب استراتژی سازگار'),
                onTap: () => Navigator.pop(ctx, 'scanner'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// همه‌ی دکمه‌های اتصال اول می‌پرسند: آنلاین یا آفلاین، بعد موتور VPN.
  /// اول می‌پرسد نت جهانی یا ملی، بعد آنلاین/آفلاین
  String _netPickLabel(String k) {
    switch (k) {
      case 'world_online':
        return '🌐 نت جهانی • آنلاین';
      case 'world_offline':
        return '📦 نت جهانی • آفلاین';
      case 'nat_online':
        return '🌐 نت ملی • آنلاین';
      default:
        return '📦 نت ملی • آفلاین';
    }
  }

  /// NETMODE1: یک پرسش به‌جای دو پرسش (شبکه + آنلاین/آفلاین).
  /// آخرین انتخاب در حافظه‌ی گوشی می‌ماند و بالای فهرست «ادامه با قبلی» است.
  /// تغییر حالت‌ها فقط بعد از تایید انجام می‌شود (لغو = هیچ‌چیز عوض نمی‌شود).
  Future<bool> pickNetworkThenOnlineOffline({bool ask = false, bool apply = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString('net_pick_last');
    // NETASK: با انتخاب ذخیره‌شده دیگر نمی‌پرسد؛ فقط با ask=true (منوی «آفلاین»
    // و مداد جادویی) دوباره پرسیده می‌شود
    // NATSOLO: حالت‌های معمولی فقط جهانی هستند؛ نت ملی دکمه‌ی مستقل خودش را دارد
    final String? pick = (!ask && last != null && last.startsWith('world'))
        ? last
        : await showDialog<String>(
      context: context,
      builder: (dctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('نوع اتصال'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (last != null && last.startsWith('world'))
                ListTile(
                  leading: const Icon(Icons.replay),
                  title: Text('ادامه با انتخاب قبلی: ${_netPickLabel(last)}'),
                  onTap: () => Navigator.pop(dctx, last),
                ),
              for (final o in const [
                'world_online',
                'world_offline',
              ])
                ListTile(
                  leading: Icon(o.endsWith('_online')
                      ? Icons.public
                      : Icons.folder_outlined),
                  title: Text(_netPickLabel(o)),
                  onTap: () => Navigator.pop(dctx, o),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('انصراف')),
          ],
        ),
      ),
    );
    if (pick == null) return false;
    final net = false; // NATSOLO: هیچ حالت معمولی نت ملی را روشن نمی‌کند
    final off = pick.endsWith('_offline');
    if (off && !natHotReady()) {
      // اولین بار: پوشه هنوز ساخته نشده، پس آفلاین خالی است
      final build = await showDialog<bool>(
        context: context,
        builder: (dctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('⚠️ هنوز پوشه ساخته نشده'),
            content: const Text(
                'برای اتصال آفلاین، اول پوشه‌ی منابع تازه ساخته می‌شود. '
                'الان بساز و حدود ۱۰ دقیقه صبر کن؛ بعد «اتصال آفلاین» را بزن.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dctx, false),
                  child: const Text('انصراف')),
              TextButton(
                  onPressed: () => Navigator.pop(dctx, true),
                  child: const Text('ساخت پوشه')),
            ],
          ),
        ),
      );
      if (build == true) {
        unawaited(natHotEnsure(force: true));
        _set('پوشه‌ی منابع تازه در حال ساخت است (حدود ۱۰ دقیقه)');
      }
      return false;
    }
    await prefs.setString('net_pick_last', pick);
    // NETCANCEL: اگر apply=false باشد، انتخاب فقط نگه داشته می‌شود و بعد از
    // انتخاب موتور اعمال می‌شود؛ لغو موتور هیچ حالتی را عوض نمی‌کند
    if (!apply) {
      _pendingNet = net;
      _pendingOff = off;
      return true;
    }
    await _applyNetPick(net, off);
    return true;
  }

  void _resetNetworkHealthCounters() {
    fails = 0;
    slowCount = 0;
    speedTick = 0;
    lowSpeed = 0;
    badPingRun = 0;
    noData = 0;
    stallRun = 0;
    siteFail = 0;
    siteSeen = false;
    siteNever = 0;
    siteNeverSwitches = 0;
    betterRun = 0;
    _lowSince = null;
    _persBadPingRun = 0;
    lastDomesticTunnelRttMs = null;
    _spWin.clear();
    _spFor = null;
    _spAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> _applyNetPick(bool net, bool off) async {
    // خلبان محلی/ابری روی نت ملی هم مجاز است؛ حالت انتخاب‌شده را به Global اجبار نکن.
    final previousMode = nationalMode;
    userModeChoice = net;
    natForce = net;
    nationalMode = net;
    if (previousMode != nationalMode) _resetNetworkHealthCounters();
    indestructibleMode = true; // ABADIAT: هر دو حالت ابدی هستند؛ با لیست صفر جستجو تموم نمی‌شه
    offlineOnly = off;
    userOfflineChoice = off;
    if (offlineOnly) { // OFFLINE-DERIVED
      autoCycle = false;
      autoUpgrade = false;
    } else {
      autoCycle = true;
      autoUpgrade = !nationalMode;
    }
    if (!net && _pilotSnap != null && !localPilotOn && !aiSession && !isAutoTesting) { // MODESNAP
      _restorePilotSnap();
    }
    await ultimateSave();
  }

  /// همه‌ی دکمه‌های اتصال اول می‌پرسند: شبکه (ملی/جهانی)، آنلاین/آفلاین، بعد موتور
  /// دکمه‌ی نت ملی فقط «آنلاین/آفلاین» می‌پرسد؛ شبکه از قبل ملی است
  Future<bool> _askOnlineOfflineNet(bool net) async {
    final ok = await _askOnlineOfflineMode();
    if (!ok) return false;
    _pendingNet = scannerMode ? (_scannerTargetNationalMode ?? nationalMode) : net;
    _pendingOff = offlineOnly;
    return true;
  }

  Future<bool> pickEngineThenStart(Future<void> Function() start,
      {bool askMode = true,
      bool? forceNet,
      bool keepNet = false,
      bool skipEngine = false}) async {
    // همه‌ی اتصال‌ها جهانی هستند؛ فقط دکمه‌ی نت ملی (forceNet: true) حالت ملی می‌دهد.
    // خلبان (keepNet) حالت شبکه را دست نمی‌زند.
    scannerMode = false;
    _scannerTargetNationalMode = null;
    _pendingNet = null;
    zeroTrafficRun.clear(); // LOOPCAP: هر بار دکمه‌ی اتصال شمارنده‌ها از نو
    realStartsRun = 0;
    if (askMode) {
      final ok = forceNet != null
          ? await _askOnlineOfflineNet(forceNet)
          : keepNet
              ? await _askOnlineOfflineMode()
              : await _askOnlineOfflineNet(false);
      if (!ok) return false;
    } else if (forceNet == null && !keepNet) {
      _pendingNet = false;
      _pendingOff = offlineOnly;
    }
    // دیالوگ «پیشنهاد VPN» حذف شد: فقط V2Ray باقی مانده و مستقیم انتخاب می‌شود
    // (skipEngine دیگر لازم نیست ولی برای سازگاری با فراخوانی‌ها نگه داشته شده)
    const String e = 'v2ray';
    applyPilotEngine(e);
    // PILOTSTOP: هر اتصالی که کاربر خودش بزند، خلبان‌ها را خاموش می‌کند.
    // این کار بعد از انتخاب موتور است تا لغو چیزی را عوض نکند.
    if (localPilotOn) stopLocalPilot();
    if (aiSession) stopAiSession();
    _restorePilotSnap(); // PILOTREV: تنظیمات خلبان برگردد، بعد انتخاب شبکه اعمال شود
    final pn = _pendingNet;
    final po = _pendingOff;
    _pendingNet = null;
    if (pn != null) await _applyNetPick(pn, po);
    if (scannerMode) {
      final report = await KingNationalScannerEngine.runPreflight(
        knownServers: <Server>[...pending, ...good, ...natRestPending, for (final entry in _resMap.values) entry.s],
        onStatus: (message) => _set(message),
        cancelled: () => !mounted || connected || appGone || !scannerMode,
        addDiscovered: (items) => _natRangeAdd(items),
      );
      if (!report.completed) {
        _set('اسکنر پیش از اتصال متوقف شد؛ هیچ نتیجه ناقصی ثبت نشد');
        return false;
      }
      _set(report.summary);
    }
    await start();
    return true;
  }

  // انتخاب آنلاین/آفلاین برای دکمه‌ی اتصال اصلی؛ false = لغو شد
  Future<bool> _askOnlineOfflineMode() async {
    scannerMode = false;
    _scannerTargetNationalMode = null;
    var mode = await _pickOnlineOffline();
    if (mode == null) return false;
    if (mode == 'scanner') {
      scannerMode = true;
      offlineOnly = false;
      userOfflineChoice = false;
      _scannerTargetNationalMode = await KingNationalScannerEngine.detectNationalMode();
      if (_scannerTargetNationalMode == null) {
        _set('اسکنر: شواهد شبکه قطعی نیست؛ حالت شبکه فعلی حفظ می‌شود');
      } else {
        _set(_scannerTargetNationalMode!
            ? 'اسکنر: مسیر داخلی محتمل است؛ آماده‌سازی نت ملی...'
            : 'اسکنر: مسیر جهانی در دسترس است؛ آماده‌سازی حالت جهانی...');
      }
      await ultimateSave();
      return true;
    }
    if (mode == 'personal') {
      // سرور شخصی مسیر جدا دارد؛ همین‌جا اجرا می‌شود و جریان آنلاین/آفلاین ادامه نمی‌یابد
      // ONLYFOLDER: همیشه از «پوشه‌ی سرورهای شخصی»: اول لیست روی صفحه، بعد پینگ، بعد اتصال
      unawaited(_personalAdThen(personalFolderConnect));
      return false;
    }
    if (mode == 'offline' && !natHotReady()) {
      // اولین بار: پوشه هنوز ساخته نشده، پس آفلاین خالی است
      final build = await showDialog<bool>(
        context: context,
        builder: (dctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('⚠️ هنوز پوشه ساخته نشده'),
            content: const Text(
                'برای اتصال آفلاین، اول پوشه‌ی منابع تازه ساخته می‌شود. '
                'الان بساز و حدود ۱۰ دقیقه صبر کن؛ بعد «اتصال آفلاین» را بزن.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dctx, false),
                  child: const Text('انصراف')),
              TextButton(
                  onPressed: () => Navigator.pop(dctx, true),
                  child: const Text('ساخت پوشه')),
            ],
          ),
        ),
      );
      if (build == true) {
        unawaited(natHotEnsure(force: true));
        _set('پوشه‌ی منابع تازه در حال ساخت است (حدود ۱۰ دقیقه)');
      }
      return false; // اتصال آفلاین بعد از ساخته شدن پوشه
    }
    _markUserTouched(const ['offlineOnly']);
    offlineOnly = mode == 'offline';
    userOfflineChoice = offlineOnly;
    if (offlineOnly) { // OFFLINE-DERIVED
      autoCycle = false;
      autoUpgrade = false;
    } else {
      autoCycle = true;
      autoUpgrade = !nationalMode;
    }
    // MODESNAP: restore snapshot در _applyNetPick انجام می‌شود (وقتی nationalMode عوض شود).
    // این تابع فقط offlineOnly را تغییر می‌دهد و snapshot را دست نمی‌زند.
    await ultimateSave();
    return true;
  }

  void stopAiSession() {
    aiSession = false;
    aiLoop?.cancel();
    aiLoop = null;
    // Restore modes the pilot forced
    if (_pilotForcedUltra) {
      ultraMode = false;
      _pilotForcedUltra = false;
    }
    if (_pilotForcedIndestructible) {
      indestructibleMode = false;
      _pilotForcedIndestructible = false;
    }
    _pilotConnectedAt = null;
    if (!localPilotOn) _restorePilotSnap(); // PILOTREV
  }

  Future<void> aiAutopilotTick() async {
    if (!aiSession || !mounted || !_hasAnyAiKey) return;
    if (busy || switching || aiLoading.value) return;
    // The deterministic pilot handles fast network events; the local LLM
    // advises at a lower cadence to protect battery, heat and memory.
    if (!wantVpn && !connected) {
      wantVpn = true;
      abort = false;
    }
    aiLoading.value = true;
    try {
      if (connected) _pilotConnectedAt ??= DateTime.now();
      _set('خلبان محلی: تحلیل اینترنت و مکان...');
      final answer = await aiAsk(aiPrompt());
      // A user stop during local inference must invalidate the pending answer.
      if (!mounted || !aiSession || !localPilotOn) return;
      aiShow(answer);
      applyAiSuggest();
      if (!aiSession || !localPilotOn) return;
      await aiRunAction();
      if (aiSession && wantVpn && !connected && !busy && !switching) {
        _set('خلبان: هنوز وصل نیست — جستجوی سرور...');
        await _acquire(strictRow: false, speed: true);
      }
      if (connected && current != null) {
        _pilotConnectedAt ??= DateTime.now();
        final holdOk = DateTime.now().difference(_pilotConnectedAt!) >=
            const Duration(minutes: 3);
        final sp = current!.speed ?? 0;
        if (holdOk &&
            sp > 0 &&
            minSpeedKB > 0 &&
            sp * 1024 < minSpeedKB &&
            !busy &&
            !switching) {
          final best = _pilotBestStandby();
          if (best != null) {
            lastWhy = 'خلبان: سرعت پایین';
            await _swapTo(best);
            _pilotConnectedAt = DateTime.now();
          }
        }
      } else if (!connected) {
        _pilotConnectedAt = null;
      }
      if (aiSession && connected) {
        _set('خلبان محلی فعال • $aiLastProvider • ${_connStatus()}');
      }
    } catch (e, stk) {
      logError(e, stk);
      // Keep the connection state machine alive even if local inference fails.
      if (aiSession && wantVpn && !connected && !busy) {
        try {
          await connect();
        } catch (inner, innerSt) {
          logError(inner, innerSt);
        }
      }
    } finally {
      aiLoading.value = false;
    }
  }

  Future<void> aiRunAction() async {
    final a = aiActionName;
    aiActionName = '';
    if (!aiSession || !localPilotOn || a.isEmpty || a == 'none') return;
    lastWhy = 'خلبان AI: $a';
    if (a == 'switch_best') {
      // Respect 3-minute hold after connect (same as local pilot)
      final holdOk = _pilotConnectedAt == null ||
          DateTime.now().difference(_pilotConnectedAt!) >=
              const Duration(minutes: 3);
      if (!holdOk || busy || switching) return;
      final best = _pilotBestStandby();
      if (best != null) {
        await _swapTo(best);
        _pilotConnectedAt = DateTime.now();
      }
    } else if (a == 'refresh_lists') {
      // Do NOT wipe good/failed — only force a fresh download when disconnected
      if (!connected) {
        listTime = null;
        lastFetchTry = DateTime.fromMillisecondsSinceEpoch(0);
        await _loadPending(bg: true, exhausted: true);
      }
    } else if (a == 'reset_blacklist' && !connected) {
      // PILOTGUARD: فقط وقتی وصل نیستیم؛ وگرنه هر ۹۰ ثانیه سرورهای مرده دوباره تست می‌شوند
      failed.clear();
      for (final g in good) {
        g.badAt = null;
        g.miss = 0;
      }
      unawaited(_saveCache());
    } else if (a == 'connect') {
      if (!connected && !busy) {
        turboSpeed = true;
        _applyTurboLevers();
        await connect();
      }
    } else if (a == 'enable_turbo') {
      turboSpeed = true;
      muxEnabled = true;
      muxConc = max(muxConc, 24);
      _applyTurboLevers();
      _saveSettings();
    }
  }

  void applyAiSuggest() {
    final m = aiSuggest.value;
    if (m.isEmpty) return;
    if (aiSession || localPilotOn) {
      _pilotSnap ??= _beginPilotSnap(); // PILOTREV
    }
    // PILOTRATE: هر ۵ دقیقه حداکثر یک بار تنظیمات را عوض کند (جلوگیری از نوسان و تغییر مداوم)
    final nowA = DateTime.now();
    if (_aiApplyAt != null && nowA.difference(_aiApplyAt!) < const Duration(minutes: 5)) {
      aiSuggest.value = <String, int>{};
      return;
    }
    _aiApplyAt = nowA;
    int g(String k, int d, int lo, int hi) =>
        (m.containsKey(k) ? m[k]!.clamp(lo, hi).toInt() : d);
    // PILOTCLAMP: سقف‌های محافظ برای جلوگیری از اشباع CPU/RAM و مصرف بی‌رویه دیتا.
    // Keep the LLM's ranges aligned with the prompt and phone resource budget.
    fastWorkers = g('fastWorkers', fastWorkers, 1, 20);
    bgWorkers = g('bgWorkers', bgWorkers, 1, 3);
    delayTimeout =
        Duration(seconds: g('timeout', delayTimeout.inSeconds, 3, 45));
    batchSize = g('batch', batchSize, 1, 300);
    minSpeedKB = g('minSpeedKB', minSpeedKB, 0, 1000);
    badPingMs = g('badPingMs', badPingMs, 70, 7000);
    speedTopN = g('speedTopN', speedTopN, 1, 10);
    applyNumSuggest(m);
    const protoKeys = ['vless', 'vmess', 'trojan', 'ss'];
    if (protoKeys.any((p) => m.containsKey('proto_$p'))) {
      protoSel.clear();
      for (final p in protoKeys) {
        if (m['proto_$p'] == 1) protoSel.add(p);
      }
      pending = [];
    }
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

  void aiSheet() {
    final tokenC = TextEditingController();
    final ownerC = TextEditingController(text: 'cafeeteriaa');
    final repoC = TextEditingController(text: 'King-vpn');
    final branchC = TextEditingController(text: 'main');
    final taskC = TextEditingController();
    var progress = 0.0;
    var downloading = false;
    var working = false;
    var ready = KingLocalAi.instance.isLoaded;
    var tokenSaved = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: StatefulBuilder(builder: (ctx, setS) {
              Future<void> loadLocalModel() async {
                if (downloading || working) return;
                setS(() { downloading = true; progress = 0; });
                try {
                  await KingLocalAi.instance.loadModel(
                    onProgress: (value) {
                      if (ctx.mounted) setS(() => progress = value.clamp(0.0, 1.0));
                    },
                  );
                  if (ctx.mounted) setS(() => ready = true);
                  aiText.value = 'مدل کدنویس محلی آماده است. اجرای استنتاج روی همین گوشی انجام می‌شود.';
                } catch (e) {
                  aiText.value = 'بارگذاری مدل محلی ناموفق بود: $e';
                } finally {
                  if (ctx.mounted) setS(() => downloading = false);
                }
              }

              Future<void> saveToken() async {
                try {
                  final token = tokenC.text;
                  await KingLocalAi.instance.saveGitHubToken(token);
                  if (!ctx.mounted) return;
                  tokenC.clear();
                  setS(() => tokenSaved = true);
                  aiText.value = 'توکن GitHub به‌صورت امن روی همین گوشی ذخیره شد.';
                } catch (e) {
                  aiText.value = 'ذخیره توکن انجام نشد: $e';
                }
              }

              Future<void> createRepair() async {
                if (working) return;
                if (!KingAiOwnerAuth.instance.hasActiveSession) {
                  aiText.value = 'برای درخواست تغییر کد، ابتدا مالک اصلی باید از پنل امن کینگ احراز هویت کند.';
                  return;
                }
                final owner = ownerC.text.trim();
                final repoName = repoC.text.trim();
                final base = branchC.text.trim();
                final task = taskC.text.trim();
                if (owner.isEmpty || repoName.isEmpty || base.isEmpty || task.isEmpty) {
                  aiText.value = 'نام مالک، مخزن، شاخه اصلی و شرح مشکل را کامل کن.';
                  return;
                }
                final hasToken = await KingLocalAi.instance.hasGitHubToken();
                if (!ctx.mounted) return;
                if (!hasToken) {
                  aiText.value = 'ابتدا توکن GitHub را در همین صفحه ذخیره کن.';
                  return;
                }
                setS(() => working = true);
                aiLoading.value = true;
                try {
                  if (!KingLocalAi.instance.isLoaded) {
                    await KingLocalAi.instance.loadModel();
                    if (ctx.mounted) setS(() => ready = true);
                  }
                  aiText.value = '۱/۳ دریافت فایل‌های مرتبط از GitHub...';
                  final files = await KingLocalAi.instance.readRepositoryContext(
                    owner: owner, repository: repoName, baseBranch: base, task: task);
                  if (files.isEmpty) throw StateError('فایل کد قابل‌خواندن در مخزن پیدا نشد.');
                  aiText.value = '۲/۴ جست‌وجوی Google و مطالعه مستندات رسمی...';
                  List<Map<String, String>> research = const [];
                  try {
                    research = await KingLocalAi.instance.researchGoogle(task);
                  } catch (e) {
                    aiText.value = 'جست‌وجوی Google در دسترس نبود؛ تحلیل با سورس مخزن ادامه می‌یابد: $e';
                  }
                  aiText.value = '۳/۴ تحلیل کد و تولید اصلاح توسط مدل محلی...';
                  final proposal = await KingLocalAi.instance.proposeRepair(
                    task: task, sourceFiles: files, researchNotes: research);
                  final changes = proposal['changes'] as Map<String, String>;
                  if (changes.isEmpty) {
                    aiText.value = 'مدل محلی تغییر امن و مستندی پیشنهاد نکرد. توضیح: ${proposal['summary']}';
                    return;
                  }
                  aiText.value = '۴/۴ ساخت شاخه و Pull Request در GitHub...';
                  final url = await KingLocalAi.instance.createRepairPullRequest(
                    owner: owner,
                    repository: repoName,
                    baseBranch: base,
                    title: task.length > 70 ? task.substring(0, 70) : task,
                    summary: '${proposal['summary']}\n\nفایل‌های تغییرکرده: ${changes.keys.join(', ')}',
                    changes: changes,
                  );
                  aiText.value = 'پیشنهاد اصلاح توسط مدل داخلی ساخته شد. قبل از ادغام، نتیجه CI و تغییرات را بررسی کن:\n$url';
                } catch (e, st) {
                  errJournalAdd(e, st: st);
                  aiText.value = 'چرخه اصلاح خودکار متوقف شد: $e';
                } finally {
                  aiLoading.value = false;
                  if (ctx.mounted) setS(() => working = false);
                }
              }

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🧠 مهندس هوش مصنوعی داخلی King',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => const KingAiConsolePage(),
                          ));
                        },
                        icon: const Icon(Icons.admin_panel_settings),
                        label: const Text('بازکردن پنل امن مالک و کینگ'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'مدل کدنویس روی گوشی اجرا می‌شود؛ برای دانلود اولیه حدود ۱٫۱۲ گیگابایت فضا و اینترنت لازم است. پس از دانلود، استنتاج مدل آفلاین انجام می‌شود. جست‌وجوی وب فقط منبع تحقیق است.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFCDD1D8))),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: Text(ready ? 'مدل محلی بارگذاری شده' : 'مدل کدنویس هنوز بارگذاری نشده')),
                      FilledButton.tonal(
                        onPressed: downloading || working ? null : loadLocalModel,
                        child: Text(downloading ? 'در حال دریافت...' : 'دانلود / بارگذاری مدل')),
                    ]),
                    if (downloading) ...[
                      LinearProgressIndicator(value: progress == 0 ? null : progress),
                      Text('${(progress * 100).toStringAsFixed(0)}%'),
                    ],
                    const Divider(height: 24),
                    const Text('اتصال امن GitHub', style: TextStyle(fontWeight: FontWeight.w600)),
                    const Text(
                      'توکن Fine-grained با دسترسی Contents: Read and write و Pull requests: Read and write بساز. توکن در Keystore اندروید ذخیره می‌شود و وارد prompt مدل نمی‌شود.',
                      style: TextStyle(fontSize: 11, color: Color(0xFFCDD1D8))),
                    TextField(
                      controller: tokenC,
                      obscureText: true,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(labelText: 'GitHub token')),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        onPressed: saveToken,
                        child: Text(tokenSaved ? 'توکن ذخیره شد' : 'ذخیره امن توکن')),
                    ),
                    const Divider(height: 24),
                    const Text('مهندسی و اصلاح کد مخزن', style: TextStyle(fontWeight: FontWeight.w600)),
                    TextField(controller: ownerC, textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(labelText: 'GitHub owner')),
                    TextField(controller: repoC, textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(labelText: 'Repository')),
                    TextField(controller: branchC, textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(labelText: 'شاخه پایه')),
                    TextField(
                      controller: taskC,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'مشکل یا قابلیت موردنظر',
                        hintText: 'مثلاً خطای مشخص را تحلیل کن، علت را پیدا کن و اصلاح تست‌پذیر پیشنهاد بده.')),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: working || downloading ? null : createRepair,
                        child: Text(working ? 'هوش مصنوعی در حال کار است...' : 'تحلیل کد و ساخت Pull Request')),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'امنیت: مدل فقط فایل‌های lib، test و tools را می‌تواند تغییر دهد؛ حداکثر ۳ فایل. تغییر مستقیم شاخه اصلی، ادغام خودکار، فایل‌های امضا/مجوز/هسته بومی و فایل‌های CI مسدود هستند. پذیرش تغییر فقط پس از بررسی diff و موفقیت CI انجام می‌شود.',
                      style: TextStyle(fontSize: 11, color: Color(0xFFCDD1D8))),
                    ValueListenableBuilder<bool>(
                      valueListenable: aiLoading,
                      builder: (_, l, __) => l
                        ? const Padding(padding: EdgeInsets.only(top: 10),
                            child: LinearProgressIndicator())
                        : const SizedBox.shrink()),
                    ValueListenableBuilder<String>(
                      valueListenable: aiText,
                      builder: (_, t, __) => t.isEmpty ? const SizedBox.shrink()
                        : Padding(padding: const EdgeInsets.only(top: 10),
                            child: SelectableText(t)),
                    ),
                    ValueListenableBuilder<Map<String, int>>(
                      valueListenable: aiSuggest,
                      builder: (_, sg, __) => sg.isEmpty ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('تنظیمات پیشنهادی: ${sg.entries.map((e) => '${e.key}=${e.value}').join(' • ')}'),
                                FilledButton(
                                  onPressed: () { applyAiSuggest(); Navigator.pop(ctx); },
                                  child: Text('اعمال تنظیمات پیشنهادی (${sg.length})')),
                              ])),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    ).whenComplete(() {
      tokenC.dispose();
      ownerC.dispose();
      repoC.dispose();
      branchC.dispose();
      taskC.dispose();
    });
  }

  // ---- خلبان محلی King Pro (داخل HomeExtras) ----

  /// Probe the active network class through the tunnel. Telegram is never a
  /// universal health gate: domestic and global data-plane checks are separate.
  Future<Map<String, bool?>> _localProbeSites() async {
    final out = <String, bool?>{'tg': null, 'yt': null, 'ig': null, 'net': null};
    if (!connected) return out;
    try {
      final urls = nationalMode ? _tunnelTestUrlsNational : _tunnelTestUrlsGlobal;
      final checks = await Future.wait(urls.map((url) => _siteOpens(url, viaCore: true)
          .timeout(const Duration(seconds: 8), onTimeout: () => false)));
      // A single reachable site is a weak hint, not a successful tunnel check.
      out['net'] = checks.where((ok) => ok).length >= 2;
      // Service-specific probes remain informational only; they do not decide
      // whether the tunnel is healthy or trigger an engine switch.
    } catch (e, stk) {
      logError(e, stk);
    }
    return out;
  }

  int _localScore({
    required bool connected,
    required bool? net,
    required int? ping,
    required double? speed,
    required int good,
    double? rate,
  }) {
    if (!connected) return 0;
    var sc = 25; // پایه اتصال
    // سرعت واقعی مهم‌ترین سیگنال است (پروب سایت اغلب false منفی می‌دهد)
    if (speed != null && speed > 0) {
      if (speed >= 1.5) {
        sc += 40;
      } else if (speed >= 0.6) {
        sc += 30;
      } else if (speed >= 0.3) {
        sc += 20;
      } else if (speed < 0.1) {
        sc -= 15;
      } else {
        sc += 8;
      }
    }
    if (ping != null) {
      if (ping < 300) {
        sc += 15;
      } else if (ping < 600) {
        sc += 10;
      } else if (ping < 1200) {
        sc += 5;
      } else if (ping > 2500) {
        sc -= 10;
      }
    }
    if (net == true) sc += 15;
    if (net == false) sc -= 12;
    if (good >= 3) sc += 5;
    // تاریخچه‌ی موفقیت این نوع سرور (۰..۱) — افت بیشتر = امتیاز کمتر
    if (rate != null) sc += ((rate - 0.5) * 20).round();
    return sc.clamp(0, 100);
  }

  Future<_LocalNetSnap> _localGather({bool probe = true}) async {
    String op = natOpKey.isNotEmpty ? natOpKey : _localLastOp;
    if (op.isNotEmpty) _localLastOp = op;

    String proto = '-', net = '-', sec = '-';
    int? ping;
    double? spd;
    int svc = -1;
    if (current != null) {
      try {
        final spec = describeConfig(current!.link);
        proto = spec.protocol;
        net = spec.network;
        sec = spec.security;
      } catch (e, stk) { logError(e, stk); }
      ping = current!.ping;
      if (!nationalMode && current!.speed != null && current!.speed! > 0) {
        spd = current!.speed;
      }
      svc = current!.svc;
    }

    bool? tg, yt, ig, netOk;
    if (probe && connected) {
      final p = await _localProbeSites();
      tg = p['tg'];
      yt = p['yt'];
      ig = p['ig'];
      netOk = p['net'];
      if (netOk == true) {
        _localNetFail = 0;
      } else if (netOk == false) {
        _localNetFail++;
      }
    }

    final score = _localScore(
      connected: connected,
      net: netOk,
      ping: ping,
      speed: spd,
      good: good.length,
      rate: current == null ? null : _profRate(current!),
    );

    return _LocalNetSnap(
      connected: connected,
      wifi: false,
      operatorKey: op.isNotEmpty ? op : 'نامشخص',
      configProto: proto,
      configNet: net,
      configSec: sec,
      pingMs: ping,
      speedMBs: spd,
      goodCount: good.length,
      pendingCount: pending.length,
      failedCount: failed.length,
      turbo: turboSpeed,
      frag: fragEnabled,
      mux: muxEnabled,
      reason: lastWhy,
      tgOk: tg,
      ytOk: yt,
      igOk: ig,
      netOk: netOk,
      score: score,
      svcMask: svc,
    );
  }

  _LocalDecision _localDecide(_LocalNetSnap s) {
    final set = <String, int>{};
    final why = StringBuffer();
    String act = 'none';
    var conf = 80;
    // hold تطبیقی با قدرت: قدرت بالاتر → واکنش کمی زودتر (حداقل ۱۲۰ث)
    final minHoldSec = (180 - (min(_localPower, 20) * 3).clamp(0, 60)).clamp(120, 180);

    // -------- CONNECTED --------
    if (s.connected) {
      _localFailStreak = 0;
      if (_localConnectedSince == null) {
        _localConnectedSince = DateTime.now();
      }
      final uptime = DateTime.now().difference(_localConnectedSince!).inSeconds;
      final spd = s.speedMBs;
      final hasSpeed = spd != null && spd >= 0.25;
      final softSpeed = spd != null && spd >= 0.12;
      final hasPing = s.pingMs != null && s.pingMs! > 0 && s.pingMs! < 3000;
      final observedBadTransport =
          (spd != null && spd < 0.10) ||
          (s.pingMs != null && s.pingMs! >= 3000);
      // Telegram is not a universal health endpoint and is not a gate on domestic-only links.
      final repeatedDataPlaneFailure = _localNetFail >= 2 && s.netOk == false;
      final deadTunnel = !hasSpeed && !hasPing &&
          (observedBadTransport || repeatedDataPlaneFailure);
      final weakTunnel = !hasSpeed && softSpeed && s.score < 40;
      // Consecutive failure of the class-appropriate tunnel data-plane probe
      // may trigger failover; service-specific sites are not universal gates.
      final svcFail = s.netOk == false;
      if (svcFail) {
        _localSvcFail++;
      } else {
        _localSvcFail = 0;
      }
      // PILOTHOLD: a tunnel with real speed or still inside its hold time is not switched because of a probe
      if (svcFail && _localSvcFail >= 2 && !hasSpeed && uptime >= minHoldSec) {
        if (current != null) current!.badAt = DateTime.now();
        _localSvcFail = 0;
        return _LocalDecision('switch_best', set,
            'آزمون مسیر داده ناموفق ×۲ → سرور بعدی',
            confidence: 92);
      }

      if (uptime < minHoldSec && !deadTunnel) {
        _localPhase = 'stable';
        _localSlowStreak = 0;
        _localGoodStreak++;
        why.writeln(
            '✅ وصل پایدار — uptime ${uptime}s/${minHoldSec}s — تعویض ممنوع');
        if (hasSpeed) {
          why.writeln(
              'سرعت ${spd!.toStringAsFixed(2)} MB/s • امتیاز ${s.score}');
        }
        return _LocalDecision('none', set, why.toString().trim(),
            confidence: 99);
      }

      if (hasSpeed || (hasPing && s.score >= 40)) {
        _localPhase = 'stable';
        _localSlowStreak = 0;
        _localGoodStreak++;
        why.writeln(
            '✅ نگه می‌داریم — سرعت/پینگ OK • امتیاز ${s.score} • uptime ${uptime}s');
        return _LocalDecision('none', set, why.toString().trim(),
            confidence: 98);
      }

      // لایه پیش‌بینی: ضعیف ولی نه مرده → soft_recover قبل از تعویض کامل
      _localPhase = 'degraded';
      _localSlowStreak++;
      if (weakTunnel &&
          _localSlowStreak >= 2 &&
          _localSlowStreak < 4 &&
          uptime >= minHoldSec) {
        act = 'soft_recover';
        conf = 85;
        why.writeln(
            'پیش‌بینی ضعف ×$_localSlowStreak → بازیابی نرم (ladder/turbo)');
        return _LocalDecision(act, set, why.toString().trim(),
            confidence: conf);
      }
      if (deadTunnel &&
          _localSlowStreak >= 4 &&
          s.goodCount > 0 &&
          uptime >= minHoldSec) {
        act = 'switch_best';
        conf = 92;
        why.writeln(
            'تونل مرده ×$_localSlowStreak بعد از ${uptime}s → تعویض هوشمند');
      } else {
        why.writeln(
            'ضعیف — صبر $_localSlowStreak/4 • uptime ${uptime}s • قدرت $_localPower');
      }
      return _LocalDecision(act, set, why.toString().trim(), confidence: conf);
    }

    // -------- DISCONNECTED --------
    _localConnectedSince = null;
    _localSvcFail = 0;
    _localSlowStreak = 0;
    _localPhase = _localFailStreak >= 2 ? 'recover' : 'search';

    set['fastWorkers'] = fastWorkers;
    set['timeout'] = delayTimeout.inSeconds;

    // یادگیری فقط از نتیجه‌ی تأییدشده؛ تعداد تلاش‌ها به‌تنهایی «برد» نیست.
    // Keep operator learning isolated by the active Pilot route class;
    // a result on international access must not bias domestic-only decisions.
    final opKey = _pilotExperienceOperatorKey(s.operatorKey);
    String? memoryBest;
    var memoryBestW = 0;
    if (opKey.isNotEmpty) {
      for (final e in _localOpWins.entries) {
        if (!e.key.startsWith('$opKey|')) continue;
        final losses = _localOpLosses[e.key] ?? 0;
        final total = e.value + losses;
        final winRate = total == 0 ? 0.0 : e.value / total;
        final netWins = e.value - losses;
        // Do not let a tiny lucky sample dominate the next connection choice.
        if (total >= 5 && e.value >= 4 && winRate >= 0.75 &&
            netWins >= 3 && netWins > memoryBestW) {
          memoryBestW = netWins;
          memoryBest = e.key.split('|').last;
        }
      }
    }

    if (memoryBest != null &&
        memoryBestW >= 3 &&
        memoryBest == 'connect') {
      act = memoryBest;
      conf = 94;
      why.writeln(
          'حافظه اپراتور «$opKey»: $act قبلاً $memoryBestW بار موفق');
    } else if (s.goodCount > 0) {
      act = 'connect';
      conf = 93;
      why.writeln('قطع — ${s.goodCount} سرور سالم → اتصال فوری');
    } else if (s.pendingCount > 8) {
      act = 'connect';
      conf = 86;
      why.writeln('قطع — صف ${s.pendingCount} → جستجو/اتصال');
    } else {
      act = 'connect';
      conf = 75;
      why.writeln('قطع است → شروع اتصال (قدرت $_localPower)');
    }

    if (opKey.isNotEmpty && act != 'none') {
      final memoryKey = '$opKey|$act';
      final wins = _localOpWins[memoryKey] ?? 0;
      final losses = _localOpLosses[memoryKey] ?? 0;
      final total = wins + losses;
      final winRate = total == 0 ? 0.0 : wins / total;
      if (total >= 5 && wins >= 4 && winRate >= 0.75) {
        conf = min(100, conf + 5);
        why.writeln('تقویت اطمینان از حافظه: $wins برد از $total نتیجه');
      }
    }

    _localFailStreak++;
    return _LocalDecision(act, set, why.toString().trim(), confidence: conf);
  }

  // Use one scoring function for both the current endpoint and standby
  // candidates, so both are compared on the same evidence scale.
  double _pilotStandbyScore(Server s) {
    var score = 0.0;
    final now = DateTime.now();
    bool isFresh(DateTime? measuredAt, Duration maxAge) {
      if (measuredAt == null) return false;
      final age = now.difference(measuredAt);
      return !age.isNegative && age <= maxAge;
    }

    // A recent core check is required before ping/service evidence can rank
    // an endpoint. A recent speed sample has its own, shorter validity window.
    final pingFresh = isFresh(s.checkedAt, const Duration(minutes: 4));
    final pingSuccessfulFresh = pingFresh && s.ping != null && s.ping! > 0;
    final speedFresh = isFresh(s.speedAt, const Duration(minutes: 5));
    // Service bits need a recent endpoint check; measured throughput has
    // its own timestamp and remains useful even when the ping sample ages out.
    if (!nationalMode) {
      if (pingSuccessfulFresh && s.svc >= 0) {
        score += ((s.svc & 1) != 0 ? 40 : 0) +
            ((s.svc & 2) != 0 ? 30 : 0) +
            ((s.svc & 4) != 0 ? 20 : 0);
      }
      if (speedFresh && (s.speed ?? 0) > 0) {
        score += s.speed! * 50;
      }
    }
    final ping = s.ping;
    if (pingFresh && ping != null && ping > 0) {
      score += max(0, 100 - ping / 15);
    }
    // Verified historical tunnel outcomes decay independently in NNIE.
    final learned = NationalNetworkIntelligence.scoreFor(
      NationalNetworkIntelligence.keyOfServer(s),
    );
    score += (learned.clamp(-20.0, 100.0) * 0.25).toDouble();
    score += (_profRate(s) - 0.5) * 30;
    return score;
  }

  // Hysteresis: don't disrupt a working tunnel for a marginal score gain.
  // A 12-point margin filters noisy ping/throughput fluctuations.
  Server? _pilotBestStandby() {
    final candidates = _pickList()
        .where((s) => !identical(s, current) && !_bad(s))
        .toList();
    Server? best;
    var bestScore = -1e12;
    for (final s in candidates) {
      final score = _pilotStandbyScore(s);
      if (score > bestScore) {
        bestScore = score;
        best = s;
      }
    }
    final active = current;
    if (best == null || active == null) return best;
    if (bestScore < _pilotStandbyScore(active) + 12.0) return null;
    return best;
  }

  Future<void> _pilotLoadExperience() async {
    if (_pilotExperienceLoaded) return;
    _pilotExperienceLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pilotExperiencePrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      Map<String, int> readMap(Object? value) {
        if (value is! Map) return <String, int>{};
        return <String, int>{
          for (final entry in value.entries)
            if (entry.key is String && entry.value is num)
              (entry.key as String): (entry.value as num).toInt().clamp(0, 10000).toInt(),
        };
      }
      _localOpWins = readMap(decoded['wins']);
      _localOpLosses = readMap(decoded['losses']);
    } catch (e, st) {
      logError(e, st);
    }
  }

  Future<void> _pilotSaveExperience() async {
    try {
      // Bound memory size and values; experience is advisory, never authority.
      Map<String, int> bounded(Map<String, int> source) {
        final entries = source.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        return Map<String, int>.fromEntries(entries.take(100).map(
          (e) => MapEntry(e.key, e.value.clamp(0, 10000).toInt()),
        ));
      }
      _localOpWins = bounded(_localOpWins);
      _localOpLosses = bounded(_localOpLosses);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pilotExperiencePrefsKey, jsonEncode({
        'version': 1,
        'wins': _localOpWins,
        'losses': _localOpLosses,
      }));
    } catch (e, st) {
      logError(e, st);
    }
  }

  void _pilotBeginExperience(String operatorKey, String action) {
    final op = operatorKey.trim();
    if (op.isEmpty || action.isEmpty) return;
    _pilotPendingExperienceKey = '$op|$action';
    _pilotPendingExperienceAt = DateTime.now();
    _pilotPendingWasConnected = connected;
    _pilotPendingServerLink = current?.link;
    _pilotPendingPositiveSamples = 0;
    _pilotPendingLastPositiveAt = null;
  }

  Future<void> _pilotReconcileExperience(_LocalNetSnap snap) async {
    final key = _pilotPendingExperienceKey;
    final at = _pilotPendingExperienceAt;
    if (key == null || at == null) return;
    final now = DateTime.now();
    final action = key.split('|').last;
    final elapsed = now.difference(at);
    // A connected core alone is not success. Require class-appropriate
    // data-plane/throughput evidence twice, at least 10s apart, after action.
    final hasData = snap.connected &&
        (snap.netOk == true || (snap.speedMBs != null && snap.speedMBs! >= 0.25));
    final transitioned = switch (action) {
      'connect' => !_pilotPendingWasConnected && snap.connected,
      'switch_best' => snap.connected && current?.link != null &&
          current!.link != _pilotPendingServerLink,
      'soft_recover' => snap.connected,
      _ => false,
    };
    final verified = elapsed >= const Duration(seconds: 10) && hasData && transitioned;
    if (verified) {
      final last = _pilotPendingLastPositiveAt;
      if (last == null || now.difference(last) >= const Duration(seconds: 10)) {
        _pilotPendingPositiveSamples++;
        _pilotPendingLastPositiveAt = now;
      }
    } else if (!hasData || !transitioned) {
      _pilotPendingPositiveSamples = 0;
      _pilotPendingLastPositiveAt = null;
    }
    final confirmed = _pilotPendingPositiveSamples >= 2;
    final expiredFailure = !confirmed && elapsed >= const Duration(minutes: 3);
    if (!confirmed && !expiredFailure) return;
    if (confirmed) {
      _localOpWins[key] = (_localOpWins[key] ?? 0) + 1;
    } else {
      _localOpLosses[key] = (_localOpLosses[key] ?? 0) + 1;
    }
    _pilotPendingExperienceKey = null;
    _pilotPendingExperienceAt = null;
    _pilotPendingWasConnected = false;
    _pilotPendingServerLink = null;
    _pilotPendingPositiveSamples = 0;
    _pilotPendingLastPositiveAt = null;
    await _pilotSaveExperience();
  }

  Future<void> _localApply(_LocalDecision d) async {
    _localLastAction = d.action;

    if (d.settings.containsKey('fastWorkers')) {
      fastWorkers = d.settings['fastWorkers']!.clamp(1, 32);
    }
    if (d.settings.containsKey('timeout')) {
      delayTimeout = Duration(seconds: d.settings['timeout']!.clamp(2, 30));
    }
    if (d.settings.containsKey('muxConc')) {
      muxConc = d.settings['muxConc']!.clamp(4, 32);
    }
    if (d.settings.containsKey('mux') == true && d.settings['mux'] == 1) {
      muxEnabled = true;
    }

    if (d.action != 'none') {
      lastWhy = 'خلبان محلی: ${d.action}';
    }

    switch (d.action) {
      case 'connect':
        if (!connected && !busy) {
          _pilotBeginExperience(_pilotExperienceOperatorKey(_localLastOp), 'connect');
          turboSpeed = true;
          _applyTurboLevers();
          await connect();
        }
        break;
      case 'soft_recover':
        _pilotBeginExperience(_pilotExperienceOperatorKey(_localLastOp), 'soft_recover');
        // بازیابی نرم: فقط توربو همان سرور قبل از تعویض کامل (جدید: بدون نت ملی)
        if (connected && current != null && !busy && !switching) {
          turboSpeed = true;
          muxEnabled = true;
          muxConc = max(muxConc, 24);
          _applyTurboLevers();
          try {
            unawaited(_measureCurrent(current!));
          } catch (e, stk) { logError(e, stk); }
        }
        break;
      case 'switch_best':
        if (!busy && !switching) {
          final best = _pilotBestStandby();
          if (best != null) {
            _pilotBeginExperience(_pilotExperienceOperatorKey(_localLastOp), 'switch_best');
            await _swapTo(best);
            _localConnectedSince = DateTime.now();
            _localSlowStreak = 0;
          }
        }
        break;
      case 'refresh_lists':
        // هرگز لیست سالم/سیاه را نابود نکن
        if (!connected) {
          listTime = null;
          lastFetchTry = DateTime.fromMillisecondsSinceEpoch(0);
          await _loadPending(bg: true, exhausted: true);
        }
        break;
      case 'reset_blacklist':
        failed.clear();
        for (final g in good) {
          g.badAt = null;
          g.miss = 0;
        }
        unawaited(_saveCache());
        break;
      case 'enable_turbo':
        // فقط فلگ — بدون ریستارت تونل
        turboSpeed = true;
        muxEnabled = true;
        muxConc = max(muxConc, 32);
        _saveSettings();
        break;
      default:
        break;
    }
  }

  /// اگر تیک اجباری به‌خاطر کار دیگر گم شد، ۵ ثانیه بعد دوباره امتحان کن (حداکثر ۶۰ بار)
  void _localRetryLater() {
    if (_localRetryN >= 60 || !localPilotOn) return;
    _localRetryN++;
    dbg('خلبان: تیک به‌خاطر کار در جریان عقب ماند • تلاش دوباره #$_localRetryN');
    Future.delayed(const Duration(seconds: 5), () {
      if (localPilotOn && mounted) localPilotTick(force: true);
    });
  }

  // TOGGLES: خلبان بر اساس نتیجه‌ی اتصال، Fragment / ماتریس / IP تمیز را خودش روشن و خاموش می‌کند
  void _localTuneToggles() {
    var changed = false;
    if (connected) {
      _localGoodTog++;
      // وصل و پایدار: ماتریس سنگین است، خاموشش کن تا دیتا کم شود
      if (_localGoodTog >= 3 && ultraMode) {
        ultraMode = false;
        changed = true;
      }
    } else if (wantVpn) {
      _localGoodTog = 0;
      if (_localFailStreak >= 2) {
        // جستجو شکست می‌خورد: IP تمیز و Fragment (نت ملی) را روشن کن
        if (!cleanIpMode) {
          cleanIpMode = true;
          changed = true;
        }
        if (nationalMode && !fragEnabled) {
          fragEnabled = true;
          changed = true;
        }
      }
      if (_localFailStreak >= 3 && nationalMode && !ultraMode) {
        ultraMode = true;
        changed = true;
      }
    }
    if (changed) unawaited(_saveSettings().catchError((e) => logError(e)));
  }


  /// Lets the on-device model review difficult pilot decisions at a low cadence.
  /// The deterministic state machine remains authoritative and all model actions
  /// pass explicit evidence/hold-time gates before they can affect the tunnel.
  Future<_LocalDecision> _localAiReview(
      _LocalNetSnap snap, _LocalDecision base) async {
    final ai = KingLocalAi.instance;
    if (!ai.isLoaded || ai.isBusy) return base;
    if (base.confidence >= 96 && _localPhase == 'stable') return base;
    if (_localPhase != 'degraded' &&
        _localPhase != 'recover' &&
        _localFailStreak == 0 &&
        _localSlowStreak < 2) {
      return base;
    }
    final now = DateTime.now();
    final last = _localAiAdvisorAt;
    if (last != null && now.difference(last) < const Duration(minutes: 6)) {
      return base;
    }
    _localAiAdvisorAt = now;
    final evidence = <String, Object?>{
      'networkMode': nationalMode ? 'domestic' : 'global',
      'networkClass': PilotNetworkProbe.current.mode.name,
      'domesticProbeHealth': PilotNetworkProbe.current.domestic.name,
      'globalProbeHealth': PilotNetworkProbe.current.global.name,
      'domesticProbeLatencyMs': PilotNetworkProbe.current.domesticLatencyMs,
      'globalProbeLatencyMs': PilotNetworkProbe.current.globalLatencyMs,
      'probeConfidence': PilotNetworkProbe.current.confidence,
      'phase': _localPhase,
      'connected': snap.connected,
      'operator': snap.operatorKey,
      'protocol': snap.configProto,
      'transport': snap.configNet,
      'security': snap.configSec,
      'pingMs': snap.pingMs,
      'speedMBps': snap.speedMBs,
      'dataPlaneOk': snap.netOk,
      'telegramOk': snap.tgOk,
      'youtubeOk': snap.ytOk,
      'instagramOk': snap.igOk,
      'healthyServers': snap.goodCount,
      'pendingServers': snap.pendingCount,
      'failedServers': snap.failedCount,
      'qualityScore': snap.score,
      'slowStreak': _localSlowStreak,
      'serviceFailStreak': _localSvcFail,
      'connectionFailStreak': _localFailStreak,
      'baseAction': base.action,
      'baseConfidence': base.confidence,
      'baseReason': base.explain,
      'uptimeSeconds': _localConnectedSince == null
          ? 0
          : now.difference(_localConnectedSince!).inSeconds,
    };
    try {
      final raw = await ai.askPilot(
        'Review this VPN pilot decision using only the evidence below. '
        'Return exactly the required JSON. Do not invent data. '
        'If uncertain choose action none. Evidence: ${jsonEncode(evidence)}',
        maxTokens: 192,
      ).timeout(const Duration(seconds: 18));
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start < 0 || end <= start) return base;
      final decoded = jsonDecode(raw.substring(start, end + 1));
      if (decoded is! Map ||
          decoded['action'] is! String ||
          decoded['confidence'] is! num ||
          decoded['reason'] is! String) {
        return base;
      }
      final action = decoded['action'] as String;
      final confidence = (decoded['confidence'] as num).round().clamp(0, 100).toInt();
      final reason = (decoded['reason'] as String).trim();
      if (confidence < 88 ||
          !const {'none', 'connect', 'switch_best', 'soft_recover'}.contains(action)) {
        return base;
      }

      // Hard gates: never let the model start a second connect, switch a
      // healthy tunnel, or choose a standby that does not exist.
      if (snap.connected && action == 'connect') return base;
      if (!snap.connected && action != 'connect' && action != 'none') return base;
      if (action == 'switch_best') {
        final uptime = _localConnectedSince == null
            ? 0
            : now.difference(_localConnectedSince!).inSeconds;
        if (!snap.connected ||
            snap.goodCount <= 0 ||
            _localSvcFail < 2 ||
            uptime < 180) {
          return base;
        }
      }
      if (action == 'soft_recover' &&
          (!snap.connected ||
              _localPhase != 'degraded' ||
              _localSlowStreak < 2)) {
        return base;
      }
      if (action == 'connect' && (snap.connected || offlineOnly && snap.goodCount == 0)) {
        return base;
      }

      // The model may veto an unnecessary failover, or add a cautious soft
      // recovery when repeated evidence says the tunnel is degraded.
      if (action == base.action) {
        return _LocalDecision(
          base.action,
          base.settings,
          '${base.explain} • بازبینی مدل محلی: ${reason.isEmpty ? "تأیید شد" : reason}',
          confidence: min(base.confidence, confidence).toInt(),
        );
      }
      if (action == 'none' &&
          (base.action == 'switch_best' || base.action == 'soft_recover')) {
        return _LocalDecision(
          'none',
          const <String, int>{},
          '${base.explain} • مدل محلی با تعویض/بازیابی مخالفت کرد: ${reason.isEmpty ? "شواهد کافی نیست" : reason}',
          confidence: confidence,
        );
      }
      if (action == 'soft_recover' &&
          base.action == 'none' &&
          snap.connected &&
          _localPhase == 'degraded' &&
          _localSlowStreak >= 2) {
        return _LocalDecision(
          'soft_recover',
          base.settings,
          'پیشنهاد مدل محلی پس از شواهد ضعف تکراری: $reason',
          confidence: confidence,
        );
      }
    } catch (e, st) {
      // A timeout or unavailable model never blocks the deterministic pilot.
      logError(e, st);
    }
    return base;
  }

  Future<void> localPilotTick({bool force = false}) async {
    if (!localPilotOn || !mounted) return;
    // PILOTRETRY: تیک خلبان وقتی کار دیگری در جریان است، قبلاً بی‌صدا گم می‌شد
    // (تیک اجباری شروع خلبان هم گم می‌شد و کادر «تیک نزد» می‌شد). حالا دوباره تلاش می‌کند.
    if (busy || switching || localPilotLoading.value) {
      if (force) _localRetryLater();
      return;
    }
    _localRetryN = 0;
    if (!force &&
        _localLastTick != null &&
        DateTime.now().difference(_localLastTick!) < const Duration(seconds: 40)) {
      return;
    }
    // PILOT-KEEP: a short abort / switch / search can leave wantVpn false.
    // Only the user's stop button disables the pilot, so restore its intent here.
    if (!wantVpn && !connected) {
      wantVpn = true;
      abort = false;
    }
    // STABLE-PILOT: a working tunnel that was switched less than 3 minutes ago
    // is left alone (stops the repeated switches)
    if (connected && lastState == 'CONNECTED' &&
        DateTime.now().difference(lastSwitch) < const Duration(minutes: 3)) {
      // PILOTNOTICK-FIX: یک تیک اجباری که کاری نکرد (تونل پایدار است) هم تیک حساب
      // می‌شود؛ وگرنه تست خودکار آن را «خلبان تیکی نزد» ثبت می‌کرد.
      if (force) {
        _localTickN++;
        dbg('خلبان: تیک #$_localTickN • تونل پایدار است (تعویض کمتر از ۳ دقیقه پیش) • بدون تعویض');
      }
      return;
    }

    localPilotLoading.value = true;
    _localLastTick = DateTime.now();
    _localTickN++;
    try {
      localPilotText.value =
          '⏳ قدرت $_localPower ($_localPowerLabel): پروب + اینترنت + مکان...';

      // When the tunnel is down, re-check the underlying link identity. The
      // diagnosis cache is keyed by interface identity, so a Wi-Fi/mobile switch
      // triggers fresh evidence while repeated ticks on the same network are cheap.
      if (!connected) {
        final previousMode = nationalMode;
        await _pilotDetectNetworkMode();
        if (previousMode != nationalMode) {
          _applyModePreset(nationalMode, offlineOnly, true);
        }
      }
      // Start optional tuning only after the underlying-link diagnosis has
      // completed, so its probes cannot accidentally run through a new tunnel.
      // Pilot uses its own evidence gathering and optimizer; generic AutoTune is separate.

      // قدرت را هر تیک با شبکه هماهنگ کن (تمام‌اتوماتیک)
      final wantPower = _localAutoPickPower();
      if (wantPower != _localPower) {
        _localApplyMaxPowerProfile(power: wantPower);
      }

      await _pilotLoadExperience();
      final snap = await _localGather(probe: true);
      await _pilotReconcileExperience(snap);
      final baseDecision = _localDecide(snap);
      final decision = await _localAiReview(snap, baseDecision);

      final report = StringBuffer();
      report.writeln(
          '👑 خلبان ∞  •  قدرت $_localPower ($_localPowerLabel)  •  قله $_localPeakPower  •  تیک #$_localTickN');
      report.writeln('────────────────────────');
      report.writeln(snap.toHuman());
      report.writeln('────────────────────────');
      report.writeln(
          '🎯 تصمیم: ${decision.action == "none" ? "نگه‌داری (پایدار)" : decision.action}  |  اطمینان: ${decision.confidence}%');
      report.writeln(decision.explain);
      if (decision.settings.isNotEmpty) {
        report.writeln('⚙️ ${decision.settings}');
      }
      report.writeln(
          '⚙️ اتو: workers=$fastWorkers timeout=${delayTimeout.inSeconds}s '
          'mux=$muxEnabled turbo=$turboSpeed');
      localPilotText.value = report.toString().trim();

      await _localApply(decision);
      _localTuneToggles(); // TOGGLES
      try {
        await kingSelfHeal(reason: 'pilot');
      } catch (e, stk) { logError(e, stk); }

      // PILOTKEEP2: خلبان روشن که وصل نیست خودش دوباره تلاش می‌کند (بلوک زیر دست‌نخورده)
      // OFFLINE-PILOT: در حالت آفلاین اگر هیچ سرور سالمی در پوشه نیست، خلبان دیگر وصل نمی‌کند
      // (قبلاً یک سرور تصادفی و تست‌نشده را وصل می‌کرد و بعد پشت‌سرهم عوض می‌کرد)
      final offlineNoHealthy = offlineOnly && standbyCount == 0;
      if (localPilotOn && !connected && !busy && !switching && !offlineNoHealthy) wantVpn = true;
      // اگر هنوز قطع است دوباره وصل کن
      if (localPilotOn && wantVpn && !connected && !busy && !switching && !offlineNoHealthy) {
        if (decision.action == 'none' || decision.action == 'connect') {
          await connect();
        }
      }

      // بازه تطبیقی: پایدار = آهسته‌تر، قطع = سریع‌تر
      // DOHAUTO: IP (DoH) را خلبان خودش روشن/خاموش می‌کند بر اساس نتیجه‌ی اتصال
      if (connected) {
        _localConnFail = 0;
        if (!ipMode) {
          ipMode = true;
          await _saveSettings();
        }
      } else if (wantVpn) {
        _localConnFail++;
        if (_localConnFail >= 2 && ipMode) {
          ipMode = false;
          _localConnFail = 0;
          await _saveSettings();
        }
      }
      _localReschedule();
    } catch (e, stk) {
      logError(e, stk);
      localPilotText.value =
          'خطای خلبان: ${e.toString().replaceFirst("Exception: ", "")}';
      if (localPilotOn && wantVpn && !connected && !busy && !(offlineOnly && standbyCount == 0)) {
        try {
          await connect();
        } catch (e, stk) { logError(e, stk); }
      }
    } finally {
      localPilotLoading.value = false;
    }
  }

  void _localReschedule() {
    if (!localPilotOn) return;
    localPilotLoop?.cancel();
    // بازه تطبیقی با فاز + قدرت (قدرت بالاتر = چک کمی سریع‌تر در بحران)
    int sec;
    if (_localPhase == 'stable') {
      sec = (180 - _localPower.clamp(0, 40)).clamp(90, 180);
    } else if (_localPhase == 'degraded') {
      sec = (90 - _localPower.clamp(0, 40)).clamp(35, 90);
    } else {
      sec = (30 - (_localPower / 2).floor().clamp(0, 15)).clamp(12, 30);
    }
    localPilotLoop = Timer.periodic(Duration(seconds: sec), (_) {
      localPilotTick();
    });
  }

  /// قدرت خلبان: ۰ تا ∞ — بدون سقف سخت؛ فقط با وضعیت شبکه/مکان بالا و پایین می‌شود
  String get _localPowerLabel {
    if (_localPower <= 0) return 'آرام';
    if (_localPower <= 2) return 'عادی';
    if (_localPower <= 5) return 'قوی';
    if (_localPower <= 10) return 'سخت';
    if (_localPower <= 20) return 'اضطراری';
    return 'حداکثر بی‌نهایت';
  }

  /// اعمال پروفایل از روی قدرت (۰…∞) — همه عددها فرمولی، بدون سقف قدرت
  void _localApplyMaxPowerProfile({int? power}) {
    _pilotSnap ??= _beginPilotSnap(); // PILOTREV
    // PILOTCAP: در حالت عادی قدرت تا ۱۰ است؛ در نت ملی سقف قدرت بالاتر است
    // (سقف workers/batch جداگانه و ثابت است و هسته را حفاظت می‌کند)
    // No arbitrary pilot-level ceiling. Individual resource controls below
    // remain bounded by safe runtime limits and real device capacity.
    final p = max(0, power ?? _localPower);
    _localPower = p;
    if (p > _localPeakPower) _localPeakPower = p;

    // --- سوییچ‌های حیاتی (همیشه اتوماتیک) ---
    proxyMode = false;
    turboSpeed = true;
    muxEnabled = true;
    // Current speed-test endpoints are international Cloudflare endpoints.
    // Do not use them as a national-only health gate until domestic throughput
    // endpoints with stable, measurable payloads are configured.
    autoSpeed = !nationalMode;
    savedFirst = true;
    if (userOfflineChoice != true) offlineOnly = false;
    autoCycle = !offlineOnly;
    // Keep national-specific routing/scan policy after the pilot power profile.
    fragEnabled = nationalMode;
    cleanIpMode = nationalMode;
    ipMode = nationalMode;
    autoUpgrade = !nationalMode && !offlineOnly;
    minSpeedKB = 0;
    // NORMALPARITY: مثل اتصال عادی، ۳ تست هم‌زمان (نه مقدار تصادفی از قبل)
    // PILOTUSER: اگر کاربر «تست همزمان» را خودش تنظیم کرده، همان عدد را نگه می‌دارد؛ وگرنه ۳
    fastWorkers = (fwUserSet && fwUserValue >= 1) ? fwUserValue.clamp(1, 32) : 3;
    bgWorkers = 3;

    // فرمول‌های پیوسته نسبت به قدرت (هرچه بالاتر = تهاجمی‌تر)
    // workers: 35 → رشد آرام تا سقف عملی سخت‌افزار
    // سقف ۶۰ هم‌زمان (هم‌اندازه‌ی گیت تست هسته)
    // NORMALPARITY: خلبان باید مثل اتصال عادی رفتار کنه (طبق درخواست کاربر).
    // پس fastWorkers=3 و bgWorkers=3 رو ست می‌کنیم. بعد از توقف خلبان،
    // _restorePilotSnap مقدار اصلی کاربر رو برمی‌گردونه. پس این override
    // موقتی است و به تنظیمات کاربر آسیب نمی‌زنه.
    // Infinite learning level, bounded operational knobs: prevent integer
    // overflow and keep actual workers/timeouts within safe device limits.
    final timeoutPower = min(p, 52);
    final batchPower = min(p, 12);
    final pingPower = min(p, 68);
    final concurrencyPower = min(p, 12);
    delayTimeout = Duration(seconds: (9 + timeoutPower * 0.7).clamp(8, 45).round());
    tcpTimeout = Duration(milliseconds: (3500 + timeoutPower * 250).clamp(3000, 15000).round());
    batchSize = (180 + batchPower * 10).clamp(100, 300).toInt();
    final basePing = sniSpoofAll ? 5000 : 3000;
    badPingMs = max(basePing, (2500 + pingPower * 80).clamp(2000, 8000).toInt());
    watchFailLimit = (3 + (min(p, 36) / 4).floor()).clamp(2, 12).toInt();
    speedTopN = (2 + (min(p, 40) / 5).floor()).clamp(1, 10).toInt();
    muxConc = (8 + concurrencyPower * 2).clamp(8, 32).toInt();

    // سوییچ‌های وابسته به قدرت / مکان / نوع جستجو
    if (p >= 2) ultraMode = true;

    _applyTurboLevers();
    unawaited(_saveSettings());
  }

  /// محاسبه قدرت از اینترنت + مکان/اپراتور + نوع جستجو (عادی / نت ملی)
  /// بدون سقف: با هر شکست بیشتر بالا می‌رود؛ با پایداری آرام پایین می‌آید
  int _localAutoPickPower() {
    var p = 1; // پایه روزمره

    if (indestructibleMode) p += 2;

    // --- مکان / اپراتور ---
    final op = (_localLastOp.isNotEmpty ? _localLastOp : natOpKey).toLowerCase();
    if (op.contains('ایرانسل') || op.contains('irancell') || op.contains('mci') ||
        op.contains('همراه') || op.contains('رایتل') || op.contains('rightel')) {
      p += 2; // اپراتورهای ایران معمولاً فیلتر سنگین‌تر
    }
    if (op.isNotEmpty && op != 'نامشخص') {
      // اگر این اپراتور قبلاً زیاد شکست خورده، قدرت بالاتر
      final fails = _localOpFails.entries
          .where((e) => e.key.startsWith(op))
          .fold<int>(0, (a, e) => a + e.value);
      p += (fails / 2).floor().clamp(0, 15);
    }

    // --- وضعیت اتصال / جستجو ---
    if (!connected) {
      p += 1;
      if (good.isEmpty) p += 2;
      if (pending.isEmpty && fetchedAll.isEmpty) p += 3; // لیست خالی = سخت‌تر
    } else if (!nationalMode) {
      final spd = current?.speed;
      if (spd != null && spd > 0 && spd < 0.15) p += 2; // وصل ولی خیلی کند
      if (spd != null && spd >= 1.0 && _localFailStreak == 0) {
        p = max(0, p - 1); // اینترنت خوب → کمی آرام‌تر
      }
    }

    // --- شکست‌ها: هر شکست قدرت را بالا می‌برد (مسیر به ∞) ---
    p += _localFailStreak * 2;
    p += _localSlowStreak;
    if (_localNetFail >= 3) p += 2;

    // --- پایداری: آرام پایین بیا (نه یک‌دفعه) ---
    if (_localGoodStreak >= 5 && _localFailStreak == 0 && connected) {
      p = max(0, p - 2);
    }
    if (_localPhase == 'stable' && connected && _localFailStreak == 0) {
      p = max(0, p - 1);
    }

    // No software level ceiling; per-setting controls below enforce safe limits.
    return max(0, p);
  }

  /// تشخیص پیش از اتصال؛ شواهد نامشخص، انتخاب قبلی کاربر را دست‌نخورده می‌گذارد.
  Future<NatNetworkClass> _pilotDetectNetworkMode() async {
    // Dedicated Smart Pilot probes; never consume general scanner results,
    // user IP ranges, or a probe routed through an active VPN tunnel.
    if (connected) return NatNetworkClass.unknown;
    try {
      final previousMode = nationalMode;
      final evidence = await PilotNetworkProbe.refresh()
          .timeout(const Duration(seconds: 9), onTimeout: () =>
              const NetworkEvidence(
                domestic: LinkHealth.unknown,
                global: LinkHealth.unknown,
              ));
      final strategy = choosePilotNetworkStrategy(evidence);
      if (!_pilotNetworkModePinned) {
        if (strategy == PilotNetworkStrategy.domestic) {
          nationalMode = true;
        } else if (strategy == PilotNetworkStrategy.global) {
          nationalMode = false;
        }
      } else {
        dbg('PILOT-MODE-PINNED: keeping explicit user-selected ${nationalMode ? 'domestic' : 'global'} strategy');
      }
      natForce = nationalMode;
      userModeChoice = nationalMode;
      if (previousMode != nationalMode) {
        _resetNetworkHealthCounters();
        await ultimateSave();
      }
      final modeLabel = switch (evidence.mode) {
        DetectedNetworkMode.domesticOnly => 'فقط مسیر داخلی تأیید شد',
        DetectedNetworkMode.globalOnly => 'مسیر جهانی تأیید شد',
        DetectedNetworkMode.dualStack => 'مسیر داخلی و جهانی هر دو در دسترس‌اند',
        DetectedNetworkMode.offline => 'هیچ مسیر آزمایشی پاسخ نداد',
        DetectedNetworkMode.unknown => 'شواهد کافی نیست؛ حالت قبلی حفظ شد',
      };
      final strategyLabel = nationalMode ? 'نت ملی' : 'جهانی/حالت قبلی';
      localPilotText.value = 'خلبان هوشمند ∞ • اسکن اختصاصی شبکه\n'
          '$modeLabel\nراهبرد: $strategyLabel • '
          'شواهد: داخلی ${evidence.domesticSamples} / جهانی ${evidence.globalSamples}';
      return switch (evidence.mode) {
        DetectedNetworkMode.domesticOnly => NatNetworkClass.domesticOnlyLikely,
        DetectedNetworkMode.globalOnly ||
        DetectedNetworkMode.dualStack => NatNetworkClass.globalReachable,
        DetectedNetworkMode.offline => NatNetworkClass.transportRestricted,
        DetectedNetworkMode.unknown => NatNetworkClass.unknown,
      };
    } catch (e, st) {
      logError(e, st);
      localPilotText.value = 'اسکن اختصاصی خلبان ناموفق بود؛ حالت قبلی حفظ شد.';
      return NatNetworkClass.unknown;
    }
  }

  void ensureLocalPilotRunning() {
    if (aiSession) stopAiSession();
    final wasOff = !localPilotOn;
    localPilotOn = true;
    wantVpn = true;
    abort = false;
    if (!wasOff && localPilotLoop != null) {
      // قبلاً روشن بوده — فقط مطمئن شو wantVpn زنده است
      return;
    }
    _localPhase = 'boot';
    _localTickN = 0;
    _localFailStreak = 0;
    _localSlowStreak = 0;
    _localGoodStreak = 0;
    _localNetFail = 0;
    _localConnectedSince = null;
    _localPeakPower = 1;
    _localPower = 1;
    _localApplyMaxPowerProfile(power: 1);
    localPilotText.value =
        '👑 خلبان خودکار فعال است\n'
        '⚠ تنظیمات برای خلبان عوض شد. برای جستجوی عادی: تنظیمات ← «برگرداندن همه‌ی عددها به پیش‌فرض»\n'
        '• فقط «اتصال» کافی است — بقیه اتوماتیک\n'
        '• قدرت ۰→∞ با اینترنت و مکان';
    _localReschedule();
    Future.delayed(const Duration(seconds: 3), () {
      if (localPilotOn) localPilotTick(force: true);
    });
    // تشخیص اپراتور و شبکه فقط یک بار در startLocalPilot انجام می‌شود.
  }

  Future<void> startLocalPilot({bool pinNetworkMode = false}) async {
    if (localPilotOn || _localPilotStarting) return;
    _pilotNetworkModePinned = pinNetworkMode;
    _localPilotStarting = true;
    try {
      _pilotSnap ??= _beginPilotSnap();
      // The primary pilot uses the one runtime actually shipped in this build.
      // It does not ask the user to choose a network mode or a fictional engine.
      applyPilotEngine('v2ray');
      // Load persisted endpoint outcomes before the first standby ranking.
      await NationalNetworkIntelligence.load();
      await _pilotDetectNetworkMode();
      _applyModePreset(nationalMode, offlineOnly, true); // one pilot, two internal strategies
      ensureLocalPilotRunning();
      // When the verified on-device model is loaded, attach King's advisory
      // loop to the same unified pilot. Without it, deterministic control still works.
      if (_hasAnyAiKey) {
        aiSession = true;
        aiAutopilotStart();
      }
      final eng = _engineLabel(pilotEngine);
      final modeLabel = nationalMode
          ? (_pilotNetworkModePinned ? 'نت ملی (انتخاب صریح)' : 'نت ملی (خودکار)')
          : (_pilotNetworkModePinned ? 'نت جهانی (انتخاب صریح)' : 'جهانی/حالت قبلی');
      localPilotText.value =
          '👑 خلبان هوشمند ∞ فعال شد • موتور: $eng\n'
          '• شبکه: $modeLabel\n'
          '• قدرت و روش اتصال بر اساس شواهد و منابع دستگاه تنظیم می‌شود\n'
          '• سلامت داخلی و جهانی مستقل ارزیابی می‌شوند';
    } catch (e, stk) {
      logError(e, stk);
      localPilotText.value = 'شروع خلبان ناموفق بود؛ تنظیمات قبلی بازیابی شد.';
      _pilotNetworkModePinned = false;
      _restorePilotSnap();
      return;
    } finally {
      _localPilotStarting = false;
    }
    unawaited(() async {
      try {
        final want = _localAutoPickPower();
        _localApplyMaxPowerProfile(power: want);
        if (!connected && !busy) {
          await connect();
        } else {
          await localPilotTick(force: true);
        }
      } catch (e, stk) {
        logError(e, stk);
        if (!connected && !busy) {
          try {
            await connect();
          } catch (e2) {
            logError(e2);
          }
        }
      }
    }());
  }

  // PILOTREV: خلبان (محلی و King) تنظیمات را موقتاً عوض می‌کند. قبل از اولین تغییر
  // مقدارهای کاربر ذخیره می‌شود و با توقف خلبان یا با اتصال عادی بعدی برمی‌گردد.
  Map<String, Object?> _takePilotSnap() => {
        'fwUserSet': fwUserSet,
        'fwUserValue': fwUserValue,
        'fastWorkers': fastWorkers,
        'bgWorkers': bgWorkers,
        'delayTimeout': delayTimeout,
        'tcpTimeout': tcpTimeout,
        'batchSize': batchSize,
        'badPingMs': badPingMs,
        'watchFailLimit': watchFailLimit,
        'speedTopN': speedTopN,
        'muxConc': muxConc,
        'ultraMode': ultraMode,
        'indestructibleMode': indestructibleMode,
        'fragEnabled': fragEnabled,
        'proxyMode': proxyMode,
        'turboSpeed': turboSpeed,
        'muxEnabled': muxEnabled,
        'autoSpeed': autoSpeed,
        'autoCycle': autoCycle,
        'savedFirst': savedFirst,
        'offlineOnly': offlineOnly,
        'minSpeedKB': minSpeedKB,
        'firstBatchSize': firstBatchSize,
        'maxBatches': maxBatches,
        'ipMode': ipMode,
        'iranRoute': iranRoute,
        'autoUpgrade': autoUpgrade,
        'fastDelay': fastDelay,
        'badPingSwitch': badPingSwitch,
        'cleanIpMode': cleanIpMode,
        'smartOrder': smartOrder,
        'protoSel': List<String>.from(protoSel),
        'numValues': <String, int>{for (final o in numOpts) o.id: o.get()},
      };

  // USERTOUCH: شروع خلبان؛ فقط وقتی snapshot تازه ساخته می‌شود مجموعه پاک می‌شود
  Map<String, Object?> _beginPilotSnap() {
    _pilotUserTouched.clear();
    return _takePilotSnap();
  }

  void _restorePilotSnap() {
    final s = _pilotSnap;
    if (s == null || localPilotOn || aiSession) return;
    _pilotSnap = null;
    if (!_pilotUserTouched.contains('fwUserSet')) fwUserSet = s['fwUserSet'] as bool? ?? fwUserSet;
    if (!_pilotUserTouched.contains('fwUserValue')) fwUserValue = s['fwUserValue'] as int? ?? fwUserValue;
    if (!_pilotUserTouched.contains('fastWorkers')) fastWorkers = s['fastWorkers'] as int;
    if (!_pilotUserTouched.contains('bgWorkers')) bgWorkers = s['bgWorkers'] as int;
    if (!_pilotUserTouched.contains('delayTimeout')) delayTimeout = s['delayTimeout'] as Duration;
    if (!_pilotUserTouched.contains('tcpTimeout')) tcpTimeout = s['tcpTimeout'] as Duration;
    if (!_pilotUserTouched.contains('batchSize')) batchSize = s['batchSize'] as int;
    if (!_pilotUserTouched.contains('badPingMs')) badPingMs = s['badPingMs'] as int;
    if (!_pilotUserTouched.contains('watchFailLimit')) watchFailLimit = s['watchFailLimit'] as int;
    if (!_pilotUserTouched.contains('speedTopN')) speedTopN = s['speedTopN'] as int;
    if (!_pilotUserTouched.contains('muxConc')) muxConc = s['muxConc'] as int;
    if (!_pilotUserTouched.contains('ultraMode')) ultraMode = s['ultraMode'] as bool;
    if (!_pilotUserTouched.contains('indestructibleMode')) indestructibleMode = s['indestructibleMode'] as bool;
    if (!_pilotUserTouched.contains('fragEnabled')) fragEnabled = s['fragEnabled'] as bool;
    if (!_pilotUserTouched.contains('proxyMode')) proxyMode = s['proxyMode'] as bool;
    if (!_pilotUserTouched.contains('turboSpeed')) turboSpeed = s['turboSpeed'] as bool;
    if (!_pilotUserTouched.contains('muxEnabled')) muxEnabled = s['muxEnabled'] as bool;
    if (!_pilotUserTouched.contains('autoSpeed')) autoSpeed = s['autoSpeed'] as bool;
    if (!_pilotUserTouched.contains('autoCycle')) autoCycle = s['autoCycle'] as bool;
    if (!_pilotUserTouched.contains('savedFirst')) savedFirst = s['savedFirst'] as bool;
    if (!_pilotUserTouched.contains('offlineOnly')) offlineOnly = s['offlineOnly'] as bool;
    if (!_pilotUserTouched.contains('minSpeedKB')) minSpeedKB = s['minSpeedKB'] as int;
    if (!_pilotUserTouched.contains('firstBatchSize')) firstBatchSize = s['firstBatchSize'] as int? ?? firstBatchSize;
    if (!_pilotUserTouched.contains('maxBatches')) maxBatches = s['maxBatches'] as int? ?? maxBatches;
    if (!_pilotUserTouched.contains('ipMode')) ipMode = s['ipMode'] as bool? ?? ipMode;
    if (!_pilotUserTouched.contains('iranRoute')) iranRoute = s['iranRoute'] as bool? ?? iranRoute;
    if (!_pilotUserTouched.contains('autoUpgrade')) autoUpgrade = s['autoUpgrade'] as bool? ?? autoUpgrade;
    if (!_pilotUserTouched.contains('fastDelay')) fastDelay = s['fastDelay'] as bool? ?? fastDelay;
    if (!_pilotUserTouched.contains('badPingSwitch')) badPingSwitch = s['badPingSwitch'] as bool? ?? badPingSwitch;
    if (!_pilotUserTouched.contains('cleanIpMode')) cleanIpMode = s['cleanIpMode'] as bool? ?? cleanIpMode;
    if (!_pilotUserTouched.contains('smartOrder')) smartOrder = s['smartOrder'] as bool? ?? smartOrder;
    final savedProto = s['protoSel'];
    if (savedProto is List && !_pilotUserTouched.contains('protoSel')) {
      protoSel
        ..clear()
        ..addAll(savedProto.whereType<String>());
    }
    final savedNums = s['numValues'];
    if (savedNums is Map) {
      for (final o in numOpts) {
        final value = savedNums[o.id];
        if (value is int && !_pilotUserTouched.contains(_numVarName(o.id))) {
          o.set(value.clamp(o.lo, o.hi).toInt());
        }
      }
      saveNumPrefs();
    }
    _pilotUserTouched.clear(); // USERTOUCH
    _localPower = 1;
    unawaited(_saveSettings());
  }

  void stopLocalPilot() {
    _pilotNetworkModePinned = false;
    localPilotOn = false;
    localPilotLoop?.cancel();
    localPilotLoop = null;
    _localPhase = 'boot';
    final peak = _localPeakPower;
    _localPower = 1;
    localPilotText.value =
        'خلبان متوقف شد.\nقله قدرت این نشست: $peak';
    if (aiSession) {
      stopAiSession(); // cancels King's local advisory loop and restores once
    } else {
      _restorePilotSnap(); // PILOTREV
    }
  }

}


// NUMPATCH ======================= عددهای قابل تنظیم =======================
// first search (used by patch_fast.py): it stops at the FIRST healthy server
// (for the web-reachability row: the first verified endpoint). Safety: after [firstCapSec]
// seconds it goes on with the ones found.
int firstCapSec = 15; // BEST: کمی بیشتر برای پیدا کردن سرور سالم

// the AI assistant must not change these
// AI may change every number (no locked keys)
const aiLockedNums = <String>{};

class NumOpt {
  final String id, title;
  final int lo, hi, def, aiHi; // hi = سقف واقعی که برنامه واقعاً اعمال می‌کند
  final bool extra; // shown in the extra section
  final int Function() get;
  final void Function(int) _setter;
  NumOpt(this.id, this.title, this.lo, this.hi, this.def, this.aiHi,
      this.extra, this.get, this._setter);
  // هر عددی بیرون از بازه‌ی واقعی بیاید (دستی، پروفایل، ریموت) به سقف کشیده می‌شود
  void set(int v) => _setter(v.clamp(lo, hi).toInt());
}

final List<NumOpt> numOpts = [
  // BEST PROFILE defaults — هم‌تراز با پیش‌فرض main.dart
  NumOpt('fastWorkers', 'تست همزمان (جستجوی اول)', 1, 32, 3, 32, false,
      () => fastWorkers.clamp(1, 32), (v) => fastWorkers = v.clamp(1, 32)),
  NumOpt('bgWorkers', 'تست همزمان (وقتی وصل است)', 1, 32, 3, 32, false,
      () => bgWorkers.clamp(1, 32), (v) => bgWorkers = v.clamp(1, 32)),
  NumOpt('timeout', 'تایم‌اوت هر تست (ثانیه)', 3, 45, 8, 45, false,
      () => delayTimeout.inSeconds, (v) => delayTimeout = Duration(seconds: v)),
  NumOpt('batch', 'اندازه دسته', 1, 300, 120, 300, false,
      () => batchSize, (v) => batchSize = v),
  NumOpt('minPingMs', 'حداقل پینگ معتبر', 0, 1000, 0, 1000, false,
      () => minPingMs, (v) => minPingMs = v),
  NumOpt('speedTopN', 'تعداد سرور برای تست سرعت', 1, 30, 5, 30, false,
      () => speedTopN, (v) => speedTopN = v),
  NumOpt('badPingMs', 'پینگ بد از', 70, 7000, 3000, 7000, false,
      () => badPingMs, (v) => badPingMs = v),
  NumOpt('minSpeedKB', 'تعویض اگر سرعت کمتر از', 0, 1000, 0, 1000, false,
      () => minSpeedKB, (v) => minSpeedKB = v),
  NumOpt('listRefreshMin', 'هر چند دقیقه لیست جدید', 1, 1440, 180, 1440, false,
      () => listRefreshMin, (v) => listRefreshMin = v),
  NumOpt('failMin', 'سرور خراب تا چند دقیقه تست نشود', 1, 1440, 90, 1440, false,
      () => failMin, (v) {
    failMin = v;
    failWindow = Duration(minutes: v);
  }),
  NumOpt('recheckMin', 'بررسی دوباره سرورهای سالم (دقیقه)', 1, 1440, 20, 1440,
      false, () => recheckMin, (v) {
    recheckMin = v;
    recheckAfter = Duration(minutes: v);
  }),
  // ----- 12 new options -----
  NumOpt('tcpWorkers', 'پیش‌فیلتر TCP همزمان', 1, 200, 60, 200, true,
      () => tcpWorkers, (v) => tcpWorkers = v),
  NumOpt('tcpTimeout', 'تایم‌اوت TCP (دهم ثانیه)', 1, 300, 35, 300, true,
      () => tcpTimeout.inMilliseconds ~/ 100,
      (v) => tcpTimeout = Duration(milliseconds: v * 100)),
  NumOpt('maxPerSource', 'حداکثر سرور از هر منبع', 1, 500, 120, 500, true,
      () => maxPerSource, (v) => maxPerSource = v),
  NumOpt('fetchWorkers', 'دانلود همزمان لیست‌ها', 1, 20, 8, 20, true,
      () => fetchWorkers, (v) => fetchWorkers = v),
  NumOpt('fetchDeadline', 'مهلت دانلود لیست‌ها (ثانیه)', 5, 120, 45, 120, true,
      () => fetchDeadline.inSeconds,
      (v) => fetchDeadline = Duration(seconds: v)),
  NumOpt('firstBatchSize', 'اندازه دسته‌ی اول', 1, 300, 50, 300, true,
      () => firstBatchSize, (v) => firstBatchSize = v),
  NumOpt('standbyBatchSize', 'اندازه دسته (وقتی وصل است)', 1, 300, 40, 300,
      true, () => standbyBatchSize, (v) => standbyBatchSize = v),
  NumOpt('maxBatches', 'حداکثر تعداد دسته در هر جستجو', 1, 50, 8, 50, true,
      () => maxBatches, (v) => maxBatches = v),
  NumOpt('watchFailLimit', 'تعداد پینگ ناموفق تا تعویض', 1, 10, 3, 10, true,
      () => watchFailLimit, (v) => watchFailLimit = v),
  NumOpt('badPingLimit', 'تعداد پینگ بد تا تعویض', 1, 10, 3, 10, true,
      () => badPingLimit, (v) => badPingLimit = v),
  NumOpt('missLimit', 'تعداد شکست تا حذف سرور سالم', 1, 10, 3, 10, true,
      () => missLimit, (v) => missLimit = v),
  NumOpt('watchEvery', 'فاصله‌ی چک اتصال (ثانیه)', 5, 300, 30, 300, true,
      () => watchEvery.inSeconds, (v) => watchEvery = Duration(seconds: v)),
  // ----- first search: time cap -----
  NumOpt('firstCapSec', 'سقف زمان جستجوی اول (ثانیه)', 5, 120, 15, 120, true,
      () => firstCapSec, (v) => firstCapSec = v),
];

// یک‌بار: همگام‌سازی با پروفایل BEST (اگر قبلاً فقط batch300 اعمال شده بود)
Future<void> loadNumPrefs(SharedPreferences p) async {
  await _loadNumPrefs0(p);
  if (p.getBool('bestProfile26') != true) {
    for (final o in numOpts) {
      o.set(o.def);
    }
    await p.setBool('bestProfile26', true);
    await p.setBool('batch300', true); // جلوگیری از override قدیمی
    saveNumPrefs();
  }
  // FWDEF27: پیش‌فرض جدید یک‌بار برای نصب‌های قدیمی: جستجوی اول ۲۰، وقتی وصل است ۳
  if (p.getBool('fwDefault27') != true) {
    fastWorkers = 3;
    bgWorkers = 3;
    await p.setBool('fwDefault27', true);
    saveNumPrefs();
  }
  if (p.getBool('bgWorkersOne') != true) {
    bgWorkers = 3; // تست همزمان (وقتی وصل است) → ۳
    await p.setBool('bgWorkersOne', true);
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
    final fu = j['fwUser']; // FWUSER
    if (fu is num && fu.toInt() >= 1) {
      fwUserValue = fu.toInt().clamp(1, 32).toInt();
      fwUserSet = true;
      fastWorkers = fwUserValue;
    }
  } catch (e, stk) {
    logError(e, stk);
  }
}

Future<void> saveNumPrefs() async {
  try {
    final p = await SharedPreferences.getInstance();
    final mp = <String, int>{for (final o in numOpts) o.id: o.get()};
    // NUMPREF: همه‌ی کلیدهای numOpts پوشش داده می‌شوند؛ اگر snapshot فعال
    // است، مقدار snapshot بر مقدار زنده اولویت دارد.
    final sv = _pilotSnap?['numValues'];
    if (sv is Map) {
      for (final o in numOpts) {
        final v = sv[o.id];
        if (v is int && !_pilotUserTouched.contains(_numVarName(o.id))) {
          mp[o.id] = v;
        }
      }
    }
    mp['fwUser'] = fwUserSet ? fwUserValue : 0; // FWUSER
    await p.setString('numx', jsonEncode(mp));
  } catch (e, stk) {
    logError(e, stk);
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
            o.hi.toDouble(),
            0,
            (x) {
              _markUserTouched([_numVarName(o.id)]);
              o.set(x.round());
            }),
    ];

extension NumHomeExtras on _HomePageState {
  void resetNumbers() {
    if (localPilotOn) stopLocalPilot(); // RESETSNAP
    if (aiSession) stopAiSession(); // RESETSNAP
    _pilotSnap = null; // RESETSNAP
    _pilotUserTouched.clear(); // RESETSNAP
    _markUserTouched(_allTouchKeys());
    _applyModePreset(false, false, false); // BESTDEF
    for (final o in numOpts) {
      o.set(o.def);
    }
    // بولین‌های BEST هم برگردند
    autoSpeed = false; // تست سرعت پیش‌فرض خاموش است
    autoUpgrade = true;
    badPingSwitch = true;
    savedFirst = true;
    smartOrder = true;
    autoCycle = true;
    turboSpeed = true;
    betterSwitch = true;
    sortSpeed = true;
    secureDns = true;
    dnsProv = 'auto';
    muxEnabled = true;
    muxConc = 32;
    fragEnabled = false;
    cleanIpMode = true;
    npvParse = true;
    saveNumPrefs();
    _saveSettings();
    autoTune = false; // AUTOTUNEPATCH: reset = manual numbers
    autoTuneSave();
    _set('✅ همه‌ی عددها و تنظیمات سرعت به پیش‌فرض BEST برگشتند');
  }

  // برگرداندن کامل: همه‌ی عددها + همه‌ی کلیدهای روشن/خاموش به مقدار اولیه‌ی برنامه
  void resetAllToDefaults() {
    if (localPilotOn) stopLocalPilot(); // RESETSNAP
    if (aiSession) stopAiSession(); // RESETSNAP
    _pilotSnap = null; // RESETSNAP
    _pilotUserTouched.clear(); // RESETSNAP
    _markUserTouched(_allTouchKeys());
    _applyModePreset(false, false, false); // BESTDEF

    SharedPreferences.getInstance().then((p) async {
      for (final k in const [
        'speedoff27', 'lowdata_v1', 'restore_speed_v1', 'best_defaults_v4',
        'fw5_v1', 'workers12_v2', 'contsearch_v1', 'cip_v2', 'idm_v2',
        'nat_v2', 'defsync_v1', 'defsync_v2', 'badping2000_v1',
        'tuned_v1', 'tuned_v2', 'tuned_v3', 'tuned_v4', 'tuned_v5',
        'bestProfile26', 'fwDefault27', 'bgWorkersOne',
      ]) {
        await p.setBool(k, true);
      }
      await p.setBool('autotune_on2', false);
    });
    natRound = 1;
    sniSpoofAll = true;
    muxConc = 32;
    resetNumbers();
    fwUserSet = false; // FWUSER: برگشت به پیش‌فرض ۳
    fwUserValue = 3;
    autoTune = false;
    proxyMode = false;
    onlyHealthySrc = true;
    ipMode = false;
    ultraMode = false;
    indestructibleMode = true;
    turboSpeed = true;
    fastDelay = true;
    iranRoute = true;
    iranGeoip = false;
    iranMore = true;
    blockQuic = true;
    lanDirect = true;
    routeOnly = false;
    fragEnabled = false;
    muxEnabled = true;
    secureDns = true;
    cleanIpMode = true;
    npvParse = true;
    offlineOnly = false;
    dataSaver = false;
    autoNetReconnect = true;
    preflightOn = true;
    saveNumPrefs();
    unawaited(_saveSettings());
    unawaited(ultimateSave());
    unawaited(autoTuneSave());
    _set('✅ همه‌ی تنظیمات به پیش‌فرض برگشتند');
  }

  Widget resetNumButton(StateSetter setS) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => setS(resetAllToDefaults),
            icon: const Icon(Icons.restart_alt),
            label: const Text('↩️ برگرداندن همه‌ی تنظیمات به پیش‌فرض'),
          ),
        ),
      );

  // AI suggestions use hardware-safe ceilings; manual settings keep their full ranges.
  void applyNumSuggest(Map<String, int> m) {
    // Numeric controls can expose broad manual ranges, but an AI response must
    // never turn them into thousands of concurrent sockets/workers or huge batches.
    const aiSafeMax = <String, int>{
      'fastWorkers': 20,
      'bgWorkers': 3,
      'timeout': 45,
      'batch': 300,
      'tcpWorkers': 20,
      'tcpTimeout': 150,
      'maxPerSource': 200,
      'fetchWorkers': 8,
      'fetchDeadline': 60,
      'firstBatchSize': 200,
      'standbyBatchSize': 100,
      'maxBatches': 10,
      'watchFailLimit': 10,
      'badPingLimit': 10,
      'missLimit': 10,
      'watchEvery': 180,
      'firstCapSec': 30,
      'speedTopN': 10,
    };
    for (final o in numOpts) {
      if (aiLockedNums.contains(o.id)) continue;
      final v = m['num_${o.id}'];
      if (v != null) {
        final safeHi = min(o.hi, aiSafeMax[o.id] ?? o.hi);
        o.set(v.clamp(o.lo, safeHi).toInt());
      }
    }
    saveNumPrefs();
  }
}


// TUNEDPATCH ===================== مقدارهای بهینه BEST (یکدست با numOpts) =====================
const Map<String, dynamic> _tunedSettings = {
  't': 8, // delayTimeout sec
  'bw2': 3, // bgWorkers
  'st': 5, // speedTopN
  'bp': 3000, // badPingMs
  'ms': 0, // minSpeedKB
  'lr': 180, // listRefreshMin
  'fm': 90, // failMin
  'rm': 20, // recheckMin
  'a2': true, // autoUpgrade
  'i': true, // ?
  'cip': true, // cleanIpMode
  'sdns': true, // secureDns
  'sf': true, // savedFirst
  'so': true, // smartOrder
  'ac': true, // autoCycle
  'o': true,
  'u': false,
  'fd': true,
  'bps': true, // badPingSwitch
  'npv': true, // npvParse
  'irm': true, // iranMore
  'bq': true, // blockQuic
  'lan': true, // lanDirect
  'ro': false, // routeOnly
  'frg': false, // fragEnabled
  'mux': true,
  'mc': 32, // muxConc
  'ig': false, // iranGeoip
  'um': false, // ultraMode — پیش‌فرض خاموش (جستجو سریع‌تر)
  'idm': true, // indestructibleMode
  'tb': true, // turboSpeed
  'fw2': 3, // fastWorkers
};
// BEST PROFILE — هم‌تراز numOpts.def
const Map<String, int> _tunedNums = {
  'fastWorkers': 3,
  'bgWorkers': 3,
  'timeout': 8,
  'batch': 120,
  'speedTopN': 5,
  'badPingMs': 3000,
  'minSpeedKB': 0,
  'listRefreshMin': 180,
  'failMin': 90,
  'recheckMin': 20,
  'tcpWorkers': 60,
  'tcpTimeout': 35,
  'maxPerSource': 120,
  'fetchWorkers': 6,
  'fetchDeadline': 25,
  'firstBatchSize': 50,
  'standbyBatchSize': 40,
  'maxBatches': 8,
  'watchFailLimit': 3,
  'badPingLimit': 3,
  'missLimit': 3,
  'watchEvery': 30,
  'firstCapSec': 15,
};

// v2/v3/v4: همان BEST تا نسخه‌های قدیمی هم یکدست شوند
const Map<String, dynamic> _tunedSettings2 = {
  't': 8,
  'bw2': 3,
  'st': 5,
  'bp': 3000,
  'ms': 0,
  'lr': 180,
  'fm': 90,
  'rm': 20,
  'a2': true,
  'ac': true,
  'frg': false,
  'mux': true,
  'mc': 32,
  'tb': true,
  'um': false,
  'idm': true,
  'sf': true,
  'so': true,
  'bps': true,
  'sdns': true,
  'fw2': 3,
};
const Map<String, int> _tunedNums2 = {
  'fastWorkers': 3,
  'bgWorkers': 3,
  'timeout': 8,
  'batch': 120,
  'speedTopN': 5,
  'badPingMs': 3000,
  'minSpeedKB': 0,
  'listRefreshMin': 180,
  'failMin': 90,
  'recheckMin': 20,
  'tcpWorkers': 60,
  'tcpTimeout': 35,
  'maxPerSource': 120,
  'fetchWorkers': 6,
  'fetchDeadline': 25,
  'firstBatchSize': 50,
  'standbyBatchSize': 40,
  'maxBatches': 8,
  'watchFailLimit': 3,
  'badPingLimit': 3,
  'firstCapSec': 15,
};

const Map<String, dynamic> _tunedSettings3 = {
  't': 8,
  'bw2': 3,
  'st': 5,
  'bp': 3000,
  'ms': 0,
  'lr': 180,
  'fm': 90,
  'rm': 20,
  'a2': true,
  'ac': true,
  'frg': false,
  'mux': true,
  'mc': 32,
  'tb': true,
  'um': false,
  'idm': true,
  'sf': true,
  'so': true,
  'bps': true,
  'sdns': true,
  'fw2': 3,
};
const Map<String, int> _tunedNums3 = {
  'fastWorkers': 3,
  'bgWorkers': 3,
  'timeout': 8,
  'batch': 120,
  'speedTopN': 5,
  'badPingMs': 3000,
  'minSpeedKB': 0,
  'listRefreshMin': 180,
  'failMin': 90,
  'recheckMin': 20,
  'tcpWorkers': 60,
  'fetchWorkers': 6,
  'firstBatchSize': 50,
  'standbyBatchSize': 40,
  'maxBatches': 8,
  'firstCapSec': 15,
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
    // TUNEDV2: best values for national / slow internet, applied ONCE.
    // fastWorkers is forced to 50 (the user's fixed number).
    if (p.getBool('tuned_v2') != true) {
      final st = p.getString('settings');
      if (st != null) {
        final j = jsonDecode(st);
        if (j is Map) {
          final m = Map<String, dynamic>.from(j);
          _tunedSettings2.forEach((k, v) => m[k] = v);
          m['fw2'] = 3;
          await p.setString('settings', jsonEncode(m));
        }
      }
      final nx = p.getString('numx');
      if (nx != null) {
        final j = jsonDecode(nx);
        if (j is Map) {
          final m = Map<String, dynamic>.from(j);
          _tunedNums2.forEach((k, v) => m[k] = v);
          m['fastWorkers'] = 3;
          await p.setString('numx', jsonEncode(m));
        }
      }
      await p.setBool('tuned_v2', true);
    }
    // TUNEDV3 kept as applied flag for old installs
    if (p.getBool('tuned_v3') != true) {
      await p.setBool('tuned_v3', true);
    }
    // TUNEDV4: low data + multi-x speed + fastWorkers=50; AI fully free
    if (p.getBool('tuned_v4') != true) {
      final st = p.getString('settings');
      if (st != null) {
        final j = jsonDecode(st);
        if (j is Map) {
          final m = Map<String, dynamic>.from(j);
          _tunedSettings3.forEach((k, v) => m[k] = v);
          m['fw2'] = 3;
          await p.setString('settings', jsonEncode(m));
        }
      } else {
        await p.setString(
            'settings',
            jsonEncode({
              'ver': 6,
              ..._tunedSettings3,
              'fw2': 3,
            }));
      }
      final nx = p.getString('numx');
      if (nx != null) {
        final j = jsonDecode(nx);
        if (j is Map) {
          final m = Map<String, dynamic>.from(j);
          _tunedNums3.forEach((k, v) => m[k] = v);
          m['fastWorkers'] = 3;
          await p.setString('numx', jsonEncode(m));
        }
      }
      await p.setBool('tuned_v4', true);
    }
    // TUNEDV5: پروفایل BEST (سرعت + پایداری) — یک‌بار برای همه نصب‌های قدیمی
    if (p.getBool('tuned_v5') != true) {
      final st = p.getString('settings');
      if (st != null) {
        final j = jsonDecode(st);
        if (j is Map) {
          final m = Map<String, dynamic>.from(j);
          _tunedSettings.forEach((k, v) => m[k] = v);
          m['fw2'] = 3;
          m['st'] = 5;
          m['bw2'] = 3;
          m['bp'] = 3000;
          m['ms'] = 0;
          m['a2'] = true;
          m['ac'] = true;
          m['tb'] = true;
          m['mux'] = true;
          m['mc'] = 32;
          await p.setString('settings', jsonEncode(m));
        }
      }
      final nx = p.getString('numx');
      if (nx != null) {
        final j = jsonDecode(nx);
        if (j is Map) {
          final m = Map<String, dynamic>.from(j);
          _tunedNums.forEach((k, v) => m[k] = v);
          m['fastWorkers'] = 3;
          await p.setString('numx', jsonEncode(m));
        }
      } else {
        await p.setString('numx', jsonEncode(_tunedNums));
      }
      await p.setBool('tuned_v5', true);
      await p.setBool('bestProfile26', true);
    }
  } catch (e, stk) {
    logError(e, stk);
  }
  return p.getString('settings');
}

// ======================= خلبان هوشمند ∞ (موتور محلی King Pro، بدون کلید API) =======================
// موتور تصمیم‌گیری چندلایه — سریع‌تر و پایدارتر از هر دستیار ابری.
// لایه‌ها: پروب واقعی سایت‌ها | امتیازدهی چندعاملی | حافظه اپراتور | ماشین‌حالت
// هیچ کلید API لازم نیست. تا قطع دستی کاربر، کنترل کامل دارد.

int _localConnFail = 0; // DOHAUTO: connect failures in a row
int _localGoodTog = 0; // TOGGLES: connected ticks in a row
bool localPilotOn = false;
bool _localPilotStarting = false; // prevents duplicate starts during network classification
// Explicit owner/user network commands stay pinned for this Pilot session.
// Automatic Pilot mode may still switch when fresh quorum evidence changes.
bool _pilotNetworkModePinned = false;

// FWUSER: مقدار دستی کاربر برای «تست همزمان (جستجوی اول)». پیش‌فرض ۳؛
// اگر کاربر خودش عدد گذاشته باشد، هر اتصال عادی همان عدد (تا ۳۲) را نگه می‌دارد.
int fwUserValue = 3;
bool fwUserSet = false;
void setUserFastWorkers(int v) {
  _markUserTouched(const ['fastWorkers', 'fwUserSet', 'fwUserValue']);
  fwUserValue = v.clamp(1, 32).toInt();
  fwUserSet = true;
  fastWorkers = fwUserValue;
}
bool healActive = false; // ADAUTO: خودترمیمی خودکار در حال کار است
// انتخاب صریح کاربر: null = نامشخص (خودکار)، true = نت ملی، false = نت جهانی
bool? userModeChoice;
int _localRetryN = 0; // تعداد تلاش‌های تیک خلبان که گم شده (فیلد باید بیرون extension باشد)
// انتخاب صریح کاربر: null = نامشخص، true = آفلاین، false = آنلاین
bool? userOfflineChoice;
Map<String, Object?>? _pilotSnap; // PILOTREV: قبل از تغییر خلبان، تنظیمات کاربر (top-level چون extension نمی‌تونه فیلد داشته باشه)

// SNAPHELPER: مقدار مؤثر یک کلید تنظیمات. اگر خلبان فعال است و snapshot
// مقداری دارد، آن برمی‌گردد؛ وگرنه مقدار زنده. saveNumPrefs و _saveSettings
// فقط از این هلپرها می‌خوانند تا مقدار موقت خلبان روی دیسک ننشیند.
Object? _eff(Map<String, Object?>? snap, String topKey, Object? live) {
  if (_pilotUserTouched.contains(topKey)) return live;
  final v = snap?[topKey];
  return v ?? live;
}

// SNAPHELPER: Duration از snapshot به ثانیه (int) تبدیل می‌شود؛ jsonEncode روی Duration خطا می‌دهد.
int _effSec(Map<String, Object?>? snap, String topKey, Duration live) {
  if (_pilotUserTouched.contains(topKey)) return live.inSeconds;
  final v = snap?[topKey];
  return v is Duration ? v.inSeconds : live.inSeconds;
}

// SNAPHELPER: مقدار عددی numOpts از snapshot.numValues (همه‌ی numOpts آن‌جا هستند).
int _effNum(Map<String, Object?>? snap, String numId, int live) {
  if (_pilotUserTouched.contains(_numVarName(numId))) return live;
  final nv = snap?['numValues'];
  if (nv is Map && nv[numId] is int) return nv[numId] as int;
  return live;
}

// USERTOUCH: نام متغیرهای snapshot که کاربر در حین خلبان صریحاً عوض کرده.
// فقط وقتی خلبان فعال است (snapshot هست) پر می‌شود. restore برای این کلیدها
// مقدار زنده را نگه می‌دارد، و saveNumPrefs/_saveSettings هم همین مقدار را
// می‌نویسند تا دیسک با حالت بعد از restore یکی بماند.
final Set<String> _pilotUserTouched = <String>{};

void _markUserTouched(Iterable<String> keys) {
  if (_pilotSnap != null) _pilotUserTouched.addAll(keys);
}

// USERTOUCH: id عددی numOpts → نام متغیر در snapshot
String _numVarName(String id) => id == 'batch'
    ? 'batchSize'
    : id == 'timeout'
        ? 'delayTimeout'
        : id;

// USERTOUCH: همه‌ی کلیدهایی که reset کاربر ممکن است عوض کند
Iterable<String> _allTouchKeys() => <String>[
      'fwUserSet', 'fwUserValue', 'fastWorkers', 'bgWorkers', 'delayTimeout',
      'tcpTimeout', 'batchSize', 'badPingMs', 'watchFailLimit', 'speedTopN',
      'muxConc', 'ultraMode', 'indestructibleMode', 'fragEnabled', 'proxyMode',
      'turboSpeed', 'muxEnabled', 'autoSpeed', 'autoCycle', 'savedFirst',
      'offlineOnly', 'minSpeedKB', 'firstBatchSize', 'maxBatches', 'ipMode',
      'iranRoute', 'autoUpgrade', 'fastDelay', 'badPingSwitch', 'cleanIpMode',
      'smartOrder', 'protoSel', 'numValues',
      ...numOpts.map((o) => _numVarName(o.id)),
    ];
// سیاست شبکه ملی/جهانی در مدل مستقل NetworkEvidence نگهداری می‌شود؛
// شکست Global نباید سلامت Domestic را به‌تنهایی باطل کند.
bool? _pendingNet; // NETCANCEL: انتخاب شبکه‌ی موقت تا انتخاب موتور
bool _pendingOff = false;
Timer? localPilotLoop;
final localPilotText = ValueNotifier<String>(
    'خلبان هوشمند ∞ آماده است.\nیادگیری محلی • تحلیل واقعی شبکه • بدون وابستگی به API');
final localPilotLoading = ValueNotifier<bool>(false);

// Track flags forced by cloud pilot so stop can restore them
bool _pilotForcedUltra = false;
bool _pilotForcedIndestructible = false;
DateTime? _pilotConnectedAt; // hold before cloud pilot may switch
// Engine ID from EngineCapabilityRegistry; only verified runtimes are selectable.
String pilotEngine = 'v2ray';

// قدرت خلبان محلی
int _localPower = 1;
int _localPeakPower = 1; // بالاترین قدرت دیده‌شده در این نشست

String _localLastOp = '';
String _localLastAction = '';
DateTime? _localLastTick;
DateTime? _localAiAdvisorAt; // throttles optional on-device LLM pilot reviews
DateTime? _busyStuckSince; // BUSYCLEAR: when the busy flag started looking stuck
DateTime? _localConnectedSince;
int _localFailStreak = 0;
int _localSlowStreak = 0;
int _localGoodStreak = 0;
int _localTickN = 0;
int _localSvcFail = 0; // consecutive active-network data-plane probe failures
int _localNetFail = 0;

// حافظه یادگیری محلی: اپراتور → آخرین اقدام موفق / امتیاز
Map<String, int> _localOpWins = {}; // confirmed successes by operator/action
Map<String, int> _localOpLosses = {}; // confirmed failures by operator/action
const String _pilotExperiencePrefsKey = 'king_pilot_experience_v1';
bool _pilotExperienceLoaded = false;
String _pilotExperienceOperatorKey(String operator) =>
    'v2|${operator.trim().isEmpty ? 'unknown' : operator.trim()}|${nationalMode ? 'domestic' : 'global'}';
String? _pilotPendingExperienceKey;
bool _pilotPendingWasConnected = false;
String? _pilotPendingServerLink;
int _pilotPendingPositiveSamples = 0;
DateTime? _pilotPendingLastPositiveAt;
DateTime? _pilotPendingExperienceAt;
final Map<String, int> _localOpFails = {};

// ماشین‌حالت
// boot | search | stable | degraded | recover
String _localPhase = 'boot';

class _LocalNetSnap {
  final bool connected;
  final bool wifi;
  final String operatorKey;
  final String configProto;
  final String configNet;
  final String configSec;
  final int? pingMs;
  final double? speedMBs; // MB/s
  final int goodCount;
  final int pendingCount;
  final int failedCount;
  final bool turbo;
  final bool frag;
  final bool mux;
  final String reason;
  // پروب زنده
  final bool? tgOk;
  final bool? ytOk;
  final bool? igOk;
  final bool? netOk;
  final int score; // 0..100
  final int svcMask; // current server svc bits

  _LocalNetSnap({
    required this.connected,
    required this.wifi,
    required this.operatorKey,
    required this.configProto,
    required this.configNet,
    required this.configSec,
    required this.pingMs,
    required this.speedMBs,
    required this.goodCount,
    required this.pendingCount,
    required this.failedCount,
    required this.turbo,
    required this.frag,
    required this.mux,
    required this.reason,
    this.tgOk,
    this.ytOk,
    this.igOk,
    this.netOk,
    this.score = 0,
    this.svcMask = -1,
  });

  String toHuman() {
    final b = StringBuffer();
    b.writeln(connected ? '🟢 متصل' : '🔴 قطع');
    b.writeln('🧠 فاز: $_localPhase  |  امتیاز: $score/100');
    if (operatorKey.isNotEmpty) b.writeln('📡 اپراتور: $operatorKey');
    if (configProto != '-') {
      b.writeln('⚙️ $configProto / $configNet / $configSec');
    }
    if (pingMs != null) b.writeln('⏱ پینگ: ${pingMs}ms');
    if (speedMBs != null && speedMBs! > 0) {
      b.writeln('🚀 سرعت: ${speedMBs!.toStringAsFixed(2)} MB/s');
    }
    b.writeln(
        '📦 سالم:$goodCount  صف:$pendingCount  سیاه:$failedCount');
    b.writeln(
        '🔧 turbo=${turbo ? "✓" : "✗"} mux=${mux ? "✓" : "✗"} frag=${frag ? "✓" : "✗"}');
    if (reason.isNotEmpty) b.writeln('📝 $reason');
    return b.toString().trim();
  }
}

class _LocalDecision {
  final String action;
  final Map<String, int> settings;
  final String explain;
  final int confidence; // 0..100

  _LocalDecision(this.action, this.settings, this.explain,
      {this.confidence = 70});
}

// Local-first command field: commands stay on-device and are routed to the
// app's Smart Pilot. No external AI key or network request is required.
