import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config_lab.dart';

class KingConfigLabPage extends StatefulWidget {
  const KingConfigLabPage({super.key, this.initialConfig = ''});

  final String initialConfig;

  @override
  State<KingConfigLabPage> createState() => _KingConfigLabPageState();
}

class _KingConfigLabPageState extends State<KingConfigLabPage> {
  late final TextEditingController _config;
  late final TextEditingController _address;
  late final TextEditingController _port;
  late final TextEditingController _sni;
  late final TextEditingController _host;
  late final TextEditingController _path;
  final List<KingConfigProbe> _probes = [];
  String _status = 'یک کانفیگ VLESS، VMess یا Trojan وارد کنید.';
  String _generated = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _config = TextEditingController(text: widget.initialConfig);
    _address = TextEditingController();
    _port = TextEditingController();
    _sni = TextEditingController();
    _host = TextEditingController();
    _path = TextEditingController();
    _loadFields();
  }

  void _loadFields() {
    try {
      final doc = KingConfigDocument.parse(_config.text);
      _address.text = doc.address;
      _port.text = doc.port?.toString() ?? '';
      _sni.text = doc.sni;
      _host.text = doc.hostHeader;
      _path.text = doc.values['path']?.toString() ??
          (doc.values['_query'] is Map
              ? (doc.values['_query'] as Map)['path']?.toString() ?? ''
              : '');
    } catch (_) {
      // The user may still be entering a link.
    }
  }

  Future<void> _scan() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _probes.clear();
      _status = 'در حال بررسی DNS، TCP و TLS مقصد همین کانفیگ…';
    });
    try {
      final doc = KingConfigDocument.parse(_config.text);
      final ports = int.tryParse(_port.text);
      final results = await const KingConfigAutoScanner().scan(
        doc,
        additionalSni: [_sni.text, _host.text].where((s) => s.trim().isNotEmpty),
        additionalPorts: ports == null ? const [] : [ports],
      );
      if (!mounted) return;
      setState(() {
        _probes
          ..clear()
          ..addAll(results);
        _status = 'بررسی تمام شد: ${results.where((r) => r.success).length} نتیجهٔ موفق از ${results.length} آزمایش. موفقیت TLS یا TCP به‌تنهایی به معنی اتصال VPN نیست.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'خطا در خواندن کانفیگ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _build() {
    try {
      final doc = KingConfigDocument.parse(_config.text);
      final overrides = <String, Object?>{};
      if (_address.text.trim().isNotEmpty) overrides['address'] = _address.text.trim();
      if (_port.text.trim().isNotEmpty) overrides['port'] = _port.text.trim();
      if (_sni.text.trim().isNotEmpty) overrides['sni'] = _sni.text.trim();
      if (_host.text.trim().isNotEmpty) overrides['host'] = _host.text.trim();
      if (_path.text.trim().isNotEmpty) overrides['path'] = _path.text;
      final output = doc.withOverrides(overrides).toShareLink();
      setState(() {
        _generated = output;
        _status = 'نسخهٔ ویرایش‌شده ساخته شد. قبل از استفاده، سازگاری آن را با سرور و هسته بررسی کنید.';
      });
    } catch (e) {
      setState(() => _status = 'ساخت کانفیگ انجام نشد: $e');
    }
  }

  @override
  void dispose() {
    _config.dispose();
    _address.dispose();
    _port.dispose();
    _sni.dispose();
    _host.dispose();
    _path.dispose();
    super.dispose();
  }

  Widget _field(String label, TextEditingController controller,
      {TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('آزمایشگاه کانفیگ KING')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('کانفیگ ورودی', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _config,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'vless://… یا vmess://… یا trojan://…',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _loadFields(),
          ),
          const SizedBox(height: 16),
          const Text('ویرایش دستی فیلدها', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _field('Address / IP / Domain', _address),
          _field('Port', _port, keyboardType: TextInputType.number),
          _field('SNI', _sni),
          _field('Host', _host),
          _field('Path', _path),
          FilledButton.icon(
            onPressed: _build,
            icon: const Icon(Icons.build),
            label: const Text('ساخت کانفیگ ویرایش‌شده'),
          ),
          if (_generated.isNotEmpty) ...[
            const SizedBox(height: 10),
            SelectableText(_generated),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(text: _generated)),
                icon: const Icon(Icons.copy),
                label: const Text('کپی کانفیگ ساخته‌شده'),
              ),
            ),
          ],
          const Divider(height: 32),
          const Text('اسکن خودکار مقصد کانفیگ', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _scan,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.radar),
            label: Text(_busy ? 'در حال اسکن…' : 'شروع اسکن خودکار'),
          ),
          const SizedBox(height: 8),
          Text(_status),
          for (final probe in _probes)
            ListTile(
              dense: true,
              leading: Icon(
                probe.success ? Icons.check_circle : Icons.cancel,
                color: probe.success ? Colors.green : Colors.red,
              ),
              title: Text('${probe.kind.name}: ${probe.value}'),
              subtitle: Text([
                if (probe.latency != null) '${probe.latency!.inMilliseconds} ms',
                if (probe.detail.isNotEmpty) probe.detail,
              ].join(' • ')),
            ),
        ],
      ),
    );
  }
}
