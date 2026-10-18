import 'package:flutter/material.dart';
import '../../../core/services/teacher_access_code_service.dart';
import '../../../models/user_profile.dart';
import '../../forum/pages/forum_page.dart';

class AccessCodeDialog extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final String classId;
  final VoidCallback onSuccess;

  const AccessCodeDialog({
    super.key,
    required this.locale,
    required this.profile,
    required this.classId,
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
      final isValid = await _service.validateAccessCode(code, widget.classId);

      if (!mounted) return;

      if (isValid) {
        widget.onSuccess();
        if (mounted) {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ForumPage(
                locale: widget.locale,
                profile: widget.profile,
              ),
            ),
          );
        }
      } else {
        setState(() {
          _error = _isFrench ? 'Code invalide.' : 'Invalid code.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _isFrench ? 'Erreur lors de la vérification.' : 'Verification error.';
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
                ? 'Entrez le code d\'accès fourni par votre enseignant pour accéder au forum.'
                : 'Enter the access code provided by your teacher to access the forum.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            enabled: !_loading,
            decoration: InputDecoration(
              labelText: _isFrench ? 'Code d\'accès' : 'Access code',
              hintText: 'fise...',
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
