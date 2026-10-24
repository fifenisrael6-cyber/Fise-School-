import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// L'administrateur est seul responsable du calendrier officiel des examens.
/// Le PDF est joint ensuite par l'enseignant affecté à la salle.
class AdminEvaluationSchedulePage extends StatefulWidget {
  const AdminEvaluationSchedulePage({super.key, required this.locale});
  final Locale locale;

  @override
  State<AdminEvaluationSchedulePage> createState() => _AdminEvaluationSchedulePageState();
}

class _AdminEvaluationSchedulePageState extends State<AdminEvaluationSchedulePage> {
  final SupabaseClient _db = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _exams = [];
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _schedules = [];
  List<Map<String, dynamic>> _classSubjects = [];

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait<dynamic>([
        _db.from('school_classes')
            .select('id,name,display_name,subsystem,sector,is_active')
            .eq('is_active', true).order('display_name'),
        _db.from('subjects')
            .select('id,name_fr,name_en,is_active')
            .eq('is_active', true).order('name_fr'),
        _db.from('exams')
            .select('id,code,name_fr,name_en,active')
            .eq('active', true).order('name_fr'),
        _db.from('profiles')
            .select('id,first_name,last_name,email,subsystem,sector')
            .eq('role', 'teacher').order('last_name'),
        _db.from('evaluations')
            .select('id,teacher_id,subject_id,exam_id,title,starts_at,due_at,results_visible_at,pdf_path,pdf_name,correction_pdf_path,correction_pdf_name,status,evaluation_classes(class_id)')
            .not('exam_id', 'is', null).order('starts_at'),
        _db.from('class_subjects')
            .select('class_id,subject_id').eq('is_active', true),
      ]);
      if (!mounted) return;
      setState(() {
        _classes = (results[0] as List).map((r) => Map<String, dynamic>.from(r)).toList();
        _subjects = (results[1] as List).map((r) => Map<String, dynamic>.from(r)).toList();
        _exams = (results[2] as List).map((r) => Map<String, dynamic>.from(r)).toList();
        _teachers = (results[3] as List).map((r) => Map<String, dynamic>.from(r)).toList();
        _schedules = (results[4] as List).map((raw) {
          final row = Map<String, dynamic>.from(raw);
          final targets = row.remove('evaluation_classes') as List? ?? const [];
          final targetClassId = targets.isEmpty
              ? null
              : Map<String, dynamic>.from(targets.first as Map)['class_id'];
          return {
            ...row,
            'class_id': targetClassId,
            'title_fr': row['title'],
            'title_en': row['title'],
            'results_publish_at': row['results_visible_at'],
            'evaluation_file_path': row['pdf_path'],
            'evaluation_file_name': row['pdf_name'],
          };
        }).toList();
        _classSubjects = (results[5] as List).map((r) => Map<String, dynamic>.from(r)).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _label(Map<String, dynamic>? row, String frenchKey, String englishKey) {
    if (row == null) return '';
    final first = row[_fr ? frenchKey : englishKey]?.toString().trim() ?? '';
    final second = row[_fr ? englishKey : frenchKey]?.toString().trim() ?? '';
    return first.isNotEmpty ? first : second;
  }

  String _teacherLabel(Map<String, dynamic> row) {
    final name = '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'.trim();
    return name.isNotEmpty ? name : (row['email']?.toString() ?? row['id'].toString());
  }

  Map<String, dynamic>? _byId(List<Map<String, dynamic>> list, dynamic id) {
    for (final row in list) {
      if (row['id']?.toString() == id?.toString()) return row;
    }
    return null;
  }

  List<Map<String, dynamic>> _subjectsForClass(String? classId) {
    if (classId == null) return const [];
    final ids = _classSubjects
        .where((r) => r['class_id'].toString() == classId)
        .map((r) => r['subject_id'].toString()).toSet();
    return _subjects.where((s) => ids.contains(s['id'].toString())).toList();
  }

  List<Map<String, dynamic>> _teachersForClass(Map<String, dynamic>? schoolClass) {
    if (schoolClass == null) return const [];
    return _teachers.where((teacher) =>
      teacher['subsystem'] == schoolClass['subsystem'] &&
      teacher['sector'] == schoolClass['sector']).toList();
  }

  DateTime _defaultStart() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final isWeekend = tomorrow.weekday == DateTime.saturday ||
        tomorrow.weekday == DateTime.sunday;
    return DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      isWeekend ? 18 : 19,
      isWeekend ? 0 : 20,
    );
  }

  bool _isAllowedWindow(DateTime startsAt, DateTime dueAt) {
    if (startsAt.year != dueAt.year ||
        startsAt.month != dueAt.month ||
        startsAt.day != dueAt.day) {
      return false;
    }
    final isWeekend = startsAt.weekday == DateTime.saturday ||
        startsAt.weekday == DateTime.sunday;
    final earliest = isWeekend
        ? const TimeOfDay(hour: 18, minute: 0)
        : const TimeOfDay(hour: 19, minute: 20);
    final startMinutes = startsAt.hour * 60 + startsAt.minute;
    final dueMinutes = dueAt.hour * 60 + dueAt.minute;
    final earliestMinutes = earliest.hour * 60 + earliest.minute;
    return startMinutes >= earliestMinutes &&
        dueMinutes <= 22 * 60 &&
        dueMinutes > startMinutes;
  }

  Future<DateTime?> _pickDateTime(BuildContext context, DateTime current) async {
    final date = await showDatePicker(
      context: context,
      initialDate: current.isBefore(DateTime.now()) ? DateTime.now() : current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _date(DateTime value) {
    final d = value.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _createSchedule() async {
    if (_classes.isEmpty || _exams.isEmpty || _subjects.isEmpty || _teachers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_fr
        ? 'Il manque des classes, examens, matières ou enseignants actifs.'
        : 'Active classrooms, exams, subjects or teachers are missing.')));
      return;
    }
    String? classId;
    String? examId;
    String? subjectId;
    String? teacherId;
    DateTime startsAt = _defaultStart();
    DateTime dueAt = startsAt.add(const Duration(hours: 2));
    DateTime resultsAt = dueAt.add(const Duration(days: 1));
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final schoolClass = _byId(_classes, classId);
          final subjectOptions = _subjectsForClass(classId);
          final teacherOptions = _teachersForClass(schoolClass);
          if (subjectId != null && !subjectOptions.any((s) => s['id'].toString() == subjectId)) subjectId = null;
          if (teacherId != null && !teacherOptions.any((t) => t['id'].toString() == teacherId)) teacherId = null;
          return AlertDialog(
            title: Text(_fr ? 'Programmer une évaluation officielle' : 'Schedule an official exam'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey('class-$classId'),
                    initialValue: classId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: _fr ? 'Salle / classe' : 'Classroom'),
                    items: _classes.map((c) => DropdownMenuItem(
                      value: c['id'].toString(),
                      child: Text(c['display_name']?.toString() ?? c['name'].toString(), overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (v) => setDialogState(() {
                      classId = v;
                      subjectId = null;
                      teacherId = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey('exam-$examId'),
                    initialValue: examId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: _fr ? 'Examen concerné' : 'Exam'),
                    items: _exams.map((e) => DropdownMenuItem(
                      value: e['id'].toString(),
                      child: Text(_label(e, 'name_fr', 'name_en'), overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (v) => setDialogState(() => examId = v),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey('subject-$classId-$subjectId'),
                    initialValue: subjectId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: _fr ? 'Matière de cette salle' : 'Subject in this class'),
                    items: subjectOptions.map((s) => DropdownMenuItem(
                      value: s['id'].toString(),
                      child: Text(_label(s, 'name_fr', 'name_en'), overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (v) => setDialogState(() => subjectId = v),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey('teacher-$classId-$teacherId'),
                    initialValue: teacherId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: _fr ? 'Enseignant responsable du PDF' : 'Teacher responsible for the PDF'),
                    items: teacherOptions.map((t) => DropdownMenuItem(
                      value: t['id'].toString(), child: Text(_teacherLabel(t), overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (v) => setDialogState(() => teacherId = v),
                  ),
                  const SizedBox(height: 14),
                  _timeButton(
                    dialogContext,
                    _fr ? 'Début de l’épreuve' : 'Exam starts',
                    startsAt,
                    (v) => setDialogState(() {
                      startsAt = v;
                      dueAt = v.add(const Duration(hours: 2));
                      resultsAt = dueAt.add(const Duration(hours: 24));
                    }),
                  ),
                  _timeButton(
                    dialogContext,
                    _fr ? 'Fin de l’épreuve' : 'Exam ends',
                    dueAt,
                    (v) => setDialogState(() {
                      dueAt = v;
                      resultsAt = v.add(const Duration(hours: 24));
                    }),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_fr ? 'Publication automatique de la correction' : 'Automatic correction release'),
                    subtitle: Text(_date(resultsAt)),
                    trailing: const Icon(Icons.lock_clock_outlined),
                  ),
                  const SizedBox(height: 8),
                  Text(_fr
                    ? 'Le PDF sera ajouté ensuite par l’enseignant affecté. Il ne sera accessible aux élèves que pendant la période prévue.'
                    : 'The assigned teacher will attach the PDF later. Students can access it only during the scheduled exam window.',
                    style: Theme.of(dialogContext).textTheme.bodySmall),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_fr ? 'Annuler' : 'Cancel')),
              FilledButton(
                onPressed: () {
                  if (classId == null || examId == null || subjectId == null || teacherId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_fr ? 'Choisissez classe, examen, matière et enseignant.' : 'Select class, exam, subject and teacher.')));
                    return;
                  }
                  if (!dueAt.isAfter(startsAt) || resultsAt.isBefore(dueAt)) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_fr
                      ? 'La fin doit être après le début et les résultats après la fin.'
                      : 'The end must follow the start, and results must be released after the end.')));
                    return;
                  }
                  Navigator.pop(dialogContext, {
                    'class_id': classId, 'exam_id': examId, 'subject_id': subjectId,
                    'teacher_id': teacherId, 'starts_at': startsAt, 'due_at': dueAt,
                    'results_publish_at': resultsAt,
                  });
                },
                child: Text(_fr ? 'Programmer' : 'Schedule'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null) return;
    final selectedExam = _byId(_exams, result['exam_id']);
    final selectedSubject = _byId(_subjects, result['subject_id']);
    final selectedClass = _byId(_classes, result['class_id']);
    final starts = result['starts_at'] as DateTime;
    final due = result['due_at'] as DateTime;
    if (!_isAllowedWindow(starts, due)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_fr
        ? 'Horaires autorisés : du lundi au vendredi de 19 h 20 à 22 h, le week-end de 18 h à 22 h. L’épreuve doit se terminer le même jour.'
        : 'Allowed hours: Monday-Friday 19:20-22:00, weekends 18:00-22:00. The exam must finish on the same day.')));
      return;
    }
    final title = '${selectedExam?['name_fr'] ?? selectedExam?['name_en'] ?? ''} — ${selectedSubject?['name_fr'] ?? selectedSubject?['name_en'] ?? ''} (${selectedClass?['display_name'] ?? ''})';
    String? evaluationId;
    try {
      final inserted = await _db.from('evaluations').insert({
        'teacher_id': result['teacher_id'],
        'subject_id': result['subject_id'],
        'exam_id': result['exam_id'],
        'title': title,
        'instructions': 'Épreuve officielle programmée par l’administration.',
        'starts_at': starts.toUtc().toIso8601String(),
        'due_at': due.toUtc().toIso8601String(),
        'results_visible_at': (result['results_publish_at'] as DateTime).toUtc().toIso8601String(),
        'max_score': 20,
        'weight': 1,
        'status': 'draft',
      }).select('id').single();
      evaluationId = inserted['id'].toString();
      await _db.from('evaluation_classes').insert({
        'evaluation_id': evaluationId,
        'class_id': result['class_id'],
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_fr
          ? 'Épreuve programmée. L’enseignant doit maintenant envoyer le sujet PDF et son corrigé PDF.'
          : 'Exam scheduled. The teacher must now upload the exam PDF and its correction PDF.')));
        await _load();
      }
    } catch (e) {
      if (evaluationId != null) {
        try { await _db.from('evaluations').delete().eq('id', evaluationId); } catch (_) {}
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((_fr ? 'Échec de programmation : ' : 'Scheduling failed: ') + e.toString())));
    }
  }

  Future<void> _generateBatchSchedule() async {
    if (_exams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        _fr ? 'Aucun examen actif disponible.' : 'No active exam available.')));
      return;
    }
    String? examId = _exams.first['id']?.toString();
    DateTime startDate = DateTime.now().add(const Duration(days: 1));
    final daysController = TextEditingController(text: '7');
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) =>
        AlertDialog(
          title: Text(_fr ? 'Programmer automatiquement' : 'Generate schedule automatically'),
          content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: examId,
              isExpanded: true,
              decoration: InputDecoration(labelText: _fr ? 'Examen' : 'Exam'),
              items: _exams.map((e) => DropdownMenuItem<String>(
                value: e['id'].toString(),
                child: Text(_label(e, 'name_fr', 'name_en'), overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (v) => setDialogState(() => examId = v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_fr ? 'Date de début' : 'Start date'),
              subtitle: Text('${startDate.day.toString().padLeft(2, '0')}/${startDate.month.toString().padLeft(2, '0')}/${startDate.year}'),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final picked = await showDatePicker(
                  context: dialogContext,
                  initialDate: startDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setDialogState(() => startDate = DateTime(picked.year, picked.month, picked.day));
              },
            ),
            TextField(
              controller: daysController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: _fr ? 'Nombre de jours (1 à 30)' : 'Number of days (1 to 30)',
                helperText: _fr ? 'Il faut au moins un jour par matière.' : 'At least one day per subject is required.',
              ),
            ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_fr ? 'Annuler' : 'Cancel')),
            FilledButton(onPressed: () {
              final days = int.tryParse(daysController.text.trim());
              if (examId == null || days == null || days < 1 || days > 30) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
                  _fr ? 'Choisissez un examen et un nombre de jours entre 1 et 30.' : 'Select an exam and 1–30 days.')));
                return;
              }
              Navigator.pop(dialogContext, {'exam_id': examId, 'start_date': startDate, 'days': days});
            }, child: Text(_fr ? 'Générer' : 'Generate')),
          ],
        ),
      ),
    );
    daysController.dispose();
    if (result == null || !mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final response = await _db.rpc('generate_official_exam_schedule', params: {
        'p_exam_id': result['exam_id'],
        'p_start_date': (result['start_date'] as DateTime).toIso8601String().substring(0, 10),
        'p_days': result['days'],
        'p_class_ids': null,
      });
      if (!mounted) return;
      final data = Map<String, dynamic>.from(response as Map);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_fr
        ? 'Programmation terminée : ${data['created'] ?? 0} épreuve(s), ${data['skipped_existing'] ?? 0} déjà présente(s), ${data['missing_teacher'] ?? 0} sans enseignant.'
        : 'Schedule complete: ${data['created'] ?? 0} exam(s), ${data['skipped_existing'] ?? 0} already present, ${data['missing_teacher'] ?? 0} without a teacher.')));
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() { _loading = false; _error = e.toString(); });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          (_fr ? 'Échec de la programmation automatique : ' : 'Automatic scheduling failed: ') + e.toString())));
      }
    }
  }

  Widget _timeButton(BuildContext context, String label, DateTime current, ValueChanged<DateTime> onSet) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(_date(current)),
      trailing: const Icon(Icons.edit_calendar_outlined),
      onTap: () async {
        final selected = await _pickDateTime(context, current);
        if (selected != null) onSet(selected);
      },
    );
  }

  String _scheduleLabel(Map<String, dynamic> row) {
    final title = _fr ? row['title_fr']?.toString() : row['title_en']?.toString();
    return (title ?? '').trim().isNotEmpty ? title!.trim() : (_fr ? 'Évaluation officielle' : 'Official exam');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'Calendrier des évaluations' : 'Exam schedule'),
        actions: [IconButton(onPressed: _generateBatchSchedule, icon: const Icon(Icons.auto_awesome), tooltip: _fr ? 'Programmer toutes les matières' : 'Schedule all subjects'), IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: _fr ? 'Actualiser' : 'Refresh')],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createSchedule,
        icon: const Icon(Icons.add_alarm),
        label: Text(_fr ? 'Programmer' : 'Schedule'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!)))
              : _schedules.isEmpty
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_fr ? 'Aucune évaluation officielle programmée.' : 'No official exams scheduled yet.')))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        itemCount: _schedules.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final row = _schedules[i];
                          final schoolClass = _byId(_classes, row['class_id']);
                          final subject = _byId(_subjects, row['subject_id']);
                          final teacher = _byId(_teachers, row['teacher_id']);
                          final hasPdf = (row['evaluation_file_path']?.toString() ?? '').isNotEmpty;
                          final starts = DateTime.tryParse(row['starts_at']?.toString() ?? '');
                          final ends = DateTime.tryParse(row['due_at']?.toString() ?? '');
                          return Card(child: ListTile(
                            leading: Icon(hasPdf ? Icons.picture_as_pdf : Icons.event_note, color: hasPdf ? Colors.green : Colors.orange),
                            title: Text(_scheduleLabel(row), style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text([
                              schoolClass?['display_name']?.toString() ?? '',
                              _label(subject, 'name_fr', 'name_en'),
                              if (starts != null) _date(starts),
                              if (ends != null) (_fr ? 'Fin : ' : 'Ends: ') + _date(ends),
                              _teacherLabel(teacher ?? {'id': row['teacher_id'] ?? ''}),
                              hasPdf ? (_fr ? 'PDF joint' : 'PDF attached') : (_fr ? 'PDF en attente de l’enseignant' : 'Waiting for teacher PDF'),
                            ].where((s) => s.trim().isNotEmpty).join(' · ')),
                          ));
                        },
                      ),
                    ),
    );
  }
}
