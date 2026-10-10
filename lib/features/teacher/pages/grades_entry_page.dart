import 'package:flutter/material.dart';

import '../../../core/services/grade_service.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../models/grades.dart';
import '../../../models/user_profile.dart';

/// Saisie des notes : salle → matière → période → une note sur 20 par élève.
class GradesEntryPage extends StatefulWidget {
  final Locale locale;
  final UserProfile? profile;
  final bool asAdmin;

  const GradesEntryPage({
    super.key,
    required this.locale,
    this.profile,
    this.asAdmin = false,
  });

  @override
  State<GradesEntryPage> createState() => _GradesEntryPageState();
}

class _GradesEntryPageState extends State<GradesEntryPage> {
  final _service = GradeService();
  bool _loading = true;
  bool _loadingGrid = false;
  bool _saving = false;
  String? _error;

  List<GradeClassOption> _classes = const [];
  List<GradeSubject> _subjects = const [];
  List<GradePeriod> _periods = const [];
  List<RosterStudent> _roster = const [];
  String? _classId;
  String? _subjectId;
  String? _periodId;

  final Map<String, TextEditingController> _scores = {};
  final Map<String, TextEditingController> _comments = {};

  bool get _fr => widget.locale.languageCode == 'fr';
  String get _lang => widget.locale.languageCode;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final c in _scores.values) {
      c.dispose();
    }
    for (final c in _comments.values) {
      c.dispose();
    }
    _scores.clear();
    _comments.clear();
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _init() async {
    try {
      final classes = widget.asAdmin
          ? await _service.listAllClasses()
          : await CourseService().listTeacherCompatibleClasses();
      final periods = await _service.listPeriods();
      if (!mounted) {
        return;
      }
      setState(() {
        _classes = classes;
        _periods = periods;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = _fr ? 'Chargement impossible. Vérifiez votre connexion.' : 'Unable to load. Check your connection.';
      });
    }
  }

  Future<void> _pickClass(String? id) async {
    setState(() {
      _classId = id;
      _subjectId = null;
      _subjects = const [];
      _roster = const [];
      _disposeControllers();
    });
    if (id == null) {
      return;
    }
    try {
      if (!widget.asAdmin) {
        await CourseService().authorizeTeacherClasses([id]);
      }
      final subjects = await _service.listClassSubjects(id);
      if (!mounted) {
        return;
      }
      setState(() => _subjects = subjects);
    } catch (e) {
      if (mounted) {
        _snack(_fr ? 'Matières indisponibles.' : 'Subjects unavailable.');
      }
    }
  }

  Future<void> _loadGrid() async {
    final classId = _classId;
    final subjectId = _subjectId;
    final periodId = _periodId;
    if (classId == null || subjectId == null || periodId == null) {
      return;
    }
    setState(() => _loadingGrid = true);
    try {
      final roster = await _service.roster(classId);
      final grades = await _service.listGrades(classId: classId, subjectId: subjectId, periodId: periodId);
      if (!mounted) {
        return;
      }
      _disposeControllers();
      for (final s in roster) {
        final g = grades[s.id];
        _scores[s.id] = TextEditingController(text: g == null ? '' : g.score.toString());
        _comments[s.id] = TextEditingController(text: g?.comment ?? '');
      }
      setState(() {
        _roster = roster;
        _loadingGrid = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _loadingGrid = false);
      _snack(_fr ? 'Liste des élèves indisponible.' : 'Student list unavailable.');
    }
  }

  Future<void> _save() async {
    final classId = _classId;
    final subjectId = _subjectId;
    final periodId = _periodId;
    if (classId == null || subjectId == null || periodId == null) {
      return;
    }

    final scores = <String, double>{};
    final comments = <String, String>{};
    for (final s in _roster) {
      final raw = _scores[s.id]?.text.trim().replaceAll(',', '.') ?? '';
      if (raw.isEmpty) {
        continue;
      }
      final value = double.tryParse(raw);
      if (value == null || value < 0 || value > 20) {
        _snack(_fr
            ? 'Note invalide pour ${s.fullName} (entre 0 et 20).'
            : 'Invalid mark for ${s.fullName} (0 to 20).');
        return;
      }
      scores[s.id] = value;
      comments[s.id] = _comments[s.id]?.text ?? '';
    }
    if (scores.isEmpty) {
      _snack(_fr ? 'Aucune note à enregistrer.' : 'No marks to save.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.saveGrades(
        classId: classId,
        subjectId: subjectId,
        periodId: periodId,
        scores: scores,
        comments: comments,
      );
      if (mounted) {
        _snack(_fr ? 'Notes enregistrées.' : 'Marks saved.');
      }
    } catch (e) {
      if (mounted) {
        _snack(_fr ? 'Échec de l’enregistrement : $e' : 'Save failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_fr ? 'Saisie des notes' : 'Enter marks')),
      bottomNavigationBar: _roster.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: Text(_fr ? 'Enregistrer les notes' : 'Save marks'),
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_classes.isEmpty)
                      Text(_fr
                          ? 'Aucune salle ne vous est affectée. Contactez l’administration.'
                          : 'No classroom assigned to you. Contact the administration.'),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _classId,
                      decoration: InputDecoration(labelText: _fr ? 'Salle' : 'Class', border: const OutlineInputBorder()),
                      items: _classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.displayName))).toList(),
                      onChanged: _pickClass,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _subjectId,
                      decoration: InputDecoration(labelText: _fr ? 'Matière' : 'Subject', border: const OutlineInputBorder()),
                      items: _subjects.map((s) => DropdownMenuItem(value: s.subjectId, child: Text(s.nameFor(_lang)))).toList(),
                      onChanged: (v) {
                        setState(() => _subjectId = v);
                        _loadGrid();
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _periodId,
                      decoration: InputDecoration(labelText: _fr ? 'Période' : 'Period', border: const OutlineInputBorder()),
                      items: _periods.map((p) => DropdownMenuItem(value: p.id, child: Text(p.labelFor(_lang)))).toList(),
                      onChanged: (v) {
                        setState(() => _periodId = v);
                        _loadGrid();
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_loadingGrid) const Center(child: CircularProgressIndicator()),
                    if (!_loadingGrid && _roster.isNotEmpty)
                      ..._roster.map(
                        (s) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(s.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              Row(children: [
                                SizedBox(
                                  width: 96,
                                  child: TextField(
                                    controller: _scores[s.id],
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(labelText: '/20', border: OutlineInputBorder(), isDense: true),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _comments[s.id],
                                    decoration: InputDecoration(
                                      labelText: _fr ? 'Remarque (optionnel)' : 'Remark (optional)',
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ]),
                            ]),
                          ),
                        ),
                      ),
                    if (!_loadingGrid && _roster.isEmpty && _classId != null && _subjectId != null && _periodId != null)
                      Text(_fr ? 'Aucun élève dans cette salle.' : 'No students in this class.'),
                  ],
                ),
    );
  }
}
