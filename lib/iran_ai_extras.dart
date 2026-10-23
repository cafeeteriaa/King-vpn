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

// ======================= Multi-AI =======================
// Gemini / Grok (xAI) / Claude (Anthropic) / ChatGPT (OpenAI) / DeepSeek
String geminiKey = '';
String geminiModel = 'gemini-flash-latest';
String grokKey = '';
String grokModel = 'grok-3';
String claudeKey = '';
String claudeModel = 'claude-sonnet-4-20250514';
String openaiKey = '';
String openaiModel = 'gpt-4o-mini';
String deepseekKey = '';
String deepseekModel = 'deepseek-chat';
// auto | grok | claude | openai | deepseek | gemini
String aiProvider = 'auto';
String aiLastProvider = '';

class GeminiLocationError implements Exception {
  @override
  String toString() => 'Gemini روی IP این سرور مسدود است (منطقه/آی‌پی)';
}

class AiApiError implements Exception {
  final String msg;
  AiApiError(this.msg);
  @override
  String toString() => msg;
}

class GrokApiError extends AiApiError {
  GrokApiError(super.msg);
}

final aiText = ValueNotifier<String>('');
final aiLoading = ValueNotifier<bool>(false);
// تنظیمات پیشنهادی دستیار (کلید → عدد). با دکمه‌ی «اعمال» روی اپ اعمال می‌شود.
final aiSuggest = ValueNotifier<Map<String, int>>(<String, int>{});
DateTime _lastAutoAi = DateTime.fromMillisecondsSinceEpoch(0);
String aiActionName = '';

bool get _hasAnyAiKey =>
    geminiKey.isNotEmpty ||
    grokKey.isNotEmpty ||
    claudeKey.isNotEmpty ||
    openaiKey.isNotEmpty ||
    deepseekKey.isNotEmpty;

Future<void> loadGeminiPrefs(SharedPreferences p) async {
  geminiKey = p.getString('gem_key') ?? '';
  geminiModel = p.getString('gem_model') ?? geminiModel;
  grokKey = p.getString('grok_key') ?? '';
  grokModel = p.getString('grok_model') ?? grokModel;
  claudeKey = p.getString('claude_key') ?? '';
  claudeModel = p.getString('claude_model') ?? claudeModel;
  openaiKey = p.getString('openai_key') ?? '';
  openaiModel = p.getString('openai_model') ?? openaiModel;
  deepseekKey = p.getString('deepseek_key') ?? '';
  deepseekModel = p.getString('deepseek_model') ?? deepseekModel;
  aiProvider = p.getString('ai_prov') ?? aiProvider;
}

Future<void> saveGeminiPrefs() async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString('gem_key', geminiKey);
    await p.setString('gem_model', geminiModel);
    await p.setString('grok_key', grokKey);
    await p.setString('grok_model', grokModel);
    await p.setString('claude_key', claudeKey);
    await p.setString('claude_model', claudeModel);
    await p.setString('openai_key', openaiKey);
    await p.setString('openai_model', openaiModel);
    await p.setString('deepseek_key', deepseekKey);
    await p.setString('deepseek_model', deepseekModel);
    await p.setString('ai_prov', aiProvider);
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
  } catch (e) {
    logError(e);
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
      } catch (e) {
        logError(e);
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
      if (t != null) {
        aiLastProvider = 'Gemini';
        return t;
      }
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

// ----------------------- Grok (xAI) -----------------------
Future<String?> _grokTry(String route, String prompt) async {
  if (grokKey.isEmpty) return null;
  final c = HttpClient()
    ..findProxy = ((_) => route)
    ..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await c
        .postUrl(Uri.parse('https://api.x.ai/v1/chat/completions'))
        .timeout(const Duration(seconds: 10));
    req.headers.set('content-type', 'application/json');
    req.headers.set('authorization', 'Bearer $grokKey');
    req.add(utf8.encode(jsonEncode({
      'model': grokModel,
      'messages': [
        {
          'role': 'system',
          'content':
              'You are Grok, the AI assistant inside King VPN (Iran). '
              'Answer in Persian. Be practical about VPN, national net, speed, and settings.'
        },
        {'role': 'user', 'content': prompt}
      ],
      'temperature': 0.4,
    })));
    final res = await req.close().timeout(const Duration(seconds: 45));
    final body = await res
        .transform(const Utf8Decoder(allowMalformed: true))
        .join()
        .timeout(const Duration(seconds: 45));
    if (res.statusCode == 200) {
      try {
        final j = jsonDecode(body);
        final t = (j['choices'][0]['message']['content'] ?? '').toString().trim();
        return t.isEmpty ? 'پاسخ خالی بود.' : t;
      } catch (e) {
        logError(e);
        throw GrokApiError('پاسخ Grok قابل خواندن نبود');
      }
    }
    final cut = body.length > 180 ? body.substring(0, 180) : body;
    throw GrokApiError('Grok ${res.statusCode}: $cut');
  } finally {
    c.close(force: true);
  }
}

Future<String> grokAsk(String prompt) async {
  final routes = proxyMode
      ? <String>['PROXY 127.0.0.1:$httpProxyPort', 'DIRECT']
      : <String>['DIRECT', 'PROXY 127.0.0.1:$httpProxyPort'];
  Object? lastErr;
  for (final r in routes) {
    try {
      final t = await _grokTry(r, prompt);
      if (t != null) {
        aiLastProvider = 'Grok';
        return t;
      }
    } on IOException catch (e) {
      lastErr = e;
    } on TimeoutException catch (e) {
      lastErr = e;
    } on GrokApiError catch (e) {
      lastErr = e;
    }
  }
  throw lastErr ?? Exception('Grok بدون پاسخ');
}

// OpenAI-compatible chat (ChatGPT, DeepSeek, and similar)
Future<String?> _openAiCompatTry({
  required String route,
  required String prompt,
  required String key,
  required String model,
  required String url,
  required String label,
  Map<String, String>? extraHeaders,
}) async {
  if (key.isEmpty) return null;
  final c = HttpClient()
    ..findProxy = ((_) => route)
    ..connectionTimeout = const Duration(seconds: 8);
  try {
    final req =
        await c.postUrl(Uri.parse(url)).timeout(const Duration(seconds: 10));
    req.headers.set('content-type', 'application/json');
    req.headers.set('authorization', 'Bearer $key');
    extraHeaders?.forEach(req.headers.set);
    req.add(utf8.encode(jsonEncode({
      'model': model,
      'messages': [
        {
          'role': 'system',
          'content':
              'You are the AI assistant inside King VPN (Iran). '
              'Answer in Persian. Be practical about VPN, national net, speed, settings.'
        },
        {'role': 'user', 'content': prompt}
      ],
      'temperature': 0.4,
    })));
    final res = await req.close().timeout(const Duration(seconds: 50));
    final body = await res
        .transform(const Utf8Decoder(allowMalformed: true))
        .join()
        .timeout(const Duration(seconds: 50));
    if (res.statusCode == 200) {
      try {
        final j = jsonDecode(body);
        final t =
            (j['choices'][0]['message']['content'] ?? '').toString().trim();
        return t.isEmpty ? 'پاسخ خالی بود.' : t;
      } catch (e) {
        logError(e);
        throw AiApiError('پاسخ $label قابل خواندن نبود');
      }
    }
    final cut = body.length > 180 ? body.substring(0, 180) : body;
    throw AiApiError('$label ${res.statusCode}: $cut');
  } finally {
    c.close(force: true);
  }
}

Future<String> _openAiCompatAsk({
  required String prompt,
  required String key,
  required String model,
  required String url,
  required String label,
  Map<String, String>? extraHeaders,
}) async {
  final routes = proxyMode
      ? <String>['PROXY 127.0.0.1:$httpProxyPort', 'DIRECT']
      : <String>['DIRECT', 'PROXY 127.0.0.1:$httpProxyPort'];
  Object? lastErr;
  for (final r in routes) {
    try {
      final t = await _openAiCompatTry(
        route: r,
        prompt: prompt,
        key: key,
        model: model,
        url: url,
        label: label,
        extraHeaders: extraHeaders,
      );
      if (t != null) {
        aiLastProvider = label;
        return t;
      }
    } on IOException catch (e) {
      lastErr = e;
    } on TimeoutException catch (e) {
      lastErr = e;
    } on AiApiError catch (e) {
      lastErr = e;
    }
  }
  throw lastErr ?? Exception('$label بدون پاسخ');
}

Future<String> openaiAsk(String prompt) => _openAiCompatAsk(
      prompt: prompt,
      key: openaiKey,
      model: openaiModel,
      url: 'https://api.openai.com/v1/chat/completions',
      label: 'ChatGPT',
    );

Future<String> deepseekAsk(String prompt) => _openAiCompatAsk(
      prompt: prompt,
      key: deepseekKey,
      model: deepseekModel,
      url: 'https://api.deepseek.com/chat/completions',
      label: 'DeepSeek',
    );

// Claude (Anthropic Messages API)
Future<String?> _claudeTry(String route, String prompt) async {
  if (claudeKey.isEmpty) return null;
  final c = HttpClient()
    ..findProxy = ((_) => route)
    ..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await c
        .postUrl(Uri.parse('https://api.anthropic.com/v1/messages'))
        .timeout(const Duration(seconds: 10));
    req.headers.set('content-type', 'application/json');
    req.headers.set('x-api-key', claudeKey);
    req.headers.set('anthropic-version', '2023-06-01');
    req.add(utf8.encode(jsonEncode({
      'model': claudeModel,
      'max_tokens': 2048,
      'system':
          'You are the AI assistant inside King VPN (Iran). '
          'Answer in Persian. Be practical about VPN, national net, speed, settings.',
      'messages': [
        {'role': 'user', 'content': prompt}
      ],
    })));
    final res = await req.close().timeout(const Duration(seconds: 50));
    final body = await res
        .transform(const Utf8Decoder(allowMalformed: true))
        .join()
        .timeout(const Duration(seconds: 50));
    if (res.statusCode == 200) {
      try {
        final j = jsonDecode(body);
        final parts = j['content'] as List? ?? const [];
        final t = parts
            .map((p) => (p is Map ? (p['text'] ?? '') : '').toString())
            .join('\n')
            .trim();
        return t.isEmpty ? 'پاسخ خالی بود.' : t;
      } catch (e) {
        logError(e);
        throw AiApiError('پاسخ Claude قابل خواندن نبود');
      }
    }
    final cut = body.length > 180 ? body.substring(0, 180) : body;
    throw AiApiError('Claude ${res.statusCode}: $cut');
  } finally {
    c.close(force: true);
  }
}

Future<String> claudeAsk(String prompt) async {
  final routes = proxyMode
      ? <String>['PROXY 127.0.0.1:$httpProxyPort', 'DIRECT']
      : <String>['DIRECT', 'PROXY 127.0.0.1:$httpProxyPort'];
  Object? lastErr;
  for (final r in routes) {
    try {
      final t = await _claudeTry(r, prompt);
      if (t != null) {
        aiLastProvider = 'Claude';
        return t;
      }
    } on IOException catch (e) {
      lastErr = e;
    } on TimeoutException catch (e) {
      lastErr = e;
    } on AiApiError catch (e) {
      lastErr = e;
    }
  }
  throw lastErr ?? Exception('Claude بدون پاسخ');
}

// unified entry: auto tries providers in order until one answers
Future<String> aiAsk(String prompt) async {
  final want = aiProvider;

  Future<String> run(String id) async {
    switch (id) {
      case 'grok':
        if (grokKey.isEmpty) throw Exception('کلید Grok نیست (console.x.ai)');
        return grokAsk(prompt);
      case 'claude':
        if (claudeKey.isEmpty) {
          throw Exception('کلید Claude نیست (console.anthropic.com)');
        }
        return claudeAsk(prompt);
      case 'openai':
        if (openaiKey.isEmpty) {
          throw Exception('کلید ChatGPT نیست (platform.openai.com)');
        }
        return openaiAsk(prompt);
      case 'deepseek':
        if (deepseekKey.isEmpty) {
          throw Exception('کلید DeepSeek نیست (platform.deepseek.com)');
        }
        return deepseekAsk(prompt);
      case 'gemini':
        if (geminiKey.isEmpty) {
          throw Exception('کلید Gemini نیست (aistudio.google.com)');
        }
        return geminiAsk(prompt);
      default:
        throw Exception('ارائه‌دهنده ناشناخته: $id');
    }
  }

  if (want != 'auto') return run(want);

  // auto order: Grok → Claude → ChatGPT → DeepSeek → Gemini
  final order = <String>[
    if (grokKey.isNotEmpty) 'grok',
    if (claudeKey.isNotEmpty) 'claude',
    if (openaiKey.isNotEmpty) 'openai',
    if (deepseekKey.isNotEmpty) 'deepseek',
    if (geminiKey.isNotEmpty) 'gemini',
  ];
  if (order.isEmpty) {
    throw Exception(
        'هیچ کلید API نیست. یکی از Grok / Claude / ChatGPT / DeepSeek / Gemini را وارد کن.');
  }
  Object? lastErr;
  for (final id in order) {
    try {
      return await run(id);
    } catch (e) {
      lastErr = e;
    }
  }
  throw lastErr ?? Exception('هیچ دستیار AI جواب نداد');
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
    } catch (e) { logError(e); }
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

String? _mirrorOf(String u) {
  final l = _mirrorsOf(u);
  return l.isEmpty ? null : l.first;
}

int _mirrorBest = 0; // index of the mirror host that worked last

// asks every url at the same time, the first good (200) answer wins
Future<http.Response?> _raceGet(List<String> urls, Duration t) {
  final c = Completer<http.Response?>();
  var left = urls.length;
  if (left == 0) return Future.value(null);
  for (final u in urls) {
    http.get(Uri.parse(u)).timeout(t).then((r) {
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
      return r;
    } catch (e) {
      logError(e);
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
      } catch (e) {
        logError(e);
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
// ======================= هشدار مصرف بالا =======================
// قبل از روشن شدن قابلیت‌های پرمصرف (دستیارها، خلبان‌ها، نت ملی) هشدار می‌دهد.
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
          'این قابلیت حجم اینترنت زیادی مصرف می‌کند، چون مدام سرورها را تست و جستجو می‌کند.\n\n'
          'برای برگشت به اتصال عادی و کم‌مصرف: تنظیمات ← «↩️ برگرداندن همه‌ی تنظیمات به پیش‌فرض» را بزن.',
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
    sb.writeln('NationalMode: $nationalMode ultra=$ultraMode turbo=$turboSpeed '
        'indestructible=$indestructibleMode natLevel=$natLevel');
    sb.writeln('Operator: $natOpKey provider=$aiProvider lastAi=$aiLastProvider');
    sb.writeln('Mux=$muxEnabled conc=$muxConc frag=$fragEnabled');
    if (c != null) {
      final v = natVarFor(c);
      final vn = (v >= 0 && v < _natVarNames.length) ? _natVarNames[v] : '$v';
      sb.writeln('Current kind: ${_profKey(c)} ping=${c.ping}ms '
          'speed=${(c.speed ?? 0).toStringAsFixed(2)}MB/s variant=$vn');
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
        '"reset_blacklist" (give failed servers another chance), '
        '"connect" (start full server search and connect), '
        '"search_national" (Iran national-net aggressive search), '
        '"enable_turbo" (max throughput levers), '
        '"escalate" (widen search / raise natLevel), '
        'or "none".\n'
        'Be proactive: if not connected use connect; if speed is poor use '
        'switch_best; if few healthy servers use refresh_lists; if national '
        'net use search_national.\n'
        'You have FULL freedom over every numeric setting in range and every '
        'toggle (1/0). Prefer higher throughput (Mux on, Fragment off) when '
        'the tunnel already works; prefer low data when searching lists.\n\n'
        '$sb';
  }

  // PILOT: richer prompt when Grok fully drives the VPN
  String grokPilotPrompt() {
    final base = aiPrompt();
    return 'You are Grok fully piloting King VPN on this phone until the user '
        'disconnects. Analyze network quality and location (operator/ASN only, '
        'no personal data). Decide the next concrete action to keep the best '
        'possible connection.\n'
        'Prefer actions over long text. Always end with SETTINGS JSON including '
        'an "action" key. Prefer Grok-style direct decisions.\n\n$base';
  }

  // auto = بعد از اتصال به‌صورت خودکار (هیچ‌وقت سرور را عوض نمی‌کند)
  Future<void> aiAnalyze({bool auto = false}) async {
    if (aiLoading.value) return;
    if (!_hasAnyAiKey) {
      if (!auto) {
        aiText.value =
            'اول کلید API گروک (console.x.ai) یا جمینای را وارد و ذخیره کن.';
      }
      return;
    }
    if (!connected) {
      if (!auto) {
        aiText.value =
            'اول به VPN وصل شو (ترجیحاً با «اتصال به سرور مخصوص AI»).';
      }
      return;
    }
    aiLoading.value = true;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        if (!auto) {
          final who = aiProvider == 'grok'
              ? 'Grok'
              : (aiProvider == 'gemini' ? 'Gemini' : 'دستیار (Grok/Gemini)');
          aiText.value = attempt == 0
              ? 'در حال ارسال آمار به $who...'
              : 'این سرور برای AI جواب نداد؛ تعویض به سرور مخصوص AI...';
        }
        try {
          aiShow(await aiAsk(aiPrompt()));
          if (aiLastProvider.isNotEmpty && !auto) {
            aiText.value = '[$aiLastProvider]\n${aiText.value}';
          }
          applyAiSuggest();
          if (auto && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('🤖 تحلیل $aiLastProvider آماده شد'),
              duration: const Duration(seconds: 8),
              action: SnackBarAction(
                  label: 'نمایش', onPressed: () => this.aiSheet()),
            ));
          }
          return;
        } on GeminiLocationError {
          current?.ai = false;
          // if Grok is available, try it once without switching server
          if (grokKey.isNotEmpty && aiProvider != 'gemini') {
            try {
              aiShow(await grokAsk(aiPrompt()));
              if (aiLastProvider.isNotEmpty) {
                aiText.value = '[$aiLastProvider]\n${aiText.value}';
              }
              applyAiSuggest();
              return;
            } catch (e) { logError(e); }
          }
          if (auto) return; // خودکار: اتصال را به‌هم نمی‌زنیم
          final has =
              _usable().any((s) =>
              s.ai == true && s.ping != null && !identical(s, current));
          if (attempt == 1 || !has) {
            aiText.value =
                'Gemini روی این سرور باز نمی‌شود. کلید Grok بگذار یا ردیف «🤖 سرورهای مخصوص هوش مصنوعی» را بزن.';
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
    if (!_hasAnyAiKey || !aiSession) return;
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
        Timer.periodic(const Duration(seconds: 90), (_) => aiAutopilotTick());
    Future.delayed(const Duration(seconds: 8), aiAutopilotTick);
  }

  /// امتیاز و دلیل پیشنهاد هر موتور VPN (عدد بالاتر = قوی‌تر برای شرایط فعلی)
  List<({String id, String title, String sub, IconData icon, int score, String why})>
      _rankVpnEngines() {
    final nat = nationalMode || natForce;
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
        score: 70 + (nV2 > 0 ? 15 : 0) + (nat ? -5 : 10),
        why: nat
            ? 'پروتکل اصلی؛ در نت ملی گاهی نیاز به Fragment دارد'
            : 'بهترین گزینه عمومی — سرور زیاد و پایدار',
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
                    color: Color(0xFF1B5E20).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF4CAF50)),
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
                            ? Color(0xFF1B5E20).withValues(alpha: 0.35)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isBest
                                  ? const Color(0xFF4CAF50)
                                  : Colors.grey.shade700,
                            ),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: isBest
                                ? const Color(0xFF2E7D32)
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
                                    color: Color(0xFF81C784),
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
    // V2Ray is the only engine left.
    pilotEngine = 'v2ray';
    proto = 'all';
    connRow = null;
    if (mounted) setState(() {});
    _set('موتور انتخاب شد: ${_engineLabel(e)}');
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
            ],
          ),
        ),
      ),
    );
  }

  /// همه‌ی دکمه‌های اتصال اول می‌پرسند: آنلاین یا آفلاین، بعد موتور VPN.
  Future<bool> pickEngineThenStart(Future<void> Function() start,
      {bool askMode = true}) async {
    if (askMode) {
      final ok = await _askOnlineOfflineMode();
      if (!ok) return false;
    }
    final e = await pickVpnEngineDialog();
    if (e == null) return false;
    applyPilotEngine(e);
    await start();
    return true;
  }

  // انتخاب آنلاین/آفلاین برای دکمه‌ی اتصال اصلی؛ false = لغو شد
  Future<bool> _askOnlineOfflineMode() async {
    var mode = await _pickOnlineOffline();
    if (mode == null) return false;
    if (mode == 'offline' && !natHotReady()) {
      // اولین بار: پوشه هنوز ساخته نشده، پس آفلاین خالی است
      final goOnline = await showDialog<bool>(
        context: context,
        builder: (dctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('⚠️ هنوز پوشه ساخته نشده'),
            content: const Text(
                'برای اتصال آفلاین یک بار این کار را بکن:\n'
                '۱. دکمه‌ی «پوشه‌ی سرورهای سالم» را بزن و گزینه‌ی «پوشه منابع تازه» را انتخاب کن.\n'
                '۲. حدود ۱۰ دقیقه صبر کن تا کانفیگ‌ها (۳۰ هزار تا) ذخیره شوند.\n'
                'بعد از آن اتصال آفلاین کار می‌کند. الان می‌توانی آنلاین وصل شوی.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dctx, false),
                  child: const Text('انصراف')),
              TextButton(
                  onPressed: () => Navigator.pop(dctx, true),
                  child: const Text('اتصال آنلاین')),
            ],
          ),
        ),
      );
      if (goOnline != true) return false;
      mode = 'online';
    }
    offlineOnly = mode == 'offline';
    await ultimateSave();
    return true;
  }

  // FULL PILOT: Grok takes over from search to keep-alive until user disconnects
  Future<void> startGrokPilot() async {
    if (!_hasAnyAiKey) {
      _set('اول کلید Grok یا Gemini را در دستیار ذخیره کن');
      aiSheet();
      return;
    }
    // جلوگیری از تداخل با خلبان محلی
    if (localPilotOn) stopLocalPilot();
    // prefer Grok for pilot when available
    if (grokKey.isNotEmpty && aiProvider == 'gemini') {
      aiProvider = 'auto';
      await saveGeminiPrefs();
    }
    aiSession = true;
    wantVpn = true;
    abort = false;
    turboSpeed = true;
    // کم‌مصرف: خلبان دیگر حالت شکست‌ناپذیر (جستجوی بی‌پایان) را اجباری نمی‌کند
    // تا دیتای اینترنت زیاد مصرف نشود. در صورت نیاز کاربر خودش روشن می‌کند.
    if (!ultraMode) {
      ultraMode = true;
      _pilotForcedUltra = true;
    }
    // keep current indestructibleMode — do not force it on (saves data)
    // lower concurrent tests while pilot is active
    bgWorkers = min(bgWorkers, 2);
    firstBatchSize = min(firstBatchSize, 30);
    maxBatches = min(maxBatches, 4);
    _applyTurboLevers();
    final eng = _engineLabel(pilotEngine);
    _set('خلبان Grok ($eng): تحلیل شبکه و جستجوی بهترین سرور...');
    aiAutopilotStart();
    // immediate bootstrap without waiting for first AI round-trip
    unawaited(() async {
      try {
        await natDetectOperator();
        await _natDetect();
        if (!connected && !busy) {
          if (nationalMode) {
            natForce = true;
            _set('خلبان: نت ملی تشخیص داده شد — جستجوی گسترده...');
          }
          await connect(); // was fire-and-forget — errors were lost
        }
      } catch (e) {
        logError(e);
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

  void stopGrokPilot() {
    aiSession = false;
    aiLoop?.cancel();
    aiLoop = null;
    // Restore modes the pilot forced (do not touch nationalMode — network may still be cut)
    if (_pilotForcedUltra) {
      ultraMode = false;
      _pilotForcedUltra = false;
    }
    if (_pilotForcedIndestructible) {
      indestructibleMode = false;
      _pilotForcedIndestructible = false;
    }
    _pilotConnectedAt = null;
  }

  Future<void> aiAutopilotTick() async {
    if (!aiSession || !mounted || !_hasAnyAiKey) return;
    if (busy || switching || aiLoading.value) return;
    // user turned VPN off → pilot ends
    if (!wantVpn && !connected) {
      stopGrokPilot();
      return;
    }
    aiLoading.value = true;
    try {
      _set('خلبان AI: تحلیل اینترنت و مکان...');
      final prompt = grokPilotPrompt();
      try {
        aiShow(await aiAsk(prompt));
      } on GeminiLocationError {
        // try any other provider that has a key
        aiShow(await aiAsk(prompt));
      }
      applyAiSuggest();
      await aiRunAction();
      // if still disconnected, force a connect cycle
      if (aiSession && wantVpn && !connected && !busy && !switching) {
        _set('خلبان: هنوز وصل نیست — جستجوی سرور...');
        if (aiActionName.isEmpty) {
          await _acquire(strictRow: false, speed: true);
        }
      }
      // if connected but very slow, nudge switch — only after 3 min hold
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
          final l = _pickList()
              .where((s) => !identical(s, current))
              .toList();
          if (l.isNotEmpty) {
            lastWhy = 'خلبان: سرعت پایین';
            await _swapTo(l.first);
            _pilotConnectedAt = DateTime.now(); // reset hold after switch
          }
        }
      } else if (!connected) {
        _pilotConnectedAt = null;
      }
      if (aiSession && connected) {
        _set('خلبان Grok فعال • $aiLastProvider • ${_connStatus()}');
      }
    } on GeminiLocationError {
      current?.ai = false;
      if (grokKey.isNotEmpty) {
        try {
          aiShow(await grokAsk(grokPilotPrompt()));
          applyAiSuggest();
          await aiRunAction();
        } catch (e) { logError(e); }
      } else if (_usable().any((s) => s.ai == true && !identical(s, current))) {
        await connectRow('r:ai');
      }
    } catch (e) {
      logError(e);
      // still try to stay connected
      if (aiSession && wantVpn && !connected && !busy) {
        try {
          await connect();
        } catch (e) { logError(e); }
      }
    } finally {
      aiLoading.value = false;
    }
  }

  Future<void> aiRunAction() async {
    final a = aiActionName;
    aiActionName = '';
    if (a.isEmpty || a == 'none') return;
    lastWhy = 'خلبان AI: $a';
    if (a == 'switch_best') {
      // Respect 3-minute hold after connect (same as local pilot)
      final holdOk = _pilotConnectedAt == null ||
          DateTime.now().difference(_pilotConnectedAt!) >=
              const Duration(minutes: 3);
      if (!holdOk || busy || switching) return;
      final l = _pickList().where((s) => !identical(s, current)).toList();
      if (l.isNotEmpty) {
        await _swapTo(l.first);
        _pilotConnectedAt = DateTime.now();
      }
    } else if (a == 'refresh_lists') {
      // Do NOT wipe good/failed — only force a fresh download when disconnected
      if (!connected) {
        listTime = null;
        lastFetchTry = DateTime.fromMillisecondsSinceEpoch(0);
        await _loadPending(bg: true, exhausted: true);
      }
    } else if (a == 'reset_blacklist') {
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
    } else if (a == 'search_national') {
      natForce = true;
      // do not force endless search — keeps data usage low
      nationalMode = true;
      if (!busy) await connect();
    } else if (a == 'enable_turbo') {
      turboSpeed = true;
      muxEnabled = true;
      muxConc = max(muxConc, 24);
      if (!nationalMode) fragEnabled = false;
      _applyTurboLevers();
      _saveSettings();
      if (connected && current != null && !busy) {
        unawaited(_turboAfterConnect(current!));
      }
    } else if (a == 'escalate') {
      await _natEscalate(max(natLevel * 2, 4));
      if (!connected && !busy) await connect();
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
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  if (await confirmHeavyFeature(context, 'دستیارهای AI')) {
                    this.aiSheet();
                  }
                },
                icon: const Icon(Icons.smart_toy_outlined, size: 18),
                label: Text(
                    '🤖 دستیارهای AI (Grok/Claude/ChatGPT/DeepSeek/Gemini'
                    '${aiLastProvider.isEmpty ? '' : ' · $aiLastProvider'})'),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: busy
                    ? null
                    : () async {
                        if (aiSession) {
                          stopGrokPilot();
                          _set(
                              'خلبان AI خاموش شد — برای قطع کامل VPN دکمه قطع را بزن');
                        } else {
                          if (!await confirmHeavyFeature(context, 'خلبان کامل AI')) return;
                          await pickEngineThenStart(startGrokPilot);
                        }
                      },
                icon: Icon(aiSession ? Icons.flight_land : Icons.flight_takeoff,
                    size: 18),
                label: Text(aiSession
                    ? '⏹ توقف خلبان (VPN تا قطع دستی می‌ماند)'
                    : '🚀 خلبان کامل AI — کنترل خودکار تا قطع تو'),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        if (localPilotOn) {
                          stopLocalPilot();
                          _set('خلبان محلی خاموش شد — VPN تا قطع دستی می‌ماند');
                        } else {
                          if (!await confirmHeavyFeature(context, 'خلبان')) return;
                          // اگر خلبان ابری روشن بود، خاموشش کن تا تداخل نداشته باشد
                          if (aiSession) stopGrokPilot();
                          await pickEngineThenStart(() async {
                            startLocalPilot();
                          });
                        }
                      },
                icon: Icon(
                    localPilotOn ? Icons.flight_land : Icons.rocket_launch,
                    size: 18),
                label: Text(localPilotOn
                    ? '⏹ توقف خلبان (قدرت $_localPower)'
                    : '👑 خلبان'),
                style: FilledButton.styleFrom(
                  backgroundColor: localPilotOn
                      ? const Color(0xFFB71C1C)
                      : const Color(0xFF1B5E20),
                ),
              ),
            ),
            if (localPilotOn || localPilotText.value.isNotEmpty) ...[
              const SizedBox(height: 8),
              ValueListenableBuilder<String>(
                valueListenable: localPilotText,
                builder: (_, t, _) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1B0E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2E7D32), width: 1),
                  ),
                  child: Text(
                    t,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      fontFamily: 'monospace',
                      color: Color(0xFFE8F5E9),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );

  void aiSheet() {
    final k = TextEditingController(text: geminiKey);
    final m = TextEditingController(text: geminiModel);
    final gk = TextEditingController(text: grokKey);
    final gm = TextEditingController(text: grokModel);
    final ck = TextEditingController(text: claudeKey);
    final cm = TextEditingController(text: claudeModel);
    final ok = TextEditingController(text: openaiKey);
    final om = TextEditingController(text: openaiModel);
    final dk = TextEditingController(text: deepseekKey);
    final dm = TextEditingController(text: deepseekModel);
    var prov = aiProvider;
    Future<void> save() async {
      geminiKey = k.text.trim();
      final mm = m.text.trim().replaceFirst(RegExp(r'^models/'), '');
      geminiModel = mm.isEmpty ? 'gemini-flash-latest' : mm;
      grokKey = gk.text.trim();
      final gmm = gm.text.trim();
      grokModel = gmm.isEmpty ? 'grok-3' : gmm;
      claudeKey = ck.text.trim();
      final cmm = cm.text.trim();
      claudeModel = cmm.isEmpty ? 'claude-sonnet-4-20250514' : cmm;
      openaiKey = ok.text.trim();
      final omm = om.text.trim();
      openaiModel = omm.isEmpty ? 'gpt-4o-mini' : omm;
      deepseekKey = dk.text.trim();
      final dmm = dm.text.trim();
      deepseekModel = dmm.isEmpty ? 'deepseek-chat' : dmm;
      aiProvider = prov;
      for (final g in good) {
        g.ai = null;
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
            child: StatefulBuilder(builder: (ctx, setS) {
              Widget fields(String title, TextEditingController keyC,
                      TextEditingController modelC, String keyLabel,
                      String modelLabel) =>
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      TextField(
                          controller: keyC,
                          obscureText: true,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(labelText: keyLabel)),
                      TextField(
                          controller: modelC,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(labelText: modelLabel)),
                    ],
                  );
              return SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🤖 دستیارهای هوشمند (چند AI)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 6),
                    const Text(
                        'Grok، Claude، ChatGPT، DeepSeek و Gemini پشتیبانی می‌شوند. '
                        'حالت Auto به ترتیب آن‌ها را امتحان می‌کند تا یکی جواب بدهد. '
                        'کلیدها فقط روی همین گوشی ذخیره می‌شوند. لینک سرور ارسال نمی‌شود.',
                        style: TextStyle(fontSize: 12, color: Color(0xFFCDD1D8))),
                    const SizedBox(height: 8),
                    const Text('ارائه‌دهنده',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      for (final e in const [
                        ('auto', 'Auto'),
                        ('grok', 'Grok'),
                        ('claude', 'Claude'),
                        ('openai', 'ChatGPT'),
                        ('deepseek', 'DeepSeek'),
                        ('gemini', 'Gemini'),
                      ])
                        ChoiceChip(
                          label: Text(e.$2),
                          selected: prov == e.$1,
                          onSelected: (_) => setS(() => prov = e.$1),
                        ),
                    ]),
                    fields('Grok — console.x.ai', gk, gm,
                        'کلید API گروک', 'مدل (مثلاً grok-3)'),
                    fields('Claude — console.anthropic.com', ck, cm,
                        'کلید API کلود', 'مدل (مثلاً claude-sonnet-4-20250514)'),
                    fields('ChatGPT — platform.openai.com', ok, om,
                        'کلید API اوپن‌ای‌آی', 'مدل (مثلاً gpt-4o-mini)'),
                    fields('DeepSeek — platform.deepseek.com', dk, dm,
                        'کلید API دیپ‌سیک', 'مدل (مثلاً deepseek-chat)'),
                    fields('Gemini — aistudio.google.com', k, m,
                        'کلید API جمینای', 'مدل Gemini'),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      FilledButton(
                          onPressed: () async {
                            await save();
                            _set('تنظیمات دستیار ذخیره شد ($aiProvider)');
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
                            await pickEngineThenStart(() async {
                              aiSession = true;
                              aiAutopilotStart();
                              await connectRow('r:ai');
                            });
                          },
                          child: const Text('اتصال به سرور مخصوص AI')),
                      FilledButton(
                          onPressed: () async {
                            await save();
                            if (ctx.mounted) Navigator.pop(ctx);
                            await pickEngineThenStart(startGrokPilot);
                          },
                          child: const Text('🚀 خلبان کامل AI (کنترل خودکار VPN)')),
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
            );
            }),
          ),
        ),
      ),
    );
  }

  // ---- خلبان محلی King Pro (داخل HomeExtras) ----

  /// پروب سبک — اگر سرعت واقعی داریم، پروب سخت‌گیرانه نیست (گزارش: پورت هسته بسته → false اشتباه)
  Future<Map<String, bool?>> _localProbeSites({bool soft = true}) async {
    final out = <String, bool?>{
      'tg': null,
      'yt': null,
      'ig': null,
      'net': null,
    };
    if (!connected) return out;
    // اگر همین الان سرعت واقعی >0.3 داریم، فرض کن نت OK است
    final spd = current?.speed;
    if (soft && spd != null && spd >= 0.3) {
      out['net'] = true;
      out['tg'] = true; // فرض موقت؛ تعویض فقط با کندی واقعی
      return out;
    }
    try {
      final rs = await Future.wait([
        _siteOpens('https://web.telegram.org/', viaCore: true),
        _siteOpens('https://www.youtube.com/generate_204', viaCore: true),
        _siteOpens('https://www.instagram.com/', viaCore: true),
        _siteOpens('http://cp.cloudflare.com/generate_204', viaCore: true),
      ]).timeout(const Duration(seconds: 10), onTimeout: () => [false, false, false, false]);
      out['tg'] = rs[0] == true;
      out['yt'] = rs[1] == true;
      out['ig'] = rs[2] == true;
      out['net'] = rs[3] == true || out['tg'] == true || out['yt'] == true;
    } catch (e) { logError(e); }
    return out;
  }

  int _localScore({
    required bool connected,
    required bool? tg,
    required bool? yt,
    required bool? ig,
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
    if (tg == true) sc += 10;
    if (yt == true) sc += 5;
    if (net == true) sc += 5;
    if (good >= 3) sc += 5;
    // تاریخچه‌ی موفقیت این نوع سرور (۰..۱) — افت بیشتر = امتیاز کمتر
    if (rate != null) sc += ((rate - 0.5) * 20).round();
    return sc.clamp(0, 100);
  }

  Future<_LocalNetSnap> _localGather({bool probe = true}) async {
    String op = _localLastOp;
    try {
      await natDetectOperator();
      if (natOpKey.isNotEmpty) {
        op = natOpKey;
        _localLastOp = natOpKey;
      }
    } catch (e) { logError(e); }

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
      } catch (e) { logError(e); }
      ping = current!.ping;
      if (current!.speed != null && current!.speed! > 0) {
        spd = current!.speed;
      }
      svc = current!.svc;
    }

    final nat = nationalMode ||
        natForce ||
        (lastNetVerdict?.home == true && lastNetVerdict?.web == false);

    bool? tg, yt, ig, netOk;
    if (probe && connected) {
      final p = await _localProbeSites();
      tg = p['tg'];
      yt = p['yt'];
      ig = p['ig'];
      netOk = p['net'];
      if (tg == true) {
        _localTgOk++;
        _localTgFail = 0;
      } else if (tg == false) {
        _localTgFail++;
        _localTgOk = 0;
      }
    }

    final score = _localScore(
      connected: connected,
      tg: tg,
      yt: yt,
      ig: ig,
      net: netOk,
      ping: ping,
      speed: spd,
      good: good.length,
      rate: current == null ? null : _profRate(current!),
    );

    return _LocalNetSnap(
      connected: connected,
      national: nat,
      wifi: false,
      operatorKey: op.isNotEmpty ? op : (nat ? 'ملی/محدود' : 'نامشخص'),
      configProto: proto,
      configNet: net,
      configSec: sec,
      pingMs: ping,
      speedMBs: spd,
      goodCount: good.length,
      pendingCount: pending.length,
      failedCount: failed.length,
      natLvl: natLevel,
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
    final minHoldSec = (180 - (_localPower * 3).clamp(0, 60)).clamp(120, 180);

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
      final deadTunnel = !hasSpeed && !hasPing && s.score < 25;
      final weakTunnel = !hasSpeed && softSpeed && s.score < 40;
      // بین‌الملل قطع شده (تلگرام چند بار جواب نمی‌دهد) و تونل مرده است:
      // نت ملی را روشن کن؛ قطع بعدی با همان تصمیم «جستجوی ملی» وصل می‌شود
      if (deadTunnel && _localTgFail >= 2) {
        natForce = true;
        _localPhase = 'degraded';
        return _LocalDecision('switch_best', set,
            'بین‌الملل قطع ×$_localTgFail + تونل مرده → سوئیچ به نت ملی',
            confidence: 90);
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
    _localTgOk = 0;
    _localSlowStreak = 0;
    _localPhase = _localFailStreak >= 2 ? 'recover' : 'search';

    set['fastWorkers'] = fastWorkers;
    set['timeout'] = delayTimeout.inSeconds;
    set['natLevel'] = natLevel;

    // بهترین اقدام یادگرفته‌شده برای این اپراتور
    final opKey = s.operatorKey;
    String? memoryBest;
    var memoryBestW = 0;
    if (opKey.isNotEmpty) {
      for (final e in _localOpWins.entries) {
        if (e.key.startsWith('$opKey|') && e.value > memoryBestW) {
          memoryBestW = e.value;
          memoryBest = e.key.split('|').last;
        }
      }
    }

    if (s.national || _localPower >= 4) {
      act = 'search_national';
      set['natLevel'] = max(s.natLvl, max(2, natLevel));
      conf = 92;
      why.writeln(
          'قطع + ${s.national ? "نت ملی" : "قدرت $_localPower"} → جستجوی ملی سطح ${set['natLevel']}');
    } else if (memoryBest != null &&
        memoryBestW >= 3 &&
        (memoryBest == 'connect' ||
            memoryBest == 'search_national' ||
            memoryBest == 'escalate')) {
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
    } else if (_localFailStreak >= 2 || _localPower >= 6) {
      act = 'escalate';
      set['natLevel'] = min(4, max(s.natLvl + 1, 2));
      conf = 88;
      why.writeln(
          'شکست ×$_localFailStreak / قدرت $_localPower → escalate ${set['natLevel']}');
    } else {
      act = 'connect';
      conf = 75;
      why.writeln('قطع است → شروع اتصال (قدرت $_localPower)');
    }

    if (opKey.isNotEmpty && act != 'none') {
      final w = _localOpWins['$opKey|$act'] ?? 0;
      if (w >= 3) {
        conf = min(100, conf + 5);
        why.writeln('تقویت اطمینان از حافظه: $w برد');
      }
    }

    _localFailStreak++;
    return _LocalDecision(act, set, why.toString().trim(), confidence: conf);
  }

  Future<void> _localApply(_LocalDecision d) async {
    _localLastAction = d.action;

    if (d.settings.containsKey('fastWorkers')) {
      fastWorkers = d.settings['fastWorkers']!.clamp(1, 200);
    }
    if (d.settings.containsKey('timeout')) {
      delayTimeout = Duration(seconds: d.settings['timeout']!.clamp(2, 30));
    }
    if (d.settings.containsKey('natLevel')) {
      natLevel = d.settings['natLevel']!.clamp(1, 4);
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
          turboSpeed = true;
          _applyTurboLevers();
          await connect();
        }
        break;
      case 'soft_recover':
        // بازیابی نرم: توربو + ladder همان سرور قبل از تعویض کامل
        if (connected && current != null && !busy && !switching) {
          turboSpeed = true;
          muxEnabled = true;
          muxConc = max(muxConc, 24);
          _applyTurboLevers();
          try {
            final ok = await _natLadder(current!);
            if (ok) {
              _localSlowStreak = 0;
              _localConnectedSince = DateTime.now();
              final op = _localLastOp;
              if (op.isNotEmpty) {
                _localOpWins['$op|soft_recover'] =
                    (_localOpWins['$op|soft_recover'] ?? 0) + 1;
              }
            }
          } catch (e) { logError(e); }
          try {
            unawaited(_measureCurrent(current!));
          } catch (e) { logError(e); }
        }
        break;
      case 'switch_best':
        if (!busy && !switching) {
          final l = _pickList()
              .where((s) => !identical(s, current) && !_bad(s))
              .toList();
          // امتیاز ترکیبی: تلگرام + سرعت + پینگ کمتر + ترجیح پروتکل متفاوت
          Server? best;
          double bestScore = -1e9;
          final curProto = current != null
              ? (describeConfig(current!.link).protocol)
              : '';
          for (final s in l) {
            var sc = 0.0;
            if (s.svc >= 0 && (s.svc & 1) != 0) sc += 100; // تلگرام
            if (s.svc >= 0 && (s.svc & 2) != 0) sc += 30; // یوتیوب
            sc += (s.speed ?? 0) * 40;
            if (s.ping != null && s.ping! > 0) {
              sc += max(0, 80 - s.ping! / 20);
            }
            try {
              final p = describeConfig(s.link).protocol;
              if (curProto.isNotEmpty && p != curProto) sc += 15; // تنوع پروتکل
            } catch (e) { logError(e); }
            if (sc > bestScore) {
              bestScore = sc;
              best = s;
            }
          }
          if (best == null && l.isNotEmpty) {
            l.sort((a, b) => (b.speed ?? 0).compareTo(a.speed ?? 0));
            best = l.first;
          }
          if (best != null) {
            final op = _localLastOp;
            if (op.isNotEmpty) {
              final k = '$op|switch_best';
              _localOpWins[k] = (_localOpWins[k] ?? 0) + 1;
            }
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
      case 'search_national':
        natForce = true;
        // do not force endless search — keeps data usage low
        nationalMode = true;
        if (!busy) await connect();
        break;
      case 'enable_turbo':
        // فقط فلگ — بدون ریستارت تونل
        turboSpeed = true;
        muxEnabled = true;
        muxConc = max(muxConc, 16);
        if (!nationalMode) fragEnabled = false;
        _saveSettings();
        break;
      case 'escalate':
        await _natEscalate(max(natLevel, 3));
        if (!connected && !busy) await connect();
        break;
      default:
        break;
    }
  }

  Future<void> localPilotTick({bool force = false}) async {
    if (!localPilotOn || !mounted) return;
    if (busy || switching || localPilotLoading.value) return;
    if (!force &&
        _localLastTick != null &&
        DateTime.now().difference(_localLastTick!) < const Duration(seconds: 40)) {
      return;
    }
    // PILOT-KEEP: a short abort / switch / search can leave wantVpn false.
    // That must not turn the pilot off; only the user's button does that.
    if (!wantVpn && !connected) {
      return;
    }
    // STABLE-PILOT: a working tunnel that was switched less than 3 minutes ago
    // is left alone (stops the repeated search_national switches)
    if (connected && lastState == 'CONNECTED' &&
        DateTime.now().difference(lastSwitch) < const Duration(minutes: 3)) {
      return;
    }

    localPilotLoading.value = true;
    _localLastTick = DateTime.now();
    _localTickN++;
    try {
      localPilotText.value =
          '⏳ قدرت $_localPower ($_localPowerLabel): پروب + اینترنت + مکان...';

      try {
        await natDetectOperator();
      } catch (e) { logError(e); }
      try {
        await _natDetect();
      } catch (e) { logError(e); }

      // قدرت را هر تیک با شبکه هماهنگ کن (تمام‌اتوماتیک)
      final wantPower = _localNatBtn ? max(_localAutoPickPower(), 4) : _localAutoPickPower();
      if (wantPower != _localPower) {
        _localApplyMaxPowerProfile(power: wantPower);
      }

      final snap = await _localGather(probe: true);
      final decision = _localDecide(snap);

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
          'natLvl=$natLevel mux=$muxEnabled turbo=$turboSpeed');
      localPilotText.value = report.toString().trim();

      await _localApply(decision);
      try {
        await kingSelfHeal(reason: 'pilot');
      } catch (e) { logError(e); }

      // اگر هنوز قطع است دوباره وصل کن
      if (localPilotOn && wantVpn && !connected && !busy && !switching) {
        if (decision.action == 'none' || decision.action == 'connect') {
          await connect();
        }
      }

      // بازه تطبیقی: پایدار = آهسته‌تر، قطع = سریع‌تر
      _localReschedule();
    } catch (e) {
      logError(e);
      localPilotText.value =
          'خطای خلبان: ${e.toString().replaceFirst("Exception: ", "")}';
      if (localPilotOn && wantVpn && !connected && !busy) {
        try {
          await connect();
        } catch (e) { logError(e); }
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
    if (_localPower <= 10) return 'نت ملی / سخت';
    if (_localPower <= 20) return 'اضطراری';
    return 'حداکثر بی‌نهایت';
  }

  /// اعمال پروفایل از روی قدرت (۰…∞) — همه عددها فرمولی، بدون سقف قدرت
  void _localApplyMaxPowerProfile({int? power}) {
    final p = (power ?? _localPower).clamp(0, 1000000);
    _localPower = p;
    if (p > _localPeakPower) _localPeakPower = p;

    // --- سوییچ‌های حیاتی (همیشه اتوماتیک) ---
    proxyMode = false;
    turboSpeed = true;
    muxEnabled = true;
    autoSpeed = true;
    autoCycle = true;
    savedFirst = true;
    offlineOnly = false;
    minSpeedKB = 0;

    // فرمول‌های پیوسته نسبت به قدرت (هرچه بالاتر = تهاجمی‌تر)
    // workers: 35 → رشد آرام تا سقف عملی سخت‌افزار
    fastWorkers = (35 + p * 4).clamp(20, 200).toInt();
    bgWorkers = (2 + (p / 3).floor()).clamp(1, 20).toInt();
    // timeout ثانیه: 9 + قدرت p
    delayTimeout =
        Duration(seconds: (9 + p * 0.7).clamp(8, 45).round());
    tcpTimeout = Duration(
        milliseconds: (3500 + p * 250).clamp(3000, 15000).round());
    batchSize = (180 + p * 15).clamp(100, 800).toInt();
    badPingMs = (2500 + p * 80).clamp(2000, 8000).toInt();
    watchFailLimit = (3 + (p / 4).floor()).clamp(2, 12).toInt();
    speedTopN = (2 + (p / 5).floor()).clamp(1, 10).toInt();
    muxConc = (16 + p * 2).clamp(8, 64).toInt();
    natWorkers = (4 + p).clamp(4, 24).toInt();
    // سطح ماتریس ملی: 1..4
    natLevel = (1 + (p / 3).floor()).clamp(1, 4).toInt();

    // سوییچ‌های وابسته به قدرت / مکان / نوع جستجو
    if (p >= 2) ultraMode = true;
    if (p >= 4) {
      nationalMode = true;
      autoCycle = true;
      try {
        natGrow((80 + p * 20).clamp(80, 600).toInt());
      } catch (e) { logError(e); }
    }
    if (p >= 8) {
      indestructibleMode = true;
      try {
        natGrow((150 + p * 25).clamp(150, 800).toInt());
      } catch (e) { logError(e); }
    }
    // Fragment فقط وقتی شبکه سخت است (نت ملی / قدرت بالا)
    fragEnabled = p >= 5 && (nationalMode || natForce);

    _applyTurboLevers();
    unawaited(_saveSettings());
  }

  /// محاسبه قدرت از اینترنت + مکان/اپراتور + نوع جستجو (عادی / نت ملی)
  /// بدون سقف: با هر شکست بیشتر بالا می‌رود؛ با پایداری آرام پایین می‌آید
  int _localAutoPickPower() {
    var p = 1; // پایه روزمره

    // --- اینترنت / تشخیص شبکه ---
    final v = lastNetVerdict;
    if (v != null) {
      if (v.home == true && v.web == false) {
        p += 5; // نت ملی کلاسیک
      } else if (v.web == false) {
        p += 3; // بین‌الملل بسته
      } else if (v.tls == false || v.tcp == false) {
        p += 2; // شبکه نیمه‌خراب
      } else if (v.dnsPoison == true) {
        p += 2;
      }
    }
    if (nationalMode || natForce) p += 4;
    if (indestructibleMode) p += 2;

    // --- مکان / اپراتور ---
    final op = (_localLastOp.isNotEmpty ? _localLastOp : natOpKey).toLowerCase();
    if (op.contains('ایرانسل') || op.contains('irancell') || op.contains('mci') ||
        op.contains('همراه') || op.contains('رایتل') || op.contains('rightel') ||
        op.contains('ملی') || op.contains('national')) {
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
    } else {
      final spd = current?.speed;
      if (spd != null && spd > 0 && spd < 0.15) p += 2; // وصل ولی خیلی کند
      if (spd != null && spd >= 1.0 && _localFailStreak == 0) {
        p = max(0, p - 1); // اینترنت خوب → کمی آرام‌تر
      }
    }

    // --- شکست‌ها: هر شکست قدرت را بالا می‌برد (مسیر به ∞) ---
    p += _localFailStreak * 2;
    p += _localSlowStreak;
    if (_localTgFail >= 3) p += 2;

    // --- پایداری: آرام پایین بیا (نه یک‌دفعه) ---
    if (_localGoodStreak >= 5 && _localFailStreak == 0 && connected) {
      p = max(0, p - 2);
    }
    if (_localPhase == 'stable' && connected && _localFailStreak == 0) {
      p = max(0, p - 1);
    }

    // هرگز منفی نشود؛ سقف نرم فقط برای جلوگیری از int دیوانه‌وار در UI
    return p.clamp(0, 1000000);
  }

  /// فعال‌سازی خلبان بدون حلقهٔ اتصال (برای وقتی کاربر فقط «اتصال» زده)
  void ensureLocalPilotRunning() {
    if (aiSession) stopGrokPilot();
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
    _localTgOk = 0;
    _localTgFail = 0;
    _localConnectedSince = null;
    _localPeakPower = 1;
    _localPower = 1;
    _localApplyMaxPowerProfile(power: _localNatBtn ? 4 : 1);
    localPilotText.value =
        '👑 خلبان خودکار فعال است\n'
        '⚠ تنظیمات برای خلبان عوض شد. برای جستجوی عادی: تنظیمات ← «برگرداندن همه‌ی عددها به پیش‌فرض»\n'
        '• فقط «اتصال» کافی است — بقیه اتوماتیک\n'
        '• قدرت ۰→∞ با اینترنت و مکان';
    _localReschedule();
    Future.delayed(const Duration(seconds: 3), () {
      if (localPilotOn) localPilotTick(force: true);
    });
    // تشخیص شبکه در پس‌زمینه و تنظیم قدرت — بدون connect دوباره
    unawaited(() async {
      try {
        await natDetectOperator();
        try {
          await _natDetect();
        } catch (e) { logError(e); }
        final want = _localNatBtn ? max(_localAutoPickPower(), 4) : _localAutoPickPower();
        if (want != _localPower) {
          _localApplyMaxPowerProfile(power: want);
        }
      } catch (e) { logError(e); }
    }());
  }

  void startLocalPilot({bool national = false}) {
    _localNatBtn = national;
    ensureLocalPilotRunning();
    final eng = _engineLabel(pilotEngine);
    localPilotText.value =
        '👑 خلبان فعال شد • موتور: $eng\n'
        '• قدرت خودکار از ۰ تا ∞\n'
        '• اینترنت، مکان، جستجوی عادی و نت ملی را خودش تشخیص می‌دهد\n'
        '• فقط روی موتور انتخاب‌شده کار می‌کند';
    unawaited(() async {
      try {
        await natDetectOperator();
        try {
          await _natDetect();
        } catch (e) { logError(e); }
        final want = _localNatBtn ? max(_localAutoPickPower(), 4) : _localAutoPickPower();
        _localApplyMaxPowerProfile(power: want);
        if (nationalMode || _localPower >= 4) {
          natForce = true;
          _resInject();
        }
        if (!connected && !busy) {
          await connect();
        } else {
          await localPilotTick(force: true);
        }
      } catch (e) {
        logError(e);
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

  void stopLocalPilot() {
    localPilotOn = false;
    _localNatBtn = false;
    localPilotLoop?.cancel();
    localPilotLoop = null;
    _localPhase = 'boot';
    if (_localPower >= 8) {
      indestructibleMode = false;
    }
    final peak = _localPeakPower;
    _localPower = 1;
    localPilotText.value =
        'خلبان متوقف شد.\nقله قدرت این نشست: $peak';
  }

}


// NUMPATCH ======================= عددهای قابل تنظیم =======================
// first search (used by patch_fast.py): it stops at the FIRST healthy server
// (for the Gemini row: the first Gemini server). Safety: after [firstCapSec]
// seconds it goes on with the ones found.
int firstCapSec = 15; // BEST: کمی بیشتر برای پیدا کردن سرور سالم

// the AI assistant must not change these
// AI may change every number (no locked keys)
const aiLockedNums = <String>{};

class NumOpt {
  final String id, title;
  final int lo, hi, def, aiHi; // aiHi = hi so AI has full range
  final bool extra; // shown in the extra section
  final int Function() get;
  final void Function(int) set;
  NumOpt(this.id, this.title, this.lo, this.hi, this.def, this.aiHi,
      this.extra, this.get, this.set);
}

final List<NumOpt> numOpts = [
  // BEST PROFILE defaults — هم‌تراز با پیش‌فرض main.dart
  NumOpt('fastWorkers', 'تست همزمان (جستجوی اول)', 1, 1000, 50, 1000, false,
      () => fastWorkers, (v) => fastWorkers = v),
  NumOpt('bgWorkers', 'تست همزمان (وقتی وصل است)', 1, 1000, 1, 1000, false,
      () => bgWorkers, (v) => bgWorkers = v),
  NumOpt('timeout', 'تایم‌اوت هر تست (ثانیه)', 1, 1000, 8, 1000, false,
      () => delayTimeout.inSeconds, (v) => delayTimeout = Duration(seconds: v)),
  NumOpt('batch', 'اندازه دسته', 1, 1000, 120, 1000, false,
      () => batchSize, (v) => batchSize = v),
  NumOpt('minPingMs', 'حداقل پینگ معتبر', 0, 1000, 0, 1000, false,
      () => minPingMs, (v) => minPingMs = v),
  NumOpt('speedTopN', 'تعداد سرور برای تست سرعت', 1, 1000, 5, 1000, false,
      () => speedTopN, (v) => speedTopN = v),
  NumOpt('badPingMs', 'پینگ بد از', 70, 7000, 2500, 7000, false,
      () => badPingMs, (v) => badPingMs = v),
  NumOpt('minSpeedKB', 'تعویض اگر سرعت کمتر از', 0, 50000, 80, 50000, false,
      () => minSpeedKB, (v) => minSpeedKB = v),
  NumOpt('listRefreshMin', 'هر چند دقیقه لیست جدید', 1, 1000, 180, 1000, false,
      () => listRefreshMin, (v) => listRefreshMin = v),
  NumOpt('failMin', 'سرور خراب تا چند دقیقه تست نشود', 1, 1000, 90, 1000, false,
      () => failMin, (v) {
    failMin = v;
    failWindow = Duration(minutes: v);
  }),
  NumOpt('recheckMin', 'بررسی دوباره سرورهای سالم (دقیقه)', 1, 1000, 20, 1000,
      false, () => recheckMin, (v) {
    recheckMin = v;
    recheckAfter = Duration(minutes: v);
  }),
  // ----- 12 new options -----
  NumOpt('tcpWorkers', 'پیش‌فیلتر TCP همزمان', 1, 1000, 60, 1000, true,
      () => tcpWorkers, (v) => tcpWorkers = v),
  NumOpt('tcpTimeout', 'تایم‌اوت TCP (دهم ثانیه)', 1, 1000, 35, 1000, true,
      () => tcpTimeout.inMilliseconds ~/ 100,
      (v) => tcpTimeout = Duration(milliseconds: v * 100)),
  NumOpt('maxPerSource', 'حداکثر سرور از هر منبع', 1, 1000, 120, 1000, true,
      () => maxPerSource, (v) => maxPerSource = v),
  NumOpt('fetchWorkers', 'دانلود همزمان لیست‌ها', 1, 1000, 6, 1000, true,
      () => fetchWorkers, (v) => fetchWorkers = v),
  NumOpt('fetchDeadline', 'مهلت دانلود لیست‌ها (ثانیه)', 1, 1000, 25, 1000, true,
      () => fetchDeadline.inSeconds,
      (v) => fetchDeadline = Duration(seconds: v)),
  NumOpt('firstBatchSize', 'اندازه دسته‌ی اول', 1, 1000, 50, 1000, true,
      () => firstBatchSize, (v) => firstBatchSize = v),
  NumOpt('standbyBatchSize', 'اندازه دسته (وقتی وصل است)', 1, 1000, 40, 1000,
      true, () => standbyBatchSize, (v) => standbyBatchSize = v),
  NumOpt('maxBatches', 'حداکثر تعداد دسته در هر جستجو', 1, 1000, 8, 1000, true,
      () => maxBatches, (v) => maxBatches = v),
  NumOpt('watchFailLimit', 'تعداد پینگ ناموفق تا تعویض', 1, 1000, 3, 1000, true,
      () => watchFailLimit, (v) => watchFailLimit = v),
  NumOpt('badPingLimit', 'تعداد پینگ بد تا تعویض', 1, 1000, 3, 1000, true,
      () => badPingLimit, (v) => badPingLimit = v),
  NumOpt('missLimit', 'تعداد شکست تا حذف سرور سالم', 1, 1000, 3, 1000, true,
      () => missLimit, (v) => missLimit = v),
  NumOpt('watchEvery', 'فاصله‌ی چک اتصال (ثانیه)', 1, 1000, 30, 1000, true,
      () => watchEvery.inSeconds, (v) => watchEvery = Duration(seconds: v)),
  // ----- first search: time cap -----
  NumOpt('firstCapSec', 'سقف زمان جستجوی اول (ثانیه)', 1, 1000, 15, 1000, true,
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
  if (p.getBool('bgWorkersOne') != true) {
    bgWorkers = 1; // تست همزمان (وقتی وصل است) از ۳ به ۱
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
    // بولین‌های BEST هم برگردند
    autoSpeed = true;
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
    if (muxConc < 16) muxConc = 16;
    fragEnabled = false;
    cleanIpMode = true;
    npvParse = true;
    saveNumPrefs();
    _saveSettings();
    _set('✅ همه‌ی عددها و تنظیمات سرعت به پیش‌فرض BEST برگشتند');
  }

  // برگرداندن کامل: همه‌ی عددها + همه‌ی کلیدهای روشن/خاموش به مقدار اولیه‌ی برنامه
  void resetAllToDefaults() {
    resetNumbers();
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

  // AI has full range [lo, hi] — no artificial caps
  void applyNumSuggest(Map<String, int> m) {
    for (final o in numOpts) {
      if (aiLockedNums.contains(o.id)) continue;
      final v = m['num_${o.id}'];
      if (v != null) o.set(v.clamp(o.lo, o.hi).toInt());
    }
    saveNumPrefs();
  }
}


// TUNEDPATCH ===================== مقدارهای بهینه BEST (یکدست با numOpts) =====================
const Map<String, dynamic> _tunedSettings = {
  't': 8, // delayTimeout sec
  'bw2': 1, // bgWorkers
  'st': 5, // speedTopN
  'bp': 2500, // badPingMs
  'ms': 80, // minSpeedKB
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
  'fw2': 50, // fastWorkers
};
// BEST PROFILE — هم‌تراز numOpts.def
const Map<String, int> _tunedNums = {
  'fastWorkers': 50,
  'bgWorkers': 1,
  'timeout': 8,
  'batch': 120,
  'speedTopN': 5,
  'badPingMs': 2500,
  'minSpeedKB': 80,
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
  'bw2': 1,
  'st': 5,
  'bp': 2500,
  'ms': 80,
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
  'fw2': 50,
};
const Map<String, int> _tunedNums2 = {
  'fastWorkers': 50,
  'bgWorkers': 1,
  'timeout': 8,
  'batch': 120,
  'speedTopN': 5,
  'badPingMs': 2500,
  'minSpeedKB': 80,
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
  'bw2': 1,
  'st': 5,
  'bp': 2500,
  'ms': 80,
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
  'fw2': 50,
};
const Map<String, int> _tunedNums3 = {
  'fastWorkers': 50,
  'bgWorkers': 1,
  'timeout': 8,
  'batch': 120,
  'speedTopN': 5,
  'badPingMs': 2500,
  'minSpeedKB': 80,
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
          m['fw2'] = 50;
          await p.setString('settings', jsonEncode(m));
        }
      }
      final nx = p.getString('numx');
      if (nx != null) {
        final j = jsonDecode(nx);
        if (j is Map) {
          final m = Map<String, dynamic>.from(j);
          _tunedNums2.forEach((k, v) => m[k] = v);
          m['fastWorkers'] = 50;
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
          m['fw2'] = 50;
          await p.setString('settings', jsonEncode(m));
        }
      } else {
        await p.setString(
            'settings',
            jsonEncode({
              'ver': 6,
              ..._tunedSettings3,
              'fw2': 50,
            }));
      }
      final nx = p.getString('numx');
      if (nx != null) {
        final j = jsonDecode(nx);
        if (j is Map) {
          final m = Map<String, dynamic>.from(j);
          _tunedNums3.forEach((k, v) => m[k] = v);
          m['fastWorkers'] = 50;
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
          m['fw2'] = 50;
          m['st'] = 5;
          m['bw2'] = 3;
          m['bp'] = 2500;
          m['ms'] = 80;
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
          m['fastWorkers'] = 50;
          await p.setString('numx', jsonEncode(m));
        }
      } else {
        await p.setString('numx', jsonEncode(_tunedNums));
      }
      await p.setBool('tuned_v5', true);
      await p.setBool('bestProfile26', true);
    }
  } catch (e) {
    logError(e);
  }
  return p.getString('settings');
}

// ======================= خلبان محلی King Pro (بدون کلید API) =======================
// موتور تصمیم‌گیری چندلایه — سریع‌تر و پایدارتر از هر دستیار ابری.
// لایه‌ها: پروب واقعی سایت‌ها | امتیازدهی چندعاملی | حافظه اپراتور | ماشین‌حالت
// هیچ کلید API لازم نیست. تا قطع دستی کاربر، کنترل کامل دارد.

bool localPilotOn = false;
Timer? localPilotLoop;
final localPilotText = ValueNotifier<String>(
    'خلبان محلی King Pro آماده است.\nبدون API • تحلیل واقعی شبکه • اولویت تلگرام');
final localPilotLoading = ValueNotifier<bool>(false);

// Track flags forced by cloud pilot so stop can restore them
bool _pilotForcedUltra = false;
bool _pilotForcedIndestructible = false;
DateTime? _pilotConnectedAt; // hold before cloud pilot may switch
// engine the pilot/assistant should use: v2ray only
String pilotEngine = 'v2ray';

// قدرت خلبان محلی
int _localPower = 1;
int _localPeakPower = 1; // بالاترین قدرت دیده‌شده در این نشست

String _localLastOp = '';
String _localLastAction = '';
DateTime? _localLastTick;
DateTime? _busyStuckSince; // BUSYCLEAR: when the busy flag started looking stuck
DateTime? _localConnectedSince;
int _localFailStreak = 0;
int _localSlowStreak = 0;
int _localGoodStreak = 0;
// دکمه‌ی «جستجوی سرور با نت ملی» خلبان را با قدرت حداقل ۴ (نت ملی) روشن می‌کند
bool _localNatBtn = false;
int _localTickN = 0;
int _localTgOk = 0; // consecutive telegram OK
int _localTgFail = 0;

// حافظه یادگیری محلی: اپراتور → آخرین اقدام موفق / امتیاز
final Map<String, int> _localOpWins = {}; // action hash → win count
final Map<String, int> _localOpFails = {};

// ماشین‌حالت
// boot | search | stable | degraded | recover
String _localPhase = 'boot';

class _LocalNetSnap {
  final bool connected;
  final bool national;
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
  final int natLvl;
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
    required this.national,
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
    required this.natLvl,
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
    b.writeln(national ? '🇮🇷 نت ملی/محدود' : '🌍 اینترنت بین‌الملل');
    if (configProto != '-') {
      b.writeln('⚙️ $configProto / $configNet / $configSec');
    }
    if (pingMs != null) b.writeln('⏱ پینگ: ${pingMs}ms');
    if (speedMBs != null && speedMBs! > 0) {
      b.writeln('🚀 سرعت: ${speedMBs!.toStringAsFixed(2)} MB/s');
    }
    // سایت‌ها
    String bit(String name, bool? v) =>
        v == null ? '$name:?' : (v ? '$name:✅' : '$name:❌');
    b.writeln(
        '🌐 ${bit("تلگرام", tgOk)}  ${bit("یوتیوب", ytOk)}  ${bit("اینستا", igOk)}  ${bit("نت", netOk)}');
    b.writeln(
        '📦 سالم:$goodCount  صف:$pendingCount  سیاه:$failedCount  nat:$natLvl');
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
