import 'package:flutter/material.dart';
import '../../../core/services/teacher_access_code_service.dart';
import '../../../core/services/group_message_service.dart';
import '../../../core/services/private_message_service.dart';
import '../../../models/user_profile.dart';
import '../../messages/pages/messages_hub_page.dart';

class AccessCodeDialog extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final String? classId;
  final VoidCallback onSuccess;

  const AccessCodeDialog({
    super.key,
    required this.locale,
    required this.profile,
    this.classId,
    required this.onSuccess,
  });

  @override
  State<AccessCodeDialog> createState() => _AccessCodeDialogState();
}

class _AccessCodeDialogState extends State<AccessCodeDialog> {
  final TeacherAccessCodeService _service = TeacherAccessCodeService();
  final TextEditingController _codeController = TextEditingController();
  bool _loading = false;
  String? _error;

  bool get _isFrench => widget.locale.languageCode == 'fr';
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _validateAndAccess() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _error = _isFrench ? 'Veuillez entrer le code.' : 'Please enter the code.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final normalizedCode = code.toUpperCase();
      if (!RegExp(r'^FISE-[A-Z0-9-]{3,}$').hasMatch(normalizedCode)) {
        throw ArgumentError('Code invalide');
      }

      // Inscrire l'élève dans la salle associée au code, puis déverrouiller
      // la messagerie privée avec ce même code.
      await _service.joinClassWithAccessCode(normalizedCode);
      final privateService = PrivateMessageService();
      final unlocked = await privateService.unlockTeacher(normalizedCode);
      if (!unlocked) {
        throw StateError('Code invalide ou enseignant non autorisé pour cette classe.');
      }

      // Ajouter l'élève aux groupes existants de l'enseignant. Si le code est
      // valide mais qu'aucun groupe n'a encore été créé, l'accès à la messagerie
      // privée reste disponible.
      try {
        await GroupMessageService().joinWithCode(normalizedCode);
      } catch (groupError) {
        final groupMessage = groupError.toString().toLowerCase();
        final noGroupsYet = groupMessage.contains('no message group exists') ||
            groupMessage.contains('aucun groupe') ||
            (groupMessage.contains('null') && groupMessage.contains('string'));
        if (!noGroupsYet) rethrow;
      }

      if (!mounted) return;
      widget.onSuccess();
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MessagesHubPage(
            locale: widget.locale,
            profile: widget.profile,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          final message = e.toString().toLowerCase();
          _error = message.contains('invalid') || message.contains('inactive')
              ? (_isFrench ? 'Code invalide ou non autorisé pour ta salle.' : 'Invalid or unauthorized code for your classroom.')
              : (_isFrench ? 'Impossible d\'accéder à la messagerie.' : 'Unable to access messaging.');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isFrench ? 'Code d\'accès requis' : 'Access code required',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isFrench
                ? 'Entrez le code de votre enseignant (il commence par FISE-) pour accéder à ses groupes et à sa messagerie.'
                : "Enter the access code provided by your teacher to access your teacher's messaging.",
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            enabled: !_loading,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: _isFrench ? 'Entrer le code de l’enseignant' : 'Enter teacher code',
              hintText: 'FISE-MATHS6A',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text(_isFrench ? 'Annuler' : 'Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _validateAndAccess,
          child: _loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                )
              : Text(_isFrench ? 'Accéder' : 'Access'),
        ),
      ],
    );
  }
}
