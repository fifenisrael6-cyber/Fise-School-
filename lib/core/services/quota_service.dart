import 'package:supabase_flutter/supabase_flutter.dart';

/// Fonctionnalités soumises à quota gratuit (clés identiques côté SQL).
enum QuotaFeature { lesson, qcm, annale, aiText, msgSent, msgRecv }

extension QuotaFeatureKey on QuotaFeature {
  String get key => switch (this) {
        QuotaFeature.lesson => 'lesson',
        QuotaFeature.qcm => 'qcm',
        QuotaFeature.annale => 'annale',
        QuotaFeature.aiText => 'ai_text',
        QuotaFeature.msgSent => 'msg_sent',
        QuotaFeature.msgRecv => 'msg_recv',
      };

  String label(bool fr) => switch (this) {
        QuotaFeature.lesson => fr ? 'Leçons' : 'Lessons',
        QuotaFeature.qcm => 'QCM',
        QuotaFeature.annale => fr ? 'Annales' : 'Past papers',
        QuotaFeature.aiText => fr ? 'Questions à l’IA' : 'AI questions',
        QuotaFeature.msgSent => fr ? 'Messages envoyés' : 'Messages sent',
        QuotaFeature.msgRecv => fr ? 'Messages reçus' : 'Messages received',
      };
}

class QuotaItem {
  const QuotaItem({required this.limit, required this.used, required this.remaining, this.resetsAt});
  final int limit;
  final int used;
  final int remaining;
  final DateTime? resetsAt;

  factory QuotaItem.fromMap(Map<String, dynamic> m) => QuotaItem(
        limit: (m['limit'] as num?)?.toInt() ?? 0,
        used: (m['used'] as num?)?.toInt() ?? 0,
        remaining: (m['remaining'] as num?)?.toInt() ?? 0,
        resetsAt: DateTime.tryParse('${m['resets_at'] ?? ''}')?.toLocal(),
      );
}

class QuotaStatus {
  const QuotaStatus({
    required this.premium,
    required this.premiumExpiresAt,
    required this.priceXaf,
    required this.durationDays,
    required this.hasPendingPayment,
    required this.wasPremium,
    required this.quotas,
  });

  final bool premium;
  final DateTime? premiumExpiresAt;
  final int priceXaf;
  final int durationDays;
  final bool hasPendingPayment;
  final bool wasPremium;
  final Map<String, QuotaItem> quotas;

  /// gratuit | pending | premium | expired
  String get state => premium
      ? 'premium'
      : hasPendingPayment
          ? 'pending'
          : wasPremium
              ? 'expired'
              : 'free';

  factory QuotaStatus.fromMap(Map<String, dynamic> m) {
    final raw = Map<String, dynamic>.from((m['quotas'] as Map?) ?? const {});
    return QuotaStatus(
      premium: m['premium'] == true,
      premiumExpiresAt: DateTime.tryParse('${m['premium_expires_at'] ?? ''}')?.toLocal(),
      priceXaf: (m['price_xaf'] as num?)?.toInt() ?? 2000,
      durationDays: (m['duration_days'] as num?)?.toInt() ?? 30,
      hasPendingPayment: m['has_pending_payment'] == true,
      wasPremium: m['was_premium'] == true,
      quotas: raw.map((k, v) => MapEntry(k, QuotaItem.fromMap(Map<String, dynamic>.from(v as Map)))),
    );
  }
}

class QuotaDecision {
  const QuotaDecision({required this.allowed, required this.premium, this.limit, this.used, this.resetsAt});
  final bool allowed;
  final bool premium;
  final int? limit;
  final int? used;
  final DateTime? resetsAt;
}

/// Le réseau ou le serveur n'a pas pu confirmer les droits : on ne débloque jamais par défaut.
class QuotaUnavailableException implements Exception {
  const QuotaUnavailableException();
}

class QuotaService {
  QuotaService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<QuotaStatus> status() async {
    try {
      final data = await _client.rpc('get_my_quota_status').timeout(const Duration(seconds: 10));
      return QuotaStatus.fromMap(Map<String, dynamic>.from(data as Map));
    } catch (_) {
      throw const QuotaUnavailableException();
    }
  }

  /// Consomme une unité côté serveur (idempotent pour une même [resourceId] dans la fenêtre de 24 h).
  Future<QuotaDecision> consume(QuotaFeature feature, {String? resourceId}) async {
    try {
      final data = await _client
          .rpc('consume_feature_quota', params: {'p_feature': feature.key, 'p_resource_id': resourceId})
          .timeout(const Duration(seconds: 10));
      final m = Map<String, dynamic>.from(data as Map);
      return QuotaDecision(
        allowed: m['allowed'] == true,
        premium: m['premium'] == true,
        limit: (m['limit'] as num?)?.toInt(),
        used: (m['used'] as num?)?.toInt(),
        resetsAt: DateTime.tryParse('${m['resets_at'] ?? ''}')?.toLocal(),
      );
    } catch (_) {
      throw const QuotaUnavailableException();
    }
  }

  /// Revérifie une commande auprès de Notch Pay (retour tardif, notification manquée).
  Future<String> verifyPayment({String? reference}) async {
    final res = await _client.functions.invoke('notchpay-verify', body: {if (reference != null) 'reference': reference});
    final data = res.data;
    if (data is Map && data['status'] is String) return (data['status'] as String).toUpperCase();
    return 'UNKNOWN';
  }
}
