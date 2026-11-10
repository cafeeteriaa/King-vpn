// king_extras2.dart
//
// RELIABILITY-PASS additions that are safe to ship as a fully standalone file:
//   • kingShareText()   — D1/D2/D3 (Bluetooth / SMS / nearby sharing of a config
//                          or server list) via Android's own share sheet, instead
//                          of hand-rolled Bluetooth/Wi-Fi Direct/SMS code that has
//                          no way to be tested without a real device.
//   • kingSecureUuidV4() — A18: a strong random UUID for someone setting up their
//                          own personal Xray/V2Ray server.
//   • checkHostTcp()     — an extra "is this IP:port reachable from OUTSIDE this
//                          network" signal using the public check-host.net API,
//                          to complement the app's own on-device IP/CDN scanning
//                          (nip_scan / nat_ultra), which can only see what this
//                          one phone, on this one network, can reach.
//
// WHY THIS IS A SEPARATE `import`-ed FILE, NOT `part of 'main.dart'`:
// main.dart is ~14,000 lines with a long, hard-won history of very specific
// timing/ordering fixes around VPN connection and core startup (see the
// VPNRACE / CRASHGUARD / HANGSKIP / ABORTWAIT comments throughout it). None of
// that is touched here. Keeping this file as its own library means it cannot
// collide with any of main.dart's internal (underscore-prefixed) state, and it
// can be reviewed, and even deleted, without touching main.dart at all.
//
// HOW TO WIRE IT IN (not done automatically, on purpose — see the handoff
// report for why): add one import line near the top of lib/main.dart, next to
// the other `import` lines (NOT the `part` lines):
//     import 'king_extras2.dart';
// then open the page from anywhere you like, e.g. from a menu row:
//     onTap: () => Navigator.of(context).push(
//         MaterialPageRoute<void>(builder: (_) => const KingExtrasPage())),
// This file must also be listed in .github/workflows/build.yml's file-copy
// loop (already added) so CI actually ships it.

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

/// Opens Android's native "share" chooser with [text] (e.g. one or more
/// vmess://, vless://, trojan:// or ss:// links). Returns false if the native
/// side could not even open the chooser (e.g. no MainActivity.kt build of this
/// patch yet) — it does NOT mean the user cancelled the sheet, which Android
/// does not reliably report back.
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
// Uses Random.secure() (CSPRNG), no extra package needed.
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
// check-host.net — "is IP:port reachable from several vantage points outside
// this network", as a second opinion next to the app's own on-device scanning.
// Public API, no key needed: submit a check, then poll for results.
// NOTE: the exact shape of a check-host.net result (per-node fields) is parsed
// defensively here because it could not be exercised against a live response
// from this session (no outbound network access). The submit → poll → "any
// key still null means still pending" contract is the stable, documented part
// of the API and is what this code relies on; per-node success detection just
// looks for a non-empty, non-error-shaped result and degrades to "unknown"
// rather than throwing if check-host ever changes its exact field names.
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

/// Asks check-host.net to open a TCP connection to [host]:[port] from several
/// of its own vantage points (outside this phone's network) and reports how
/// many of them succeeded. Returns null on any network/parse failure — this is
/// an optional extra signal, never required for the app's own connect logic.
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
        continue; // one bad poll shouldn't abort the whole check
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

/// Best-effort read of one node's result entry. check-host wraps a successful
/// TCP check as a list containing a map WITHOUT an "error" key (commonly with
/// a "time" field); a failure includes an "error" string. Any shape that does
/// not clearly say "error" is treated as a non-reach rather than guessed at.
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
// A small, self-contained page that ties the three features above together.
// Uses plain Material theming (not the app's private _uiGold/_uiBg constants,
// which live inside main.dart's library and are not reachable from here) so it
// renders correctly regardless of how/where it gets opened from.
// =============================================================================

class KingExtrasPage extends StatefulWidget {
  /// Optional: pre-fill the share/UUID box with e.g. the currently selected
  /// server's link(s), so the caller does not have to know this widget's
  /// internals — just pass the text you already have.
  final String initialShareText;
  const KingExtrasPage({super.key, this.initialShareText = ''});

  @override
  State<KingExtrasPage> createState() => _KingExtrasPageState();
}

class _KingExtrasPageState extends State<KingExtrasPage> {
  late final TextEditingController _shareCtrl =
      TextEditingController(text: widget.initialShareText);
  final TextEditingController _hostCtrl = TextEditingController();
  final TextEditingController _portCtrl = TextEditingController(text: '443');
  String? _uuid;
  bool _checking = false;
  CheckHostResult? _chResult;
  String? _chError;

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
          ],
        ),
      ),
    );
  }
}
