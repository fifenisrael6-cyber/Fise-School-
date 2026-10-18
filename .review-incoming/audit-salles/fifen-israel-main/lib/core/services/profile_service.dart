import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_profile.dart';
import '../offline/json_cache.dart';
import '../offline/connectivity_service.dart';

class ProfileService {
  SupabaseClient get _client => Supabase.instance.client;

  String _cacheKey(String userId) => 'profile_$userId';

  Future<UserProfile?> getCurrentProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return null;
    }

    // Do not wait for a remote request when Android reports no network.
    if (!await ConnectivityService().isOnline()) {
      return _readCachedProfile(user.id);
    }

    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 2));

      if (data == null) {
        return await _readCachedProfile(user.id);
      }
      final profile = UserProfile.fromMap(Map<String, dynamic>.from(data));
      try {
        await JsonCache.instance.write(_cacheKey(user.id), profile.toMap());
      } catch (_) {}
      return profile;
    } catch (_) {
      // The last known profile lets a previously signed-in user open the app
      // immediately without a network connection.
      return await _readCachedProfile(user.id);
    }
  }

  Future<UserProfile?> _readCachedProfile(String userId) async {
    final raw = await JsonCache.instance.read(_cacheKey(userId));
    if (raw is! Map) return null;
    try {
      final profile = UserProfile.fromMap(Map<String, dynamic>.from(raw));
      return profile.id == userId ? profile : null;
    } catch (_) {
      return null;
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
    final profile = UserProfile.fromMap(Map<String, dynamic>.from(data));
    await JsonCache.instance.write(_cacheKey(user.id), profile.toMap());
    return profile;
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

    final payload = profile.toMap();
    // Do not erase an existing language option during legacy signup/profile
    // saves that do not yet pass this optional field.
    if (profile.languageOption == null) {
      payload.remove('language_option');
    }
    final data = await _client
        .from('profiles')
        .upsert(payload)
        .select()
        .single();
    final saved = UserProfile.fromMap(Map<String, dynamic>.from(data));
    await JsonCache.instance.write(_cacheKey(user.id), saved.toMap());
    return saved;
  }
}
