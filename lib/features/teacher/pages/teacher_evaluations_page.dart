import 'package:flutter/material.dart';

import '../../../core/services/evaluation_service.dart';
import '../../../core/services/grade_service.dart';
import '../../../core/services/photo_service.dart';
import '../../../models/evaluation.dart';
import '../../../models/grades.dart';
import '../../../models/school_class.dart';
import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';
import '../widgets/class_subject_picker.dart';
import 'teacher_evaluation_review_page.dart';

String _fmt(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final l = d.toLocal();
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

/// Épreuves PDF de l'enseignant : publication, suivi des remises, vérification des corrections.
class TeacherEvaluationsPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const TeacherEvaluationsPage({super.key, required this.locale, required this.profile});

  @override
  State<TeacherEvaluationsPage> createState() => _TeacherEvaluationsPageState();
}

class _TeacherEvaluationsPageState extends State<TeacherEvaluationsPage> {
  final _service = EvaluationService();
  List<TeacherEvaluation> _items = const [];
  bool _loading = true;
  String? _error;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.listTeacherEvaluations();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = EvaluationService.friendlyError(e, fr: _fr);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_fr ? 'Épreuves à corriger' : 'Exams to grade')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.upload_file_rounded),
        label: Text(_fr ? 'Nouvelle épreuve' : 'New exam'),
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => TeacherEvaluationFormPage(locale: widget.locale, profile: widget.profile),
            ),
          );
          if (created == true) _load();
        },
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(padding: const EdgeInsets.all(24), children: [Text(_error!)])
                : _items.isEmpty
                    ? ListView(padding: const EdgeInsets.all(24), children: [
                        Text(
                          _fr ? 'Aucune épreuve publiée.' : 'No exam published yet.',
                          textAlign: TextAlign.center,
                        ),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final e = _items[i];
                          return Card(
                            margin: EdgeInsets.zero,
                            child: ListTile(
                              leading: const Icon(Icons.fact_check_rounded),
                              title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                '${e.subjectFr} · ${e.classes.join(', ')}\n'
                                '${_fr ? 'Limite' : 'Due'} ${_fmt(e.dueAt)}\n'
                                '${_fr ? 'Remises' : 'Submitted'} ${e.submittedCount} · '
                                '${_fr ? 'à valider' : 'to validate'} ${e.toReviewCount} · '
                                '${_fr ? 'validées' : 'validated'} ${e.validatedCount}'
                                '${e.errorCount > 0 ? ' · ${_fr ? 'erreurs' : 'errors'} ${e.errorCount}' : ''}',
                              ),
                              isThreeLine: true,
                              trailing: PopupMenuButton<String>(
                                tooltip: _fr ? 'Actions sur l’épreuve' : 'Exam actions',
                                onSelected: (action) async {
                                  if (action == 'close') {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (dialogContext) => AlertDialog(
                                        title: Text(_fr ? 'Annuler l’épreuve ?' : 'Cancel exam?'),
                                        content: Text(_fr
                                            ? 'L’épreuve sera fermée. Les remises déjà reçues seront conservées.'
                                            : 'The exam will be closed. Existing submissions will be kept.'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_fr ? 'Retour' : 'Back')),
                                          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_fr ? 'Fermer' : 'Close')),
                                        ],
                                      ),
                                    );
                                    if (confirmed != true || !mounted) return;
                                    try {
                                      await _service.closeEvaluation(e.id);
                                      await _load();
                                    } catch (error) {
                                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(EvaluationService.friendlyError(error, fr: _fr))));
                                    }
                                  } else if (action == 'edit') {
                                    final controller = TextEditingController(text: e.title);
                                    final title = await showDialog<String>(
                                      context: context,
                                      builder: (dialogContext) => AlertDialog(
                                        title: Text(_fr ? 'Modifier le titre' : 'Edit title'),
                                        content: TextField(
                                          controller: controller,
                                          autofocus: true,
                                          maxLength: 200,
                                          decoration: InputDecoration(labelText: _fr ? 'Titre' : 'Title'),
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_fr ? 'Retour' : 'Back')),
                                          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: Text(_fr ? 'Enregistrer' : 'Save')),
                                        ],
                                      ),
                                    );
                                    controller.dispose();
                                    if (title == null || title.trim().length < 3 || !mounted) return;
                                    try {
                                      await _service.updateEvaluationTitle(e.id, title.trim());
                                      await _load();
                                    } catch (error) {
                                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(EvaluationService.friendlyError(error, fr: _fr))));
                                    }
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(value: 'edit', child: Text(_fr ? 'Modifier le titre' : 'Edit title')),
                                  if (e.status == 'published')
                                    PopupMenuItem(value: 'close', child: Text(_fr ? 'Annuler / fermer' : 'Cancel / close')),
                                ],
                              ),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TeacherEvaluationReviewPage(
                                      locale: widget.locale,
                                      evaluation: e,
                                    ),
                                  ),
                                );
                                if (mounted) _load();
                              },
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

class _SchemeRow {
  final label = TextEditingController();
  final points = TextEditingController();
}

class TeacherEvaluationFormPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const TeacherEvaluationFormPage({super.key, required this.locale, required this.profile});

  @override
  State<TeacherEvaluationFormPage> createState() => _TeacherEvaluationFormPageState();
}

class _TeacherEvaluationFormPageState extends State<TeacherEvaluationFormPage> {
  final _service = EvaluationService();
  final _title = TextEditingController();
  final _instructions = TextEditingController();
  final _duration = TextEditingController(text: '120');
  final _grace = TextEditingController(text: '5');
  final _penalty = TextEditingController(text: '10');
  final _maxScore = TextEditingController(text: '20');
  final _weight = TextEditingController(text: '1');
  final _criteria = TextEditingController();
  final List<_SchemeRow> _scheme = [];

  List<SchoolClass> _classes = const [];
  Subject? _subject;
  List<GradePeriod> _periods = const [];
  String? _periodId;
  PickedAttachment? _pdf;
  DateTime _start = DateTime.now().add(const Duration(hours: 1));
  DateTime? _due;
  bool _useDuration = true;
  String _latePolicy = 'reject';
  bool _saving = false;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    GradeService().listPeriods().then((p) {
      if (!mounted) return;
      final open = p.where((x) => !x.isPublished).toList();
      setState(() {
        _periods = open;
        _periodId = open.isNotEmpty ? open.first.id : null;
      });
    }).catchError((_) {});
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null || !mounted) return null;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _publish() async {
    final title = _title.text.trim();
    if (title.length < 3) return _snack(_fr ? 'Saisissez le titre de l’épreuve.' : 'Enter a title.');
    if (_classes.isEmpty || _subject == null) {
      return _snack(_fr ? 'Choisissez les classes et la matière.' : 'Choose classes and subject.');
    }
    if (_pdf == null) return _snack(_fr ? 'Ajoutez le fichier PDF.' : 'Attach the PDF.');
    final minutes = int.tryParse(_duration.text.trim());
    final due = _useDuration
        ? (minutes == null || minutes <= 0 ? null : _start.add(Duration(minutes: minutes)))
        : _due;
    if (due == null || !due.isAfter(_start)) {
      return _snack(_fr ? 'La limite doit suivre le début.' : 'The deadline must be after the start.');
    }
    if (!due.isAfter(DateTime.now())) {
      return _snack(_fr ? 'La limite est déjà passée.' : 'The deadline is already past.');
    }
    final max = double.tryParse(_maxScore.text.trim().replaceAll(',', '.')) ?? 20;
    final weight = double.tryParse(_weight.text.trim().replaceAll(',', '.')) ?? 1;
    final scheme = <Map<String, dynamic>>[];
    for (var i = 0; i < _scheme.length; i++) {
      final label = _scheme[i].label.text.trim();
      final pts = double.tryParse(_scheme[i].points.text.trim().replaceAll(',', '.'));
      if (label.isEmpty && pts == null) continue;
      if (pts == null || pts <= 0) {
        return _snack(_fr ? 'Barème : points invalides ligne ${i + 1}.' : 'Invalid points on row ${i + 1}.');
      }
      scheme.add({'key': '${scheme.length + 1}', 'label': label.isEmpty ? 'Question ${scheme.length + 1}' : label, 'points': pts});
    }
    final total = scheme.fold<double>(0, (a, b) => a + (b['points'] as double));
    if (scheme.isNotEmpty && (total - max).abs() > 0.01) {
      return _snack(_fr
          ? 'Le barème totalise $total points pour une épreuve sur $max.'
          : 'The scheme totals $total points for an exam out of $max.');
    }
    setState(() => _saving = true);
    try {
      await _service.createAndPublish(
        teacherId: widget.profile.id,
        subjectId: _subject!.id,
        classIds: _classes.map((c) => c.id).toList(),
        title: title,
        instructions: _instructions.text,
        startsAt: _start,
        dueAt: due,
        durationMinutes: _useDuration ? minutes : null,
        latePolicy: _latePolicy,
        lateGraceMinutes: int.tryParse(_grace.text.trim()) ?? 5,
        latePenaltyPercent: _latePolicy == 'accept_penalty'
            ? (double.tryParse(_penalty.text.trim().replaceAll(',', '.')) ?? 0)
            : 0,
        maxScore: max,
        weight: weight,
        periodId: _periodId,
        pdfBytes: _pdf!.bytes,
        pdfName: _pdf!.name,
        scheme: scheme,
        criteria: _criteria.text,
      );
      if (!mounted) return;
      _snack(_fr ? 'Épreuve publiée : les élèves sont notifiés.' : 'Exam published: students notified.');
      Navigator.pop(context, true);
    } catch (e) {
      _snack(EvaluationService.friendlyError(e, fr: _fr));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_fr ? 'Publier une épreuve' : 'Publish an exam')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClassSubjectPicker(
            locale: widget.locale,
            teacherId: widget.profile.id,
            onChanged: (classes, subject) => setState(() {
              _classes = classes;
              _subject = subject;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: InputDecoration(labelText: _fr ? 'Titre de l’épreuve' : 'Title', border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _instructions,
            maxLines: 3,
            decoration: InputDecoration(labelText: _fr ? 'Instructions' : 'Instructions', border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.picture_as_pdf_rounded),
            label: Text(_pdf?.name ?? (_fr ? 'Choisir le PDF de l’épreuve' : 'Choose the exam PDF')),
            onPressed: () async {
              final f = await PhotoService().pickFile(allowedExtensions: const ['pdf']);
              if (f != null) setState(() => _pdf = f);
            },
          ),
          const SizedBox(height: 14),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.play_circle_outline_rounded),
            title: Text(_fr ? 'Début' : 'Start'),
            subtitle: Text(_fmt(_start)),
            onTap: () async {
              final d = await _pickDateTime(_start);
              if (d != null) setState(() => _start = d);
            },
          ),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(_fr ? 'Durée' : 'Duration')),
              ButtonSegment(value: false, label: Text(_fr ? 'Heure limite' : 'Deadline')),
            ],
            selected: {_useDuration},
            onSelectionChanged: (s) => setState(() => _useDuration = s.first),
          ),
          const SizedBox(height: 8),
          if (_useDuration)
            TextField(
              controller: _duration,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: _fr ? 'Durée (minutes)' : 'Duration (minutes)', border: const OutlineInputBorder()),
            )
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.stop_circle_outlined),
              title: Text(_fr ? 'Heure limite de remise' : 'Submission deadline'),
              subtitle: Text(_due == null ? '—' : _fmt(_due!)),
              onTap: () async {
                final d = await _pickDateTime(_due ?? _start.add(const Duration(hours: 2)));
                if (d != null) setState(() => _due = d);
              },
            ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _latePolicy,
            decoration: InputDecoration(labelText: _fr ? 'Remise tardive' : 'Late submissions', border: const OutlineInputBorder()),
            items: [
              DropdownMenuItem(value: 'reject', child: Text(_fr ? 'Refusée après la limite' : 'Rejected after deadline')),
              DropdownMenuItem(value: 'accept_flagged', child: Text(_fr ? 'Acceptée, signalée en retard' : 'Accepted, flagged late')),
              DropdownMenuItem(value: 'accept_penalty', child: Text(_fr ? 'Acceptée avec pénalité' : 'Accepted with penalty')),
            ],
            onChanged: (v) => setState(() => _latePolicy = v ?? 'reject'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _grace,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: _fr ? 'Tolérance d’envoi (min)' : 'Upload grace (min)', border: const OutlineInputBorder()),
              ),
            ),
            if (_latePolicy == 'accept_penalty') ...[
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _penalty,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: _fr ? 'Pénalité (%)' : 'Penalty (%)', border: const OutlineInputBorder()),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _maxScore,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: _fr ? 'Barème total' : 'Total marks', border: const OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _weight,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: _fr ? 'Poids dans la moyenne' : 'Weight', border: const OutlineInputBorder()),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            initialValue: _periodId,
            decoration: InputDecoration(labelText: _fr ? 'Période du bulletin' : 'Report period', border: const OutlineInputBorder()),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(_fr ? 'Aucune (hors bulletin)' : 'None (not in report)')),
              ..._periods.map((p) => DropdownMenuItem<String?>(value: p.id, child: Text(p.labelFor(widget.locale.languageCode)))),
            ],
            onChanged: (v) => setState(() => _periodId = v),
          ),
          const SizedBox(height: 16),
          Text(
            _fr ? 'Barème par question (optionnel, confidentiel)' : 'Marking scheme (optional, confidential)',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          for (var i = 0; i < _scheme.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _scheme[i].label,
                    decoration: InputDecoration(labelText: '${_fr ? 'Question' : 'Question'} ${i + 1}', border: const OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _scheme[i].points,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Pts', border: OutlineInputBorder()),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => setState(() => _scheme.removeAt(i)),
                ),
              ]),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: Text(_fr ? 'Ajouter une question' : 'Add a question'),
              onPressed: () => setState(() => _scheme.add(_SchemeRow())),
            ),
          ),
          TextField(
            controller: _criteria,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: _fr ? 'Critères / réponses attendues (non visibles des élèves)' : 'Expected answers (hidden from students)',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _publish,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.publish_rounded),
            label: Text(_fr ? 'Publier aux élèves' : 'Publish to students'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
