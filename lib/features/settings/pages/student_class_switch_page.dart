import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/json_cache.dart';
import '../../../core/services/student_class_context.dart';

class StudentClassSwitchPage extends StatefulWidget {
  final Locale locale;
  const StudentClassSwitchPage({super.key, required this.locale});

  @override
  State<StudentClassSwitchPage> createState() => _StudentClassSwitchPageState();
}

class _StudentClassSwitchPageState extends State<StudentClassSwitchPage> {
  final _codeController = TextEditingController();
  List<Map<String, dynamic>> _classes = [];
  String? _selectedClassId;
  bool _loading = false;
  bool _searched = false;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _findClasses() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _message(_fr ? 'Saisissez le code de groupe de l’enseignant.' : 'Enter the teacher group code.');
      return;
    }
    setState(() { _loading = true; _searched = false; _classes = []; _selectedClassId = null; });
    try {
      final rows = await Supabase.instance.client.rpc(
        'list_teacher_classrooms_for_student',
        params: {'p_code': code},
      ) as List;
      if (!mounted) return;
      setState(() {
        _classes = rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
        _searched = true;
        _selectedClassId = _classes.isEmpty ? null : _classes.first['class_id']?.toString();
      });
      if (_classes.isEmpty) {
        _message(_fr ? 'Aucune classe compatible trouvée pour ce code.' : 'No compatible classroom was found for this code.');
      }
    } catch (e) {
      if (mounted) _message(_fr ? 'Impossible de rechercher les classes. Vérifiez le code et la connexion.' : 'Could not load classrooms. Check the code and connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _switchClass() async {
    final classId = _selectedClassId;
    if (classId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_fr ? 'Confirmer le changement de classe' : 'Confirm classroom change'),
        content: Text(_fr ? 'Votre classe active et les matières associées seront mises à jour.' : 'Your active classroom and associated subjects will be updated.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_fr ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_fr ? 'Confirmer' : 'Confirm')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.rpc(
        'switch_student_class_with_teacher_code',
        params: {'p_code': _codeController.text.trim(), 'p_class_id': classId},
      );
      // Remove only cached data that is scoped to this student's active class.
      // Keep downloaded offline files and unrelated account data intact.
      final studentId = Supabase.instance.client.auth.currentUser?.id;
      if (studentId != null && studentId.isNotEmpty) {
        await JsonCache.instance.removeMatchingPrefixes([
          'class_subjects_$studentId',
          'student_catalog_chapters_${studentId}_',
          'student_chapter_content_${studentId}_',
        ]);
      }
      StudentClassContext.notifyChanged();
      if (!mounted) return;
      _message(_fr
          ? 'Salle modifiée. Les contenus liés à l’ancienne salle ont été actualisés.'
          : 'Classroom changed. Content linked to the previous classroom has been refreshed.');
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) _message(_fr ? 'Le changement a échoué. Vérifiez le code et la compatibilité de la classe.' : 'The change failed. Check the code and classroom compatibility.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: const Color(0xFF166534),
      foregroundColor: Colors.white,
      title: Text(_fr ? 'Changer de classe' : 'Change classroom'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          _fr ? 'Saisissez le code de groupe FISE de votre enseignant. Seules les classes compatibles proposées par cet enseignant seront affichées.' : 'Enter your teacher’s FISE group code. Only compatible classrooms offered by that teacher will be shown.',
          style: const TextStyle(height: 1.45),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _codeController,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: _fr ? 'Code de groupe enseignant' : 'Teacher group code',
            hintText: 'FISE-XXXXXX',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.key_outlined),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _loading ? null : _findClasses,
          icon: const Icon(Icons.search),
          label: Text(_fr ? 'Rechercher les classes' : 'Find classrooms'),
        ),
        if (_loading) const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
        if (_searched && _classes.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(_fr ? 'Choisissez la classe' : 'Choose a classroom', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          ..._classes.map((row) {
            final id = row['class_id']?.toString();
            final current = row['is_current'] == true;
            return Card(
              child: RadioListTile<String>(
                value: id ?? '',
                groupValue: _selectedClassId,
                onChanged: current || id == null ? null : (value) => setState(() => _selectedClassId = value),
                title: Text(row['class_name']?.toString() ?? (_fr ? 'Classe sans nom' : 'Unnamed classroom')),
                subtitle: current ? Text(_fr ? 'Classe actuelle' : 'Current classroom') : null,
              ),
            );
          }),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loading || _selectedClassId == null || _classes.any((r) => r['class_id']?.toString() == _selectedClassId && r['is_current'] == true) ? null : _switchClass,
            child: Text(_fr ? 'Confirmer le changement' : 'Confirm change'),
          ),
        ],
      ],
    ),
  );
}
