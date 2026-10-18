import 'package:supabase_flutter/supabase_flutter.dart';

class TeacherPaymentCodeService {
  final SupabaseClient _client;

  TeacherPaymentCodeService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<String> createOrGetCode() async {
    final result = await _client.rpc('create_teacher_payment_code');
    return result.toString();
  }

  Future<String?> resolveTeacherId(String code) async {
    final result = await _client.rpc(
      'resolve_teacher_payment_code',
      params: {'p_code': code.trim()},
    );
    return result?.toString();
  }

  Future<int> getWalletBalance() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return 0;
    }
    final row = await _client
        .from('teacher_wallets')
        .select('balance_xaf')
        .eq('teacher_id', user.id)
        .maybeSingle();
    return (row?['balance_xaf'] as num?)?.toInt() ?? 0;
  }

  Future<Map<String, dynamic>?> getOwnCode() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return null;
    }
    final row = await _client
        .from('teacher_payment_codes')
        .select('code, active, created_at')
        .eq('teacher_id', user.id)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }
}
