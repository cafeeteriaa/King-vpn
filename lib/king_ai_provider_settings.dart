import 'package:flutter/material.dart';
import 'king_ai_provider_pilot.dart';

/// Owner-facing configuration for King's private helper pool.
/// Providers are never exposed as separate chat destinations.
class KingAiProviderSettingsCard extends StatefulWidget {
  const KingAiProviderSettingsCard({super.key});

  @override
  State<KingAiProviderSettingsCard> createState() =>
      _KingAiProviderSettingsCardState();
}

class _KingAiProviderSettingsCardState
    extends State<KingAiProviderSettingsCard> {
  final _gemini = TextEditingController();
  final _groq = TextEditingController();
  final _mistral = TextEditingController();
  final _openRouter = TextEditingController();
  final _cloudflareToken = TextEditingController();
  final _cloudflareAccount = TextEditingController();

  bool _enabled = false;
  bool _loading = true;
  bool _saving = false;
  Map<KingAiProvider, bool> _configured = {};
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _gemini.dispose();
    _groq.dispose();
    _mistral.dispose();
    _openRouter.dispose();
    _cloudflareToken.dispose();
    _cloudflareAccount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final pilot = KingAiProviderPilot.instance;
      final enabled = await pilot.cloudEnabled;
      final configured = await pilot.configuredProviders();
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _configured = configured;
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() {
        _loading = false;
        _message = 'خواندن تنظیمات همکاران هوش مصنوعی ناموفق بود: $error';
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() { _saving = true; _message = null; });
    try {
      final pilot = KingAiProviderPilot.instance;
      final values = <KingAiProvider, String>{
        KingAiProvider.gemini: _gemini.text,
        KingAiProvider.groq: _groq.text,
        KingAiProvider.mistral: _mistral.text,
        KingAiProvider.openRouter: _openRouter.text,
        KingAiProvider.cloudflare: _cloudflareToken.text,
      };
      for (final entry in values.entries) {
        if (entry.value.trim().isNotEmpty) {
          await pilot.saveKey(entry.key, entry.value);
        }
      }
      if (_cloudflareAccount.text.trim().isNotEmpty) {
        await pilot.saveCloudflareAccountId(_cloudflareAccount.text);
      }
      await pilot.setCloudEnabled(_enabled);
      for (final controller in [
        _gemini, _groq, _mistral, _openRouter,
        _cloudflareToken, _cloudflareAccount,
      ]) {
        controller.clear();
      }
      final configured = await pilot.configuredProviders();
      if (!mounted) return;
      setState(() {
        _configured = configured;
        _message = 'کلیدها در حافظه امن دستگاه ذخیره شدند. King AI از آن‌ها فقط برای مشاوره داخلی استفاده می‌کند.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'ذخیره تنظیمات ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setEnabled(bool value) async {
    setState(() { _enabled = value; _message = null; });
    try {
      await KingAiProviderPilot.instance.setCloudEnabled(value);
      if (mounted) setState(() => _message = value
          ? 'مشاوره همکاران فعال شد؛ King AI می‌تواند برای کارهای منتخب از آن‌ها نظر تخصصی بگیرد.'
          : 'مشاوره ابری خاموش شد؛ King AI فقط با مغز محلی کار می‌کند.');
    } catch (error) {
      if (mounted) setState(() => _message = 'تغییر وضعیت انجام نشد: $error');
    }
  }

  Future<void> _clearAll() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف کلیدهای همکاران؟'),
          content: const Text('تمام کلیدهای ذخیره‌شده حذف و مشاوره ابری خاموش می‌شود.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(context, true),
                child: const Text('حذف همه')),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    try {
      final pilot = KingAiProviderPilot.instance;
      for (final provider in KingAiProvider.values) {
        await pilot.clearKey(provider);
      }
      await pilot.setCloudEnabled(false);
      if (!mounted) return;
      setState(() {
        _enabled = false;
        _configured = {};
        _message = 'کلیدهای همکاران حذف شدند.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'حذف کلیدها ناموفق بود: $error');
    }
  }

  Widget _keyField(String label, TextEditingController controller,
      KingAiProvider provider, {String? hint}) {
    final exists = _configured[provider] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: label,
          hintText: exists ? 'کلید ذخیره شده؛ برای جایگزینی کلید جدید وارد کن'
              : (hint ?? 'کلید API را وارد کن'),
          suffixIcon: Icon(exists ? Icons.verified_user_outlined : Icons.key),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _configured.values.where((value) => value).length;
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.hub_outlined),
        title: const Text('همکاران هوش مصنوعی King AI'),
        subtitle: Text(_loading
            ? 'در حال خواندن تنظیمات...'
            : '$count از ۵ سرویس کلید دارد؛ ${_enabled ? 'مشاوره فعال' : 'مشاوره خاموش'}'),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              'این سرویس‌ها صفحه چت جداگانه ندارند. فقط King AI آن‌ها را پشت‌صحنه و برای گرفتن نظر تخصصی، بازبینی پاسخ، کمک برنامه‌نویسی و طراحی کارهای چندرسانه‌ای فراخوانی می‌کند؛ پاسخ نهایی را خود King AI می‌سازد.',
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            onChanged: _loading || _saving ? null : _setEnabled,
            title: const Text('اجازه مشاوره داخلی King AI با همکاران ابری'),
            subtitle: const Text('خاموش باشد، فقط مدل محلی استفاده می‌شود.'),
          ),
          _keyField('کلید Gemini', _gemini, KingAiProvider.gemini,
              hint: 'Google AI Studio → Get API key'),
          _keyField('کلید Groq', _groq, KingAiProvider.groq,
              hint: 'Groq Console → API Keys'),
          _keyField('کلید Mistral', _mistral, KingAiProvider.mistral,
              hint: 'Mistral La Plateforme → API keys'),
          _keyField('کلید OpenRouter', _openRouter, KingAiProvider.openRouter,
              hint: 'OpenRouter → Keys؛ مسیر رایگان'),
          _keyField('توکن Cloudflare Workers AI', _cloudflareToken,
              KingAiProvider.cloudflare),
          TextField(
            controller: _cloudflareAccount,
            decoration: InputDecoration(
              labelText: 'Cloudflare Account ID',
              hintText: _configured[KingAiProvider.cloudflare] == true
                  ? 'شناسه حساب ذخیره شده؛ برای جایگزینی وارد کن'
                  : 'شناسه ۳۲ رقمی حساب',
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _loading || _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('ذخیره امن کلیدها'),
              ),
              OutlinedButton.icon(
                onPressed: _loading || _saving ? null : _clearAll,
                icon: const Icon(Icons.delete_outline),
                label: const Text('حذف همه کلیدها'),
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: Text(_message!)),
          ],
          const SizedBox(height: 8),
          const Text(
            'کلیدها در Android Secure Storage نگهداری می‌شوند. هیچ کلیدی را در چت، سورس، APK یا GitHub قرار نده. هر سرویس فقط وقتی کلید معتبر و سهمیه رایگان داشته باشد استفاده می‌شود؛ سرویس‌های ابری ممکن است متن یا کدِ خلاصه‌شده همان وظیفه را دریافت کنند.',
          ),
        ],
      ),
    );
  }
}
