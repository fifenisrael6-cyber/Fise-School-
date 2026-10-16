import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});
  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  @override
  void dispose() { _password.dispose(); _confirm.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: _password.text));
      if (!mounted) return;
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mot de passe modifié. Connectez-vous avec votre nouveau mot de passe.')));
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } on AuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Modification impossible. Ouvrez à nouveau le lien reçu par e-mail puis réessayez.')));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Créer un nouveau mot de passe')),
    body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Choisissez un mot de passe d’au moins 8 caractères et confirmez-le.', textAlign: TextAlign.center),
      const SizedBox(height: 24),
      TextFormField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Nouveau mot de passe', border: OutlineInputBorder()), validator: (v) => (v ?? '').length < 8 ? '8 caractères minimum.' : null),
      const SizedBox(height: 16),
      TextFormField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmer le mot de passe', border: OutlineInputBorder()), validator: (v) { if ((v ?? '').isEmpty) return 'Confirmez le mot de passe.'; if (v != _password.text) return 'Les mots de passe ne correspondent pas.'; return null; }),
      const SizedBox(height: 20),
      FilledButton(onPressed: _loading ? null : _save, child: _loading ? const CircularProgressIndicator() : const Text('Enregistrer le nouveau mot de passe')),
    ]))))));
}
