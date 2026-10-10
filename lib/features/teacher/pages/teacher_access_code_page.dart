import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../core/services/teacher_access_code_service.dart';
import '../../../models/school_class.dart';
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
  final TextEditingController _newCodeController = TextEditingController();
  List<TeacherAccessCode> _codes = [];
  List<SchoolClass> _classes = [];
  String? _selectedClassId;
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
    _newCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadCodes() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final codes = await _service.getTeacherAccessCodes(widget.profile.id);
      List<SchoolClass> classes = const [];
      try {
        classes = await CourseService().listTeacherCompatibleClasses();
      } catch (_) {
        // Keep existing codes visible even if the compatible-room list fails.
      }
      final available = classes.where(
        (schoolClass) => !codes.any(
          (code) => code.classId == schoolClass.id && code.isActive,
        ),
      );
      if (mounted) {
        setState(() {
          _codes = codes;
          _classes = classes;
          if (_selectedClassId == null ||
              !available.any((c) => c.id == _selectedClassId)) {
            _selectedClassId = available.isEmpty ? null : available.first.id;
          }
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

  Future<void> _createCode() async {
    final classId = _selectedClassId;
    final suffix = _newCodeController.text.trim();
    if (classId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isFrench
            ? 'Aucune salle disponible pour créer un code.'
            : 'No classroom is available for a new code.')),
      );
      return;
    }
    if (suffix.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isFrench
            ? 'Choisissez le code après le préfixe FISE-.'
            : 'Enter the code suffix after FISE-.')),
      );
      return;
    }
    try {
      await CourseService().authorizeTeacherClasses([classId]);
      await _service.getOrCreateAccessCode(widget.profile.id, classId, suffix);
      _newCodeController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isFrench
            ? 'Code FISE créé pour la salle sélectionnée.'
            : 'FISE code created for the selected classroom.')),
      );
      await _loadCodes();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isFrench
            ? 'Création impossible : $e'
            : 'Unable to create code: $e')),
      );
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

  Future<void> _shareCode(String code) async {
    await SharePlus.instance.share(ShareParams(
      text: _isFrench
          ? 'Voici mon code Fise School : $code. Saisissez-le dans l’application pour accéder à mes groupes et à ma messagerie.'
          : 'My Fise School code is $code. Enter it in the app to access my groups and messaging.',
      title: _isFrench ? 'Code Fise School' : 'Fise School code',
    ));
  }

  Future<void> _copyToClipboard(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isFrench ? 'Code copié : $code' : 'Code copied: $code'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final availableClasses = _classes.where(
      (schoolClass) => !_codes.any(
        (code) => code.classId == schoolClass.id && code.isActive,
      ),
    ).toList(growable: false);
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
                      Text(
                        _isFrench ? 'Créer un code FISE pour une salle' : 'Create a FISE code for a classroom',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      if (availableClasses.isEmpty)
                        Text(_isFrench
                            ? 'Toutes les salles compatibles ont déjà un code actif.'
                            : 'All compatible classrooms already have an active code.')
                      else ...[
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _selectedClassId,
                          decoration: InputDecoration(
                            labelText: _isFrench ? 'Salle de classe' : 'Classroom',
                            border: const OutlineInputBorder(),
                          ),
                          items: availableClasses.map((schoolClass) =>
                            DropdownMenuItem<String>(
                              value: schoolClass.id,
                              child: Text(schoolClass.displayName, overflow: TextOverflow.ellipsis),
                            ),
                          ).toList(),
                          onChanged: (value) => setState(() => _selectedClassId = value),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _newCodeController,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                            TextInputFormatter.withFunction((oldValue, newValue) => newValue.copyWith(
                              text: newValue.text.toUpperCase(),
                              selection: newValue.selection,
                            )),
                          ],
                          decoration: InputDecoration(
                            labelText: _isFrench ? 'Code choisi' : 'Your code',
                            hintText: 'MATHS6A',
                            prefixText: 'FISE-',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _createCode,
                            icon: const Icon(Icons.vpn_key_rounded),
                            label: Text(_isFrench ? 'Créer le code' : 'Create code'),
                          ),
                        ),
                      ],
                      if (_isEditing) ..._buildEditForm(),
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

  String _className(TeacherAccessCode code) {
    for (final schoolClass in _classes) {
      if (schoolClass.id == code.classId) return schoolClass.displayName;
    }
    return code.classId;
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
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          "${_isFrench ? 'Salle' : 'Class'}: ${_className(code)} • ${_isFrench ? 'Créé le' : 'Created'} ${code.createdAt.day}/${code.createdAt.month}/${code.createdAt.year}",
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              tooltip: _isFrench ? 'Modifier ce code' : 'Edit this code',
              onPressed: () {
                setState(() {
                  _isEditing = true;
                  _selectedCode = code;
                  _codeController.text = code.code;
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              onPressed: () => _copyToClipboard(code.displayCode),
              tooltip: _isFrench ? 'Copier' : 'Copy',
            ),
            IconButton(
              icon: const Icon(Icons.share_rounded),
              onPressed: () => _shareCode(code.displayCode),
              tooltip: _isFrench ? 'Partager' : 'Share',
            ),
          ],
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
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                  TextInputFormatter.withFunction((oldValue, newValue) => newValue.copyWith(
                    text: newValue.text.toUpperCase(),
                    selection: newValue.selection,
                  )),
                ],
                decoration: InputDecoration(
                  labelText: _isFrench ? 'Suite du code' : 'Code suffix',
                  hintText: 'MATHS6A',
                  prefixText: 'FISE-',
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
