import 'package:supabase_flutter/supabase_flutter.dart';

class NotchPayResult {
  final String reference;
  final String status;
  final String message;
  final String channel;
  final String phone;

  const NotchPayResult({
    required this.reference,
    required this.status,
    required this.message,
    required this.channel,
    required this.phone,
  });
}

class NotchPayService {
  NotchPayService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  bool get isConfigured => _client.auth.currentUser != null;

  Future<NotchPayResult> createPayment({
    required String email,
    required String name,
    required int amount,
    String currency = 'XAF',
    String? description,
    String? reference,
    String? teacherCode,
    required String channel,
    required String phone,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('Aucune session utilisateur active.');

    final response = await _client.functions.invoke(
      'notchpay-payment',
      body: {
        'amount': amount,
        'currency': currency,
        'email': email,
        'name': name,
        'description': description ?? 'Abonnement Fise School',
        'channel': channel,
        'phone': phone,
        if (reference != null) 'reference': reference,
        if (teacherCode != null && teacherCode.trim().isNotEmpty) 'teacher_code': teacherCode.trim(),
      },
    );
    if (response.data is! Map) throw Exception('Réponse de paiement invalide.');
    final data = Map<String, dynamic>.from(response.data as Map);
    final returnedReference = data['reference'];
    if (returnedReference is! String || returnedReference.trim().isEmpty) {
      final error = data['error'];
      throw Exception(error is String ? error : 'La demande de paiement n’a pas été créée.');
    }
    return NotchPayResult(
      reference: returnedReference,
      status: (data['status'] ?? 'PENDING').toString(),
      message: (data['message'] ?? 'Demande envoyée. Confirme le paiement sur ton téléphone.').toString(),
      channel: (data['channel'] ?? channel).toString(),
      phone: (data['phone'] ?? phone).toString(),
    );
  }

  Future<Map<String, dynamic>> verifyPayment(String reference) async {
    final response = await _client.functions.invoke(
      'notchpay-verify',
      body: {'reference': reference},
    );
    if (response.data is! Map) {
      throw Exception('Réponse de vérification du paiement invalide.');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<String> getPaymentStatus(String reference) async {
    final result = await _client.from('payment_orders')
        .select('status').eq('reference', reference).maybeSingle();
    if (result == null) throw Exception('Commande de paiement introuvable.');
    return (result['status'] ?? 'UNKNOWN').toString().toUpperCase();
  }
}
