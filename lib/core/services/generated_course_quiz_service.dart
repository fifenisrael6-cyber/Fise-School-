import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Génération et correction sécurisées des QCM à partir d'une leçon publiée.
/// Les bonnes réponses ne sont jamais conservées dans le cache local.
class GeneratedCourseQuizService {
  GeneratedCourseQuizService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String _cacheKey(String lessonId, String language) =>
      "fise_generated_quiz_v1:${_client.auth.currentUser?.id ?? 'anonymous'}:$lessonId:$language";

  Future<Map<String, dynamic>> generate({
    required String lessonId,
    required String language,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'course-quiz',
        body: {
          'action': 'generate',
          'lesson_id': lessonId,
          'language': language == 'en' ? 'en' : 'fr',
        },
      );
      final data = _asMap(response.data);
      if (response.status < 200 || response.status >= 300 || data['error'] != null) {
        throw Exception(data['error'] ?? 'Impossible de générer le QCM.');
      }
      final safeData = Map<String, dynamic>.from(data)..remove('corrections');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey(lessonId, language), jsonEncode(safeData));
      return safeData;
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey(lessonId, language));
      if (cached != null) {
        try {
          final value = _asMap(jsonDecode(cached));
          value['cachedOffline'] = true;
          return value;
        } catch (_) {
          // Ignore a damaged local cache and report the original error.
        }
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> submit({
    required String quizId,
    required Map<String, int> answers,
  }) async {
    final response = await _client.functions.invoke(
      'course-quiz',
      body: {
        'action': 'submit',
        'quiz_id': quizId,
        'answers': answers,
      },
    );
    final data = _asMap(response.data);
    if (response.status < 200 || response.status >= 300 || data['error'] != null) {
      throw Exception(data['error'] ?? 'Impossible de corriger le QCM.');
    }
    return data;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) return value.map((key, item) => MapEntry(key.toString(), item));
    throw const FormatException('Réponse du serveur invalide.');
  }
}
