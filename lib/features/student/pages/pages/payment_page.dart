import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

  bool _loading = false;
  String? _teacherId;

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void dispose() {
    _teacherCodeController.dispose();
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
