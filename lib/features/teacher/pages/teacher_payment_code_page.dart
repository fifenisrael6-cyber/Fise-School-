import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  bool _loading = true;
  String? _code;
  int _balance = 0;
  String? _vocation;
  bool _savingVocation = false;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Always load the canonical shared FISE code. This RPC also synchronizes
      // the legacy payment-code row, so group access and payments use one code.
      final sharedCode = await _service.createOrGetCode();
      final balance = await _service.getWalletBalance();
      final vocationRow = await Supabase.instance.client
          .from('profiles').select('teacher_vocation')
          .eq('id', widget.profile.id).maybeSingle();
      if (mounted) {
        setState(() {
          _code = sharedCode.trim().toUpperCase();
          _balance = balance;
          _vocation = vocationRow?['teacher_vocation']?.toString();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _fr
                  ? 'Impossible de charger votre code unique FISE. Vérifiez votre connexion puis réessayez.'
                  : 'Unable to load your unique FISE code. Check your connection and try again.',
            ),
          ),
        );
      }
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    setState(() => _loading = true);
    try {
      final code = await _service.createOrGetCode();
      if (mounted) {
        setState(() => _code = code);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _fr
                  ? 'Impossible de récupérer le code unique FISE. Réessayez.'
                  : 'Unable to retrieve the unique FISE code. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveVocation(String? value) async {
    if (value == null || _savingVocation) return;
    setState(() => _savingVocation = true);
    try {
      await Supabase.instance.client.rpc(
        'set_my_teacher_vocation',
        params: {'p_vocation': value},
      );
      if (mounted) {
        setState(() => _vocation = value);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_fr ? 'Filière enseignée enregistrée.' : 'Teaching stream saved.'),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_fr ? 'Impossible d’enregistrer la filière.' : 'Unable to save the teaching stream.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _savingVocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_fr ? 'Code de paiement enseignant' : 'Teacher payment code')),
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
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _fr ? 'Filière enseignée (obligatoire pour les commissions Premium)'
                            : 'Teaching stream (required for Premium commissions)',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _vocation,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: _fr ? 'Filière' : 'Teaching stream',
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'scientific',
                          child: Text(_fr ? 'Scientifique' : 'Scientific'),
                        ),
                        DropdownMenuItem(
                          value: 'literary',
                          child: Text(_fr ? 'Littéraire' : 'Literary'),
                        ),
                      ],
                      onChanged: _savingVocation ? null : _saveVocation,
                    ),
                    if (_savingVocation)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      _fr ? 'Votre code unique' : 'Your unique code',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _fr
                          ? 'Partagez ce code aux élèves qui souhaitent payer Premium en vous désignant comme enseignant référent. Après un paiement réussi, 200 FCFA sont crédités dans votre portefeuille.'
                          : 'Share this code with students who choose to pay Premium with you as their teacher. After a successful payment, 200 XAF are credited to your wallet.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else if (_code == null)
                      FilledButton.icon(
                        onPressed: _create,
                        icon: const Icon(Icons.add_link_rounded),
                        label: Text(_fr ? 'Créer mon code' : 'Create my code'),
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
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 2),
                        ),
                      ),
                    if (_code != null) ...[
                      const SizedBox(height: 18),
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
                            Expanded(
                              child: Text(_fr ? 'Solde enseignant' : 'Teacher balance'),
                            ),
                            Text('$_balance XAF', style: const TextStyle(fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    ],
                    if (_code != null) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await _create();
                        },
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(_fr ? 'Récupérer mon code' : 'Refresh my code'),
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
