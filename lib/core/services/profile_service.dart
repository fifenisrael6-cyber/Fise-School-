import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_profile.dart';
import '../offline/json_cache.dart';

class ProfileService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<UserProfile?> getCurrentProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return null;
    }

    final cacheKey = 'profile_${user.id}';
    // Un compte déjà utilisé sur cet appareil retrouve immédiatement son
    // interface locale. La mise à jour serveur se fait sans bloquer l'écran.
    final cached = await JsonCache.instance.read(cacheKey);
    if (cached is Map) {
      try {
        final profile = UserProfile.fromMap(Map<String, dynamic>.from(cached));
        unawaited(_refreshProfile(cacheKey, user.id));
        return profile;
      } catch (_) {
        // Cache invalide : réessayer avec les données serveur.
      }
    }

    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle()
          .timeout(JsonCache.networkTimeout);
      if (data == null) {
        return null;
      }
      try {
        await JsonCache.instance.write(cacheKey, data);
      } catch (_) {}
      return UserProfile.fromMap(data);
    } catch (_) {
      // Relecture défensive si un cache a été écrit entre temps.
      final fallback = await JsonCache.instance.read(cacheKey);
      if (fallback is Map) {
        return UserProfile.fromMap(Map<String, dynamic>.from(fallback));
      }
      rethrow;
    }
  }

  Future<void> _refreshProfile(String cacheKey, String userId) async {
    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle()
          .timeout(JsonCache.networkTimeout);
      if (data == null) {
        await JsonCache.instance.remove(cacheKey);
        return;
      }
      await JsonCache.instance.write(cacheKey, data);
    } catch (_) {
      // Le réseau reste facultatif pour l'affichage de l'espace utilisateur.
    }
  }

  Future<UserProfile> updateEditableProfile({
    required String firstName,
    required String lastName,
    required String preferredLanguage,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('No active user session.');
    }
    final data = await _client
        .from('profiles')
        .update({
          'first_name': firstName.trim(),
          'last_name': lastName.trim(),
          'preferred_language': preferredLanguage,
        })
        .eq('id', user.id)
        .select()
        .single();
    return UserProfile.fromMap(data);
  }

  Future<UserProfile> saveCurrentProfile({
    required String firstName,
    required String lastName,
    required String email,
    required String role,
    String preferredLanguage = 'fr',
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
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Aucune session utilisateur active.');
    }

    final profile = UserProfile(
      id: user.id,
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      email: email.trim(),
      role: role,
      preferredLanguage: preferredLanguage,
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

    final data = await _client
        .from('profiles')
        .upsert(profile.toMap())
        .select()
        .single();

    return UserProfile.fromMap(data);
  }
}
