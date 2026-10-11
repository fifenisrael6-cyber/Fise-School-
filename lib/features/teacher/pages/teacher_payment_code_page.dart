import 'package:flutter/material.dart';

import '../../../core/services/teacher_payment_code_service.dart';
import '../../../models/user_profile.dart';

class TeacherPaymentCodePage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const TeacherPaymentCodePage({
    super.key,
    required this.locale,
    required this.profile,
  });

  @override
  State<TeacherPaymentCodePage> createState() => _TeacherPaymentCodePageState();
}

class _TeacherPaymentCodePageState extends State<TeacherPaymentCodePage> {
  final TeacherPaymentCodeService _service = TeacherPaymentCodeService();
  bool _loading = true;
  String? _code;
  int _balance = 0;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final existing = await _service.getOwnCode();
      final balance = await _service.getWalletBalance();
      if (!mounted) return;
      setState(() {
        _code = existing != null && existing['active'] == true
            ? existing['code']?.toString()
            : null;
        _balance = balance;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_fr
              ? 'Impossible de charger votre code partagé. Réessayez.'
              : 'Unable to load your shared code. Try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'Code unique et paiements' : 'Shared code and payments'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.qr_code_2_rounded,
                        size: 64, color: Color(0xFF166534)),
                    const SizedBox(height: 18),
                    Text(
                      _fr ? 'Votre code unique' : 'Your shared code',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _fr
                          ? 'Le code affiché ici est exactement le même que celui utilisé pour la messagerie privée et les groupes. Créez ou modifiez votre code vous-même dans la page « Code unique ».'
                          : 'The code shown here is exactly the same one used for private messages and groups. Create or change it yourself on the “Shared code” page.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else if (_code == null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _fr
                              ? 'Aucun code partagé n’est encore enregistré. Ouvrez la page « Code unique », choisissez votre propre code, puis revenez ici. Aucun code ne sera généré automatiquement.'
                              : 'No shared code is registered yet. Open the “Shared code” page and choose your own code, then return here. No code will be generated automatically.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: SelectableText(
                          _code!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    if (!_loading && _code != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.account_balance_wallet_outlined,
                                color: Color(0xFF166534)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                  _fr ? 'Solde enseignant' : 'Teacher balance'),
                            ),
                            Text('$_balance XAF',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(_fr
                          ? 'Actualiser le code et le solde'
                          : 'Refresh code and balance'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
