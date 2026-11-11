// king_extras2.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

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
