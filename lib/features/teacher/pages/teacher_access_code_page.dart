import 'package:flutter/material.dart';
import '../../../core/services/teacher_access_code_service.dart';
import '../../../models/teacher_access_code.dart';
import '../../../models/user_profile.dart';

class TeacherAccessCodePage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const TeacherAccessCodePage({
    super.key,
    required this.locale,
    required this.profile,
  });

  @override
  State<TeacherAccessCodePage> createState() => _TeacherAccessCodePageState();
}

class _TeacherAccessCodePageState extends State<TeacherAccessCodePage> {
  final TeacherAccessCodeService _service = TeacherAccessCodeService();
  final TextEditingController _codeController = TextEditingController();
  List<TeacherAccessCode> _codes = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _isEditing = false;

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _loadCodes();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadCodes() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final codes = await _service.getTeacherAccessCodes(widget.profile.id);
      if (!mounted) return;
      setState(() {
        _codes = codes;
        _loading = false;
        // If no code exists, show the manual creation form immediately.
        _isEditing = codes.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = _isFrench
            ? 'Impossible de charger le code. Vérifiez votre connexion.'
            : 'Unable to load the code. Check your connection.';
        _loading = false;
      });
    }
  }

  Future<void> _saveCode() async {
    final value = _codeController.text.trim();
    if (value.isEmpty) {
      _showMessage(_isFrench
          ? 'Choisissez votre propre code avant d’enregistrer.'
          : 'Enter the code you want to use.');
      return;
    }

    setState(() => _saving = true);
    try {
      final sharedCode = await _service.setMySharedCode(value);
      if (!mounted) return;
      _codeController.clear();
      _showMessage(_isFrench
          ? 'Votre code unique $sharedCode est enregistré pour la messagerie, les groupes et les paiements.'
          : 'Your shared code $sharedCode is saved for private messages, groups, and payments.');
      await _loadCodes();
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Bad state: ', '');
      _showMessage(message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isFrench ? 'Mon code unique' : 'My shared code',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5EC),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isFrench
                                  ? 'Un seul code pour les trois services'
                                  : 'One code for all three services',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(_isFrench
                                ? 'Créez vous-même votre code. Le même code sert à la messagerie privée, aux groupes et aux paiements. Le système ne génère pas de code à votre place.'
                                : 'Choose your own code. The same code is used for private messages, groups, and payments. The system will not generate one for you.'),
                            const SizedBox(height: 16),
                            if (_codes.isEmpty)
                              Text(_isFrench
                                  ? 'Vous n’avez pas encore de code.'
                                  : 'You have not created a code yet.')
                            else
                              ..._codes.map((code) => Card(
                                    child: ListTile(
                                      leading: const CircleAvatar(
                                        backgroundColor: Color(0xFF166534),
                                        child: Icon(Icons.vpn_key_rounded,
                                            color: Colors.white),
                                      ),
                                      title: SelectableText(
                                        code.displayCode,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                        ),
                                      ),
                                      subtitle: Text(_isFrench
                                          ? 'Code commun : messagerie, groupes et paiement'
                                          : 'Shared code: messaging, groups, and payments'),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.copy_rounded),
                                        tooltip: _isFrench ? 'Copier' : 'Copy',
                                        onPressed: () => _showMessage(
                                          _isFrench
                                              ? 'Code à copier : ${code.displayCode}'
                                              : 'Code to copy: ${code.displayCode}',
                                        ),
                                      ),
                                    ),
                                  )),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_isEditing)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  _codes.isEmpty
                                      ? (_isFrench ? 'Créer mon code' : 'Create my code')
                                      : (_isFrench ? 'Modifier mon code' : 'Change my code'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _codeController,
                                  textCapitalization: TextCapitalization.characters,
                                  autocorrect: false,
                                  decoration: InputDecoration(
                                    labelText: _isFrench ? 'Code choisi par vous' : 'Your chosen code',
                                    hintText: 'EXEMPLE123',
                                    prefixText: 'FISE-',
                                    helperText: _isFrench
                                        ? '3 à 40 caractères : lettres, chiffres, - ou _.'
                                        : '3–40 characters: letters, numbers, - or _.',
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: _saving ? null : _saveCode,
                                  child: _saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : Text(_isFrench ? 'Enregistrer le même code partout' : 'Save the shared code'),
                                ),
                                if (_codes.isNotEmpty)
                                  TextButton(
                                    onPressed: () => setState(() => _isEditing = false),
                                    child: Text(_isFrench ? 'Annuler' : 'Cancel'),
                                  ),
                              ],
                            ),
                          ),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: () {
                            _codeController.clear();
                            setState(() => _isEditing = true);
                          },
                          icon: const Icon(Icons.edit_rounded),
                          label: Text(_isFrench ? 'Choisir un autre code' : 'Choose another code'),
                        ),
                    ],
                  ),
                ),
    );
  }
}
