import 'package:flutter/material.dart';
import '../../../core/services/student_class_change_service.dart';

class StudentClassSwitchPage extends StatefulWidget {
  final Locale locale;
  const StudentClassSwitchPage({super.key, required this.locale});

  @override
  State<StudentClassSwitchPage> createState() => _StudentClassSwitchPageState();
}

class _StudentClassSwitchPageState extends State<StudentClassSwitchPage> {
  final StudentClassChangeService _service = StudentClassChangeService();
  List<Map<String, dynamic>> _classes = [];
  String? _selectedClassId;
  bool _loading = true;
  String? _error;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final classes = await _service.listNextClasses();
      if (!mounted) return;
      setState(() {
        _classes = classes;
        _selectedClassId = classes.isEmpty
            ? null
            : classes.first['class_id']?.toString();
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = _fr
              ? 'Impossible de charger les salles. Vérifiez votre connexion puis réessayez.'
              : 'Could not load classrooms. Check your connection and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _switchClass() async {
    final classId = _selectedClassId;
    if (classId == null) return;

    final selected = _classes.firstWhere(
      (row) => row['class_id']?.toString() == classId,
    );
    final className = selected['class_name']?.toString() ??
        (_fr ? 'la classe sélectionnée' : 'the selected classroom');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_fr ? 'Confirmer le changement de salle' : 'Confirm classroom change'),
        content: Text(_fr
            ? 'Passer à « $className » ? Cyber actualisera votre espace scolaire selon cette classe. Votre compte restera le même.'
            : 'Switch to “$className”? Cyber will refresh your school space for this classroom. Your account will remain the same.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_fr ? 'Annuler' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_fr ? 'Confirmer' : 'Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _service.changeClass(classId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_fr
              ? 'Salle modifiée. Votre espace scolaire va être actualisé.'
              : 'Classroom changed. Your school space will refresh.'),
        ),
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = _fr
            ? 'Le changement a échoué. Cette salle n’est peut-être plus disponible. Réessayez.'
            : 'The change failed. This classroom may no longer be available. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF166534),
          foregroundColor: Colors.white,
          title: Text(_fr ? 'Changer de salle' : 'Change classroom'),
          actions: [
            IconButton(
              onPressed: _loading ? null : _loadClasses,
              tooltip: _fr ? 'Actualiser' : 'Refresh',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadClasses,
                child: ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    Text(
                      _fr
                          ? 'Choisissez une salle selon le sous-système, l’enseignement, la série ou la spécialité. Les filières et les niveaux précédents sont proposés lorsqu’ils sont configurés dans le catalogue scolaire.'
                          : 'Choose a classroom or pathway from the available school system. Series, technical specialties and previous levels are listed when they are configured for your subsystem.',
                      style: const TextStyle(height: 1.45),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _loadClasses,
                        icon: const Icon(Icons.refresh),
                        label: Text(_fr ? 'Réessayer' : 'Try again'),
                      ),
                    ],
                    if (_classes.isEmpty && _error == null) ...[
                      const SizedBox(height: 24),
                      Text(
                        _fr
                            ? 'Aucune salle active n’est disponible pour le moment.'
                            : 'No active classrooms are available right now.',
                      ),
                    ],
                    if (_classes.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        _fr ? 'Salles disponibles' : 'Available classrooms',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      ..._classes.map((row) {
                        final id = row['class_id']?.toString();
                        final isCurrent = false;
                        final name = row['class_name']?.toString() ??
                            (_fr ? 'Salle sans nom' : 'Unnamed classroom');
                        final details = [
                          row['exam_level_label']?.toString(),
                          row['track_label']?.toString(),
                          row['subsystem']?.toString(),
                          row['sector']?.toString(),
                        ].where((value) => value != null && value.trim().isNotEmpty).join(' • ');
                        return Card(
                          child: RadioListTile<String>(
                            value: id ?? '',
                            groupValue: _selectedClassId,
                            onChanged: id == null || id.isEmpty
                                ? null
                                : (value) => setState(() => _selectedClassId = value),
                            title: Text(name),
                            subtitle: Text([
                              if (details.isNotEmpty) details,
                              if (isCurrent) (_fr ? 'Salle actuelle' : 'Current classroom'),
                            ].join(' • ')),
                          ),
                        );
                      }),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _loading ||
                                  _selectedClassId == null ||
                                  _classes.any((row) =>
                                      row['class_id']?.toString() == _selectedClassId &&
                                      row['is_current'] == true)
                              ? null
                              : _switchClass,
                          child: Text(_fr ? 'Confirmer le changement' : 'Confirm change'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      );
}
