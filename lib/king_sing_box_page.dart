import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sing_box/sing_box.dart';
import 'king_sing_box_core.dart';

class KingSingBoxPage extends StatefulWidget {
  const KingSingBoxPage({super.key});
  @override
  State<KingSingBoxPage> createState() => _KingSingBoxPageState();
}

class _KingSingBoxPageState extends State<KingSingBoxPage> {
  final _input = TextEditingController();
  Stream<SingBoxConnectionState>? _states;
  Stream<SingBoxConnectionStats>? _stats;
  String _message = 'در حال آماده‌سازی...';
  String _version = '';
  bool _busy = false;

  @override
  void initState() { super.initState(); unawaited(_init()); }

  Future<void> _init() async {
    try {
      await KingSingBoxCore.instance.initialize();
      final version = await KingSingBoxCore.instance.version();
      if (!mounted) return;
      setState(() {
        _version = version;
        _states = KingSingBoxCore.instance.watchState();
        _stats = KingSingBoxCore.instance.watchStats();
        _message = 'هسته آماده است؛ لینک یا JSON را وارد کنید';
      });
    } catch (e) { if (mounted) setState(() => _message = 'آماده‌سازی ناموفق: $e'); }
  }

  Future<void> _connect() async {
    if (_busy) return;
    setState(() { _busy = true; _message = 'در حال اعتبارسنجی و اتصال...'; });
    try {
      await KingSingBoxCore.instance.connect(_input.text);
      if (mounted) setState(() => _message = 'اتصال توسط هسته تأیید شد');
    } catch (e) { if (mounted) setState(() => _message = 'خطا: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _disconnect() async {
    if (_busy) return;
    setState(() { _busy = true; _message = 'در حال توقف امن تونل...'; });
    try {
      await KingSingBoxCore.instance.disconnect();
      if (mounted) setState(() => _message = 'تونل متوقف شد');
    } catch (e) { if (mounted) setState(() => _message = 'توقف تأیید نشد: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  String _rate(int value) {
    if (value < 1024) return '$value B/s';
    if (value < 1048576) return '${(value / 1024).toStringAsFixed(1)} KB/s';
    return '${(value / 1048576).toStringAsFixed(2)} MB/s';
  }

  String _status(SingBoxConnectionStatus s) {
    switch (s) {
      case SingBoxConnectionStatus.disconnected: return 'قطع';
      case SingBoxConnectionStatus.connecting: return 'در حال اتصال';
      case SingBoxConnectionStatus.connected: return 'متصل';
      case SingBoxConnectionStatus.disconnecting: return 'در حال قطع';
    }
  }

  @override
  void dispose() { _input.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('هستهٔ مستقل چندپروتکلی libbox')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('وضعیت موتور', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          StreamBuilder<SingBoxConnectionState>(
            stream: _states,
            initialData: SingBoxConnectionState.initial,
            builder: (context, snap) {
              final state = snap.data ?? SingBoxConnectionState.initial;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('وضعیت: ${_status(state.status)}'),
                if (state.error != null) Text('آخرین خطا: ${state.error}'),
              ]);
            },
          ),
          if (_version.isNotEmpty) Text('نسخهٔ هسته: $_version'),
          Text(_message),
          const SizedBox(height: 10),
          StreamBuilder<SingBoxConnectionStats>(
            stream: _stats,
            initialData: SingBoxConnectionStats.empty,
            builder: (context, snap) {
              final stats = snap.data ?? SingBoxConnectionStats.empty;
              return Row(children: [
                Expanded(child: Text('دریافت: ${_rate(stats.downloadSpeed)}')),
                Expanded(child: Text('ارسال: ${_rate(stats.uploadSpeed)}')),
              ]);
            },
          ),
        ]),
      )),
      const SizedBox(height: 12),
      const Text('لینک VLESS، VMess، Trojan، Shadowsocks، Hysteria2، TUIC یا JSON کامل پیکربندی را وارد کنید.'),
      const SizedBox(height: 8),
      TextField(controller: _input, minLines: 6, maxLines: 14,
        autocorrect: false, enableSuggestions: false,
        decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'لینک یا JSON پیکربندی...')),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: FilledButton.icon(onPressed: _busy ? null : _connect,
          icon: const Icon(Icons.play_arrow), label: const Text('اتصال با libbox'))),
        const SizedBox(width: 10),
        Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _disconnect,
          icon: const Icon(Icons.stop), label: const Text('قطع اتصال'))),
      ]),
      const SizedBox(height: 12),
      const Text('این موتور تونل مستقل دارد؛ هنگام جابه‌جایی مالکیت TUN با Xray و WireGuard هماهنگ می‌شود و هسته‌های قبلی حذف نمی‌شوند.'),
    ]),
  );
}
