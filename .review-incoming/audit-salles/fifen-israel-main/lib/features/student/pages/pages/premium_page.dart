import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/notchpay_service.dart';
import '../../../../core/services/quota_service.dart';
import '../../../../core/services/subscription_service.dart';
import '../../../../models/user_profile.dart';

class PremiumPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const PremiumPage({super.key, required this.locale, required this.profile});

  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
  final SubscriptionService _subscriptionService = SubscriptionService();

  final NotchPayService _notchPayService = NotchPayService();

  SubscriptionInfo? _subscriptionInfo;
  QuotaStatus? _quota;

  bool _loading = true;
  bool _processingPayment = false;

  @override
  void initState() {
    super.initState();
    _loadSubscription();
  }

  Future<void> _loadSubscription() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      // Retour tardif : si un paiement est en attente, on le revérifie auprès de Notch Pay.
      try {
        await QuotaService().verifyPayment();
      } catch (_) {}
      try {
        _quota = await QuotaService().status();
      } catch (_) {}
      final info = await _subscriptionService.getSubscriptionInfo();

      if (!mounted) {
        return;
      }

      setState(() {
        _subscriptionInfo = info;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _subscriptionInfo = const SubscriptionInfo(
          plan: 'free',
          isPremium: false,
          status: 'free',
          expiresAt: null,
          remainingDays: 0,
        );

        _loading = false;
      });
    }
  }

  Future<void> _startPremiumPayment() async {
    if (_processingPayment) {
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      _showMessage(
        widget.locale.languageCode == 'fr'
            ? 'Tu dois être connecté pour effectuer un paiement.'
            : 'You must be signed in to make a payment.',
      );

      return;
    }

    final email = user.email?.trim();

    if (email == null || email.isEmpty) {
      _showMessage(
        widget.locale.languageCode == 'fr'
            ? 'Aucune adresse e-mail n’est associée à ton compte.'
            : 'No email address is associated with your account.',
      );

      return;
    }

    setState(() {
      _processingPayment = true;
    });

    try {
      final metadata = user.userMetadata;

      final metadataName =
          metadata?['full_name'] ??
          metadata?['name'] ??
          metadata?['display_name'];

      final name = metadataName is String && metadataName.trim().isNotEmpty
          ? metadataName.trim()
          : 'Fise School Student';

      final payment = await _notchPayService.createPayment(
        email: email,
        name: name,
        amount: 2000,
        currency: 'XAF',
        description: 'Abonnement Fise School Premium - 30 jours',
      );

      if (!mounted) {
        return;
      }

      final authorizationUrl = payment.authorizationUrl;

      if (authorizationUrl.trim().isEmpty) {
        _showMessage(
          widget.locale.languageCode == 'fr'
              ? 'Le lien de paiement est vide.'
              : 'The payment link is empty.',
        );

        return;
      }

      final url = Uri.tryParse(authorizationUrl);

      if (url == null || !url.hasScheme || !url.hasAuthority) {
        _showMessage(
          widget.locale.languageCode == 'fr'
              ? 'Le lien de paiement reçu est invalide.'
              : 'The payment link received is invalid.',
        );

        return;
      }

      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);

      if (!mounted) {
        return;
      }

      if (!opened) {
        _showMessage(
          widget.locale.languageCode == 'fr'
              ? 'Impossible d’ouvrir la page de paiement.'
              : 'Unable to open the payment page.',
        );

        return;
      }

      _showMessage(
        widget.locale.languageCode == 'fr'
            ? 'La page de paiement a été ouverte. Après le paiement, actualise ton abonnement.'
            : 'The payment page has been opened. After payment, refresh your subscription.',
      );
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        widget.locale.languageCode == 'fr'
            ? 'Session utilisateur invalide : ${error.message}'
            : 'Invalid user session: ${error.message}',
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showMessage(
        widget.locale.languageCode == 'fr'
            ? 'Une erreur est survenue pendant le paiement.'
            : 'An error occurred during payment.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingPayment = false;
        });
      }
    }
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';

  List<Widget> _statusAndQuotas(bool fr) {
    final q = _quota;
    if (q == null) return const [];
    final label = switch (q.state) {
      'premium' => fr
          ? 'Premium actif${q.premiumExpiresAt == null ? '' : ' jusqu’au ${_fmt(q.premiumExpiresAt!)}'}'
          : 'Premium active${q.premiumExpiresAt == null ? '' : ' until ${_fmt(q.premiumExpiresAt!)}'}',
      'pending' => fr ? 'Paiement en attente de confirmation' : 'Payment awaiting confirmation',
      'expired' => fr ? 'Abonnement expiré' : 'Subscription expired',
      _ => fr ? 'Compte gratuit' : 'Free account',
    };
    final widgets = <Widget>[
      Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    ];
    if (!q.premium) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(Text(fr ? 'Quotas gratuits (par période de 24 h)' : 'Free quotas (per 24 h)',
          style: const TextStyle(fontWeight: FontWeight.w700)));
      for (final f in QuotaFeature.values) {
        final item = q.quotas[f.key];
        if (item == null) continue;
        final reset = item.resetsAt == null
            ? ''
            : (fr ? ' • renouvelé le ${_fmt(item.resetsAt!)}' : ' • resets ${_fmt(item.resetsAt!)}');
        widgets.add(Text('${f.label(fr)} : ${item.remaining}/${item.limit}$reset'));
      }
    }
    return widgets;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isFrench = widget.locale.languageCode == 'fr';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Fise School Premium',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadSubscription,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStatusCard(isFrench: isFrench),
                      const SizedBox(height: 18),
                      _buildFeaturesCard(isFrench: isFrench),
                      const SizedBox(height: 18),
                      _buildPaymentCard(isFrench: isFrench),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildStatusCard({required bool isFrench}) {
    final info = _subscriptionInfo;

    if (info != null && info.isPremium) {
      final expiration = info.expiresAt;

      String expirationText = '';

      if (expiration != null) {
        final day = expiration.day.toString().padLeft(2, '0');

        final month = expiration.month.toString().padLeft(2, '0');

        final year = expiration.year.toString();

        expirationText = isFrench
            ? 'Expire le $day/$month/$year'
            : 'Expires on $day/$month/$year';
      }

      return Card(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF166534), Color(0xFF15803D)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isFrench
                          ? 'Abonnement Premium actif'
                          : 'Premium subscription active',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isFrench
                          ? '${info.remainingDays} jour(s) restant(s)'
                          : '${info.remainingDays} day(s) remaining',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (expirationText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        expirationText,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.lock_open_rounded,
                color: Color(0xFF166534),
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isFrench ? 'Mode gratuit' : 'Free plan',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    isFrench
                        ? 'Passe à Premium pour débloquer davantage de fonctionnalités.'
                        : 'Upgrade to Premium to unlock more features.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturesCard({required bool isFrench}) {
    final features = isFrench
        ? <String>[
            'Accès aux contenus Premium',
            'Cours et ressources supplémentaires',
            'Fonctionnalités pédagogiques avancées',
            'Exercices et révisions enrichis',
            'Expérience Fise School Premium',
          ]
        : <String>[
            'Access to Premium content',
            'Additional courses and resources',
            'Advanced learning features',
            'Enhanced exercises and revision',
            'Fise School Premium experience',
          ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isFrench ? 'Fonctionnalités Premium' : 'Premium features',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            ...features.map(
              (feature) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF166534),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        feature,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentCard({required bool isFrench}) {
    final isPremium = _subscriptionInfo?.isPremium ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.payments_rounded,
                  color: Color(0xFF166534),
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isFrench ? 'Abonnement Premium' : 'Premium subscription',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              isFrench
                  ? '2 000 FCFA pour 30 jours de Premium.'
                  : '2,000 XAF for 30 days of Premium.',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              isFrench
                  ? 'Le paiement est effectué de manière sécurisée via Notch Pay.'
                  : 'Payment is securely processed through Notch Pay.',
            ),
            const SizedBox(height: 12),
            ..._statusAndQuotas(isFrench),
            const SizedBox(height: 18),
            if (isPremium)
              OutlinedButton.icon(
                onPressed: _loadSubscription,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(
                  isFrench
                      ? 'Actualiser mon abonnement'
                      : 'Refresh my subscription',
                ),
              )
            else
              FilledButton.icon(
                onPressed: _processingPayment ? null : _startPremiumPayment,
                icon: _processingPayment
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.lock_open_rounded),
                label: Text(
                  _processingPayment
                      ? isFrench
                            ? 'Ouverture du paiement...'
                            : 'Opening payment...'
                      : isFrench
                      ? 'Activer Premium — 2 000 FCFA'
                      : 'Activate Premium — 2,000 XAF',
                ),
              ),
            const SizedBox(height: 10),
            Text(
              isFrench
                  ? 'Après le paiement, actualise ton abonnement pour vérifier son activation.'
                  : 'After payment, refresh your subscription to check its activation.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
