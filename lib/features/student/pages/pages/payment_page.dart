import 'package:flutter/material.dart';

import '../../../../core/services/notchpay_service.dart';
import '../../../../models/user_profile.dart';

class PaymentPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const PaymentPage({super.key, required this.locale, required this.profile});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final NotchPayService _notchPayService = NotchPayService();
  final TextEditingController _phoneController = TextEditingController();

  bool _loading = false;
  bool _verifying = false;
  String _provider = 'cm.orange';
  String? _lastReference;
  String? _lastStatus;

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  static const int _subscriptionAmount = 2000;

  Future<void> _startPayment() async {
    if (_loading) return;
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isFrench
            ? 'Saisis le numéro MTN ou Orange à débiter.'
            : 'Enter the MTN or Orange number to charge.'),
      ));
      return;
    }

    setState(() => _loading = true);
    try {
      final payment = await _notchPayService.createPayment(
        amount: _subscriptionAmount,
        currency: 'XAF',
        description: _isFrench
            ? 'Abonnement Fise School Premium — 30 jours'
            : 'Fise School Premium subscription — 30 days',
        channel: _provider,
        phone: phone,
      );
      if (!mounted) return;
      setState(() {
        _lastReference = payment.reference;
        _lastStatus = payment.status.toUpperCase();
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(payment.message),
          behavior: SnackBarBehavior.floating,
        ));
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyPayment() async {
    final reference = _lastReference;
    if (reference == null || _verifying) return;
    setState(() => _verifying = true);
    try {
      final result = await _notchPayService.verifyPayment(reference);
      final status = (result['status'] ?? 'UNKNOWN').toString().toUpperCase();
      if (!mounted) return;
      setState(() => _lastStatus = status);
      final message = status == 'SUCCESS'
          ? (_isFrench
              ? 'Paiement confirmé. Premium est activé.'
              : 'Payment confirmed. Premium is active.')
          : status == 'FAILED'
              ? (_isFrench
                  ? 'Le paiement a échoué ou a été annulé.'
                  : 'Payment failed or was cancelled.')
              : (_isFrench
                  ? 'Paiement encore en attente. Confirme la demande sur ton téléphone puis réessaie.'
                  : 'Payment is still pending. Confirm the request on your phone and try again.');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ));
    } finally {
      if (mounted) setState(() => _verifying = false);
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

                      DropdownButtonFormField<String>(
                        value: _provider,
                        decoration: InputDecoration(
                          labelText: _isFrench ? 'Opérateur de paiement' : 'Payment operator',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                        ),
                        items: [
                          DropdownMenuItem(value: 'cm.orange', child: Text('Orange Money')),
                          DropdownMenuItem(value: 'cm.mtn', child: Text('MTN Mobile Money')),
                        ],
                        onChanged: _loading ? null : (value) {
                          if (value != null) setState(() => _provider = value);
                        },
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: _isFrench ? 'Numéro Mobile Money' : 'Mobile Money number',
                          hintText: '6XXXXXXXX',
                          prefixIcon: const Icon(Icons.phone_android_rounded),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isFrench
                            ? 'Le code unique FISE de l’enseignant est géré dans les groupes et les évaluations. Aucun code enseignant n’est à saisir ici.'
                            : 'The teacher’s unique FISE code is managed by groups and assessments. No teacher code is entered here.',
                        style: const TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                      if (_lastReference != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          '${_isFrench ? 'Référence' : 'Reference'} : $_lastReference\n${_isFrench ? 'État' : 'Status'} : ${_lastStatus ?? 'PENDING'}',
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        OutlinedButton.icon(
                          onPressed: _verifying ? null : _verifyPayment,
                          icon: _verifying
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.verified_outlined),
                          label: Text(_isFrench ? 'Vérifier le paiement' : 'Verify payment'),
                        ),
                      ],
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
