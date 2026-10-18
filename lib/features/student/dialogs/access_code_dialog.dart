import 'package:flutter/material.dart';
import '../../../core/services/teacher_access_code_service.dart';
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
      final classId = widget.classId;
      if (classId == null || classId.trim().isEmpty) {
        throw StateError('Student classroom is not configured.');
      }
      final valid = await _service.validateAccessCode(code, classId);
      if (!valid) {
        throw StateError('Invalid or unauthorized access code.');
      }
      if (!mounted) return;
      _openMessages();
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
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _switchClassroom() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _error = _isFrench ? 'Entrez d’abord le code unique de l’enseignant.' : 'Enter the teacher code first.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final classrooms = await _service.listSwitchableClassrooms(code);
      if (!mounted) return;
      if (classrooms.isEmpty) {
        throw StateError('No compatible classrooms found for this teacher code.');
      }

      String? selectedClassId;
      final chosenClassId = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(_isFrench ? 'Choisir la nouvelle salle' : 'Choose the new classroom'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isFrench
                        ? 'Le changement ne sera effectué qu’après votre confirmation.'
                        : 'Your classroom changes only after you confirm.',
                  ),
                  const SizedBox(height: 12),
                  ...classrooms.map((room) {
                    final id = room['class_id']?.toString() ?? '';
                    final name = room['class_name']?.toString() ?? id;
                    final isCurrent = room['is_current'] == true;
                    return RadioListTile<String>(
                      value: id,
                      groupValue: selectedClassId,
                      title: Text(name),
                      subtitle: isCurrent
                          ? Text(_isFrench ? 'Salle actuelle' : 'Current classroom')
                          : null,
                      onChanged: id.isEmpty
                          ? null
                          : (value) => setDialogState(() => selectedClassId = value),
                    );
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(_isFrench ? 'Annuler' : 'Cancel'),
              ),
              FilledButton(
                onPressed: selectedClassId == null
                    ? null
                    : () => Navigator.of(dialogContext).pop(selectedClassId),
                child: Text(_isFrench ? 'Confirmer' : 'Confirm'),
              ),
            ],
          ),
        ),
      );

      if (chosenClassId == null) return;
      await _service.switchStudentClassroom(code: code, classId: chosenClassId);
      if (!mounted) return;
      widget.onSuccess();
      _openMessages();
    } catch (e) {
      if (mounted) {
        final message = e.toString().toLowerCase();
        setState(() {
          _error = message.contains('invalid') || message.contains('incompatible')
              ? (_isFrench
                  ? 'Code invalide ou salle non compatible avec votre profil.'
                  : 'Invalid code or classroom incompatible with your profile.')
              : (_isFrench
                  ? 'Impossible de changer de salle. Vérifiez le code et réessayez.'
                  : 'Could not change classroom. Check the code and try again.');
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openMessages() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessagesHubPage(
          locale: widget.locale,
          profile: widget.profile,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isFrench ? 'Code d\'accès requis' : 'Access code required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isFrench
                ? 'Entrez le code d’accès fourni par votre enseignant pour accéder à sa messagerie.'
                : "Enter the code provided by your teacher to access their messaging.",
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            enabled: !_loading,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: _isFrench ? 'Code d’accès' : 'Access code',
              hintText: 'FISE-XXXXXX',
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
        TextButton(
          onPressed: _loading ? null : _switchClassroom,
          child: Text(_isFrench ? 'Changer de salle' : 'Switch classroom'),
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
