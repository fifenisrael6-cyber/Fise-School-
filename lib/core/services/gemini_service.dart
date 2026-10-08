import 'dart:async';
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

/// Contexte scolaire envoyé à l'IA quand l'élève demande de l'aide depuis
/// une leçon (classe, série, matière, chapitre, leçon en cours).
/// Les champs vides sont simplement ignorés.
class AiLessonContext {
  final String? className;
  final String? series;
  final String? subject;
  final String? chapter;
  final String? lessonTitle;
  final String? lessonContent;

  const AiLessonContext({
    this.className,
    this.series,
    this.subject,
    this.chapter,
    this.lessonTitle,
    this.lessonContent,
  });

  bool get isEmpty =>
      [className, series, subject, chapter, lessonTitle, lessonContent]
          .every((value) => value == null || value.trim().isEmpty);

  Map<String, String> toMap() {
    String clean(String? value, int max) {
      final text = (value ?? '').trim();
      return text.length <= max ? text : text.substring(0, max);
    }

    return {
      'className': clean(className, 120),
      'series': clean(series, 120),
      'subject': clean(subject, 160),
      'chapter': clean(chapter, 200),
      'lessonTitle': clean(lessonTitle, 200),
      // Le serveur limite aussi la taille ; on évite d'envoyer trop de texte
      // sur une connexion faible.
      'lessonContent': clean(lessonContent, 6000),
    };
  }
}

/// Erreur IA avec un message déjà lisible par l'utilisateur.
class AiServiceException implements Exception {
  final String message;
  final bool retryable;

  const AiServiceException(this.message, {this.retryable = true});

  @override
  String toString() => message;
}

class GeminiService {
  GeminiService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<String> ask({
    required String message,
    UserProfile? profile,
    List<AiHistoryMessage> history = const [],
    Uint8List? attachmentBytes,
    String? attachmentMimeType,
    String? attachmentName,
    String mode = 'student',
    AiLessonContext? context,
    String languageCode = 'fr',
  }) async {
    final isFrench = (profile?.preferredLanguage ?? languageCode) != 'en';
    final cleanMessage = message.trim();
    if (cleanMessage.isEmpty && attachmentBytes == null) {
      throw AiServiceException(
        isFrench ? 'Écris une question avant d’envoyer.' : 'Type a question first.',
        retryable: false,
      );
    }

    final lessonContext = context;
    final body = <String, dynamic>{
      'message': cleanMessage,
      'history': history.take(20).map((item) => item.toMap()).toList(),
      // Demande seulement : le serveur vérifie le rôle réel en base.
      'mode': mode == 'admin' ? 'admin' : 'student',
      'language': isFrench ? 'fr' : 'en',
      if (lessonContext != null && !lessonContext.isEmpty)
        'context': lessonContext.toMap(),
      // Gardé pour les anciennes versions déployées de la fonction.
      // La fonction sécurisée ignore ces valeurs et lit le profil en base.
      if (profile != null)
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
    };

    try {
      final response = await _client.functions
          .invoke('gemini-chat', body: body)
          .timeout(const Duration(seconds: 75));
      return _readAnswer(response.data, isFrench);
    } on AiServiceException {
      rethrow;
    } on FunctionException catch (error) {
      throw _fromFunctionError(error, isFrench);
    } on TimeoutException {
      throw AiServiceException(
        isFrench
            ? 'La réponse prend trop de temps. Vérifie ta connexion puis réessaie.'
            : 'The answer is taking too long. Check your connection and try again.',
      );
    } catch (_) {
      throw AiServiceException(
        isFrench
            ? 'Impossible de joindre l’assistant. Vérifie ta connexion Internet puis réessaie.'
            : 'Unable to reach the assistant. Check your Internet connection and try again.',
      );
    }
  }

  String _readAnswer(Object? data, bool isFrench) {
    if (data is! Map) {
      throw AiServiceException(
        isFrench ? 'Réponse de l’assistant invalide. Réessaie.' : 'Invalid assistant response. Try again.',
      );
    }
    final map = Map<String, dynamic>.from(data);
    final error = map['error'];
    if (error is String && error.trim().isNotEmpty) {
      throw _messageForError(error.trim(), null, isFrench);
    }
    final text = map['text'];
    if (text is! String || text.trim().isEmpty) {
      throw AiServiceException(
        isFrench
            ? 'L’assistant n’a retourné aucune réponse. Reformule ta question puis réessaie.'
            : 'The assistant returned no answer. Rephrase your question and try again.',
      );
    }
    return text.trim();
  }

  AiServiceException _fromFunctionError(FunctionException error, bool isFrench) {
    final details = error.details;
    String? serverMessage;
    if (details is Map && details['error'] is String) {
      serverMessage = (details['error'] as String).trim();
    } else if (details is String && details.trim().isNotEmpty) {
      serverMessage = details.trim();
    }
    return _messageForError(serverMessage ?? '', error.status, isFrench);
  }

  AiServiceException _messageForError(String raw, int? status, bool isFrench) {
    if (status == 401 || raw.contains('Invalid or expired session') || raw.contains('Authentication required')) {
      return AiServiceException(
        isFrench ? 'Ta session a expiré. Reconnecte-toi puis réessaie.' : 'Your session expired. Sign in again.',
        retryable: false,
      );
    }
    if (status == 403 || raw.contains('administrateurs') || raw.contains('Administrator access')) {
      return AiServiceException(
        isFrench ? 'Cette fonction n’est pas autorisée pour ton compte.' : 'This feature is not allowed for your account.',
        retryable: false,
      );
    }
    if (status == 413 || raw.contains('trop volumineux') || raw.contains('too large')) {
      return AiServiceException(
        isFrench ? 'Fichier trop volumineux. La limite est de 8 Mo.' : 'File is too large. The limit is 8 MB.',
        retryable: false,
      );
    }
    if (status == 400 && raw.isNotEmpty && !raw.contains('required')) {
      // Messages déjà rédigés par la fonction (ex. type de fichier refusé).
      return AiServiceException(raw, retryable: false);
    }
    // Message déjà rédigé en clair par la fonction (réponse vide, demande bloquée).
    if (raw.isNotEmpty && raw != 'AI_TEMPORARILY_UNAVAILABLE' && raw.length <= 200 && !raw.contains('GEMINI') && !raw.contains('Gemini') && !raw.contains('not configured')) {
      return AiServiceException(raw);
    }
    return AiServiceException(
      isFrench
          ? 'L’assistant IA est temporairement indisponible. Réessaie dans un instant.'
          : 'The AI assistant is temporarily unavailable. Try again in a moment.',
    );
  }
}
