import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_service.dart';
import '../offline/offline_repository.dart';

class AuthService {
  SupabaseClient get _client => Supabase.instance.client;
  final ProfileService _profileService = ProfileService();

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );

    await _ensureProfile(response.user);
  }

  /// Retourne true si une session est créée immédiatement.
  /// Avec la confirmation e-mail activée, Supabase peut retourner false
  /// tout en ayant créé correctement le compte.
  Future<bool> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String role,
    String? subsystem,
    String? sector,
    String? examLevelId,
    String? examId,
    String? seriesId,
    String? specialtyId,
    String? examLevel,
    String? exam,
    String? track,
    String? languageOption,
    String? className,
    String? classId,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    final response = await _client.auth.signUp(
      email: cleanEmail,
      password: password,
      data: {
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'email': cleanEmail,
        'role': role,
        'subsystem': subsystem,
        'sector': sector,
        'exam_level_id': examLevelId,
        'exam_id': examId,
        'series_id': seriesId,
        'specialty_id': specialtyId,
        'exam_level': examLevel,
        'exam': exam,
        'track': track,
        'language_option': languageOption,
        'class_name': className,
        'class_id': classId,
      },
    );

    final user = response.user;
    if (user != null && response.session != null) {
      await _profileService.saveCurrentProfile(
        firstName: firstName,
        lastName: lastName,
        email: cleanEmail,
        role: role,
        subsystem: subsystem,
        sector: sector,
        examLevelId: examLevelId,
        examId: examId,
        seriesId: seriesId,
        specialtyId: specialtyId,
        examLevel: examLevel,
        exam: exam,
        track: track,
        className: className,
      );
    }

    return response.session != null;
  }

  Future<void> _ensureProfile(User? user) async {
    if (user == null) {
      return;
    }

    final existing = await _profileService.getCurrentProfile();
    if (existing != null) {
      return;
    }

    final metadata = user.userMetadata ?? const <String, dynamic>{};

    await _profileService.saveCurrentProfile(
      firstName: metadata['first_name'] as String? ?? '',
      lastName: metadata['last_name'] as String? ?? '',
      email: user.email ?? (metadata['email'] as String? ?? ''),
      role: metadata['role'] as String? ?? 'student',
      subsystem: metadata['subsystem'] as String?,
      sector: metadata['sector'] as String?,
      examLevelId: metadata['exam_level_id'] as String?,
      examId: metadata['exam_id'] as String?,
      seriesId: metadata['series_id'] as String?,
      specialtyId: metadata['specialty_id'] as String?,
      examLevel: metadata['exam_level'] as String?,
      exam: metadata['exam'] as String?,
      track: metadata['track'] as String?,
      className: metadata['class_name'] as String?,
    );
  }

  Future<void> signOut() async {
    try {
      await OfflineRepository().clearCourses();
      await OfflineRepository().clearLessons();
    } catch (e) {
      debugPrint('Nettoyage du cache hors ligne impossible: $e');
    }
    await _client.auth.signOut();
  }
}
