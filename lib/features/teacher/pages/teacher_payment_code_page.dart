import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/teacher_payment_code_service.dart';
import '../../../models/user_profile.dart';

class TeacherPaymentCodePage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const TeacherPaymentCodePage({super.key, required this.locale, required this.profile});

  @override
  State<TeacherPaymentCodePage> createState() => _TeacherPaymentCodePageState();
}

class _TeacherPaymentCodePageState extends State<TeacherPaymentCodePage> {
  final _service = TeacherPaymentCodeService();
  final _codeController = TextEditingController();
  bool _loading = true;
  bool _editing = false;
  String? _code;
  int _balance = 0;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final existing = await _service.getOwnCode();
      _balance = await _service.getWalletBalance();
      if (existing != null && existing['active'] == true) {
        _code = existing['code']?.toString();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_fr
              ? 'Impossible de charger le code FISE. Réessayez plus tard.'
              : 'Unable to load the FISE code. Please try again later.')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final value = _codeController.text.trim().toUpperCase();
    if (!RegExp(r'^(FISE-?)?[A-Z0-9]{6}
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_fr
            ? 'Choisissez exactement 6 lettres ou chiffres, avec ou sans le préfixe FISE-.'
            : 'Choose exactly 6 letters or numbers, with or without the FISE- prefix.')),
      );
      return;
    }

    final normalized = value.startsWith('FISE-')
        ? value
        : value.startsWith('FISE')
            ? 'FISE-${value.substring(4)}'
            : 'FISE-$value';

    setState(() => _loading = true);
    try {
      final saved = await _service.saveCode(normalized);
      if (mounted) {
        setState(() {
          _code = saved;
          _editing = false;
          _codeController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_fr ? 'Votre code unique FISE est enregistré.' : 'Your unique FISE code has been saved.')),
        );
      }
    } catch (error) {
      if (mounted) {
        final raw = error.toString();
        final message = raw.contains('already used')
            ? (_fr ? 'Ce code est déjà utilisé par un autre enseignant.' : 'This code is already used by another teacher.')
            : (_fr ? 'Impossible d’enregistrer ce code. Vérifiez le format.' : 'Unable to save this code. Check the format.');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_fr ? 'Mon code unique FISE' : 'My unique FISE code')),
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
                    const Icon(Icons.qr_code_2_rounded, size: 64, color: Color(0xFF166534)),
                    const SizedBox(height: 18),
                    Text(
                      _fr ? 'Un seul code pour les groupes, paiements et évaluations' : 'One code for groups, payments and evaluations',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _fr
                          ? 'Créez vous-même votre code. Les élèves doivent utiliser ce code pour accéder à vos groupes et évaluations et pour vous désigner lors d’un paiement Premium. Les publications ordinaires de la salle restent accessibles à tous les élèves de cette salle. Le code ne confirme jamais un paiement à lui seul.'
                          : 'Choose your own code. Students must use this code to access your groups and evaluations and to identify you for a Premium payment. Ordinary classroom posts remain available to every student in that classroom. The code alone never confirms a payment.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else if (_code == null || _editing) ...[
                      TextField(
                        controller: _codeController,
                        autofocus: _editing,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]'))],
                        decoration: InputDecoration(
                          labelText: _fr ? 'Le code que vous choisissez' : 'Your chosen code',
                          hintText: 'FISE-AB12CD',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_rounded),
                        label: Text(_fr ? 'Enregistrer mon code' : 'Save my code'),
                      ),
                      if (_editing)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _editing = false;
                              _codeController.clear();
                            });
                          },
                          child: Text(_fr ? 'Annuler' : 'Cancel'),
                        ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: SelectableText(
                          _code!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 2),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: _code!));
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(_fr ? 'Code copié.' : 'Code copied.')),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_rounded),
                        label: Text(_fr ? 'Copier le code' : 'Copy code'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          _codeController.text = _code!;
                          setState(() => _editing = true);
                        },
                        icon: const Icon(Icons.edit_rounded),
                        label: Text(_fr ? 'Modifier mon code' : 'Change my code'),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF166534)),
                            const SizedBox(width: 12),
                            Expanded(child: Text(_fr ? 'Solde enseignant' : 'Teacher balance')),
                            Text('$_balance XAF', style: const TextStyle(fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    ],
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
).hasMatch(value)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_fr
            ? 'Choisissez 4 à 12 lettres ou chiffres, avec ou sans le préfixe FISE-.'
            : 'Choose 4 to 12 letters or numbers, with or without the FISE- prefix.')),
      );
      return;
    }

    final normalized = value.startsWith('FISE-')
        ? value
        : value.startsWith('FISE')
            ? 'FISE-${value.substring(4)}'
            : 'FISE-$value';

    setState(() => _loading = true);
    try {
      final saved = await _service.saveCode(normalized);
      if (mounted) {
        setState(() {
          _code = saved;
          _editing = false;
          _codeController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_fr ? 'Votre code unique FISE est enregistré.' : 'Your unique FISE code has been saved.')),
        );
      }
    } catch (error) {
      if (mounted) {
        final raw = error.toString();
        final message = raw.contains('already used')
            ? (_fr ? 'Ce code est déjà utilisé par un autre enseignant.' : 'This code is already used by another teacher.')
            : (_fr ? 'Impossible d’enregistrer ce code. Vérifiez le format.' : 'Unable to save this code. Check the format.');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_fr ? 'Mon code unique FISE' : 'My unique FISE code')),
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
                    const Icon(Icons.qr_code_2_rounded, size: 64, color: Color(0xFF166534)),
                    const SizedBox(height: 18),
                    Text(
                      _fr ? 'Un seul code pour vos groupes et paiements' : 'One code for your groups and payments',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _fr
                          ? 'Créez vous-même votre code. Les élèves peuvent l’utiliser pour retrouver les groupes auxquels leur classe a droit et pour vous désigner lors d’un paiement Premium. Le code ne confirme jamais un paiement à lui seul.'
                          : 'Choose your own code. Students can use it to find groups their classroom is allowed to join and to identify you for a Premium payment. The code alone never confirms a payment.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else if (_code == null || _editing) ...[
                      TextField(
                        controller: _codeController,
                        autofocus: _editing,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]'))],
                        decoration: InputDecoration(
                          labelText: _fr ? 'Le code que vous choisissez' : 'Your chosen code',
                          hintText: 'FISE-AB12CD',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_rounded),
                        label: Text(_fr ? 'Enregistrer mon code' : 'Save my code'),
                      ),
                      if (_editing)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _editing = false;
                              _codeController.clear();
                            });
                          },
                          child: Text(_fr ? 'Annuler' : 'Cancel'),
                        ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: SelectableText(
                          _code!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 2),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: _code!));
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(_fr ? 'Code copié.' : 'Code copied.')),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_rounded),
                        label: Text(_fr ? 'Copier le code' : 'Copy code'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          _codeController.text = _code!;
                          setState(() => _editing = true);
                        },
                        icon: const Icon(Icons.edit_rounded),
                        label: Text(_fr ? 'Modifier mon code' : 'Change my code'),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF166534)),
                            const SizedBox(width: 12),
                            Expanded(child: Text(_fr ? 'Solde enseignant' : 'Teacher balance')),
                            Text('$_balance XAF', style: const TextStyle(fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    ],
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
