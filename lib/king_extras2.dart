// king_extras2.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'prefs_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// =============================================================================
// D1/D2/D3 — share via Android's own share sheet (Bluetooth, SMS, Nearby Share,
// Telegram, email, or any other app installed that accepts shared text).
// =============================================================================

const MethodChannel _kingShareChannel = MethodChannel('king/share');

Future<bool> kingShareText(String text, {String subject = ''}) async {
  try {
    final ok = await _kingShareChannel
        .invokeMethod<bool>('shareText', {'text': text, 'subject': subject});
    return ok ?? false;
  } catch (_) {
    return false;
  }
}

// =============================================================================
// A18 — strong random UUID (RFC 4122 v4) for a self-hosted Xray/V2Ray server.
// =============================================================================

String kingSecureUuidV4() {
  final rnd = Random.secure();
  final b = List<int>.generate(16, (_) => rnd.nextInt(256));
  b[6] = (b[6] & 0x0F) | 0x40; // version 4
  b[8] = (b[8] & 0x3F) | 0x80; // variant 10xx
  String hx(int s, int e) =>
      b.sublist(s, e).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hx(0, 4)}-${hx(4, 6)}-${hx(6, 8)}-${hx(8, 10)}-${hx(10, 16)}';
}

// =============================================================================
// check-host.net — external reachability check
// =============================================================================

class CheckHostResult {
  final int totalNodes;
  final int okNodes;
  final List<String> nodeNotes;
  final bool timedOut;
  const CheckHostResult({
    required this.totalNodes,
    required this.okNodes,
    required this.nodeNotes,
    this.timedOut = false,
  });
  bool get anyReachable => okNodes > 0;
  String get summary => timedOut
      ? 'پاسخ کامل نرسید (برخی گره‌ها جواب ندادند)'
      : '$okNodes از $totalNodes گره در دسترس بود';
}

Future<CheckHostResult?> checkHostTcp(
  String host,
  int port, {
  int maxNodes = 5,
  Duration pollEvery = const Duration(seconds: 2),
  Duration timeout = const Duration(seconds: 25),
}) async {
  try {
    final submitUri = Uri.parse(
        'https://check-host.net/check-tcp?host=$host:$port&max_nodes=$maxNodes');
    final submitRes = await http
        .get(submitUri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));
    if (submitRes.statusCode != 200) return null;
    final submitJson = jsonDecode(submitRes.body);
    if (submitJson is! Map || submitJson['ok'] != true) return null;
    final requestId = submitJson['request_id']?.toString();
    final nodesField = submitJson['nodes'];
    final totalNodes = nodesField is Map ? nodesField.length : maxNodes;
    if (requestId == null || requestId.isEmpty) return null;

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(pollEvery);
      final resUri = Uri.parse('https://check-host.net/check-result/$requestId');
      http.Response r;
      try {
        r = await http
            .get(resUri, headers: const {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        continue;
      }
      if (r.statusCode != 200) continue;
      final data = jsonDecode(r.body);
      if (data is! Map) continue;
      final stillPending = data.values.any((v) => v == null);
      if (stillPending) continue;

      var ok = 0;
      final notes = <String>[];
      data.forEach((node, value) {
        final reached = _checkHostNodeReached(value);
        if (reached) ok++;
        notes.add('$node: ${reached ? "OK" : "-"}');
      });
      return CheckHostResult(
          totalNodes: totalNodes, okNodes: ok, nodeNotes: notes);
    }
    return const CheckHostResult(
        totalNodes: 0, okNodes: 0, nodeNotes: [], timedOut: true);
  } catch (_) {
    return null;
  }
}

bool _checkHostNodeReached(dynamic value) {
  if (value is! List || value.isEmpty) return false;
  final first = value.first;
  if (first is Map) {
    if (first.containsKey('error')) return false;
    if (first.containsKey('time') || first.containsKey('address')) return true;
  }
  return false;
}

// =============================================================================
// صفحه اصلی امکانات تکمیلی (دریافت اطلاعات از main.dart)
// =============================================================================

class KingExtrasPage extends StatefulWidget {
  final String initialShareText;
  final String initialHost;
  final String initialPort;

  const KingExtrasPage({
    super.key,
    this.initialShareText = '',
    this.initialHost = '',
    this.initialPort = '443',
  });

  @override
  State<KingExtrasPage> createState() => _KingExtrasPageState();
}

class _KingExtrasPageState extends State<KingExtrasPage> {
  late final TextEditingController _shareCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  
  String? _uuid;
  bool _checking = false;
  CheckHostResult? _chResult;
  String? _chError;

  @override
  void initState() {
    super.initState();
    
    // پر کردن خودکار باکس‌ها
    _shareCtrl = TextEditingController(text: widget.initialShareText);
    _hostCtrl = TextEditingController(text: widget.initialHost);
    _portCtrl = TextEditingController(text: widget.initialPort);

    // تولید خودکار UUID
    _genUuid();
  }

  @override
  void dispose() {
    _shareCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _doShare() async {
    final text = _shareCtrl.text.trim();
    if (text.isEmpty) return;
    final ok = await kingShareText(text, subject: 'King VPN');
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('اشتراک‌گذاری باز نشد؛ متن در کلیپ‌بورد کپی شد.')));
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  void _genUuid() {
    setState(() => _uuid = kingSecureUuidV4());
  }

  Future<void> _runCheckHost() async {
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim());
    if (host.isEmpty || port == null || port <= 0 || port > 65535) {
      setState(() {
        _chError = 'آدرس یا پورت نامعتبر است';
        _chResult = null;
      });
      return;
    }
    setState(() {
      _checking = true;
      _chError = null;
      _chResult = null;
    });
    final r = await checkHostTcp(host, port);
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (r == null) {
        _chError = 'check-host.net جواب نداد (اینترنت یا خود سرویس را چک کن)';
      } else {
        _chResult = r;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('امکانات تکمیلی')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---- Share ----
            const Text('اشتراک‌گذاری نزدیک / آفلاین',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            const Text(
                'لینک کانفیگ یا لیست سرورها را بچسبان؛ شیت اشتراک‌گذاری اندروید باز '
                'می‌شود (بلوتوث، پیامک، Nearby Share، تلگرام، ایمیل، هر اپ دیگری).',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: _shareCtrl,
              maxLines: 4,
              minLines: 1,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), hintText: 'vless://... یا چند لینک'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _doShare,
              icon: const Icon(Icons.share),
              label: const Text('اشتراک‌گذاری'),
            ),
            const Divider(height: 32),

            // ---- UUID ----
            const Text('UUID تصادفی و امن برای سرور شخصی',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SelectableText(_uuid ?? '—',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
                ),
                IconButton(
                  tooltip: 'ساخت UUID جدید',
                  icon: const Icon(Icons.refresh),
                  onPressed: _genUuid,
                ),
                if (_uuid != null)
                  IconButton(
                    tooltip: 'کپی',
                    icon: const Icon(Icons.copy),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: _uuid!)),
                  ),
              ],
            ),
            const Divider(height: 32),

            // ---- check-host.net ----
            const Text('آزمایش در دسترس بودن از بیرون (check-host.net)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            const Text(
                'جدا از اسکن داخل اپ (که فقط از همین گوشی و همین شبکه می‌بیند)، این '
                'یک نظر دوم از چند نقطه‌ی دیگر دنیا می‌گیرد.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _hostCtrl,
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(), hintText: 'IP یا دامنه'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _portCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(border: OutlineInputBorder(), hintText: 'پورت'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _checking ? null : _runCheckHost,
              icon: _checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.public),
              label: Text(_checking ? 'در حال بررسی…' : 'بررسی'),
            ),
            if (_chError != null) ...[
              const SizedBox(height: 8),
              Text(_chError!, style: const TextStyle(color: Colors.redAccent)),
            ],
            if (_chResult != null) ...[
              const SizedBox(height: 8),
              Text(_chResult!.summary,
                  style: TextStyle(
                      color: _chResult!.anyReachable
                          ? Colors.green
                          : Colors.redAccent,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(_chResult!.nodeNotes.join(' • '),
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],

            const Divider(height: 40),

            // ---- راهنمای ساده (بخش جدید) ----
            const Text('💡 راهنمای ساده این صفحه',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.amber)),
            const SizedBox(height: 12),
            
            // راهنمای بخش ۱
            const Text('۱. اشتراک‌گذاری نزدیک (آفلاین):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            const Text(
              'اگر یک سرور خوب پیدا کردی و می‌خواهی به دوستت بدهی، لینک آن در باکس بالا قرار دارد. با زدن دکمه «اشتراک‌گذاری»، می‌توانی آن را از طریق بلوتوث، تلگرام یا پیامک برای دوستت بفرستی؛ حتی بدون اینترنت!',
              style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.5),
            ),
            const SizedBox(height: 16),

            // راهنمای بخش ۲
            const Text('۲. UUID برای سرور شخصی:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            const Text(
              'اگر می‌خواهی با Cloudflare سرور شخصی خودت را بسازی، به یک رمز عبور بسیار قوی (UUID) نیاز داری. این کد به صورت خودکار ساخته شده است. آن را کپی کن و در تنظیمات سرور شخصی‌ات قرار بده تا فقط تو اجازه اتصال داشته باشی.',
              style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.5),
            ),
            const SizedBox(height: 16),

            // راهنمای بخش ۳
            const Text('۳. آزمایش دسترسی از بیرون:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            const Text(
              'گاهی اپ می‌گوید سرور خراب است، ولی شاید اینترنت خودت مشکل داشته باشد. با زدن دکمه «بررسی»، این بخش از ۵ نقطه مختلف دنیا (مثل آلمان و آمریکا) سرور را تست می‌کند. اگر نتیجه سبز بود (۵ از ۵)، یعنی سرور کاملاً سالم است و مشکل از گوشی یا اینترنت توست. اگر قرمز بود، یعنی سرور واقعاً فیلتر یا خاموش شده است.',
              style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.5),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Cloudflare auto-deploy: builds a personal VLESS/WebSocket Worker in the user's
// own Cloudflare account, using only an API Token the user pastes once.
// =============================================================================

const String _kCfCompatDate = '2024-09-23';

// Worker source. Placeholder YOUR_UUID_HEX is replaced at deploy time.
const String _kCfWorkerTemplate = r'''
import { connect } from 'cloudflare:sockets';

const UUID_HEX = 'YOUR_UUID_HEX';

export default {
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === '/') return new Response('King VPN Auto Server', { status: 200 });
    if (request.headers.get('Upgrade') !== 'websocket') return new Response('Expected websocket', { status: 426 });

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    server.accept();

    let remote = null;
    let writer = null;

    server.addEventListener('close', () => {
      try { if (remote) remote.close(); } catch (_) {}
    });

    server.addEventListener('message', async (event) => {
      try {
        const chunk = new Uint8Array(event.data);

        if (remote) {
          await writer.write(chunk);
          return;
        }

        if (chunk.length < 24) { server.close(1003, 'Invalid data'); return; }

        const version = chunk[0];
        const uuid = Array.from(chunk.slice(1, 17)).map(b => b.toString(16).padStart(2, '0')).join('');
        if (uuid !== UUID_HEX) { server.close(1008, 'Invalid UUID'); return; }

        const optLen = chunk[17];
        const cmd = chunk[18 + optLen];
        if (cmd !== 1) { server.close(1003, 'Only TCP is supported'); return; }

        const port = (chunk[19 + optLen] << 8) | chunk[20 + optLen];
        const addrType = chunk[21 + optLen];
        let p = 22 + optLen;
        let host = '';

        if (addrType === 1) {
          host = Array.from(chunk.slice(p, p + 4)).join('.');
          p += 4;
        } else if (addrType === 2) {
          const len = chunk[p];
          host = new TextDecoder().decode(chunk.slice(p + 1, p + 1 + len));
          p += 1 + len;
        } else if (addrType === 3) {
          const parts = [];
          for (let i = 0; i < 8; i++) {
            parts.push(((chunk[p + i * 2] << 8) | chunk[p + i * 2 + 1]).toString(16));
          }
          host = parts.join(':');
          p += 16;
        } else {
          server.close(1003, 'Bad address type');
          return;
        }

        remote = connect({ hostname: host, port: port });
        writer = remote.writable.getWriter();

        // VLESS response header, then the first payload that came with the request.
        server.send(new Uint8Array([version, 0]));
        const payload = chunk.slice(p);
        if (payload.length) await writer.write(payload);

        remote.readable.pipeTo(new WritableStream({
          write(data) { server.send(data); },
        })).catch(() => {}).finally(() => {
          try { server.close(1000, 'done'); } catch (_) {}
        });
      } catch (e) {
        try { server.close(1011, 'Connection failed'); } catch (_) {}
      }
    });

    return new Response(null, { status: 101, webSocket: client });
  },
};
''';

class CfDeployResult {
  final String link;
  final String workerName;
  const CfDeployResult(this.link, this.workerName);
}

String _cfErrText(http.Response r) {
  try {
    final j = jsonDecode(r.body);
    final errs = j is Map ? j['errors'] : null;
    if (errs is List && errs.isNotEmpty) {
      final msgs = errs
          .map((e) => e is Map ? (e['message'] ?? e.toString()) : e.toString())
          .join(' | ');
      return 'HTTP ${r.statusCode}: $msgs';
    }
  } catch (_) {}
  return 'HTTP ${r.statusCode}';
}

/// Creates a Worker in the user's Cloudflare account and returns a vless:// link.
/// Throws an Exception with a readable message on failure.
Future<CfDeployResult> cloudflareAutoDeploy(String token) async {
  final auth = {'Authorization': 'Bearer $token'};
  const timeout = Duration(seconds: 30);

  // Step 1: account id
  final accRes = await http
      .get(Uri.parse('https://api.cloudflare.com/client/v4/accounts'), headers: auth)
      .timeout(timeout);
  if (accRes.statusCode != 200) {
    throw Exception('گرفتن Account ID ناموفق بود (${_cfErrText(accRes)}). توکن و دسترسی Account Settings (Read) را بررسی کن.');
  }
  final accJson = jsonDecode(accRes.body) as Map;
  final accounts = (accJson['result'] as List?) ?? const [];
  if (accounts.isEmpty) {
    throw Exception('هیچ حسابی برای این توکن پیدا نشد.');
  }
  final accountId = (accounts.first as Map)['id'] as String;

  // Step 2: upload the Worker as an ES module (multipart is required for `import`)
  final uuid = kingSecureUuidV4().replaceAll('-', '');
  final workerName = 'king-vpn-${Random.secure().nextInt(9999)}';
  final script = _kCfWorkerTemplate.replaceAll('YOUR_UUID_HEX', uuid);
  final boundary = 'kingcf${DateTime.now().microsecondsSinceEpoch}';
  final metadata = jsonEncode({
    'main_module': 'worker.js',
    'compatibility_date': _kCfCompatDate,
    'bindings': [],
  });
  final body = '--$boundary\r\n'
      'Content-Disposition: form-data; name="metadata"\r\n'
      'Content-Type: application/json\r\n\r\n'
      '$metadata\r\n'
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="worker.js"; filename="worker.js"\r\n'
      'Content-Type: application/javascript+module\r\n\r\n'
      '$script\r\n'
      '--$boundary--\r\n';

  final scriptUrl =
      'https://api.cloudflare.com/client/v4/accounts/$accountId/workers/scripts/$workerName';
  final putRes = await http
      .put(
        Uri.parse(scriptUrl),
        headers: {...auth, 'Content-Type': 'multipart/form-data; boundary=$boundary'},
        body: body,
      )
      .timeout(timeout);
  if (putRes.statusCode != 200) {
    throw Exception('ساخت سرور ناموفق بود (${_cfErrText(putRes)}).');
  }

  // Step 3: enable the workers.dev route
  final subRes = await http
      .post(
        Uri.parse('$scriptUrl/subdomain'),
        headers: {...auth, 'Content-Type': 'application/json'},
        body: jsonEncode({'enabled': true}),
      )
      .timeout(timeout);
  if (subRes.statusCode != 200) {
    throw Exception('فعال‌سازی دامنه workers.dev ناموفق بود (${_cfErrText(subRes)}).');
  }

  // Step 4: build the link
  final host = '$workerName.workers.dev';
  final link = 'vless://$uuid@$host:443?encryption=none&security=tls'
      '&sni=$host&fp=chrome&type=ws&host=$host&path=%2F%3Fed%3D2048#$workerName';
  return CfDeployResult(link, workerName);
}

class CloudflareAutoDeployPage extends StatefulWidget {
  const CloudflareAutoDeployPage({super.key});

  @override
  State<CloudflareAutoDeployPage> createState() => _CloudflareAutoDeployPageState();
}

class _CloudflareAutoDeployPageState extends State<CloudflareAutoDeployPage> {
  static const _gold = Color(0xFFFFC107);
  static const _bg = Color(0xFF0E0E12);
  static const _card = Color(0xFF1A1A22);

  final _tokenCtrl = TextEditingController();
  bool _deploying = false;
  bool _saved = false;
  String? _link;
  String? _error;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _deploy() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'اول API Token را وارد کن.');
      return;
    }
    setState(() {
      _deploying = true;
      _error = null;
      _link = null;
      _saved = false;
    });
    try {
      final r = await cloudflareAutoDeploy(token);
      if (!mounted) return;
      setState(() => _link = r.link);
    } on TimeoutException {
      if (mounted) setState(() => _error = 'اتصال به Cloudflare زمان‌بر شد. دوباره تلاش کن.');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _deploying = false);
    }
  }

  Future<void> _copyLink() async {
    final l = _link;
    if (l == null) return;
    await Clipboard.setData(ClipboardData(text: l));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('لینک کپی شد')));
  }

  Future<void> _saveToConfigs() async {
    final l = _link;
    if (l == null) return;
    final p = await SharedPreferences.getInstance();
    // D2: plaintext prefs copy removed; link lives only in secure storage
    await p.remove('personal_link');
    await p.remove('personal_exp');
    // همگام‌سازی کپی secure (همان مسیر خواندن _loadCache)
    try {
      const sec = FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true));
      await sec.write(key: 'personal_link', value: l)
          .timeout(const Duration(seconds: 3));
      await sec.delete(key: 'personal_exp')
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('در «کانفیگ‌های من» ذخیره شد. برای نمایش، برنامه را یک بار ببند و باز کن.')));
  }

  Widget _step(int n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _gold),
            ),
            child: Text('$n', style: const TextStyle(color: _gold, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.6)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _gold,
        title: const Text('🚀 ساخت خودکار سرور کلودفلر (رایگان)'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('راهنمای گرفتن API Token',
                      style: TextStyle(color: _gold, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 12),
                  _step(1, 'به سایت dash.cloudflare.com بروید.'),
                  _step(2, 'روی پروفایل خود کلیک کنید و My Profile را بزنید.'),
                  _step(3, 'از منوی سمت چپ API Tokens را انتخاب کنید.'),
                  _step(4, 'روی Create Token بزنید و پایین صفحه قالب Custom Token را انتخاب کنید.'),
                  _step(5, 'در بخش Permissions، گزینه‌های Account Settings (Read) و Workers Scripts (Edit) را انتخاب کنید.'),
                  _step(6, 'روی Continue و سپس Create Token بزنید. کد ساخته شده را کپی کنید.'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tokenCtrl,
              obscureText: true,
              enabled: !_deploying,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'API Token',
                labelStyle: const TextStyle(color: _gold),
                filled: true,
                fillColor: _card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _gold),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _deploying ? null : _deploy,
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.black,
                disabledBackgroundColor: _gold.withOpacity(0.4),
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _deploying
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                        ),
                        SizedBox(width: 12),
                        Text('در حال ساخت سرور...', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    )
                  : const Text('همین حالا سرور من را بساز',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, height: 1.6)),
            ],
            if (_link != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _gold.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('سرور شما ساخته شد ✅',
                        style: TextStyle(color: _gold, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    SelectableText(
                      _link!,
                      style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _copyLink,
                            icon: const Icon(Icons.copy, size: 18),
                            label: const Text('کپی لینک'),
                            style: OutlinedButton.styleFrom(foregroundColor: _gold),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _saved ? null : _saveToConfigs,
                            icon: Icon(_saved ? Icons.check : Icons.bookmark_add_outlined, size: 18),
                            label: Text(_saved ? 'ذخیره شد' : 'ذخیره در کانفیگ‌های من'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _gold,
                              foregroundColor: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
