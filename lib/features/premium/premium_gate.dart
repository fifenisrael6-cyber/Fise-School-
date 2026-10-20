import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/notchpay_service.dart';
import '../../core/services/quota_service.dart';
import '../../models/user_profile.dart';

/// Point d'entrée unique : vérifie les droits côté serveur et ouvre la fenêtre
/// Premium si besoin. Retourne true si l'action demandée peut continuer.
class PremiumGate {
  // Temporary application-test mode: payment/quota gates stay disabled until
  // end-to-end classroom messaging and course delivery have been validated.
  static const bool testingMode = true;

  static Future<bool> ensure(
    BuildContext context, {
    required UserProfile profile,
    required QuotaFeature feature,
    String? resourceId,
    bool premiumOnly = false,
    bool offlineFallback = false,
  }) async {
    if (testingMode) return true;
    if (profile.role != 'student') return true;
    final service = QuotaService();
    final fr = profile.preferredLanguage != 'en';
    try {
      if (!premiumOnly) {
        final decision = await service.consume(feature, resourceId: resourceId);
        if (decision.allowed) return true;
        if (!context.mounted) return false;
        return _openSheet(context, profile, feature, decision: decision, resourceId: resourceId);
      }
      final status = await service.status();
      if (status.premium) return true;
      if (!context.mounted) return false;
      return _openSheet(context, profile, feature, premiumOnlyReason: true, resourceId: resourceId);
    } on QuotaUnavailableException {
      if (offlineFallback) return true; // contenu déjà téléchargé légitimement
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(fr
              ? 'Impossible de vérifier tes droits pour le moment. Vérifie ta connexion et réessaie.'
              : 'Could not verify your access right now. Check your connection and try again.'),
        ));
      }
      return false;
    }
  }

  /// Contrôle SANS consommer d'unité, à appeler au clic sur « Envoyer » (message, photo, document, IA).
  /// Si la limite gratuite est atteinte ou si une pièce jointe est réservée au Premium,
  /// la fenêtre Premium s'ouvre immédiatement et rien n'est ajouté à la conversation.
  /// Le serveur reste l'autorité : les triggers SQL refusent de toute façon un envoi non autorisé.
  static Future<bool> canSend(
    BuildContext context, {
    required UserProfile profile,
    required QuotaFeature feature,
    bool hasAttachment = false,
  }) async {
    if (testingMode) return true;
    if (profile.role != 'student') return true;
    final fr = profile.preferredLanguage != 'en';
    try {
      final status = await QuotaService().status();
      if (status.premium) return true;
      final remaining = status.quotas[feature.key]?.remaining ?? 0;
      if (!hasAttachment && remaining > 0) return true;
      if (!context.mounted) return false;
      final paid = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => PremiumGatePage(
          profile: profile,
          feature: feature,
          premiumOnlyReason: hasAttachment,
          decision: QuotaDecision(
            allowed: false,
            premium: false,
            limit: status.quotas[feature.key]?.limit,
            resetsAt: status.quotas[feature.key]?.resetsAt,
          ),
        ),
      ));
      return paid == true;
    } on QuotaUnavailableException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(fr
              ? 'Impossible de vérifier tes droits. Vérifie ta connexion et réessaie.'
              : 'Could not verify your access. Check your connection and try again.'),
        ));
      }
      return false;
    }
  }

  /// À appeler quand le serveur renvoie QUOTA_EXCEEDED / PREMIUM_REQUIRED (ex. envoi de message, IA).
  static Future<bool> openForServerDenial(
    BuildContext context, {
    required UserProfile profile,
    required QuotaFeature feature,
    bool premiumOnly = false,
  }) =>
      testingMode ? Future<bool>.value(true) : _openSheet(context, profile, feature, premiumOnlyReason: premiumOnly);

  static Future<bool> _openSheet(
    BuildContext context,
    UserProfile profile,
    QuotaFeature feature, {
    QuotaDecision? decision,
    bool premiumOnlyReason = false,
    String? resourceId,
  }) async {
    final paid = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => PremiumGatePage(
        profile: profile,
        feature: feature,
        decision: decision,
        premiumOnlyReason: premiumOnlyReason,
      ),
    ));
    if (paid != true) return false;
    // Premium confirmé : on reprend l'action initiale sans repasser par la page précédente.
    try {
      final d = await QuotaService().consume(feature, resourceId: resourceId);
      return d.allowed;
    } catch (_) {
      return false;
    }
  }
}

class PremiumGatePage extends StatefulWidget {
  const PremiumGatePage({
    super.key,
    required this.profile,
    required this.feature,
    this.decision,
    this.premiumOnlyReason = false,
  });

  final UserProfile profile;
  final QuotaFeature feature;
  final QuotaDecision? decision;
  final bool premiumOnlyReason;

  @override
  State<PremiumGatePage> createState() => _PremiumGatePageState();
}

class _PremiumGatePageState extends State<PremiumGatePage> with WidgetsBindingObserver {
  final _quota = QuotaService();
  final _notch = NotchPayService();
  Timer? _poll;
  int _attempts = 0;
  bool _starting = false;
  bool _waiting = false;
  String? _reference;
  String? _error;

  bool get _fr => widget.profile.preferredLanguage != 'en';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour dans l'application après la page Notch Pay : on revérifie côté serveur.
    if (state == AppLifecycleState.resumed && _waiting) _check();
  }

  Future<void> _start() async {
    if (_starting) return;
    final email = widget.profile.email?.trim() ?? '';
    if (email.isEmpty) {
      setState(() => _error = _fr ? 'Aucune adresse e-mail n’est associée à ton compte.' : 'No email is linked to your account.');
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final payment = await _notch.createPayment(
        email: email,
        name: '${widget.profile.firstName} ${widget.profile.lastName}'.trim(),
        amount: 2000,
        description: 'Abonnement Fise School Premium - 30 jours',
      );
      final uri = Uri.tryParse(payment.authorizationUrl);
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) throw Exception('invalid url');
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('cannot open');
      _reference = payment.reference;
      if (!mounted) return;
      setState(() => _waiting = true);
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _check());
    } catch (_) {
      if (mounted) {
        setState(() => _error = _fr
            ? 'Impossible d’ouvrir le paiement. Réessaie dans un instant.'
            : 'Could not open the payment. Please try again shortly.');
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _check() async {
    if (!_waiting) return;
    _attempts++;
    try {
      final status = await _quota.verifyPayment(reference: _reference);
      if (!mounted) return;
      if (status == 'SUCCESS') {
        _poll?.cancel();
        Navigator.of(context).pop(true);
      } else if (status == 'FAILED' || status == 'CANCELED' || status == 'CLOSED') {
        _poll?.cancel();
        setState(() {
          _waiting = false;
          _error = _fr
              ? 'Le paiement n’a pas abouti (refusé, annulé ou expiré). Tu peux réessayer.'
              : 'The payment did not go through (declined, canceled or expired). You can try again.';
        });
      } else if (_attempts >= 36) {
        _poll?.cancel(); // ~3 min : on arrête le sondage, la confirmation tardive reste possible
        setState(() => _waiting = false);
      }
    } catch (_) {/* réseau instable : on réessaie au prochain tick */}
  }

  String _reason() {
    final f = widget.feature.label(_fr);
    if (widget.premiumOnlyReason) {
      return _fr ? '« $f » est réservé aux abonnés Premium.' : '“$f” is reserved for Premium subscribers.';
    }
    final limit = widget.decision?.limit;
    final reset = widget.decision?.resetsAt;
    final hh = reset == null ? null : '${reset.hour.toString().padLeft(2, '0')}h${reset.minute.toString().padLeft(2, '0')}';
    if (_fr) {
      return 'Tu as utilisé ${limit ?? ''} $f gratuit(s) sur 24 h.${hh == null ? '' : ' Prochaine réinitialisation à $hh.'}';
    }
    return 'You have used your ${limit ?? ''} free $f in 24 h.${hh == null ? '' : ' Resets at $hh.'}';
  }

  @override
  Widget build(BuildContext context) {
    final fr = _fr;
    final scheme = Theme.of(context).colorScheme;
    const green = Color(0xFF166534);
    final perks = fr
        ? const [
            'Leçons, QCM et annales sans limite',
            'Questions à l’IA sans limite, avec photos et documents',
            'Messagerie complète : messages, photos, documents',
            'Accès à tous les fichiers des cours (PDF, audio, vidéo)',
          ]
        : const [
            'Unlimited lessons, quizzes and past papers',
            'Unlimited AI questions, with photos and documents',
            'Full messaging: messages, photos, documents',
            'Access to all course files (PDF, audio, video)',
          ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fise School Premium'),
        backgroundColor: green,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 32,
                      backgroundColor: Color(0xFFDCFCE7),
                      child: Icon(Icons.workspace_premium_rounded, color: green, size: 36),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      fr ? 'Passe à Fise School Premium' : 'Go Fise School Premium',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.feature.label(fr),
                      style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary),
                    ),
                    const SizedBox(height: 4),
                    Text(_reason(), textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFFEFFCF3),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text('2 000 FCFA',
                        style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: green)),
                    Text(fr ? 'pour 30 jours' : 'for 30 days',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(
                      fr
                          ? 'Paiement sécurisé par Notch Pay. Activation après confirmation du paiement.'
                          : 'Secure payment by Notch Pay. Activated once the payment is confirmed.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fr ? 'Avantages Premium' : 'Premium benefits',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 8),
                    for (final perk in perks)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.check_circle_rounded, color: green, size: 20),
                            const SizedBox(width: 10),
                            Expanded(child: Text(perk)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      fr
                          ? 'Gratuit : 2 leçons, 2 QCM, 2 annales, 3 questions IA, 2 messages envoyés et 2 reçus par 24 h.'
                          : 'Free: 2 lessons, 2 quizzes, 2 past papers, 3 AI questions, 2 messages sent and 2 received per 24 h.',
                      style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
            ],
            if (_waiting) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(fr
                          ? 'En attente de la confirmation du paiement…'
                          : 'Waiting for payment confirmation…'),
                    ),
                    TextButton(onPressed: _check, child: Text(fr ? 'Vérifier' : 'Check')),
                  ]),
                ),
              ),
            ],
          ],
        ),
      ),
      // Boutons toujours visibles, jamais coupés.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: (_starting || _waiting) ? null : _start,
                  icon: _starting
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.lock_open_rounded),
                  label: Text(fr ? 'Passer à Premium' : 'Upgrade to Premium'),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(fr ? 'Fermer' : 'Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
