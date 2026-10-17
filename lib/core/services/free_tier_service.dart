import 'package:supabase_flutter/supabase_flutter.dart';

/// Consommation des droits gratuits enregistrée côté serveur.
/// Les erreurs de vérification ne débloquent jamais un nouvel accès gratuit.
class FreeTierService {
  FreeTierService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<bool> canAccessMultimedia() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    try {
      final profile = await _client.from('profiles').select('role')
          .eq('id', user.id).maybeSingle();
      if (profile?['role'] != 'student') return true;
      final premium = await _client.rpc(
        'is_student_premium',
        params: {'p_user_id': user.id},
      );
      return premium == true;
    } catch (_) {
      return false;
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
