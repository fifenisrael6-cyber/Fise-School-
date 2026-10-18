import '../../../core/services/auth_messages.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ForgotPasswordPage extends StatefulWidget {
  final Locale locale;

  const ForgotPasswordPage({super.key, required this.locale});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _sent = false;

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendLink() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _emailController.text.trim().toLowerCase(),
        redirectTo: 'fiseschool://reset-password',
      );
      if (!mounted) return;
      setState(() => _sent = true);
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AuthMessages.from(error, english: !_isFrench),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFrench
                ? 'Impossible d’envoyer le lien. Vérifie ta connexion et réessaie.'
                : 'Unable to send the link. Check your connection and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
        title: Text(_isFrench ? 'Mot de passe oublié' : 'Forgot password'),
      ),
      backgroundColor: const Color(0xFFF5F8F6),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: _sent
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Icon(
                              Icons.mark_email_read_outlined,
                              size: 56,
                              color: Color(0xFF166534),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _isFrench
                                  ? 'Vérifie ta boîte e-mail'
                                  : 'Check your email',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _isFrench
                                  ? 'Si cette adresse est associée à un compte, un lien de réinitialisation a été envoyé. Ouvre-le sur cet appareil pour choisir un nouveau mot de passe.'
                                  : 'If this address is associated with an account, a reset link has been sent. Open it on this device to choose a new password.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(_isFrench
                                  ? 'Retour à la connexion'
                                  : 'Back to sign in'),
                            ),
                          ],
                        )
                      : Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Icon(
                                Icons.lock_reset_rounded,
                                size: 54,
                                color: Color(0xFF166534),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _isFrench
                                    ? 'Réinitialiser mon mot de passe'
                                    : 'Reset my password',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _isFrench
                                    ? 'Saisis l’adresse e-mail de ton compte Fise School. Nous t’enverrons un lien pour choisir un nouveau mot de passe.'
                                    : 'Enter the email address for your Fise School account. We will send you a link to choose a new password.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 22),
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autocorrect: false,
                                decoration: InputDecoration(
                                  labelText: _isFrench
                                      ? 'Adresse e-mail'
                                      : 'Email address',
                                  prefixIcon: const Icon(Icons.email_outlined),
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  final email = (value ?? '').trim();
                                  if (email.isEmpty ||
                                      !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$')
                                          .hasMatch(email)) {
                                    return _isFrench
                                        ? 'Saisis une adresse e-mail valide.'
                                        : 'Enter a valid email address.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: _isLoading ? null : _sendLink,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF166534),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(_isFrench
                                        ? 'Envoyer le lien'
                                        : 'Send reset link'),
                              ),
                            ],
                          ),
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
