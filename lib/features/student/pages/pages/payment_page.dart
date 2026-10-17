import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/notchpay_service.dart';
import '../../../../models/user_profile.dart';

class PaymentPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const PaymentPage({super.key, required this.locale, required this.profile});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> with WidgetsBindingObserver {
  final NotchPayService _notchPayService = NotchPayService();
  bool _loading = false;
  bool _checkingPremium = true;
  bool? _isPremium;

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPremiumStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPremiumStatus();
    }
  }

  Future<void> _refreshPremiumStatus() async {
    try {
      final result = await Supabase.instance.client.rpc(
        'is_student_premium',
        params: {'p_user_id': widget.profile.id},
      );
      if (mounted) setState(() => _isPremium = result == true);
    } catch (_) {
      if (mounted) setState(() => _isPremium = null);
    } finally {
      if (mounted) setState(() => _checkingPremium = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  static const int _subscriptionAmount = int.fromEnvironment(
    'FISE_SUBSCRIPTION_AMOUNT',
    defaultValue: 2000,
  );

  Future<void> _startPayment() async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final email = widget.profile.email?.trim();

      if (email == null || email.isEmpty) {
        throw Exception(
          _isFrench
              ? 'Une adresse e-mail est nécessaire pour commencer le paiement.'
              : 'An email address is required to start the payment.',
        );
      }

      final name = '${widget.profile.firstName} ${widget.profile.lastName}'
          .trim();

      final payment = await _notchPayService.createPayment(
        email: email,
        name: name.isEmpty ? 'Fise School Student' : name,
        amount: _subscriptionAmount,
        currency: 'XAF',
        description: _isFrench
            ? 'Abonnement Fise School Premium - 30 jours'
            : 'Fise School Premium subscription - 30 days',
      );

      final paymentUrl = payment.authorizationUrl.trim();

      if (paymentUrl.isEmpty) {
        throw Exception(
          _isFrench
              ? 'Aucune adresse de paiement n’a été reçue.'
              : 'No payment address was received.',
        );
      }

      final uri = Uri.tryParse(paymentUrl);

      if (uri == null ||
          !uri.hasScheme ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        throw Exception(
          _isFrench
              ? 'L’adresse de paiement reçue est invalide.'
              : 'The payment address received is invalid.',
        );
      }

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        throw Exception(
          _isFrench
              ? 'Impossible d’ouvrir la page de paiement.'
              : 'Unable to open the payment page.',
        );
      }
      // The subscription is activated by the verified Notch Pay callback only.
      // Re-check on return to the app; never activate Premium from the client.
    } catch (error) {
      if (!mounted) {
        return;
      }

      final message = error.toString().replaceFirst('Exception: ', '');

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isFrench ? 'Paiement Fise School' : 'Fise School payment',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      backgroundColor: const Color(0xFFF5F8F6),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_checkingPremium || _isPremium == true)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _isPremium == true ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(_isPremium == true ? Icons.verified_rounded : Icons.sync_rounded,
                                  color: const Color(0xFF166534)),
                              const SizedBox(width: 10),
                              Expanded(child: Text(_isPremium == true
                                  ? (_isFrench ? 'Premium est actif sur ton compte.' : 'Premium is active on your account.')
                                  : (_isFrench ? 'Vérification de ton abonnement…' : 'Checking your subscription…'))),
                            ],
                          ),
                        ),
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.payment_rounded,
                          color: Color(0xFF166534),
                          size: 38,
                        ),
                      ),

                      const SizedBox(height: 20),

                      Text(
                        _isFrench
                            ? 'Abonnement Fise School'
                            : 'Fise School subscription',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        _isFrench
                            ? 'Accède aux fonctionnalités réservées aux abonnés.'
                            : 'Access features reserved for subscribers.',
                        style: const TextStyle(
                          color: Colors.black54,
                          height: 1.4,
                        ),
                      ),

                      const SizedBox(height: 24),

                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _isFrench ? 'Montant' : 'Amount',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              '$_subscriptionAmount XAF',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF166534),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      Text(
                        _isFrench
                            ? 'Les enseignants scientifique et littéraire affectés à ta salle reçoivent chacun 200 FCFA après confirmation du paiement. Le solde revient à Fise School.'
                            : 'The scientific and literary teachers assigned to your classroom each receive 200 XAF after payment confirmation. The remainder goes to Fise School.',
                        style: const TextStyle(color: Colors.black54, fontSize: 12, height: 1.4),
                      ),

                      const SizedBox(height: 24),

                      FilledButton.icon(
                        onPressed: _loading ? null : _startPayment,
                        icon: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.lock_rounded),
                        label: Text(
                          _loading
                              ? (_isFrench
                                    ? 'Préparation du paiement...'
                                    : 'Preparing payment...')
                              : (_isFrench ? 'Payer maintenant' : 'Pay now'),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: const Color(0xFF166534),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
