import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';

/// Gemini javobining strukturasi.
///
/// [action] `create_reminder` bo'lsa, [sentence] dan eslatma yaratiladi,
/// aks holda oddiy suhbat javobi (chat).
class GeminiReply {
  final String action; // 'chat' | 'create_reminder'
  final String reply;
  final String? sentence;

  GeminiReply({
    required this.action,
    required this.reply,
    this.sentence,
  });

  bool get isReminder => action == 'create_reminder';

  factory GeminiReply.fromJson(Map<String, dynamic> json) {
    final rawAction = (json['action'] as String? ?? 'chat').trim().toLowerCase();
    final rawSentence = (json['sentence'] as String? ?? '').trim();
    return GeminiReply(
      action: rawAction == 'create_reminder' ? 'create_reminder' : 'chat',
      reply: (json['reply'] as String? ?? '').trim(),
      sentence: rawSentence.isEmpty ? null : rawSentence,
    );
  }
}

class GeminiService {
  static final GeminiService instance = GeminiService._();
  GeminiService._();

  static const defaultModel = 'gemini-2.5-flash';
  static const _maxHistory = 40;

  /// Gemini API kaliti — build vaqtida beriladi:
  /// `flutter build apk --release --dart-define=GEMINI_API_KEY=...`
  static const defaultApiKey = String.fromEnvironment('GEMINI_API_KEY');

  String? _apiKey = defaultApiKey;
  String _model = defaultModel;
  final List<Content> _history = [];
  List<String> Function()? _remindersProvider;

  String get model => _model;
  bool get hasApiKey => _apiKey != null && _apiKey!.trim().isNotEmpty;

  void configure({required String apiKey, String model = defaultModel}) {
    _apiKey = apiKey.trim();
    _model = model;
  }

  void setRemindersProvider(List<String> Function() provider) {
    _remindersProvider = provider;
  }

  void reset() {
    _history.clear();
  }

  Content _systemPrompt() {
    final reminders = _remindersProvider?.call() ?? const <String>[];
    final now = DateTime.now();
    final today =
        DateFormat("EEEE, d-MMMM yyyy 'yil'", 'uz_UZ').format(now);
    final buf = StringBuffer()
      ..writeln('Sen "Jarvis" ismli ilovadagi ovozli AI yordamchisan.')
      ..writeln(
          'Foydalanuvchi bilan faqat o\'zbek tilida, qisqa va tabiiy gaplashasan.')
      ..writeln(
          'Javobing 2-3 jumladan oshmasin, chunki u ovoz bilan o\'qiladi.')
      ..writeln()
      ..writeln('Bugungi sana: $today.')
      ..writeln()
      ..writeln('Vazifalaring:')
      ..writeln(
          '1. Foydalanuvchi eslatma qo\'shishni so\'rasa, action="create_reminder" qilib, eslatmani tabiiy o\'zbek tilida to\'liq gap holida "sentence" maydoniga yoz (masalan: "ertaga soat 10 da shifokorga boraman", "bugun kechki soat 7 da sport zalga boraman"). "reply" ga qisqa tasdiqlash yoz.')
      ..writeln(
          '2. Agar eslatma uchun vaqt yoki kun aytilmagan bo\'lsa, avval foydalanuvchidan so\'rab oling (action="chat").')
      ..writeln(
          '3. Aks holda action="chat" qilib, savolga yoki suhbatga javob yoz.')
      ..writeln()
      ..writeln('Hozirgi eslatmalar ro\'yxati (foydalanuvchi so\'rasa aytib ber):')
      ..writeln(reminders.isEmpty
          ? '(eslatmalar yo\'q)'
          : reminders.map((r) => '- $r').join('\n'))
      ..writeln()
      ..writeln('Qo\'llanma:')
      ..writeln('- Ortiqcha suhbat qilma, faqat kerakli narsani ayt.')
      ..writeln(
          '- Agar foydalanuvchi "eslatmalarim nima" desa, ro\'yxatni qisqacha sanab, action="chat" qil.')
      ..writeln('- Qisqa javob: "reply" maydoni ovoz bilan o\'qiladi.');
    return Content.system(buf.toString());
  }

  Schema _responseSchema() {
    return Schema(
      SchemaType.object,
      description: 'Jarvis javobi',
      properties: {
        'action': Schema(
          SchemaType.string,
          enumValues: const ['chat', 'create_reminder'],
          description: 'Harakat turi',
        ),
        'reply': Schema(
          SchemaType.string,
          description: 'Ovoz bilan o\'qiladigan o\'zbekcha qisqa javob',
        ),
        'sentence': Schema(
          SchemaType.string,
          nullable: true,
          description: 'Eslatma bo\'lsa: tabiiy o\'zbekcha to\'liq gap. Aks holda bo\'sh.',
        ),
      },
      requiredProperties: const ['action', 'reply'],
    );
  }

  Future<GeminiReply> sendMessage(String userText) async {
    final key = _apiKey?.trim();
    if (key == null || key.isEmpty) {
      throw StateError('API kalit kiritilmagan');
    }

    final model = GenerativeModel(
      model: _model,
      apiKey: key,
      systemInstruction: _systemPrompt(),
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: _responseSchema(),
      ),
    );

    final userMessage = Content.text(userText.trim());
    log('Gemini: yuborilmoqda -> $userText');
    try {
      final response = await model.generateContent([
        ..._history,
        userMessage,
      ]).timeout(const Duration(seconds: 40));
      log('Gemini: javob keldi -> ${response.text}');

      final text = response.text ?? '';
      if (text.trim().isEmpty) {
        throw StateError('Gemini bo\'sh javob qaytardi');
      }

      final decoded = jsonDecode(text);
      final reply = GeminiReply.fromJson(decoded as Map<String, dynamic>);
      log('Gemini: action=${reply.action} reply=${reply.reply} sentence=${reply.sentence}');

      _history.add(userMessage);
      final modelText = response.text ?? '';
      _history.add(Content.model([TextPart(modelText)]));
      if (_history.length > _maxHistory) {
        _history.removeRange(0, _history.length - _maxHistory);
      }

      return reply;
    } on TimeoutException {
      log('Gemini: timeout');
      throw StateError('Gemini javob bermadi (timeout)');
    } catch (e) {
      log('Gemini: Xatolik -> $e');
      rethrow;
    }
  }
}
