import 'package:supabase_flutter/supabase_flutter.dart';

import '../offline/json_cache.dart';

/// Consommation des droits gratuits enregistrée côté serveur.
/// Les erreurs de vérification ne débloquent jamais un nouvel accès gratuit.
class FreeTierService {
  FreeTierService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Read-only server status for a rolling 24-hour quota. Null means the server
  /// could not verify the quota; callers must not treat that as free access.
  Future<Map<String, dynamic>?> status(String feature) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final result = await _client.rpc(
        'student_free_quota_status',
        params: {'p_feature': feature},
      );
      return result is Map ? Map<String, dynamic>.from(result) : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> canAccessMultimedia() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    final cacheKey = 'multimedia_entitlement_${user.id}';
    try {
      final profile = await _client.from('profiles').select('role')
          .eq('id', user.id).maybeSingle();
      if (profile?['role'] != 'student') {
        await JsonCache.instance.write(cacheKey, true);
        return true;
      }
      final premium = await _client.rpc(
        'is_student_premium',
        params: {'p_user_id': user.id},
      );
      final allowed = premium == true;
      await JsonCache.instance.write(cacheKey, allowed);
      return allowed;
    } catch (_) {
      // A previously verified Premium entitlement keeps downloaded multimedia
      // available offline; otherwise fail closed for the free tier.
      return await JsonCache.instance.read(cacheKey) == true;
    }
  }

  Future<bool> consume(String feature, String resourceId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    final cacheKey = 'free_tier_access_${user.id}_$feature';

    try {
      final profile = await _client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      if (profile?['role'] != 'student') return true;

      final result = await _client.rpc(
        'consume_student_free_quota',
        params: {'p_feature': feature, 'p_resource_id': resourceId},
      );
      final allowed = result is Map && result['allowed'] == true;
      if (allowed) {
        final previous = await JsonCache.instance.read(cacheKey);
        final ids = previous is List
            ? previous.map((item) => item.toString()).toSet()
            : <String>{};
        ids.add(resourceId);
        await JsonCache.instance.write(cacheKey, ids.toList());
      }
      return allowed;
    } catch (_) {
      // Offline access is limited to resources already granted while online.
      final previous = await JsonCache.instance.read(cacheKey);
      return previous is List && previous.any((item) => item.toString() == resourceId);
    }
  }
}
