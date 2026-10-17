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
  final _withdrawalAmountController = TextEditingController();
  final _withdrawalPhoneController = TextEditingController();
  String _withdrawalProvider = 'cm.orange';
  bool _withdrawing = false;
  List<Map<String, dynamic>> _withdrawals = const [];
  String? _vocation;
  bool _savingVocation = false;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void dispose() {
    _withdrawalAmountController.dispose();
    _withdrawalPhoneController.dispose();
    super.dispose();
  }

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
      final withdrawals = await _service.listWithdrawalRequests();
      final vocationRow = await Supabase.instance.client
          .from('profiles').select('teacher_vocation')
          .eq('id', widget.profile.id).maybeSingle();
      if (mounted) {
        setState(() {
          _code = sharedCode.trim().toUpperCase();
          _balance = balance;
          _withdrawals = withdrawals;
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

  Future<void> _requestWithdrawal() async {
    final amount = int.tryParse(_withdrawalAmountController.text.trim());
    final phone = _withdrawalPhoneController.text.trim();
    if (amount == null || amount < 1000 || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_fr
            ? 'Saisis au moins 1 000 FCFA et un numéro mobile.'
            : 'Enter at least 1,000 XAF and a mobile number.'),
      ));
      return;
    }
    setState(() => _withdrawing = true);
    try {
      await _service.requestWithdrawal(
        amountXaf: amount,
        provider: _withdrawalProvider,
        phone: phone,
      );
      _withdrawalAmountController.clear();
      _withdrawalPhoneController.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_fr
              ? 'Demande enregistrée, en attente de traitement.'
              : 'Request submitted and awaiting processing.'),
        ));
      }
    } catch (error) {
      if (mounted) {
        final message = error.toString().contains('Insufficient available balance')
            ? (_fr ? 'Solde disponible insuffisant.' : 'Insufficient available balance.')
            : (_fr ? 'Impossible d’enregistrer le retrait.' : 'Could not submit withdrawal.');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  String _withdrawalStatus(String status) {
    if (_fr) {
      switch (status) {
        case 'paid': return 'Payé';
        case 'rejected': return 'Refusé';
        default: return 'En attente';
      }
    }
    switch (status) {
      case 'paid': return 'Paid';
      case 'rejected': return 'Rejected';
      default: return 'Pending';
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
                              child: Text(_fr ? 'Solde disponible' : 'Available balance'),
                            ),
                            Text('$_balance XAF', style: const TextStyle(fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(_fr ? 'Demander un retrait' : 'Request a withdrawal',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(_fr
                          ? 'Choisis Orange Money ou MTN Mobile Money. Le montant est réservé et la demande attend le traitement.'
                          : 'Choose Orange Money or MTN Mobile Money. The amount is reserved while the request awaits processing.'),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _withdrawalProvider,
                        decoration: InputDecoration(
                          labelText: _fr ? 'Moyen de retrait' : 'Withdrawal method',
                          border: const OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'cm.orange', child: Text('Orange Money')),
                          DropdownMenuItem(value: 'cm.mtn', child: Text('MTN Mobile Money')),
                        ],
                        onChanged: _withdrawing ? null : (value) {
                          if (value != null) setState(() => _withdrawalProvider = value);
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _withdrawalPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: _fr ? 'Numéro mobile camerounais' : 'Cameroon mobile number',
                          hintText: '+237 6XX XXX XXX',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _withdrawalAmountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: _fr ? 'Montant (FCFA)' : 'Amount (XAF)',
                          helperText: _fr ? 'Minimum : 1 000 FCFA' : 'Minimum: 1,000 XAF',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _withdrawing ? null : _requestWithdrawal,
                        icon: _withdrawing
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.payments_outlined),
                        label: Text(_withdrawing
                            ? (_fr ? 'Envoi…' : 'Submitting…')
                            : (_fr ? 'Envoyer la demande' : 'Submit request')),
                      ),
                      if (_withdrawals.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Text(_fr ? 'Mes demandes récentes' : 'Recent withdrawal requests',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        ..._withdrawals.map((request) {
                          final provider = request['provider'] == 'cm.mtn' ? 'MTN Mobile Money' : 'Orange Money';
                          final amount = (request['amount_xaf'] as num?)?.toInt() ?? 0;
                          final status = request['status']?.toString() ?? 'pending';
                          return Card(
                            child: ListTile(
                              leading: Icon(status == 'paid' ? Icons.check_circle_outline : status == 'rejected' ? Icons.cancel_outlined : Icons.hourglass_top_rounded),
                              title: Text('${amount} XAF • $provider'),
                              subtitle: Text('${request['phone'] ?? ''} • ${_withdrawalStatus(status)}'),
                            ),
                          );
                        }),
                      ],
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
