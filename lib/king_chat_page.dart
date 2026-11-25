import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'king_ai_console.dart';
import 'king_local_ai.dart';
import 'king_voice_output.dart';
import 'king_ai_provider_orchestrator.dart';
import 'king_ai_provider_settings.dart';

class KingChatPage extends StatefulWidget {
  const KingChatPage({super.key});
  @override
  State<KingChatPage> createState() => _KingChatPageState();
}

class _KingChatPageState extends State<KingChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _speech = stt.SpeechToText();
  final _imagePicker = ImagePicker();
  XFile? _pendingImage;
  bool _useCloud = false;
  final List<Map<String, Object>> _messages = [
    {'text': 'سلام! من کینگ هستم. هر موضوعی دوست داری مطرح کن؛ می‌توانیم گفت‌وگو کنیم، سؤال حل کنیم یا چیزی یاد بگیریم.', 'king': true},
  ];
  bool _busy = false, _listening = false, _speechReady = false, _speak = true;
  bool _voiceTurn = false, _voiceSubmitted = false;
  bool _onDeviceSpeechAttempt = false, _onlineSpeechFallbackAttempted = false;
  bool _onlineSpeechConsentGranted = false;
  String? _notice, _locale;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    unawaited(_speech.cancel());
    unawaited(KingVoiceOutput.instance.stop());
    super.dispose();
  }

  void _add(String text, bool king, {String? imagePath}) {
    if (!mounted) return;
    setState(() => _messages.add({
      'text': text,
      'king': king,
      if (imagePath != null) 'imagePath': imagePath,
    }));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    });
  }

  Future<void> _pickImage() async {
    if (_busy) return;
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (!mounted || picked == null) return;
      setState(() {
        _pendingImage = picked;
        _useCloud = true;
        _notice = 'تصویر انتخاب شد؛ برای تحلیل باید به یک مدل تصویری آنلاین ارسال شود.';
      });
    } catch (error) {
      if (mounted) setState(() => _notice = 'انتخاب تصویر انجام نشد: $error');
    }
  }

  String _imageMimeType(XFile file) {
    final extension = file.path.toLowerCase().split('.').last;
    if (extension == 'png') return 'image/png';
    if (extension == 'webp') return 'image/webp';
    return 'image/jpeg';
  }

  Future<bool> _confirmCloudProcessing() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('ارسال به هوش مصنوعی آنلاین؟'),
          content: const Text(
            'برای این درخواست، متن و در صورت انتخاب تصویر، خود تصویر به ارائه‌دهنده بیرونی ارسال می‌شود. هزینه و سیاست نگهداری داده تابع همان سرویس است. فقط با اجازه تو ادامه می‌دهم.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('خیر'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('اجازه برای همین درخواست'),
            ),
          ],
        ),
      ),
    );
    return accepted == true;
  }

  Future<void> _send() async {
    // Speech callbacks may arrive after the page has been disposed.
    if (!mounted) return;
    final image = _pendingImage;
    final typedPrompt = _input.text.trim();
    if ((typedPrompt.isEmpty && image == null) || _busy) return;
    final prompt = typedPrompt.isEmpty
        ? 'این تصویر را با دقت تحلیل کن، متن‌ها و تنظیمات قابل مشاهده را استخراج کن و موارد نامشخص را حدس نزن.'
        : typedPrompt;
    final useCloud = _useCloud || image != null;
    var oneTimeConsent = false;
    if (useCloud) {
      final orchestrator = KingAiProviderOrchestrator.instance;
      if (!await orchestrator.externalProcessingEnabled) {
        if (!await _confirmCloudProcessing()) return;
        if (!mounted) return;
        oneTimeConsent = true;
      }
    }
    if (!mounted) return;
    _input.clear();
    _pendingImage = null;
    final voice = _voiceTurn;
    _voiceTurn = false;
    _add(prompt, false, imagePath: image?.path);
    setState(() { _busy = true; _notice = null; });
    try {
      final String answer;
      if (image != null) {
        answer = await KingAiProviderOrchestrator.instance.analyzeImage(
          prompt: prompt,
          imageBytes: await image.readAsBytes(),
          mimeType: _imageMimeType(image),
          explicitApproval: oneTimeConsent,
        );
      } else if (useCloud) {
        answer = await KingAiProviderOrchestrator.instance.ask(
          prompt: prompt,
          explicitApproval: oneTimeConsent,
        );
      } else {
        answer = await KingLocalAi.instance.ask(prompt, maxTokens: 1400);
      }
      if (!mounted) return;
      _add(answer, true);
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
              tooltip: _useCloud ? 'استفاده از مدل محلی' : 'استفاده از مدل آنلاین',
              onPressed: () => setState(() => _useCloud = !_useCloud),
              icon: Icon(_useCloud ? Icons.cloud_done : Icons.cloud_outlined),
            ),
            IconButton(
              tooltip: 'تنظیم هوش مصنوعی چندمدلی',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const KingAiProviderSettingsPage()),
              ),
              icon: const Icon(Icons.hub_outlined),
            ),
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (message['imagePath'] is String) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(message['imagePath']! as String),
                              fit: BoxFit.contain,
                              height: 180,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        SelectableText(message['text']! as String,
                            style: const TextStyle(color: Colors.white, height: 1.55)),
                      ],
                    ),
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                IconButton.filledTonal(
                  tooltip: 'انتخاب تصویر برای تحلیل',
                  onPressed: _busy ? null : _pickImage,
                  icon: const Icon(Icons.image_outlined),
                ),
                IconButton.filledTonal(
                  tooltip: _listening ? 'توقف ضبط' : 'صحبت کن',
                  onPressed: _busy ? null : _listen,
                  icon: Icon(_listening ? Icons.mic : Icons.mic_none,
                      color: _listening ? Colors.redAccent : null),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_pendingImage != null)
                        Row(
                          children: [
                            const Icon(Icons.image, size: 18),
                            const SizedBox(width: 6),
                            Expanded(child: Text(_pendingImage!.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: _busy ? null : () => setState(() => _pendingImage = null),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                      TextField(
                    controller: _input, minLines: 1, maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'هر چیزی دوست داری از کینگ بپرس...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(onPressed: _busy ? null : _send, icon: const Icon(Icons.send_rounded)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
