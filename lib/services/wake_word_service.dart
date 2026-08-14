import 'package:flutter/services.dart';

/// "Hey Jarvis" uyg'otuvchi so'z xizmati bilan bog'lanish.
///
/// Flutter -> Android: start/stop/pause/resume
/// Android -> Flutter: [onWakeWord] (ilova fon/yopiq holatda ham ishlaydi)
class WakeWordService {
  static final WakeWordService instance = WakeWordService._();
  WakeWordService._();

  static const _channel = MethodChannel('yordamchi/wake_word');

  /// Uyg'otuvchi so'z eshitilganda chaqiriladi.
  VoidCallback? onWakeWord;

  bool _started = false;
  int _pauseCount = 0;

  bool get isStarted => _started;

  /// Kanallarni o'rnatadi va ilova sovuq ochilganda ham
  /// "Hey Jarvis" signalini ushlaydi. runApp'dan keyin chaqiriladi.
  Future<void> init() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onWakeWord') {
        onWakeWord?.call();
      }
    });
    try {
      _started = await _channel.invokeMethod<bool>('isServiceRunning') ?? false;
      final wake = await _channel.invokeMethod<bool>('checkWakeWord') ?? false;
      if (wake) onWakeWord?.call();
    } catch (_) {
      // Native kanal hali tayyor emas — keyingi onResume tekshiradi.
    }
  }

  Future<void> start() async {
    try {
      await _channel.invokeMethod('startService');
      _started = true;
    } catch (_) {}
  }

  Future<void> stop() async {
    _started = false;
    _pauseCount = 0;
    try {
      await _channel.invokeMethod('stopService');
    } catch (_) {}
  }

  /// Eshitishni vaqtincha to'xtatadi (masalan, suhbat yoki TTS paytida).
  /// Bir nechta joy chaqirsa ham bitta [resume] bilan ochilmaydi.
  Future<void> pause() async {
    _pauseCount++;
    if (_pauseCount != 1 || !_started) return;
    try {
      await _channel.invokeMethod('pauseListening');
    } catch (_) {}
  }

  Future<void> resume() async {
    if (_pauseCount > 0) _pauseCount--;
    if (_pauseCount != 0 || !_started) return;
    try {
      await _channel.invokeMethod('resumeListening');
    } catch (_) {}
  }

  /// Batareya optimizatsiyasidan chetlashtirishni so'raydi (ekran o'chiq
  /// holatda ham ishlashi uchun).
  Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }
}
