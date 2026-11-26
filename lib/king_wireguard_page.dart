import 'package:flutter/material.dart';
import 'king_wireguard_core.dart';

/// First independently integrated KING VPN tunnel engine.
/// Accepts the native wg-quick profile format; it is not translated to Xray.
class KingWireGuardPage extends StatefulWidget {
  const KingWireGuardPage({super.key});

  @override
  State<KingWireGuardPage> createState() => _KingWireGuardPageState();
}

class _KingWireGuardPageState extends State<KingWireGuardPage> {
  final TextEditingController _profile = TextEditingController();
  final KingWireGuardCore _core = KingWireGuardCore();
  bool _busy = false;
  String _status = 'آمادهٔ اتصال';
  bool _connected = false;

  @override
  void dispose() {
    _profile.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'در حال راه‌اندازی موتور مستقل WireGuard…';
    });
    try {
      final result = await _core.connect(_profile.text);
      if (!mounted) return;
      setState(() {
        _connected = true;
        _status = 'WireGuard متصل شد • ${result['version'] ?? 'wireguard-go'}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connected = false;
        _status = 'اتصال ناموفق: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'در حال قطع WireGuard…';
    });
    try {
      await _core.disconnect();
      if (!mounted) return;
      setState(() {
        _connected = false;
        _status = 'WireGuard قطع شد';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'خطا هنگام قطع: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    try {
      final value = await _core.status();
      if (!mounted) return;
      setState(() {
        _connected = value == 'UP';
        _status = 'وضعیت موتور WireGuard: $value';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'وضعیت در دسترس نیست: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('هستهٔ مستقل WireGuard'),
          actions: [
            IconButton(
              tooltip: 'به‌روزرسانی وضعیت',
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('موتور واقعی WireGuard • wireguard-go',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text('این موتور مستقل از Xray/V2Ray اجرا می‌شود و کانفیگ اصلی WireGuard را می‌خواند.'),
                    SizedBox(height: 6),
                    Text('یک کانفیگ کامل شامل بخش‌های [Interface] و [Peer] وارد کن.'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _profile,
              minLines: 10,
              maxLines: 20,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                labelText: 'کانفیگ WireGuard',
                hintText: '[Interface]\\nPrivateKey = …\\nAddress = …\\n\\n[Peer]\\nPublicKey = …\\nEndpoint = …',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_busy || _connected) ? null : _connect,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('اتصال WireGuard'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_busy || !_connected) ? null : _disconnect,
                    icon: const Icon(Icons.stop),
                    label: const Text('قطع اتصال'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(_connected ? Icons.verified : Icons.info_outline,
                  color: _connected ? Colors.green : null),
              title: const Text('وضعیت'),
              subtitle: Text(_status),
            ),
          ],
        ),
      ),
    );
  }
}
