import 'package:supabase_flutter/supabase_flutter.dart';

class SubscriptionService {
  final SupabaseClient _client;

  SubscriptionService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  /// Vérifie si l'élève connecté possède actuellement Premium.
  Future<bool> isPremium() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      return false;
    }

    try {
      final result = await _client.rpc(
        'is_student_premium',
        params: {'p_user_id': user.id},
      );

      return result == true;
    } catch (error) {
      // En cas d'erreur réseau ou Supabase,
      // on ne débloque jamais Premium par défaut.
      return false;
    }
  }

  /// Récupère le plan actuel de l'élève.
  Future<String> getCurrentPlan() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      return 'free';
    }

    try {
      final data = await _client
          .from('profiles')
          .select('subscription_plan')
          .eq('id', user.id)
          .maybeSingle();

      final plan = data?['subscription_plan'];

      if (plan == 'premium') {
        final premium = await isPremium();

        if (premium) {
          return 'premium';
        }
      }

      return 'free';
    } catch (error) {
      return 'free';
    }
  }

  /// Récupère les informations complètes de l'abonnement.
  Future<Map<String, dynamic>?> getActiveSubscription() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      return null;
    }

    try {
      final data = await _client
          .from('student_subscriptions')
          .select('''
            id,
            user_id,
            plan,
            status,
            starts_at,
            expires_at,
            payment_order_id,
            created_at,
            updated_at
          ''')
          .eq('user_id', user.id)
          .eq('plan', 'premium')
          .eq('status', 'active')
          .order('expires_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data == null) {
        return null;
      }

      final expiresAt = data['expires_at'];

      if (expiresAt != null) {
        final expiration = DateTime.tryParse(expiresAt.toString());

        if (expiration != null && !expiration.isAfter(DateTime.now())) {
          return null;
        }
      }

      return Map<String, dynamic>.from(data);
    } catch (error) {
      return null;
    }
  }

  /// Nombre de jours restants sur Premium.
  Future<int> getRemainingDays() async {
    final subscription = await getActiveSubscription();

    if (subscription == null) {
      return 0;
    }

    final expiresAt = subscription['expires_at'];

    if (expiresAt == null) {
      return 0;
    }

    final expiration = DateTime.tryParse(expiresAt.toString());

    if (expiration == null) {
      return 0;
    }

    final difference = expiration.difference(DateTime.now()).inDays;

    return difference < 0 ? 0 : difference;
  }

  /// Retourne la date d'expiration Premium.
  Future<DateTime?> getExpirationDate() async {
    final subscription = await getActiveSubscription();

    if (subscription == null) {
      return null;
    }

    final expiresAt = subscription['expires_at'];

    if (expiresAt == null) {
      return null;
    }

    return DateTime.tryParse(expiresAt.toString());
  }

  /// Vérifie une fonctionnalité Premium.
  Future<bool> canAccessPremiumFeature() async {
    return await isPremium();
  }

  /// Vérifie que l'utilisateur connecté est bien un élève.
  Future<bool> isStudent() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      return false;
    }

    try {
      final data = await _client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      return data?['role'] == 'student';
    } catch (error) {
      return false;
    }
  }

  /// Retourne toutes les informations utiles à l'interface.
  Future<SubscriptionInfo> getSubscriptionInfo() async {
    final plan = await getCurrentPlan();
    final subscription = await getActiveSubscription();

    if (plan == 'premium' && subscription != null) {
      final expiresAt = subscription['expires_at'];

      DateTime? expiration;

      if (expiresAt != null) {
        expiration = DateTime.tryParse(expiresAt.toString());
      }

      int remainingDays = 0;

      if (expiration != null) {
        final difference = expiration.difference(DateTime.now()).inDays;

        remainingDays = difference < 0 ? 0 : difference;
      }

      return SubscriptionInfo(
        plan: 'premium',
        isPremium: true,
        status: 'active',
        expiresAt: expiration,
        remainingDays: remainingDays,
      );
    }

    return const SubscriptionInfo(
      plan: 'free',
      isPremium: false,
      status: 'free',
      expiresAt: null,
      remainingDays: 0,
    );
  }
}

class SubscriptionInfo {
  final String plan;
  final bool isPremium;
  final String status;
  final DateTime? expiresAt;
  final int remainingDays;

  const SubscriptionInfo({
    required this.plan,
    required this.isPremium,
    required this.status,
    required this.expiresAt,
    required this.remainingDays,
  });

  bool get isFree => !isPremium;
}
