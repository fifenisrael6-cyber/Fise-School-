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
    Map<String, dynamic>? schoolContext,
    String mode = 'student',
  }) async {
    final response = await _client.functions.invoke(
      'gemini-chat',
      body: {
        'message': message.trim(),
        'history': history.take(20).map((item) => item.toMap()).toList(),
        'language': profile.preferredLanguage == 'en' ? 'en' : 'fr',
        'mode': mode,
        if (schoolContext != null) 'schoolContext': schoolContext,
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
    );

    if (response.data is! Map) {
      throw Exception('Réponse IA invalide.');
    }

    final data = Map<String, dynamic>.from(response.data as Map);
    final error = data['error'];
    if (error is String && error.trim().isNotEmpty) {
      throw Exception(error.trim());
    }

    final text = data['text'];
    if (text is! String || text.trim().isEmpty) {
      throw Exception('L’assistant IA n’a retourné aucune réponse.');
    }
    return text.trim();
  }
}
