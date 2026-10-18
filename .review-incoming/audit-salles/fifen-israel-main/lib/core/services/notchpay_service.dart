import 'package:supabase_flutter/supabase_flutter.dart';

class NotchPayResult {
  final String authorizationUrl;
  final String reference;

  const NotchPayResult({
    required this.authorizationUrl,
    required this.reference,
  });
}

class NotchPayService {
  NotchPayService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Vérifie si l'utilisateur est connecté.
  bool get isConfigured {
    return _client.auth.currentUser != null;
  }

  /// Crée une demande de paiement via l'Edge Function Supabase.
  Future<NotchPayResult> createPayment({
    required String email,
    required String name,
    required int amount,
    String currency = 'XAF',
    String? description,
    String? reference,
    String? teacherCode,
  }) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw const AuthException('No active user session.');
    }

    final response = await _client.functions.invoke(
      'notchpay-payment',
      body: {
        'amount': amount,
        'currency': currency,
        'email': email,
        'name': name,
        'description': description ?? 'Abonnement Fise School',
        ...?reference == null ? null : {'reference': reference},
        ...?teacherCode == null || teacherCode.trim().isEmpty ? null : {'teacher_code': teacherCode.trim()},
      },
    );

    if (response.data is! Map) {
      throw Exception('Réponse de paiement invalide.');
    }

    final data = Map<String, dynamic>.from(response.data as Map);

    final authorizationUrl =
        data['authorization_url'] ?? data['transaction']?['authorization_url'];

    if (authorizationUrl is! String || authorizationUrl.trim().isEmpty) {
      throw Exception('Notch Pay n’a pas retourné de lien de paiement.');
    }

    final returnedReference =
        data['reference'] ??
        data['transaction']?['reference'] ??
        reference ??
        '';

    return NotchPayResult(
      authorizationUrl: authorizationUrl,
      reference: returnedReference.toString(),
    );
  }

  /// Ouvre l'URL de paiement dans le navigateur.
  Future<bool> openPaymentUrl(String url) async {
    final uri = Uri.tryParse(url);

    if (uri == null || !uri.hasScheme) {
      return false;
    }

    // L'ouverture du navigateur est volontairement laissée
    // à la page Flutter avec url_launcher.
    return true;
  }

  /// Récupère le statut actuel d'une commande de paiement.
  Future<String> getPaymentStatus(String reference) async {
    final result = await _client
        .from('payment_orders')
        .select('status')
        .eq('reference', reference)
        .maybeSingle();

    if (result == null) {
      throw Exception('Commande de paiement introuvable.');
    }

    final status = result['status'];

    if (status == null) {
      return 'UNKNOWN';
    }

    return status.toString().toUpperCase();
  }
}
