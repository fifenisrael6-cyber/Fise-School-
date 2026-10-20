import 'package:supabase_flutter/supabase_flutter.dart';

class TeacherPaymentCodeService {
  final SupabaseClient _client;

  TeacherPaymentCodeService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<String> saveCode(String code) async {
    final result = await _client.rpc(
      'set_teacher_fise_code',
      params: {'p_code': code.trim().toUpperCase()},
    );
    return result.toString();
  }

  Future<String?> resolveTeacherId(String code) async {
    final result = await _client.rpc(
      'resolve_teacher_payment_code',
      params: {'p_code': code.trim().toUpperCase()},
    );
    return result?.toString();
  }

  Future<int> getWalletBalance() async {
    final user = _client.auth.currentUser;
    if (user == null) return 0;
    final row = await _client
        .from('teacher_wallets')
        .select('balance_xaf')
        .eq('teacher_id', user.id)
        .maybeSingle();
    return (row?['balance_xaf'] as num?)?.toInt() ?? 0;
  }

  Future<Map<String, dynamic>?> getOwnCode() async {
    if (_client.auth.currentUser == null) return null;

    // The FISE code is shared by groups, payments and evaluations. Ask the
    // server for the canonical value so older accounts are synchronized too.
    final value = await _client.rpc('get_or_create_teacher_group_access_code');
    final code = value?.toString().trim() ?? '';
    if (code.isEmpty) return null;
    return <String, dynamic>{'code': code, 'active': true};
  }
}
