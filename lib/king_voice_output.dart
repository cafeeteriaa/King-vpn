import 'package:flutter_tts/flutter_tts.dart';

/// Uses the Android-installed TTS engine. Persian speech works offline when
/// the device has a Persian voice installed; text remains visible on failure.
class KingVoiceOutput {
  KingVoiceOutput._();

  static final KingVoiceOutput instance = KingVoiceOutput._();
  final FlutterTts _tts = FlutterTts();
  bool _configured = false;
  bool _speaking = false;

  Future<void> speakPersian(String value) async {
    final text = value.trim();
    if (text.isEmpty) return;
    final bounded = text.length > 900 ? text.substring(0, 900) : text;
    if (_speaking) await stop();
    if (!_configured) {
      await _tts.setLanguage('fa-IR');
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
      _configured = true;
    }
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
