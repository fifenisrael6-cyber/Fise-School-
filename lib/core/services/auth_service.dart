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
    String? className,
    String? languageOption,
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
        'class_name': className,
        'language_option': languageOption,
      },
    );

    final user = response.user;

    // Avec la confirmation e-mail, Supabase ne renvoie pas d'erreur si l'e-mail
    // existe déjà : il renvoie un utilisateur sans identité. On le signale.
    if (user != null && (user.identities?.isEmpty ?? false)) {
      throw const AuthException(
        'User already registered',
        code: 'user_already_exists',
      );
    }

    if (user != null && response.session != null) {
      // Le compte existe déjà ici : un échec de sauvegarde du profil ne doit
      // pas être présenté comme un échec d'inscription (le profil est
      // recréé à la prochaine connexion par _ensureProfile).
      try {
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
      } on PostgrestException catch (error, stackTrace) {
        debugPrint('[INSCRIPTION][PROFIL] type=${error.runtimeType}');
        debugPrint('[INSCRIPTION][PROFIL] message=${error.message}');
        debugPrint('[INSCRIPTION][PROFIL] code=${error.code}');
        debugPrint('[INSCRIPTION][PROFIL] details=${error.details}');
        debugPrint('[INSCRIPTION][PROFIL] hint=${error.hint}');
        debugPrint('[INSCRIPTION][PROFIL] stackTrace=$stackTrace');
      } catch (error, stackTrace) {
        debugPrint('[INSCRIPTION][PROFIL] type=${error.runtimeType}');
        debugPrint('[INSCRIPTION][PROFIL] message=$error');
        debugPrint('[INSCRIPTION][PROFIL] stackTrace=$stackTrace');
      }
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
