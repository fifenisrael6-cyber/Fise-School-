import 'package:supabase_flutter/supabase_flutter.dart';

class TeacherPaymentCodeService {
  final SupabaseClient _client;

  TeacherPaymentCodeService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  /// Legacy getter only. The SQL function returns the shared code and never generates one.
  Future<String> createOrGetCode() async {
    final result = await _client.rpc('create_teacher_payment_code');
    return result.toString();
  }

  Future<String> setSharedCode(String code) async {
    final result = await _client.rpc(
      'set_teacher_shared_code',
      params: {'p_code': code.trim()},
    );
    if (result == null || result.toString().trim().isEmpty) {
      throw StateError('Impossible d’enregistrer le code.');
    }
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
    if (user == null) return 0;
    final row = await _client
        .from('teacher_wallets')
        .select('balance_xaf')
        .eq('teacher_id', user.id)
        .maybeSingle();
    return (row?['balance_xaf'] as num?)?.toInt() ?? 0;
  }

  Future<Map<String, dynamic>?> getOwnCode() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    // Prefer the canonical messaging code so the payment page cannot show
    // an older, independent payment-only code.
    final accessRow = await _client
        .from('teacher_access_codes')
        .select('code, is_active, created_at')
        .eq('teacher_id', user.id)
        .eq('is_active', true)
        .order('created_at')
        .limit(1)
        .maybeSingle();
    if (accessRow != null) {
      return {
        'code': 'FISE-${accessRow['code'].toString().toUpperCase()}',
        'active': true,
        'created_at': accessRow['created_at'],
      };
    }

    final paymentRow = await _client
        .from('teacher_payment_codes')
        .select('code, active, created_at')
        .eq('teacher_id', user.id)
        .eq('active', true)
        .maybeSingle();
    return paymentRow == null ? null : Map<String, dynamic>.from(paymentRow);
  }
}
