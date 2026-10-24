import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/notchpay_service.dart';
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

  bool _loading = true;
  bool _processingPayment = false;
  bool _verifyingPayment = false;
  final TextEditingController _phoneController = TextEditingController();
  String _paymentChannel = 'cm.orange';
  String? _paymentReference;
  String? _paymentStatus;

  @override
  void initState() {
    super.initState();
    _loadSubscription();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadSubscription() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
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
    if (_processingPayment) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _showMessage(widget.locale.languageCode == 'fr'
          ? 'Tu dois être connecté pour effectuer un paiement.'
          : 'You must be signed in to make a payment.');
      return;
    }

    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showMessage(widget.locale.languageCode == 'fr'
          ? 'Saisis le numéro MTN ou Orange à débiter.'
          : 'Enter the MTN or Orange number to charge.');
      return;
    }

    setState(() => _processingPayment = true);
    try {
      final payment = await _notchPayService.createPayment(
        amount: 2000,
        currency: 'XAF',
        description: 'Abonnement Fise School Premium - 30 jours',
        channel: _paymentChannel,
        phone: phone,
      );
      if (!mounted) return;
      setState(() {
        _paymentReference = payment.reference;
        _paymentStatus = payment.status.toUpperCase();
      });
      _showMessage(payment.message);
    } on AuthException catch (error) {
      if (mounted) {
        _showMessage(widget.locale.languageCode == 'fr'
            ? 'Session utilisateur invalide : ${error.message}'
            : 'Invalid user session: ${error.message}');
      }
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _processingPayment = false);
    }
  }

  Future<void> _verifyPremiumPayment() async {
    final reference = _paymentReference;
    if (reference == null || _verifyingPayment) return;
    setState(() => _verifyingPayment = true);
    try {
      final result = await _notchPayService.verifyPayment(reference);
      final status = (result['status'] ?? 'UNKNOWN').toString().toUpperCase();
      if (!mounted) return;
      setState(() => _paymentStatus = status);
      await _loadSubscription();
      if (!mounted) return;
      _showMessage(status == 'SUCCESS'
          ? (widget.locale.languageCode == 'fr'
              ? 'Paiement confirmé. Ton abonnement Premium est activé.'
              : 'Payment confirmed. Your Premium subscription is active.')
          : status == 'FAILED'
              ? (widget.locale.languageCode == 'fr'
                  ? 'Le paiement a échoué ou a été annulé.'
                  : 'Payment failed or was cancelled.')
              : (widget.locale.languageCode == 'fr'
                  ? 'Paiement toujours en attente. Confirme la demande sur ton téléphone puis réessaie.'
                  : 'Payment is still pending. Confirm the request on your phone and try again.'));
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _verifyingPayment = false);
    }
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
                  ? '2000 FCFA pour 30 jours de Premium.'
                  : '2000 XAF for 30 days of Premium.',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              isFrench
                  ? 'Le paiement est effectué de manière sécurisée via Notch Pay.'
                  : 'Payment is securely processed through Notch Pay.',
            ),
            const SizedBox(height: 18),
            if (!isPremium) ...[
              DropdownButtonFormField<String>(
                value: _paymentChannel,
                decoration: InputDecoration(
                  labelText: isFrench ? 'Opérateur de paiement' : 'Payment operator',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'cm.orange', child: Text('Orange Money')),
                  DropdownMenuItem(value: 'cm.mtn', child: Text('MTN Mobile Money')),
                ],
                onChanged: _processingPayment ? null : (value) {
                  if (value != null) setState(() => _paymentChannel = value);
                },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: isFrench ? 'Numéro Mobile Money' : 'Mobile Money number',
                  hintText: '6XXXXXXXX',
                  prefixIcon: const Icon(Icons.phone_android_rounded),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isFrench
                    ? 'Le code unique FISE de l’enseignant est géré dans les groupes, paiements et évaluations. Aucun code enseignant n’est à saisir ici.'
                    : 'The teacher’s unique FISE code is managed by the system for groups, payments and assessments. Do not enter a teacher code here.',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
            if (_paymentReference != null) ...[
              const SizedBox(height: 12),
              Text(
                '${isFrench ? 'Référence' : 'Reference'} : $_paymentReference\n${isFrench ? 'État' : 'Status'} : ${_paymentStatus ?? 'PENDING'}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              OutlinedButton.icon(
                onPressed: _verifyingPayment ? null : _verifyPremiumPayment,
                icon: _verifyingPayment
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.verified_outlined),
                label: Text(isFrench ? 'Vérifier le paiement' : 'Verify payment'),
              ),
            ],
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
                      ? 'Activer Premium — 2000 FCFA'
                      : 'Activate Premium — 2000 XAF',
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
