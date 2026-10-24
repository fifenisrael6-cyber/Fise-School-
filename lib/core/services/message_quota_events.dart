import 'package:flutter/foundation.dart';

/// Signale un refus d'envoi pour que l'interface ouvre l'explication Premium/quota.
class MessageQuotaEvents {
  static final ValueNotifier<int> denied = ValueNotifier<int>(0);
  static String lastKind = 'quota';

  static void notify(String kind) {
    lastKind = kind;
    denied.value++;
  }

  /// Reconnaît les codes réellement renvoyés par les triggers SQL Supabase.
  static String? kindFrom(Object error) {
    final text = error.toString();
    if (text.contains('PREMIUM_REQUIRED')) return 'premium';
    if (text.contains('QUOTA_EXCEEDED') ||
        text.contains('FREE_PRIVATE_SEND_LIMIT') ||
        text.contains('FREE_GROUP_SEND_LIMIT')) {
      return 'quota';
    }
    return null;
  }
}
