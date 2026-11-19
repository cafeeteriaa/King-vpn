import 'package:flutter_tts/flutter_tts.dart';

/// Persian TTS using the Android-installed engine. Prefers a female Persian
/// voice when the device exposes one; it never claims a female voice was
/// selected when the engine does not provide that information.
class KingVoiceOutput {
  KingVoiceOutput._();

  static final KingVoiceOutput instance = KingVoiceOutput._();
  final FlutterTts _tts = FlutterTts();
  bool _configured = false;
  bool _speaking = false;
  bool _femaleVoiceSelected = false;

  bool get femaleVoiceSelected => _femaleVoiceSelected;
  bool get isSpeaking => _speaking;

  Future<void> _configure() async {
    if (_configured) return;
    await _tts.setLanguage('fa-IR');
    await _tts.setSpeechRate(0.46);
    await _tts.setPitch(1.08);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);

    try {
      final raw = await _tts.getVoices;
      if (raw is List) {
        final voices = raw.whereType<Map>().map((voice) =>
            Map<String, dynamic>.from(voice)).toList();
        final persian = voices.where((voice) {
          final locale = (voice['locale'] ?? voice['language'] ?? '')
              .toString().toLowerCase().replaceAll('_', '-');
          return locale.startsWith('fa');
        }).toList();
        Map<String, dynamic>? selected;
        for (final voice in persian) {
          final identity = [
            voice['gender'], voice['name'], voice['identifier'], voice['voice']
          ].whereType<Object>().join(' ').toLowerCase();
          if (identity.contains('female') ||
              identity.contains('woman') ||
              identity.contains('feminine') ||
              identity.contains('زن')) {
            selected = voice;
            break;
          }
        }
        selected ??= persian.isNotEmpty ? persian.first : null;
        if (selected != null && selected['name'] != null &&
            selected['locale'] != null) {
          await _tts.setVoice({
            'name': selected['name'].toString(),
            'locale': selected['locale'].toString(),
          });
          final identity = [
            selected['gender'], selected['name'], selected['identifier']
          ].whereType<Object>().join(' ').toLowerCase();
          _femaleVoiceSelected = identity.contains('female') ||
              identity.contains('woman') ||
              identity.contains('feminine') ||
              identity.contains('زن');
          if (_femaleVoiceSelected) await _tts.setPitch(1.12);
        }
      }
    } catch (_) {
      // Voice catalogs vary by Android TTS provider. Keep the Persian default.
    }
    _configured = true;
  }

  Future<void> speakPersian(String value) async {
    final text = value.trim();
    if (text.isEmpty) return;
    final bounded = text.length > 1400 ? text.substring(0, 1400) : text;
    if (_speaking) await stop();
    await _configure();
    _speaking = true;
    try {
      await _tts.speak(bounded);
    } finally {
      _speaking = false;
    }
  }

  Future<void> stop() async {
    _speaking = false;
    await _tts.stop();
  }
}
