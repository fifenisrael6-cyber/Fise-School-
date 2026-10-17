import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../features/student/pages/pages/payment_page.dart';

/// Bottom sheet shared by every student feature when the free quota is reached.
Future<void> showPremiumOfferSheet({
  required BuildContext context,
  required Locale locale,
  required UserProfile profile,
  required String feature,
}) async {
  final fr = locale.languageCode == 'fr';
  final pay = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: false,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: Color(0xFFDCFCE7),
            child: Icon(Icons.workspace_premium_rounded, color: Color(0xFF166534), size: 30),
          ),
          const SizedBox(height: 12),
          Text(
            fr ? 'Passe à Fise School Premium' : 'Upgrade to Fise School Premium',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            fr
                ? 'Tu as atteint la limite gratuite pour $feature. Débloque l’accès avec Premium.'
                : 'You have reached the free limit for $feature. Unlock access with Premium.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Column(
              children: [
                const Text('2 000 FCFA', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF166534))),
                Text(fr ? 'pour 30 jours' : 'for 30 days'),
                const SizedBox(height: 6),
                Text(
                  fr
                      ? 'Paiement sécurisé par Notch Pay. Activation après confirmation du paiement.'
                      : 'Secure payment by Notch Pay. Premium activates after payment confirmation.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.pop(sheetContext, true),
            icon: const Icon(Icons.lock_rounded),
            label: Text(fr ? 'Passer au paiement' : 'Continue to payment'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF166534),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(sheetContext, false),
            child: Text(fr ? 'Continuer gratuitement plus tard' : 'Continue for free later'),
          ),
        ],
      ),
    ),
  );
  if (pay == true && context.mounted) {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentPage(locale: locale, profile: profile),
      ),
    );
  }
}
