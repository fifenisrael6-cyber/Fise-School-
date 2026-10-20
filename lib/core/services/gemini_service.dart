import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_profile.dart';

class AiHistoryMessage {
  final String role;
  final String text;

  const AiHistoryMessage({required this.role, required this.text});

  Map<String, String> toMap() => {'role': role, 'text': text};
}

class AiDailyLimitReachedException implements Exception {
  const AiDailyLimitReachedException(this.message);

  final String message;

  static AiDailyLimitReachedException messageForLanguage(String languageCode) {
    return AiDailyLimitReachedException(
      languageCode == 'en'
          ? 'You’ve reached today’s question limit. Asking many questions without taking time to remember the answers won’t help you learn. Review your lessons first; we’ll continue tomorrow.'
          : 'Tu as atteint ta limite de questions pour aujourd’hui. Poser beaucoup de questions sans prendre le temps de retenir les réponses ne t’aide pas à apprendre. Va d’abord relire tes cours ; nous continuerons demain.',
    );
  }

  @override
  String toString() => message;
}

class AiPremiumRequiredException implements Exception {
  const AiPremiumRequiredException(this.message);
  final String message;
  @override
  String toString() => message;
}

class GeminiService {
  GeminiService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<String> ask({
    required String message,
    required UserProfile profile,
    List<AiHistoryMessage> history = const [],
    Uint8List? attachmentBytes,
    String? attachmentMimeType,
    String? attachmentName,
  }) async {
    final FunctionResponse response;
    try {
      response = await _invokeGemini(
      message: message, profile: profile, history: history,
      attachmentBytes: attachmentBytes, attachmentMimeType: attachmentMimeType, attachmentName: attachmentName);
    } on FunctionException catch (e) {
      final details = e.details;
      final Map<String, dynamic>? body = details is Map ? Map<String, dynamic>.from(details) : null;
      final lang = profile.preferredLanguage == 'en' ? 'en' : 'fr';
      if (body?['code'] == 'PREMIUM_REQUIRED' || e.status == 402) {
        throw AiPremiumRequiredException((body?['message'] ?? '').toString());
      }
      if (body?['code'] == 'DAILY_LIMIT_REACHED' || (e.status == 429 && body?['kind'] == 'question')) {
        throw AiDailyLimitReachedException.messageForLanguage(lang);
      }
      final msg = body?['message'] ?? body?['error'];
      throw Exception(msg is String && msg.trim().isNotEmpty ? msg.trim() : 'AI_REQUEST_FAILED');
    }
    if (response.data is! Map) {
      throw Exception('Réponse IA invalide.');
    }

    final data = Map<String, dynamic>.from(response.data as Map);
    final code = data['code'] ?? data['error'];
    final quotaKind = data['kind']?.toString();
    if (code == 'DAILY_LIMIT_REACHED' && quotaKind == 'question') {
      throw AiDailyLimitReachedException.messageForLanguage(
        profile.preferredLanguage == 'en' ? 'en' : 'fr',
      );
    }
    final error = data['error'];
    if (error is String && error.trim().isNotEmpty) {
      final serverMessage = data['message'];
      throw Exception(serverMessage is String && serverMessage.trim().isNotEmpty
          ? serverMessage.trim()
          : error.trim());
    }

    final text = data['text'];
    if (text is! String || text.trim().isEmpty) {
      throw Exception('L’assistant IA n’a retourné aucune réponse.');
    }
    return text.trim();
  }

  Future<FunctionResponse> _invokeGemini({
    required String message,
    required UserProfile profile,
    required List<AiHistoryMessage> history,
    Uint8List? attachmentBytes,
    String? attachmentMimeType,
    String? attachmentName,
  }) {
    return _client.functions.invoke(
      'gemini-chat',
      body: {
        'message': message.trim(),
        'history': history.take(6).map((item) => AiHistoryMessage(
          role: item.role,
          text: item.text.trim().length > 2500 ? item.text.trim().substring(0, 2500) : item.text.trim(),
        ).toMap()).toList(),
        'language': profile.preferredLanguage == 'en' ? 'en' : 'fr',
        // Kept for backwards compatibility with older deployed functions.
        // The secure function ignores these values and loads the profile from
        // the authenticated Supabase user.
        'profile': {
          'subsystem': profile.subsystem,
          'sector': profile.sector,
          'className': profile.className,
          'examLevel': profile.examLevel,
          'exam': profile.exam,
        },
        if (attachmentBytes != null)
          'attachment': {
            'name': attachmentName ?? 'attachment',
            'mimeType': attachmentMimeType ?? 'application/octet-stream',
            'base64': base64Encode(attachmentBytes),
          },
      },
    ).timeout(const Duration(seconds: 35));
  }
}
