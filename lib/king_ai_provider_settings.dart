import 'package:flutter/material.dart';

import 'king_ai_provider_orchestrator.dart';

/// Settings for user-controlled cloud model providers.
class KingAiProviderSettingsPage extends StatefulWidget {
  const KingAiProviderSettingsPage({super.key});

  @override
  State<KingAiProviderSettingsPage> createState() =>
      _KingAiProviderSettingsPageState();
}

class _KingAiProviderSettingsPageState extends State<KingAiProviderSettingsPage> {
  final _orchestrator = KingAiProviderOrchestrator.instance;
  final Map<KingAiProviderId, TextEditingController> _keys = {};
  final Map<KingAiProviderId, TextEditingController> _models = {};
  final Map<KingAiProviderId, bool> _configured = {};
  bool _externalEnabled = false;
  bool _externalCodeEnabled = false;
  bool _loading = true;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    for (final provider in KingAiProviderOrchestrator.providers) {
      _keys[provider.id] = TextEditingController();
      _models[provider.id] = TextEditingController(text: provider.defaultModel);
    }
    _load();
  }

  @override
  void dispose() {
    for (final controller in _keys.values) {
      controller.dispose();
    }
    for (final controller in _models.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final consent = await _orchestrator.externalProcessingEnabled;
      final codeConsent = await _orchestrator.externalCodeReviewEnabled;
      final states = <KingAiProviderId, bool>{};
      for (final provider in KingAiProviderOrchestrator.providers) {
        states[provider.id] = await _orchestrator.isConfigured(provider.id);
        _models[provider.id]!.text =
            await _orchestrator.getProviderModel(provider.id);
      }
      if (!mounted) return;
      setState(() {
        _externalEnabled = consent;
        _externalCodeEnabled = codeConsent;
        _configured
          ..clear()
          ..addAll(states);
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() {
        _loading = false;
        _message = 'خواندن تنظیمات ارائه‌دهندگان ناموفق بود: $error';
      });
    }
  }

  Future<void> _save(KingAiProviderDescriptor provider) async {
    final key = _keys[provider.id]!.text.trim();
    if (key.isEmpty) {
      setState(() => _message = 'کلید API را وارد کن.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _orchestrator.saveProvider(
        id: provider.id,
        apiKey: key,
        model: _models[provider.id]!.text,
      );
      if (!mounted) return;
      _keys[provider.id]!.clear();
      setState(() {
        _configured[provider.id] = true;
        _message = 'تنظیمات ' + provider.title + ' به‌صورت امن ذخیره شد.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'ذخیره انجام نشد: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(KingAiProviderDescriptor provider) async {
    setState(() => _busy = true);
    try {
      await _orchestrator.removeProvider(provider.id);
      if (!mounted) return;
      _keys[provider.id]!.clear();
      setState(() {
        _configured[provider.id] = false;
        _message = 'کلید ' + provider.title + ' از حافظه امن حذف شد.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'حذف کلید انجام نشد: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setConsent(bool enabled) async {
    try {
      await _orchestrator.setExternalProcessingEnabled(enabled);
      if (mounted) setState(() {
        _externalEnabled = enabled;
        if (!enabled) _externalCodeEnabled = false;
        _message = enabled
            ? 'پردازش ابری فعال شد؛ فقط درخواست‌هایی که خودت به مدل آنلاین می‌فرستی ارسال می‌شوند.'
            : 'پردازش ابری غیرفعال شد؛ درخواست‌ها به ارائه‌دهندگان بیرونی ارسال نمی‌شوند.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'تغییر رضایت انجام نشد: $error');
    }
  }

  Future<void> _setCodeConsent(bool enabled) async {
    try {
      await _orchestrator.setExternalCodeReviewEnabled(enabled);
      if (mounted) setState(() {
        _externalCodeEnabled = enabled;
        _message = enabled
            ? 'ارسال بخش‌های لازم از سورس پروژه برای بازبینی چندمدلی فعال شد.'
            : 'ارسال سورس پروژه به ارائه‌دهندگان بیرونی غیرفعال شد.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'تغییر رضایت کدنویسی انجام نشد: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('هوش مصنوعی چندمدلی KING AI')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: SwitchListTile(
                      value: _externalEnabled,
                      onChanged: _busy ? null : _setConsent,
                      title: const Text('اجازه استفاده از هوش مصنوعی آنلاین'),
                      subtitle: const Text(
                        'خاموش باشد، هیچ متن یا تصویری از طریق این موتور به سرویس بیرونی ارسال نمی‌شود. کلیدها جداگانه و امن نگهداری می‌شوند.',
                      ),
                    ),
                  ),
                  Card(
                    child: SwitchListTile(
                      value: _externalCodeEnabled,
                      onChanged: _busy || !_externalEnabled ? null : _setCodeConsent,
                      title: const Text('اجازه بازبینی سورس پروژه توسط چند هوش مصنوعی'),
                      subtitle: const Text(
                        'این اجازه جدا از چت ابری است. فقط در مسیر توسعه‌دهنده و پس از احراز هویت مالک، بخش‌های لازم از کد برای همه providerهای فعال ارسال می‌شوند؛ هر سرویس ممکن است هزینه جداگانه داشته باشد.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'برای هر سرویس، کلید API خودت را وارد کن. KING AI می‌تواند هنگام خطا به ارائه‌دهنده فعال بعدی برود. مدل و هزینه به حساب و تعرفه همان سرویس بستگی دارد.',
                  ),
                  const SizedBox(height: 12),
                  for (final provider in KingAiProviderOrchestrator.providers)
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    provider.title,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Icon(
                                  _configured[provider.id] == true
                                      ? Icons.verified
                                      : Icons.radio_button_unchecked,
                                  color: _configured[provider.id] == true
                                      ? Colors.green
                                      : Theme.of(context).colorScheme.outline,
                                ),
                              ],
                            ),
                            if (provider.note.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(provider.note, style: Theme.of(context).textTheme.bodySmall),
                            ],
                            const SizedBox(height: 8),
                            TextField(
                              controller: _models[provider.id],
                              enabled: !_busy,
                              decoration: const InputDecoration(
                                labelText: 'نام مدل (قابل تغییر)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _keys[provider.id],
                              enabled: !_busy,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: InputDecoration(
                                labelText: 'کلید API',
                                hintText: _configured[provider.id] == true
                                    ? 'کلید قبلی ذخیره است؛ برای تعویض، کلید جدید را وارد کن'
                                    : 'کلید را اینجا وارد کن',
                                border: const OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton(
                                    onPressed: _busy ? null : () => _save(provider),
                                    child: const Text('ذخیره امن'),
                                  ),
                                ),
                                if (_configured[provider.id] == true) ...[
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed: _busy ? null : () => _remove(provider),
                                    child: const Text('حذف کلید'),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              provider.supportsVision
                                  ? 'متن و تصویر (بسته به مدل انتخابی)'
                                  : 'فقط متن',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Divider(),
                  const Text(
                    'Cursor یک محیط/عامل برنامه‌نویسی است، نه API مدل عمومی. در این نسخه به‌عنوان ارائه‌دهنده مستقیم ثبت نشده؛ اتصال آن نیازمند مسیر رسمی Agent/CLI یا اتصال محیط توسعه جداگانه است.',
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(_message!),
                  ],
                ],
              ),
      ),
    );
  }
}
