import 'dart:async';
import 'dart:developer';
import 'dart:math' hide log;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/reminder.dart';
import '../services/gemini_service.dart';
import '../services/notification_service.dart';
import '../services/parser_service.dart';
import '../services/reminders_store.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import 'live_chat_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _parser = ParserService();

  final List<_ChatBubbleData> _messages = [];
  bool _loading = true;
  bool _thinking = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await TtsService.instance.init();
    if (!RemindersStore.instance.loaded) {
      await RemindersStore.instance.load();
    }
    GeminiService.instance
        .setRemindersProvider(() => _reminderSummaries());
    if (mounted) setState(() => _loading = false);
  }

  List<String> _reminderSummaries() {
    final active = RemindersStore.instance.reminders
        .where((r) => !r.done)
        .toList()
      ..sort((a, b) => a.when.compareTo(b.when));
    return active
        .map((r) =>
            '${r.task} — ${DateFormat('d MMMM, HH:mm', 'uz_UZ').format(r.when)}')
        .toList();
  }

  // ---------------- Actions ----------------

  Future<void> _openLiveChat() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LiveConversationScreen(
          onMessage: (role, text) {
            if (!mounted) return;
            setState(() {
              _messages.add(_ChatBubbleData(role: role, text: text));
            });
            _scrollToBottom();
          },
        ),
      ),
    );
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _textController.clear();

    setState(() {
      _messages.add(_ChatBubbleData(role: 'user', text: trimmed));
      _thinking = true;
    });
    _scrollToBottom();

    try {
      log('Chat: sendMessage boshladi');
      final reply = await GeminiService.instance.sendMessage(trimmed);
      log('Chat: sendMessage tugadi, action=${reply.action}');
      if (!mounted) return;

      if (reply.isReminder) {
        String text;
        if (reply.sentence != null && reply.sentence!.isNotEmpty) {
          final created = await _createReminder(reply.sentence!);
          text = created ? reply.reply : 'Eslatmani yarata olmadim.';
        } else {
          text = 'Eslatma uchun vaqt yozilmagan.';
        }
        if (!mounted) return;
        setState(() {
          _messages.add(_ChatBubbleData(role: 'assistant', text: text));
          _thinking = false;
        });
      } else {
        setState(() {
          _messages.add(_ChatBubbleData(role: 'assistant', text: reply.reply));
          _thinking = false;
        });
      }
      _scrollToBottom();
      await TtsService.instance.speak(reply.reply);
    } catch (e) {
      if (!mounted) return;
      log('Chat: Xatolik -> $e');
      setState(() {
        _thinking = false;
        _messages.add(_ChatBubbleData(
          role: 'system',
          text: 'Xatolik yuz berdi. Internetni tekshirib, qaytadan urinib ko\'ring.',
        ));
      });
      _scrollToBottom();
    }
  }

  Future<bool> _createReminder(String sentence) async {
    try {
      final parsed = _parser.parse(sentence);
      final reminder = Reminder(
        id: '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(99999)}',
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('AI suhbat'),
            Text(
              'Gemini bilan suhbat',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Yangi suhbat',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () {
              GeminiService.instance.reset();
              setState(() => _messages.clear());
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessages()),
          _buildComposer(context),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_messages.isEmpty && !_thinking) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.record_voice_over,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            const Text('Mikrofon tugmasini bosing va gapiring'),
            const SizedBox(height: 4),
            Text(
              'Masalan: "ertaga soat 9 da ishga boraman" yoki '
              '"bugun ob-havo qanday?"',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _messages.length + (_thinking ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i >= _messages.length) {
          return const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('O\'ylayapman...'),
                ],
              ),
            ),
          );
        }
        return _buildBubble(_messages[i]);
      },
    );
  }

  Widget _buildBubble(_ChatBubbleData msg) {
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isUser ? Colors.white : AppColors.textPrimary,
              ),
            ),
            if (!isUser) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => TtsService.instance.speak(msg.text),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.volume_up_outlined,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildComposer(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [AppShadows.card],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: const InputDecoration(
                hintText: 'Xabar yozing...',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              onSubmitted: (_) => _send(_textController.text),
            ),
          ),
          const SizedBox(width: 4),
          Material(
            color: AppColors.mint,
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Tirik suhbat',
              icon: const Icon(Icons.mic, color: AppColors.primary),
              onPressed: _openLiveChat,
            ),
          ),
          const SizedBox(width: 4),
          Material(
            color: AppColors.primary,
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Yuborish',
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: () => _send(_textController.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// Suhbat xabari.
class _ChatBubbleData {
  final String role; // user | assistant | system
  final String text;

  _ChatBubbleData({required this.role, required this.text});
}
