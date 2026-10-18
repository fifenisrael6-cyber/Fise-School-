import 'package:flutter/foundation.dart';

/// Signalé quand le serveur refuse l'envoi d'un message : 'quota' ou 'premium'.
/// Les pages de messagerie l'écoutent pour ouvrir la fenêtre Premium.
class MessageQuotaEvents {
  static final ValueNotifier<int> denied = ValueNotifier<int>(0);
  static String lastKind = 'quota';

  static void notify(String kind) {
    lastKind = kind;
    denied.value++;
  }

  /// Reconnaît les refus levés par les triggers SQL (QUOTA_EXCEEDED / PREMIUM_REQUIRED).
  static String? kindFrom(Object error) {
    final text = error.toString();
    if (text.contains('PREMIUM_REQUIRED')) return 'premium';
    if (text.contains('QUOTA_EXCEEDED')) return 'quota';
    return null;
  }
}
