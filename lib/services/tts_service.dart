import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'wake_word_service.dart';

class TtsService {
  static final TtsService instance = TtsService._();
  TtsService._();

  final FlutterTts _tts = FlutterTts();
  Future<void>? _initFuture;

  /// TTS'ni bir marta ishga tushiradi. Bir vaqtda bir nechta ekran
  /// chaqirsa ham faqat bitta ulanish yaratiladi.
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _tts.setEngine('com.google.android.tts');
      }
      final ok = await _tts.setLanguage('uz-UZ');
      if (ok != true) {
        await _tts.setLanguage('uz');
      }
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
    } catch (_) {
      // Xato tushsa ham jarayon davom etadi; takror urinish qilinmaydi.
    }
  }

  /// Ovoz bilan o'qish.
  ///
  /// [awaitCompletion] `true` bo'lsa, `speak` faqat nutq to'liq aytilgandan
  /// so'ng qaytadi (jonli suhbat davrasi uchun). `false` bo'lsa, darhol
  /// qaytadi (odatdagi suhbat uchun).
  ///
  /// Nutq paytida "Hey Jarvis" fon eshitishi pauza qilinadi — aks holda
  /// ilovaning o'z ovozi ("Jarvis" so'zi) uni xato ishga tushirib qo'yadi.
  Future<void> speak(String text, {bool awaitCompletion = false}) async {
    await init();
    final wake = WakeWordService.instance;
    await wake.pause();
    try {
      await _tts.stop();
      await _tts.awaitSpeakCompletion(awaitCompletion);
      await _tts.speak(text);
      if (!awaitCompletion) {
        // Taxminiy davomiylik; shu vaqtda fon eshitish o'chib turadi.
        await Future.delayed(Duration(milliseconds: 400 + text.length * 45));
      }
    } catch (_) {}
    await wake.resume();
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
