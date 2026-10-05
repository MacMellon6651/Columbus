import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;
  bool _enabled = true;

  bool get enabled => _enabled;
  set enabled(bool value) => _enabled = value;

  Future<void> initialize() async {
    if (_isInitialized) return;

    await _tts.setLanguage('ru-RU');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);

    _isInitialized = true;
  }

  Future<void> speak(String text) async {
    if (!_enabled) return;
    if (!_isInitialized) await initialize();
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}