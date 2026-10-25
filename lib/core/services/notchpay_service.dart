import 'package:supabase_flutter/supabase_flutter.dart';

class NotchPayResult {
  final String reference;
  final String status;
  final String message;

  const NotchPayResult({
    required this.reference,
    required this.status,
    required this.message,
  });
}

class NotchPayService {
  NotchPayService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  bool get isConfigured => _client.auth.currentUser != null;

  /// Starts a Cameroon Mobile Money charge. Teacher codes are never entered
  /// during checkout; the server resolves teachers from the student's classes.
  Future<NotchPayResult> createPayment({
    required int amount,
    String currency = 'XAF',
    String? description,
    required String channel,
    required String phone,
  }) async {
    if (_client.auth.currentUser == null) {
      throw const AuthException('No active user session.');
    }

    final response = await _client.functions.invoke(
      'notchpay-payment',
      body: {
        'amount': amount,
        'currency': currency,
        'description': description ?? 'Abonnement Fise School',
        'channel': channel,
        'phone': phone.trim(),
      },
    );

    if (response.data is! Map) {
      throw Exception('Réponse de paiement invalide.');
    }

    final data = Map<String, dynamic>.from(response.data as Map);
    final reference = data['reference']?.toString().trim() ?? '';
    if (reference.isEmpty) {
      final message = data['error']?.toString();
      throw Exception(message?.isNotEmpty == true
          ? message
          : 'Notch Pay n’a pas retourné la référence de transaction.');
    }

    return NotchPayResult(
      reference: reference,
      status: data['status']?.toString() ?? 'PENDING',
      message: data['message']?.toString() ??
          'Demande envoyée. Confirme le paiement sur ton téléphone.',
    );
  }

  /// Re-checks a transaction against Notch Pay on the trusted server.
  Future<Map<String, dynamic>> verifyPayment(String reference) async {
    final response = await _client.functions.invoke(
      'notchpay-verify',
      body: {'reference': reference.trim()},
    );
    if (response.data is! Map) {
      throw Exception('Réponse de vérification invalide.');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<String> getPaymentStatus(String reference) async {
    final result = await _client
        .from('payment_orders')
        .select('status')
        .eq('reference', reference)
        .maybeSingle();

    if (result == null) {
      throw Exception('Commande de paiement introuvable.');
    }

    return result['status']?.toString().toUpperCase() ?? 'UNKNOWN';
  }
}
