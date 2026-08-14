import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  static final SpeechService instance = SpeechService._();
  SpeechService._();

  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;

  void Function(String? errorMsg)? _onError;
  void Function(String status)? _onStatus;

  /// Global error handler; called on recognition errors (e.g. no speech).
  void setErrorHandler(void Function(String? errorMsg)? handler) {
    _onError = handler;
  }

  /// Global status handler; called on status changes (e.g. done).
  void setStatusHandler(void Function(String status)? handler) {
    _onStatus = handler;
  }

  Future<bool> init() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onError: (e) => _onError?.call(e.errorMsg),
      onStatus: (s) => _onStatus?.call(s),
    );
    return _initialized;
  }

  bool get isListening => _speech.isListening;

  /// Returns true if the Uzbek locale is available for recognition.
  Future<bool> hasUzbek() async {
    await init();
    final locales = await _speech.locales();
    return locales.any((l) => l.localeId.toLowerCase().startsWith('uz'));
  }

  /// Starts listening and calls [onResult] with partial + final text.
  Future<bool> listen({
    required void Function(String text, bool isFinal) onResult,
    void Function(String? errorMsg)? onError,
  }) async {
    final ok = await init();
    if (!ok) {
      onError?.call('Ovozni tanib olish ishlamayapti');
      return false;
    }
    String? locale;
    final locales = await _speech.locales();
    for (final l in locales) {
      final id = l.localeId.toLowerCase();
      if (id == 'uz_uz' || id == 'uz-uz' || id == 'uz') {
        locale = l.localeId;
        break;
      }
    }
    // Android'ning tanib oluvchisi ba'zan yakuniy natijada so'z oxirini
    // kesadi ("salom" -> "salo"). Buni oldini olish uchun eng uzun (to'liq)
    // oraliq natijani saqlab, yakuniy natija undan qisqa bo'lsa uni ishlatamiz.
    String best = '';
    try {
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: locale,
          listenFor: const Duration(seconds: 20),
          pauseFor: const Duration(seconds: 4),
          partialResults: true,
          cancelOnError: true,
        ),
        onResult: (result) {
          final text = result.recognizedWords;
          if (text.length > best.length) best = text;
          if (result.finalResult) {
            final finalText = text.trim().isNotEmpty ? text.trim() : best.trim();
            onResult(finalText, true);
          } else {
            onResult(text, false);
          }
        },
      );
    } catch (_) {
      onError?.call('Ovozni tanib olish ishlamadi');
      return false;
    }
    return true;
  }

  Future<void> stop() async => _speech.stop();

  Future<void> cancel() async {
    if (_speech.isListening) await _speech.cancel();
  }
}
