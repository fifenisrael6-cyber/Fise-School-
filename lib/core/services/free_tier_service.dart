import 'package:supabase_flutter/supabase_flutter.dart';

import '../offline/json_cache.dart';

/// Consommation des droits gratuits enregistrée côté serveur.
/// Les erreurs de vérification ne débloquent jamais un nouvel accès gratuit.
class FreeTierService {
  FreeTierService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

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
      if (result is Map) return result['allowed'] == true;
      return false;
    } catch (_) {
      return false;
    }
  }
}
