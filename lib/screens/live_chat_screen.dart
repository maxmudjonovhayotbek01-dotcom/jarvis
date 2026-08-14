import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/reminder.dart';
import '../services/gemini_service.dart';
import '../services/notification_service.dart';
import '../services/parser_service.dart';
import '../services/reminders_store.dart';
import '../services/speech_service.dart';
import '../services/tts_service.dart';
import '../services/wake_word_service.dart';
import '../theme/app_theme.dart';

/// Jarvis bilan jonli ovozli suhbat.
///
/// Davra: eshitish -> Gemini -> ovozli javob -> yana eshitish.
/// Foydalanuvchi "To'xtatish" tugmasini bosguncha davom etadi.
class LiveConversationScreen extends StatefulWidget {
  /// Har bir xabar qo'shilganda chaqiriladi (chat tarixi uchun).
  final void Function(String role, String text) onMessage;

  const LiveConversationScreen({super.key, required this.onMessage});

  @override
  State<LiveConversationScreen> createState() => _LiveConversationScreenState();
}

enum _LiveStatus { idle, listening, thinking, speaking }

class _LiveConversationScreenState extends State<LiveConversationScreen>
    with SingleTickerProviderStateMixin {
  final _parser = ParserService();
  final _scrollController = ScrollController();

  late final AnimationController _orb;
  final List<_Msg> _messages = [];

  bool _active = false;
  bool _popped = false;
  _LiveStatus _status = _LiveStatus.idle;
  String _liveText = '';

  @override
  void initState() {
    super.initState();
    // Suhbat davomida fon "Hey Jarvis" eshituvchi mikrofon bilan to'qnashmasin.
    WakeWordService.instance.pause();
    _orb = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _start();
  }

  @override
  void dispose() {
    _active = false;
    _orb.dispose();
    _scrollController.dispose();
    SpeechService.instance.cancel();
    TtsService.instance.stop();
    WakeWordService.instance.resume();
    super.dispose();
  }

  Future<void> _start() async {
    await TtsService.instance.init();
    if (!mounted) return;
    if (!GeminiService.instance.hasApiKey) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Avval API kalitni kiriting')),
        );
      }
      _stop();
      return;
    }
    _active = true;
    _addMessage('system', 'Jarvis bilan ovozli suhbat boshlandi. Gapiring.');
    _runLoop();
  }

  Future<void> _runLoop() async {
    var empties = 0;
    while (mounted && _active) {
      setState(() => _status = _LiveStatus.listening);
      final text = await _captureSpeech();
      if (!mounted || !_active) break;
      if (text == null || text.isEmpty) {
        empties++;
        if (empties >= 2) break;
        continue;
      }
      empties = 0;
      _addMessage('user', text);

      setState(() => _status = _LiveStatus.thinking);
      try {
        final reply = await GeminiService.instance.sendMessage(text);
        if (!mounted || !_active) break;

        String answer;
        if (reply.isReminder) {
          if (reply.sentence != null && reply.sentence!.isNotEmpty) {
            final created = await _createReminder(reply.sentence!);
            answer = created ? reply.reply : 'Eslatmani yarata olmadim.';
          } else {
            answer = 'Eslatma uchun vaqt yozilmagan.';
          }
        } else {
          answer = reply.reply;
        }

        if (!mounted || !_active) break;
        _addMessage('assistant', answer);
        setState(() => _status = _LiveStatus.speaking);

        // Nutq to'liq aytilishini kutamiz; xavfsizlik uchun chegaraviy taymer.
        final safety =
            Duration(milliseconds: math.max(15000, answer.length * 60));
        await Future.any([
          TtsService.instance.speak(answer, awaitCompletion: true),
          Future.delayed(safety),
        ]);
      } catch (e) {
        log('Live: Gemini xatolik -> $e');
        if (!mounted || !_active) break;
        _addMessage('system', 'Xatolik yuz berdi. Qayta urinyapman.');
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    _stop();
  }

  /// Bir marta eshitib, yakuniy matnni qaytaradi.
  Future<String?> _captureSpeech() async {
    final completer = Completer<String?>();
    String last = '';

    void onStatus(String s) {
      if (s == 'done' || s == 'notListening') {
        if (!completer.isCompleted) {
          completer.complete(last.trim().isEmpty ? null : last.trim());
        }
      }
    }

    void onError(String? msg) {
      if (!completer.isCompleted) completer.complete(null);
    }

    SpeechService.instance
      ..setErrorHandler(onError)
      ..setStatusHandler(onStatus);

    final ok = await SpeechService.instance.listen(
      onResult: (text, isFinal) {
        if (isFinal && text.trim().isNotEmpty) last = text.trim();
        if (mounted) setState(() => _liveText = text);
      },
    );
    if (!ok) return null;
    return completer.future;
  }

  Future<bool> _createReminder(String sentence) async {
    try {
      final parsed = _parser.parse(sentence);
      final reminder = Reminder(
        id: '${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(99999)}',
        task: parsed.task,
        place: parsed.place,
        when: parsed.when,
        createdAt: DateTime.now(),
        sourceText: sentence,
      );
      await RemindersStore.instance.add(reminder);
      await NotificationService.instance.schedule(reminder);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _addMessage(String role, String text) {
    if (!mounted) return;
    setState(() {
      _messages.add(_Msg(role: role, text: text));
    });
    widget.onMessage(role, text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _stop() async {
    if (_popped) return;
    _active = false;
    _popped = true;
    await SpeechService.instance.cancel();
    await TtsService.instance.stop();
    if (mounted) Navigator.of(context).pop();
  }

  String _statusLabel() {
    switch (_status) {
      case _LiveStatus.listening:
        return 'Eshityapman... gapiring';
      case _LiveStatus.thinking:
        return 'O\'ylayapman...';
      case _LiveStatus.speaking:
        return 'Jarvis gapirmoqda...';
      case _LiveStatus.idle:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jarvis bilan suhbat'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Yopish',
            icon: const Icon(Icons.close),
            onPressed: _stop,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            _LiveOrb(animation: _orb),
            const SizedBox(height: 16),
            Text(
              _statusLabel(),
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: AppColors.primary),
            ),
            const SizedBox(height: 6),
            Text(
              _liveText,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _messages.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _messages.length,
                      itemBuilder: (ctx, i) => _bubble(_messages[i]),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _stop,
                  icon: const Icon(Icons.stop, size: 26),
                  label: const Text('To\'xtatish'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                    minimumSize: const Size.fromHeight(56),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(_Msg msg) {
    final theme = Theme.of(context);
    final isUser = msg.role == 'user';
    final isSystem = msg.role == 'system';

    if (isSystem) {
      return Align(
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.mint,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            msg.text,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontStyle: FontStyle.italic),
          ),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          boxShadow: isUser ? null : const [AppShadows.card],
        ),
        child: Text(
          msg.text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isUser ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _Msg {
  final String role; // user | assistant | system
  final String text;

  _Msg({required this.role, required this.text});
}

class _LiveOrb extends StatelessWidget {
  final Animation<double> animation;

  const _LiveOrb({required this.animation});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 150,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = Curves.easeOut.transform(animation.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              for (final d in [0.0, 0.4, 0.7])
                Transform.scale(
                  scale: 1 + ((t + d) % 1.0) * 0.9,
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary
                          .withValues(alpha: 0.28 * (1 - ((t + d) % 1.0))),
                    ),
                  ),
                ),
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                  boxShadow: [AppShadows.fab],
                ),
                child: const Icon(Icons.mic, size: 40, color: Colors.white),
              ),
            ],
          );
        },
      ),
    );
  }
}
