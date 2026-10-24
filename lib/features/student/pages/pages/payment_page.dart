import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/services/notchpay_service.dart';
import '../../../../models/user_profile.dart';
import '../../../../core/services/teacher_payment_code_service.dart';

class PaymentPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const PaymentPage({super.key, required this.locale, required this.profile});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final NotchPayService _notchPayService = NotchPayService();
  final TeacherPaymentCodeService _teacherCodeService = TeacherPaymentCodeService();
  final TextEditingController _teacherCodeController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  String _channel = 'cm.mtn';

  bool _loading = false;
  String? _teacherId;

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void dispose() {
    _teacherCodeController.dispose();
    _phoneController.dispose();
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

      final phone = _phoneController.text.trim();
      if (phone.length != 9 || int.tryParse(phone) == null || !phone.startsWith('6')) {
        throw Exception(_isFrench ? 'Entre un numéro camerounais valide à 9 chiffres commençant par 6.' : 'Enter a valid 9-digit Cameroon phone number starting with 6.');
      }

      final teacherCode = _teacherCodeController.text.trim();
      if (teacherCode.isNotEmpty) {
        _teacherId = await _teacherCodeService.resolveTeacherId(teacherCode);
        if (_teacherId == null) {
          throw Exception(
            _isFrench ? 'Code enseignant invalide.' : 'Invalid teacher code.',
          );
        }
      }

      final name = '${widget.profile.firstName} ${widget.profile.lastName}'
          .trim();

      final payment = await _notchPayService.createPayment(
        email: email,
        name: name.isEmpty ? 'Fise School Student' : name,
        amount: _subscriptionAmount,
        currency: 'XAF',
        description: _isFrench
            ? 'Abonnement Fise School'
            : 'Fise School subscription',
        teacherCode: teacherCode.isEmpty ? null : teacherCode,
        channel: _channel,
        phone: phone,
      );

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(_isFrench
                ? 'Demande envoyée. Confirme le paiement sur ton téléphone.'
                : 'Request sent. Confirm the payment on your phone.'),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ));
      }

      // Vérification côté serveur : l'application ne marque jamais elle-même
      // une commande comme payée.
      for (var attempt = 0; attempt < 30; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 4));
        if (!mounted) return;
        final verification = await _notchPayService.verifyPayment(payment.reference);
        final status = (verification['status'] ?? 'PENDING').toString().toUpperCase();
        if (status == 'SUCCESS') {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(_isFrench
                  ? 'Paiement confirmé ! Ton abonnement Premium est activé.'
                  : 'Payment confirmed! Your Premium subscription is active.'),
              duration: const Duration(seconds: 3),
            ));
          await Future<void>.delayed(const Duration(seconds: 2));
          if (mounted) Navigator.of(context).pop();
          return;
        }
        if (['FAILED', 'CANCELED', 'CLOSED'].contains(status)) {
          throw Exception(_isFrench
              ? 'Le paiement a été refusé, annulé ou a expiré. Tu peux réessayer.'
              : 'Payment was declined, canceled, or expired. You can try again.');
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(_isFrench
                ? 'Paiement toujours en attente. Tu peux revenir dans Premium pour vérifier son état.'
                : 'Payment is still pending. Return to Premium to check its status.'),
            duration: const Duration(seconds: 6),
          ));
      }
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
                        value: _channel,
                        decoration: InputDecoration(labelText: _isFrench ? 'Choisir le mode de paiement' : 'Choose payment method', prefixIcon: const Icon(Icons.account_balance_wallet_outlined), border: const OutlineInputBorder()),
                        items: const [DropdownMenuItem(value: 'cm.mtn', child: Text('MTN Mobile Money')), DropdownMenuItem(value: 'cm.orange', child: Text('Orange Money'))],
                        onChanged: _loading ? null : (value) { if (value != null) setState(() => _channel = value); },
                      ),
                      const SizedBox(height: 16),
                      TextField(controller: _phoneController, keyboardType: TextInputType.phone, maxLength: 9, decoration: InputDecoration(labelText: _isFrench ? 'Numéro Mobile Money' : 'Mobile Money phone number', hintText: '6XXXXXXXX', prefixText: '+237 ', prefixIcon: const Icon(Icons.phone_android_rounded), border: const OutlineInputBorder(), counterText: '')),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _teacherCodeController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: _isFrench ? 'Code de l’enseignant (facultatif)' : 'Teacher code (optional)',
                          hintText: 'FISE-XXXXXXXX',
                          prefixIcon: const Icon(Icons.badge_outlined),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isFrench
                            ? 'Si vous utilisez le code d’un enseignant et que le paiement réussit, 200 FCFA sont crédités à son portefeuille.'
                            : 'If you use a teacher code and the payment succeeds, 200 XAF are credited to the teacher wallet.',
                        style: const TextStyle(color: Colors.black54, fontSize: 12),
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
