import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'king_ai_console.dart';
import 'king_local_ai.dart';
import 'king_ai_provider_pilot.dart';
import 'king_voice_output.dart';

class KingChatPage extends StatefulWidget {
  const KingChatPage({super.key});
  @override
  State<KingChatPage> createState() => _KingChatPageState();
}

class _KingChatPageState extends State<KingChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _speech = stt.SpeechToText();
  final _geminiKeyController = TextEditingController();
  final _groqKeyController = TextEditingController();
  final _mistralKeyController = TextEditingController();
  final _openRouterKeyController = TextEditingController();
  final _cloudflareTokenController = TextEditingController();
  final _cloudflareAccountController = TextEditingController();
  bool _cloudEnabled = false;
  Map<KingAiProvider, bool> _providerConfigured = <KingAiProvider, bool>{};
  final List<Map<String, Object>> _messages = [
    {'text': 'سلام! من کینگ هستم. هر موضوعی دوست داری مطرح کن؛ می‌توانیم گفت‌وگو کنیم، سؤال حل کنیم یا چیزی یاد بگیریم.', 'king': true},
  ];
  bool _busy = false, _listening = false, _speechReady = false, _speak = true;
  bool _voiceTurn = false, _voiceSubmitted = false;
  bool _onDeviceSpeechAttempt = false, _onlineSpeechFallbackAttempted = false;
  bool _onlineSpeechConsentGranted = false;
  String? _notice, _locale;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProviderSettings());
  }

  @override
  void dispose() {
    _input.dispose();
    _geminiKeyController.dispose();
    _groqKeyController.dispose();
    _mistralKeyController.dispose();
    _openRouterKeyController.dispose();
    _cloudflareTokenController.dispose();
    _cloudflareAccountController.dispose();
    _scroll.dispose();
    unawaited(_speech.cancel());
    unawaited(KingVoiceOutput.instance.stop());
    super.dispose();
  }

  void _add(String text, bool king) {
    if (!mounted) return;
    setState(() => _messages.add({'text': text, 'king': king}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    });
  }

  Future<void> _send() async {
    // Speech callbacks may arrive after the page has been disposed.
    if (!mounted) return;
    final prompt = _input.text.trim();
    if (prompt.isEmpty || _busy) return;
    _input.clear();
    final voice = _voiceTurn;
    _voiceTurn = false;
    _add(prompt, false);
    setState(() { _busy = true; _notice = null; });
    try {
      final answer = await KingAiProviderPilot.instance.ask(
        prompt,
        localFallback: () => KingLocalAi.instance.ask(prompt, maxTokens: 1400),
      );
      if (!mounted) return;
      _add(answer, true);
      if (mounted) {
        setState(() => _notice = 'پاسخ از ${KingAiProviderPilot.instance.lastUsedProvider} دریافت شد.');
      }
      // Do not start late audio if the chat page closed during local inference.
      if (mounted && (_speak || voice)) {
        try {
          await KingVoiceOutput.instance.speakPersian(answer);
          if (!KingVoiceOutput.instance.femaleVoiceSelected && mounted) {
            setState(() => _notice = 'پاسخ صوتی پخش شد؛ گوشی صدای فارسی زنانه را ارائه نکرد، بنابراین صدای پیش‌فرض فارسی استفاده شد.');
          }
        } catch (error) {
          if (mounted) setState(() => _notice = 'پاسخ متنی آماده شد، اما موتور گفتار گوشی در دسترس نیست: $error');
        }
      }
    } catch (error) {
      final raw = error.toString();
      _add(raw.contains('مدل هوش مصنوعی داخلی هنوز آماده نیست')
          ? 'مدل محلی هنوز بارگذاری نشده است. «آماده‌سازی مغز کینگ» را بزن و مدل را دانلود و بارگذاری کن.'
          : 'فعلاً نتوانستم پاسخ را تولید کنم: ${raw.replaceFirst('Exception: ', '')}', true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _handleSpeechResult(dynamic result) {
    if (!mounted) return;
    final value = result.recognizedWords.trim();
    if (value.isEmpty) return;
    if (result.finalResult) _onDeviceSpeechAttempt = false;
    setState(() {
      _input.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
      _notice = result.finalResult
          ? 'گفتار تشخیص داده شد؛ کینگ در حال پاسخ‌گویی است.'
          : 'در حال تشخیص گفتار...';
    });
    if (result.finalResult && !_voiceSubmitted) {
      _voiceSubmitted = true;
      unawaited(Future<void>.delayed(
        const Duration(milliseconds: 250),
        () {
          if (mounted) unawaited(_send());
        },
      ));
    }
  }

  Future<void> _startChatSpeech({required bool onDevice}) async {
    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(
        localeId: _locale ?? 'fa-IR',
        listenFor: const Duration(seconds: 45),
        pauseFor: const Duration(seconds: 5),
        onDevice: onDevice,
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
      ),
      onResult: _handleSpeechResult,
    );
    if (mounted) setState(() => _listening = _speech.isListening);
  }

  Future<void> _requestChatSpeechOnlineFallback() async {
    if (!_onlineSpeechConsentGranted) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('اجازه تشخیص گفتار آنلاین؟'),
            content: const Text('تشخیص آفلاین روی دستگاه در دسترس نبود. برای ادامه آنلاین ممکن است صدای تو به سرویس گفتار Android یا ارائه‌دهنده آن ارسال شود. فقط در صورت موافقت، ادامه می‌دهم.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('خیر، فقط آفلاین'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('اجازه می‌دهم'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || accepted != true) {
        _voiceTurn = false;
        if (mounted) setState(() => _notice =
            'تشخیص گفتار آنلاین مجاز نشد؛ هیچ صدایی به سرویس آنلاین ارسال نمی‌شود.');
        return;
      }
      _onlineSpeechConsentGranted = true;
    }
    await _startChatSpeechOnlineFallback();
  }

  Future<void> _startChatSpeechOnlineFallback() async {
    try {
      await _speech.stop();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      await _startChatSpeech(onDevice: false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _listening = false;
          _voiceTurn = false;
          _notice = 'تشخیص گفتار آفلاین و آنلاین در دسترس نیست: $error';
        });
      }
    }
  }

  Future<void> _listen() async {
    if (_busy) return;
    if (_listening || _speech.isListening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final permission = await Permission.microphone.request();
    if (!mounted) return;
    if (!permission.isGranted) {
      if (mounted) setState(() => _notice = 'برای گفت‌وگوی صوتی اجازه میکروفون لازم است.');
      return;
    }
    try {
      if (!_speechReady) {
        _speechReady = await _speech.initialize(
          onStatus: (_) {
            if (mounted) setState(() => _listening = _speech.isListening);
          },
          onError: (error) {
            if (!mounted) return;
            setState(() => _listening = false);
            if (_onDeviceSpeechAttempt && !_onlineSpeechFallbackAttempted) {
              _onDeviceSpeechAttempt = false;
              _onlineSpeechFallbackAttempted = true;
              setState(() => _notice =
                  'تشخیص گفتار آفلاین در دسترس نبود؛ اکنون با اطلاع تو سرویس آنلاین گفتار را امتحان می‌کنم. ممکن است صوت به سرویس گفتار دستگاه ارسال شود.');
              unawaited(_requestChatSpeechOnlineFallback());
              return;
            }
            if (_onlineSpeechFallbackAttempted) _voiceTurn = false;
            setState(() => _notice = 'تشخیص گفتار: ${error.errorMsg}');
          },
        );
        if (!mounted) return;
      }
      if (!_speechReady) {
        setState(() => _notice =
            'سرویس تشخیص گفتار گوشی فعال نیست؛ موتور گفتار را در تنظیمات Android فعال کن.');
        return;
      }
      final locales = await _speech.locales();
      if (!mounted) return;
      final fa = locales.where((e) =>
          e.localeId.toLowerCase().replaceAll('_', '-').startsWith('fa'));
      _locale = fa.isNotEmpty ? fa.first.localeId : 'fa-IR';
      _voiceTurn = true;
      _voiceSubmitted = false;
      _onlineSpeechFallbackAttempted = false;
      _onDeviceSpeechAttempt = true;
      setState(() => _notice = fa.isEmpty
          ? 'بسته فارسی آفلاین پیدا نشد؛ ابتدا fa-IR را روی خود دستگاه امتحان می‌کنم. در صورت شکست، قبل از استفاده آنلاین پیام می‌دهم.'
          : 'ابتدا تشخیص گفتار فارسی روی خود دستگاه (آفلاین) فعال می‌شود.');
      await _startChatSpeech(onDevice: true);
    } catch (error) {
      if (!mounted) return;
      if (_onDeviceSpeechAttempt && !_onlineSpeechFallbackAttempted) {
        _onDeviceSpeechAttempt = false;
        _onlineSpeechFallbackAttempted = true;
        if (mounted) setState(() => _notice =
            'شروع تشخیص آفلاین ممکن نشد؛ با اطلاع تو سرویس آنلاین گفتار را امتحان می‌کنم.');
        await _requestChatSpeechOnlineFallback();
      } else if (mounted) {
        setState(() {
          _listening = false;
          _notice = 'شروع تشخیص گفتار ناموفق بود: $error';
        });
      }
    }
  }

  Future<void> _loadProviderSettings() async {
    try {
      final pilot = KingAiProviderPilot.instance;
      final enabled = await pilot.cloudEnabled;
      final configured = await pilot.configuredProviders();
      if (!mounted) return;
      setState(() {
        _cloudEnabled = enabled;
        _providerConfigured = configured;
      });
    } catch (error) {
      if (mounted) setState(() => _notice = 'بارگذاری تنظیمات هوش مصنوعی ناموفق بود: $error');
    }
  }

  Future<void> _saveProviderSettings() async {
    final pilot = KingAiProviderPilot.instance;
    try {
      final entries = <KingAiProvider, String>{
        KingAiProvider.gemini: _geminiKeyController.text,
        KingAiProvider.groq: _groqKeyController.text,
        KingAiProvider.mistral: _mistralKeyController.text,
        KingAiProvider.openRouter: _openRouterKeyController.text,
        KingAiProvider.cloudflare: _cloudflareTokenController.text,
      };
      for (final entry in entries.entries) {
        if (entry.value.trim().isNotEmpty) {
          await pilot.saveKey(entry.key, entry.value);
        }
      }
      if (_cloudflareAccountController.text.trim().isNotEmpty) {
        await pilot.saveCloudflareAccountId(_cloudflareAccountController.text);
      }
      await pilot.setCloudEnabled(_cloudEnabled);
      for (final controller in [
        _geminiKeyController,
        _groqKeyController,
        _mistralKeyController,
        _openRouterKeyController,
        _cloudflareTokenController,
        _cloudflareAccountController,
      ]) {
        controller.clear();
      }
      await _loadProviderSettings();
      if (mounted) {
        setState(() => _notice =
            'کلیدها در حافظه امن Android ذخیره شدند. وضعیت اتصال ابری: '
            '${_cloudEnabled ? 'فعال' : 'خاموش'}؛ برای اعمال، پیام بعدی را بفرست.');
      }
    } catch (error) {
      if (mounted) setState(() => _notice = 'ذخیره تنظیمات انجام نشد: $error');
    }
  }

  Future<void> _setCloudEnabled(bool value) async {
    setState(() => _cloudEnabled = value);
    try {
      await KingAiProviderPilot.instance.setCloudEnabled(value);
      if (mounted) {
        setState(() => _notice = value
            ? 'هوش ابری فعال شد؛ متن پیام‌های بعدی ممکن است به ارائه‌دهنده‌های انتخاب‌شده ارسال شود.'
            : 'هوش ابری خاموش شد؛ پاسخ‌گویی فقط از مسیر مدل محلی انجام می‌شود.');
      }
    } catch (error) {
      if (mounted) setState(() => _notice = 'تغییر وضعیت هوش ابری ناموفق بود: $error');
    }
  }

  Future<void> _clearProviderKeys() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف کلیدهای هوش مصنوعی؟'),
          content: const Text('همه کلیدهای Gemini، Groq، Mistral، OpenRouter و Cloudflare از حافظه امن گوشی پاک می‌شوند و هوش ابری خاموش خواهد شد.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف کلیدها')),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      for (final provider in KingAiProvider.values) {
        await KingAiProviderPilot.instance.clearKey(provider);
      }
      await KingAiProviderPilot.instance.setCloudEnabled(false);
      await _loadProviderSettings();
      if (mounted) setState(() {
        _cloudEnabled = false;
        _notice = 'همه کلیدهای ارائه‌دهندگان از حافظه امن حذف شدند.';
      });
    } catch (error) {
      if (mounted) setState(() => _notice = 'حذف کلیدها ناموفق بود: $error');
    }
  }

  Widget _providerKeyField({
    required String label,
    required TextEditingController controller,
    required bool configured,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: label,
          hintText: configured ? 'کلید ذخیره شده؛ برای جایگزینی کلید جدید وارد کن' : (hint ?? 'کلید API را وارد کن'),
          suffixIcon: Icon(
            configured ? Icons.verified_user_outlined : Icons.key_outlined,
            color: configured ? Colors.green : null,
          ),
        ),
      ),
    );
  }

  Widget _buildProjectGuide(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      child: ExpansionTile(
        leading: const Icon(Icons.menu_book_outlined),
        title: const Text('راهنمای کامل King VPN و King AI'),
        subtitle: const Text('معرفی اجزای پروژه، خلبان‌ها و محل واردکردن کلیدهای API'),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .48,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('۱) King VPN چیست؟', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('King VPN یک برنامه اندرویدی Flutter/Dart است. مسیر VPN موجود بر پایه هسته Xray/V2Ray نگهداری می‌شود. هدف اصلی، اتصال پایدار به اینترنت داخلی و جهانی، پشتیبانی IPv4 و IPv6، مدیریت DNS و مسیریابی، تشخیص خرابی مسیر و بازیابی امن اتصال است.'),
                  const SizedBox(height: 10),
                  const Text('۲) خلبان هوشمند شبکه (VPN Smart Pilot)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('این خلبان مستقل از سرویس‌های ابری کار می‌کند. شواهد شبکه داخلی و جهانی را جداگانه می‌سنجد، از نمونه‌های متعدد و بررسی TLS استفاده می‌کند و در صورت ناقص یا متناقض بودن شواهد، بی‌دلیل مسیر فعال را عوض نمی‌کند. تصمیم‌های اتصال، انتخاب مسیر، failover و سلامت تونل نباید به Gemini یا هیچ API خارجی وابسته شوند.'),
                  const SizedBox(height: 10),
                  const Text('۳) مغز محلی King AI', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('مدل محلی Qwen روی خود گوشی اجرا می‌شود و مسیر پایه برای گفت‌وگو و کار آفلاین است. حافظه گفت‌وگو در فضای امن دستگاه نگهداری می‌شود. اگر اینترنت یا APIها قطع شوند، قابلیت‌های محلیِ آماده همچنان قابل استفاده‌اند.'),
                  const SizedBox(height: 10),
                  const Text('۴) خلبان هوش مصنوعی ارائه‌دهندگان', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('این خلبان جدا از VPN Smart Pilot است. بر اساس نوع درخواست، ابتدا ارائه‌دهنده مناسب را امتحان می‌کند؛ اگر سهمیه تمام شده باشد یا سرویس پاسخ ندهد، به ارائه‌دهنده بعدی و در نهایت مدل محلی برمی‌گردد. فقط کلیدهایی استفاده می‌شوند که خودت وارد کرده‌ای و گزینه هوش ابری را روشن کرده‌ای.'),
                  const SizedBox(height: 10),
                  const Text('۵) کلیدهای API را دقیقاً کجا وارد کنم؟', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('همین راهنما زیر کادر نوشتن پیام قرار دارد. این بخش را باز کن، کلید هر سرویس را در کادر همان سرویس بچسبان، در صورت استفاده از Cloudflare شناسه حساب را هم وارد کن، سپس «ذخیره امن کلیدها» را بزن. کلیدها در Android Secure Storage ذخیره می‌شوند و پس از ذخیره، کادرها خالی می‌شوند. هیچ کلیدی را داخل چت، فایل Dart، APK یا GitHub قرار نده.'),
                  const SizedBox(height: 10),
                  const Text('راهنمای دریافت کلیدها', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('• Gemini: از Google AI Studio بخش Get API key.\n• Groq: از Groq Console بخش API Keys.\n• Mistral: از Mistral La Plateforme بخش API keys.\n• OpenRouter: از صفحه Keys در OpenRouter؛ فقط مدل‌هایی که شناسه آن‌ها به :free ختم می‌شود یا مسیر رایگان رسمی را انتخاب کن.\n• Cloudflare: از داشبورد Cloudflare یک API Token با مجوز لازم Workers AI بساز و Account ID را از صفحه حساب بردار.'),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _cloudEnabled,
                    onChanged: _setCloudEnabled,
                    title: const Text('اجازه استفاده از ارائه‌دهندگان ابری رایگان'),
                    subtitle: const Text('با روشن‌کردن این گزینه، متن درخواست‌ها برای سرویس‌های دارای کلید ارسال می‌شود.'),
                  ),
                  _providerKeyField(
                    label: 'کلید Gemini',
                    controller: _geminiKeyController,
                    configured: _providerConfigured[KingAiProvider.gemini] == true,
                    hint: 'کلید Google AI Studio',
                  ),
                  _providerKeyField(
                    label: 'کلید Groq',
                    controller: _groqKeyController,
                    configured: _providerConfigured[KingAiProvider.groq] == true,
                  ),
                  _providerKeyField(
                    label: 'کلید Mistral',
                    controller: _mistralKeyController,
                    configured: _providerConfigured[KingAiProvider.mistral] == true,
                  ),
                  _providerKeyField(
                    label: 'کلید OpenRouter',
                    controller: _openRouterKeyController,
                    configured: _providerConfigured[KingAiProvider.openRouter] == true,
                  ),
                  _providerKeyField(
                    label: 'توکن Cloudflare Workers AI',
                    controller: _cloudflareTokenController,
                    configured: _providerConfigured[KingAiProvider.cloudflare] == true,
                  ),
                  _providerKeyField(
                    label: 'Cloudflare Account ID',
                    controller: _cloudflareAccountController,
                    configured: _providerConfigured[KingAiProvider.cloudflare] == true,
                    hint: 'شناسه ۳۲ رقمی حساب Cloudflare',
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : _saveProviderSettings,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('ذخیره امن کلیدها'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _clearProviderKeys,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('حذف همه کلیدها'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('۶) محدودیت رایگان و حریم خصوصی', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('رایگان‌بودن به معنی نامحدودبودن نیست؛ هر سرویس سقف درخواست، توکن یا سهمیه روزانه دارد و ممکن است شرایطش را تغییر دهد. در نسخه فعلی این اتصال، APIها برای گفت‌وگوی متنی استفاده می‌شوند؛ تولید و ویرایش تصویر یا ویدئو خودکار از این کلیدها تضمین نمی‌شود و بعضی مدل‌های تولید تصویر/ویدئو پولی هستند. Gemini Free Tier ممکن است محتوای ارسالی را برای بهبود سرویس‌های Google استفاده کند؛ اطلاعات محرمانه، رمزها، کلیدها و کانفیگ‌های خصوصی VPN را برای مدل ابری نفرست.'),
                  const SizedBox(height: 10),
                  const Text('۷) توسعه‌دهنده و امنیت پروژه', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('تغییر سورس King VPN فقط از مسیر توسعه‌دهنده و پس از احراز هویت مالک مجاز است. خلبان ارائه‌دهندگان فقط پاسخ تولید می‌کند و دسترسی نوشتن به GitHub، فایل‌های پروژه یا تنظیمات VPN ندارد. پیشنهادهای کد باید از مسیر مالک، شاخه مستقل، تست، تحلیل ایستا و Pull Request قابل بازبینی عبور کنند؛ ادغام خودکار در main مجاز نیست.'),
                  const SizedBox(height: 10),
                  Text('وضعیت ذخیره کلیدها: ${_providerConfigured.values.where((value) => value).length} ارائه‌دهنده از ۵ ارائه‌دهنده کلید کامل دارد. گزینه هوش ابری ${_cloudEnabled ? 'روشن' : 'خاموش'} است.',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearMemory() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('پاک‌کردن حافظه گفت‌وگو؟'),
          content: const Text('خاطرات مکالمه‌ای ذخیره‌شده در حافظه امن گوشی پاک می‌شود. پیام‌های همین صفحه نیز پاک خواهند شد.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('پاک کن')),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    await KingLocalAi.instance.clearConversationMemory();
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..add({'text': 'حافظه گفت‌وگوی قبلی پاک شد. از نو شروع کنیم؟', 'king': true});
      _notice = 'حافظه مکالمه از فضای امن دستگاه پاک شد.';
    });
  }

  Future<void> _openModel() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const KingAiConsolePage()));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final loaded = KingLocalAi.instance.isLoaded;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('گفت‌وگوی آزاد با کینگ'),
          actions: [
            IconButton(
              tooltip: _speak ? 'خاموش‌کردن پاسخ صوتی' : 'روشن‌کردن پاسخ صوتی',
              onPressed: () => setState(() => _speak = !_speak),
              icon: Icon(_speak ? Icons.volume_up : Icons.volume_off),
            ),
            IconButton(
              tooltip: 'پاک‌کردن حافظه گفت‌وگو',
              onPressed: _busy ? null : _clearMemory,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
        ),
        body: Column(children: [
          if (!loaded)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: ListTile(
                leading: const Icon(Icons.psychology_alt),
                title: const Text('مغز محلی کینگ آماده نیست'),
                subtitle: const Text('برای مکالمه آفلاین، مدل را یک‌بار بارگذاری کن.'),
                trailing: TextButton(onPressed: _openModel, child: const Text('آماده‌سازی')),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(14),
              itemCount: _messages.length + (_busy ? 1 : 0),
              itemBuilder: (context, index) {
                if (_busy && index == _messages.length) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 10), Text('کینگ در حال فکر کردن است...'),
                    ]),
                  );
                }
                final message = _messages[index];
                final king = message['king'] == true;
                return Align(
                  alignment: king ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .84),
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: king ? const Color(0xFF1B2B3C) : const Color(0xFF254B64),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: king ? const Color(0x5579DFFF) : const Color(0x554FC8A8)),
                    ),
                    child: SelectableText(message['text']! as String,
                        style: const TextStyle(color: Colors.white, height: 1.55)),
                  ),
                );
              },
            ),
          ),
          if (_notice != null)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Text(_notice!, style: Theme.of(context).textTheme.bodySmall)),
          SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    IconButton.filledTonal(
                      tooltip: _listening ? 'توقف ضبط' : 'صحبت کن',
                      onPressed: _busy ? null : _listen,
                      icon: Icon(_listening ? Icons.mic : Icons.mic_none,
                          color: _listening ? Colors.redAccent : null),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _input, minLines: 1, maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'هر چیزی دوست داری از کینگ بپرس...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(onPressed: _busy ? null : _send, icon: const Icon(Icons.send_rounded)),
                  ]),
                ),
                _buildProjectGuide(context),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
