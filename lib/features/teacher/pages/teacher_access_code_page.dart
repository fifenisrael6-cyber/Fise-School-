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
  String? _error;
  TeacherAccessCode? _selectedCode;
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
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final codes = await _service.getTeacherAccessCodes(widget.profile.id);
      if (mounted) {
        setState(() {
          _codes = codes;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _isFrench
              ? 'Erreur lors du chargement des codes.'
              : 'Error loading codes.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _updateCode() async {
    if (_selectedCode == null || _codeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFrench ? 'Veuillez entrer un code.' : 'Please enter a code.',
          ),
        ),
      );
      return;
    }

    try {
      await _service.updateAccessCode(
        _selectedCode!.id,
        _codeController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isFrench ? 'Code mis à jour.' : 'Code updated.',
            ),
          ),
        );
        _codeController.clear();
        setState(() => _isEditing = false);
        _loadCodes();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isFrench
                  ? 'Erreur: ${e.toString()}'
                  : 'Error: ${e.toString()}',
            ),
          ),
        );
      }
    }
  }

  void _copyToClipboard(String code) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isFrench
              ? 'Code copié: $code'
              : 'Code copied: $code',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isFrench ? 'Code d\'accès unique' : 'Access code',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!),
                )
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
                                  ? 'Votre code d\'accès unique'
                                  : 'Your unique access code',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_codes.isNotEmpty)
                              ..._codes.map((code) => _buildCodeCard(code))
                            else
                              Text(
                                _isFrench
                                    ? 'Aucun code d\'accès créé.'
                                    : 'No access code created yet.',
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_isEditing) ...
                        _buildEditForm()
                      else
                        Center(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() => _isEditing = true);
                              _codeController.clear();
                              _selectedCode = _codes.isNotEmpty ? _codes.first : null;
                            },
                            icon: const Icon(Icons.edit_rounded),
                            label: Text(
                              _isFrench ? 'Modifier le code' : 'Edit code',
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          _isFrench
                              ? 'Les élèves doivent saisir ce code pour pouvoir vous contacter en messagerie privée.'
                              : 'Students must enter this code to message you privately.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildCodeCard(TeacherAccessCode code) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF166534),
          child: const Icon(
            Icons.vpn_key_rounded,
            color: Colors.white,
          ),
        ),
        title: Text(
          code.displayCode,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          _isFrench
              ? 'Créé le ${code.createdAt.day}/${code.createdAt.month}/${code.createdAt.year}'
              : 'Created ${code.createdAt.day}/${code.createdAt.month}/${code.createdAt.year}',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.copy_rounded),
          onPressed: () => _copyToClipboard(code.displayCode),
          tooltip: _isFrench ? 'Copier' : 'Copy',
        ),
      ),
    );
  }

  List<Widget> _buildEditForm() {
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isFrench ? 'Modifier le code' : 'Edit code',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _codeController,
                decoration: InputDecoration(
                  labelText: _isFrench ? 'Nouveau code' : 'New code',
                  hintText: _isFrench
                      ? 'Ex: fise123ABC'
                      : 'Ex: fise123ABC',
                  prefixText: 'fise',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() => _isEditing = false);
                      _codeController.clear();
                    },
                    child: Text(_isFrench ? 'Annuler' : 'Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _updateCode,
                    child: Text(_isFrench ? 'Enregistrer' : 'Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
  }
}
