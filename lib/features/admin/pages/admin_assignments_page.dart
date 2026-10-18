import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/admin_school_service.dart';
import '../../../core/services/exam_catalog_service.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../models/exam_catalog.dart';
import '../../../models/pedagogy.dart';
import '../../../models/school_class.dart';

class AdminAssignmentsPage extends StatefulWidget {
  final Locale locale;

  const AdminAssignmentsPage({super.key, required this.locale});

  @override
  State<AdminAssignmentsPage> createState() => _AdminAssignmentsPageState();
}

class _AdminAssignmentsPageState extends State<AdminAssignmentsPage> {
  final SupabaseClient _client = Supabase.instance.client;

  late Future<List<Map<String, dynamic>>> _assignmentsFuture;

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _assignmentsFuture = _fetchAssignments();
  }

  Future<List<Map<String, dynamic>>> _fetchAssignments() async {
    final response = await _client
        .from('assignments')
        .select(
          'id,course_id,lesson_id,teacher_id,class_id,title_fr,title_en,'
          'instructions_fr,instructions_en,starts_at,due_at,results_publish_at,status,max_score,exam_id,subject_id,evaluation_file_name,created_at',
        )
        .order('created_at', ascending: false);

    return (response as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _assignmentsFuture = _fetchAssignments();
    });

    await _assignmentsFuture;
  }

  String _title(Map<String, dynamic> assignment) {
    final titleFr = assignment['title_fr']?.toString().trim() ?? '';
    final titleEn = assignment['title_en']?.toString().trim() ?? '';

    if (_isFrench) {
      return titleFr.isNotEmpty ? titleFr : titleEn;
    }

    return titleEn.isNotEmpty ? titleEn : titleFr;
  }

  String _instructions(Map<String, dynamic> assignment) {
    final fr = assignment['instructions_fr']?.toString().trim() ?? '';
    final en = assignment['instructions_en']?.toString().trim() ?? '';

    if (_isFrench) {
      return fr.isNotEmpty ? fr : en;
    }

    return en.isNotEmpty ? en : fr;
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'published':
        return _isFrench ? 'Publié' : 'Published';
      case 'draft':
        return _isFrench ? 'Brouillon' : 'Draft';
      case 'closed':
        return _isFrench ? 'Fermé' : 'Closed';
      case 'archived':
        return _isFrench ? 'Archivé' : 'Archived';
      default:
        return status?.isNotEmpty == true
            ? status!
            : (_isFrench ? 'Inconnu' : 'Unknown');
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'published':
        return Colors.green;
      case 'closed':
        return Colors.redAccent;
      case 'archived':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  String _formatDueDate(String? value) {
    if (value == null || value.isEmpty) {
      return _isFrench ? 'Aucune échéance' : 'No deadline';
    }

    final date = DateTime.tryParse(value);

    if (date == null) {
      return value;
    }

    final localDate = date.toLocal();

    final day = localDate.day.toString().padLeft(2, '0');
    final month = localDate.month.toString().padLeft(2, '0');
    final year = localDate.year.toString();
    final hour = localDate.hour.toString().padLeft(2, '0');
    final minute = localDate.minute.toString().padLeft(2, '0');

    return '$day/$month/$year $hour:$minute';
  }

  void _showAssignmentDetails(Map<String, dynamic> assignment) {
    final title = _title(assignment);
    final instructions = _instructions(assignment);
    final status = assignment['status']?.toString();
    final maxScore = assignment['max_score']?.toString() ?? '';
    final startsAt = assignment['starts_at']?.toString();
    final dueAt = assignment['due_at']?.toString();
    final resultsPublishAt = assignment['results_publish_at']?.toString();
    final evaluationFileName = assignment['evaluation_file_name']?.toString();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isNotEmpty
                      ? title
                      : (_isFrench
                            ? 'Devoir sans titre'
                            : 'Untitled assignment'),
                  style: Theme.of(sheetContext).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      avatar: Icon(
                        Icons.circle,
                        size: 12,
                        color: _statusColor(status),
                      ),
                      label: Text(_statusLabel(status)),
                    ),
                    if (maxScore.isNotEmpty)
                      Chip(
                        avatar: const Icon(
                          Icons.star_outline_rounded,
                          size: 18,
                        ),
                        label: Text(
                          _isFrench
                              ? 'Note max : $maxScore'
                              : 'Max score: $maxScore',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (startsAt != null && startsAt.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.play_arrow_rounded),
                    title: Text(_isFrench ? 'Début de l’évaluation' : 'Evaluation starts'),
                    subtitle: Text(_formatDueDate(startsAt)),
                  ),
                if (dueAt != null && dueAt.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_rounded),
                    title: Text(_isFrench ? 'Fin de l’évaluation' : 'Evaluation ends'),
                    subtitle: Text(_formatDueDate(dueAt)),
                  ),
                if (resultsPublishAt != null && resultsPublishAt.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.visibility_rounded),
                    title: Text(_isFrench ? 'Publication des résultats' : 'Results release'),
                    subtitle: Text(_formatDueDate(resultsPublishAt)),
                  ),
                if (evaluationFileName != null && evaluationFileName.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.picture_as_pdf_rounded),
                    title: Text(_isFrench ? 'Épreuve officielle' : 'Official exam paper'),
                    subtitle: Text(evaluationFileName),
                  ),
                const SizedBox(height: 8),
                Text(
                  instructions.isNotEmpty
                      ? instructions
                      : (_isFrench ? 'Aucune consigne.' : 'No instructions.'),
                  style: const TextStyle(height: 1.45),
                ),
                const SizedBox(height: 16),
                _buildTechnicalInfo(sheetContext, assignment),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTechnicalInfo(
    BuildContext context,
    Map<String, dynamic> assignment,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isFrench ? 'Références' : 'References',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          _infoLine(
            context,
            _isFrench ? 'ID du devoir' : 'Assignment ID',
            assignment['id']?.toString() ?? '',
          ),
          _infoLine(
            context,
            _isFrench ? 'Cours' : 'Course',
            assignment['course_id']?.toString() ?? '',
          ),
          _infoLine(
            context,
            _isFrench ? 'Leçon' : 'Lesson',
            assignment['lesson_id']?.toString() ?? '',
          ),
          _infoLine(
            context,
            _isFrench ? 'Enseignant' : 'Teacher',
            assignment['teacher_id']?.toString() ?? '',
          ),
          _infoLine(
            context,
            _isFrench ? 'Salle' : 'Classroom',
            assignment['class_id']?.toString() ?? '',
          ),
        ],
      ),
    );
  }

  Widget _infoLine(BuildContext context, String label, String value) {
    if (value.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createScheduledExam() async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) {
      _snack(_isFrench ? 'Connectez-vous comme administrateur.' : 'Sign in as an administrator.');
      return;
    }

    late final List<SchoolClass> rooms;
    late final List<ExamDefinition> exams;
    try {
      rooms = (await AdminSchoolService().listClasses())
          .where((room) => room.isActive)
          .toList(growable: false);
      exams = await ExamCatalogService().getExams();
    } catch (error) {
      _snack('${_isFrench ? 'Impossible de charger les classes et examens' : 'Unable to load classes and exams'}: $error');
      return;
    }
    if (!mounted) return;
    if (rooms.isEmpty || exams.isEmpty) {
      _snack(_isFrench
          ? 'Ajoutez d’abord les classes et examens dans le catalogue.'
          : 'Add classrooms and exams to the catalogue first.');
      return;
    }

    final titleFrController = TextEditingController();
    final titleEnController = TextEditingController();
    final instructionsController = TextEditingController();
    final chosenRoomIds = <String>{};
    final courseService = CourseService();
    Map<String, Subject> commonSubjects = <String, Subject>{};
    Subject? chosenSubject;
    ExamDefinition? chosenExam;
    PlatformFile? selectedPdf;
    DateTime startsAt = DateTime.now().add(const Duration(minutes: 5));
    DateTime dueAt = DateTime.now().add(const Duration(hours: 1));
    DateTime resultsPublishAt = DateTime.now().add(const Duration(days: 1, hours: 1));
    bool saving = false;
    String? localError;

    Map<String, SchoolClass> expandedCohort() {
      final targets = <String, SchoolClass>{};
      for (final chosen in rooms.where((room) => chosenRoomIds.contains(room.id))) {
        targets[chosen.id] = chosen;
        if (chosen.examLevelId == null) continue;
        for (final candidate in rooms) {
          if (candidate.academicYearId == chosen.academicYearId &&
              candidate.subsystem == chosen.subsystem &&
              candidate.sector == chosen.sector &&
              candidate.examLevelId == chosen.examLevelId) {
            targets[candidate.id] = candidate;
          }
        }
      }
      return targets;
    }

    Future<void> refreshCommonSubjects(StateSetter refresh) async {
      if (chosenRoomIds.isEmpty) {
        refresh(() {
          commonSubjects = <String, Subject>{};
          chosenSubject = null;
        });
        return;
      }
      try {
        // Offer subjects based only on the rooms explicitly selected by the
        // administrator. Expanding to every compatible recipient before this
        // intersection can erase all subjects when sibling streams have
        // different curricula. Compatible recipient rooms are resolved after
        // the subject is chosen, and only rooms carrying that subject receive it.
        final selectedRooms = rooms
            .where((room) => chosenRoomIds.contains(room.id))
            .toList(growable: false);
        Map<String, Subject>? intersection;
        for (final room in selectedRooms) {
          final subjects = await courseService.listSubjectsForClass(room.id);
          final byId = <String, Subject>{for (final subject in subjects) subject.id: subject};
          intersection = intersection == null
              ? byId
              : <String, Subject>{
                  for (final entry in intersection.entries)
                    if (byId.containsKey(entry.key)) entry.key: entry.value,
                };
        }
        refresh(() {
          commonSubjects = intersection ?? <String, Subject>{};
          if (chosenSubject != null && !commonSubjects.containsKey(chosenSubject!.id)) {
            chosenSubject = null;
          }
          localError = null;
        });
      } catch (error) {
        refresh(() => localError = '${_isFrench ? 'Chargement des matières impossible' : 'Unable to load subjects'}: $error');
      }
    }

    Future<DateTime?> chooseDateTime(
      BuildContext dialogContext,
      DateTime initial,
    ) async {
      final date = await showDatePicker(
        context: dialogContext,
        initialDate: initial,
        firstDate: DateTime.now().subtract(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 3650)),
      );
      if (date == null || !dialogContext.mounted) return null;
      final time = await showTimePicker(
        context: dialogContext,
        initialTime: TimeOfDay.fromDateTime(initial),
      );
      if (time == null) return null;
      return DateTime(date.year, date.month, date.day, time.hour, time.minute);
    }

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: !saving,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) {
          Future<void> saveExam() async {
            final titleFr = titleFrController.text.trim();
            final titleEn = titleEnController.text.trim().isEmpty
                ? titleFr
                : titleEnController.text.trim();
            if (chosenExam == null ||
                chosenSubject == null ||
                chosenRoomIds.isEmpty ||
                titleFr.isEmpty ||
                selectedPdf?.bytes == null ||
                selectedPdf!.bytes!.isEmpty) {
              refresh(() => localError = _isFrench
                  ? 'Choisissez l’examen, les salles, la matière, un titre et un PDF valide.'
                  : 'Choose the exam, classrooms, subject, a title and a valid PDF.');
              return;
            }
            if (!dueAt.isAfter(startsAt)) {
              refresh(() => localError = _isFrench
                  ? 'La fin doit être postérieure au début.'
                  : 'The end time must be after the start time.');
              return;
            }
            if (resultsPublishAt.isBefore(dueAt)) {
              refresh(() => localError = _isFrench
                  ? 'La publication des résultats doit être prévue à la fin de l’évaluation ou après.'
                  : 'Results must be scheduled for the end of the evaluation or later.');
              return;
            }

            final targets = <SchoolClass>[];
            try {
              for (final room in expandedCohort().values) {
                final subjects = await courseService.listSubjectsForClass(room.id);
                if (subjects.any((subject) => subject.id == chosenSubject!.id)) {
                  targets.add(room);
                }
              }
            } catch (error) {
              refresh(() => localError = '${_isFrench ? 'Vérification des matières impossible' : 'Unable to verify subjects'}: $error');
              return;
            }
            if (targets.isEmpty) {
              refresh(() => localError = _isFrench
                  ? 'Aucune salle destinataire ne possède cette matière.'
                  : 'No target classroom has this subject.');
              return;
            }

            refresh(() {
              saving = true;
              localError = null;
            });
            final safeName = selectedPdf!.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
            final path = '${currentUser.id}/${DateTime.now().millisecondsSinceEpoch}/$safeName';
            final createdIds = <String>[];
            var uploaded = false;
            try {
              await _client.storage.from('assignment-files').uploadBinary(
                path,
                selectedPdf!.bytes!,
                fileOptions: const FileOptions(
                  contentType: 'application/pdf',
                  upsert: false,
                ),
              );
              uploaded = true;

              for (final room in targets) {
                final row = await _client.from('assignments').insert({
                  'course_id': null,
                  'lesson_id': null,
                  'teacher_id': currentUser.id,
                  'class_id': room.id,
                  'subject_id': chosenSubject!.id,
                  'exam_id': chosenExam!.id,
                  'title_fr': titleFr,
                  'title_en': titleEn,
                  'instructions_fr': instructionsController.text.trim(),
                  'instructions_en': instructionsController.text.trim(),
                  'starts_at': startsAt.toUtc().toIso8601String(),
                  'due_at': dueAt.toUtc().toIso8601String(),
                  'results_publish_at': resultsPublishAt.toUtc().toIso8601String(),
                  'status': 'draft',
                  'max_score': 20,
                }).select('id').single();
                createdIds.add(row['id'].toString());
              }

              for (final id in createdIds) {
                await _client.from('assignments').update({
                  'evaluation_file_path': path,
                  'evaluation_file_name': selectedPdf!.name,
                  'published_at': DateTime.now().toUtc().toIso8601String(),
                  'status': 'published',
                }).eq('id', id);
              }

              if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
            } catch (error) {
              for (final id in createdIds) {
                try {
                  await _client.from('assignments').delete().eq('id', id);
                } catch (_) {}
              }
              if (uploaded) {
                try {
                  await _client.storage.from('assignment-files').remove([path]);
                } catch (_) {}
              }
              refresh(() {
                saving = false;
                localError = '${_isFrench ? 'Publication annulée' : 'Publication failed'}: $error';
              });
            }
          }

          String formatDateTime(DateTime value) {
            final local = value.toLocal();
            return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
          }

          return AlertDialog(
            title: Text(_isFrench ? 'Programmer une épreuve officielle' : 'Schedule an official exam'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<ExamDefinition>(
                      value: chosenExam,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: _isFrench ? 'Examen / diplôme' : 'Exam / qualification'),
                      items: exams.map((exam) => DropdownMenuItem(
                        value: exam,
                        child: Text(exam.labelFor(widget.locale.languageCode), overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: saving ? null : (value) => refresh(() => chosenExam = value),
                    ),
                    const SizedBox(height: 10),
                    Text(_isFrench
                        ? 'Sélectionnez une ou plusieurs salles. Les filières du même niveau sont ensuite vérifiées automatiquement.'
                        : 'Select one or more classrooms. Streams in the same level are then checked automatically.'),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 210),
                      child: ListView(
                        shrinkWrap: true,
                        children: rooms.map((room) => CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: chosenRoomIds.contains(room.id),
                          title: Text(room.displayName),
                          onChanged: saving ? null : (value) async {
                            refresh(() {
                              if (value == true) {
                                chosenRoomIds.add(room.id);
                              } else {
                                chosenRoomIds.remove(room.id);
                              }
                            });
                            await refreshCommonSubjects(refresh);
                          },
                        )).toList(),
                      ),
                    ),
                    DropdownButtonFormField<Subject>(
                      value: chosenSubject,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: _isFrench ? 'Matière commune' : 'Common subject'),
                      items: (commonSubjects.values.toList()
                            ..sort((a, b) => a.labelFor(widget.locale.languageCode)
                                .compareTo(b.labelFor(widget.locale.languageCode))))
                          .map((subject) => DropdownMenuItem<Subject>(
                                value: subject,
                                child: Text(subject.labelFor(widget.locale.languageCode),
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: saving || commonSubjects.isEmpty
                          ? null
                          : (value) => refresh(() => chosenSubject = value),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: titleFrController,
                      decoration: InputDecoration(labelText: _isFrench ? 'Titre de l’épreuve' : 'Exam title'),
                    ),
                    TextField(
                      controller: titleEnController,
                      decoration: InputDecoration(labelText: _isFrench ? 'Titre anglais (facultatif)' : 'English title (optional)'),
                    ),
                    TextField(
                      controller: instructionsController,
                      maxLines: 2,
                      decoration: InputDecoration(labelText: _isFrench ? 'Consignes (facultatif)' : 'Instructions (optional)'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: saving ? null : () async {
                        final picked = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: const ['pdf'],
                          withData: true,
                        );
                        if (picked != null && picked.files.isNotEmpty && dialogContext.mounted) {
                          refresh(() {
                            selectedPdf = picked.files.single;
                            localError = null;
                          });
                        }
                      },
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: Text(selectedPdf?.name ??
                          (_isFrench ? 'Choisir le PDF officiel' : 'Choose official PDF')),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: saving ? null : () async {
                        final picked = await chooseDateTime(dialogContext, startsAt);
                        if (picked != null && dialogContext.mounted) refresh(() => startsAt = picked);
                      },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text('${_isFrench ? 'Début' : 'Starts'} : ${formatDateTime(startsAt)}'),
                    ),
                    OutlinedButton.icon(
                      onPressed: saving ? null : () async {
                        final picked = await chooseDateTime(dialogContext, dueAt);
                        if (picked != null && dialogContext.mounted) {
                          refresh(() {
                            dueAt = picked;
                            if (resultsPublishAt.isBefore(dueAt)) {
                              resultsPublishAt = dueAt.add(const Duration(days: 1));
                            }
                          });
                        }
                      },
                      icon: const Icon(Icons.stop_rounded),
                      label: Text('${_isFrench ? 'Fin' : 'Ends'} : ${formatDateTime(dueAt)}'),
                    ),
                    OutlinedButton.icon(
                      onPressed: saving ? null : () async {
                        final picked = await chooseDateTime(dialogContext, resultsPublishAt);
                        if (picked != null && dialogContext.mounted) {
                          refresh(() => resultsPublishAt = picked);
                        }
                      },
                      icon: const Icon(Icons.visibility_rounded),
                      label: Text('${_isFrench ? 'Publication des résultats' : 'Results release'} : ${formatDateTime(resultsPublishAt)}'),
                    ),
                    if (localError != null) ...[
                      const SizedBox(height: 8),
                      Text(localError!, style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.of(dialogContext).pop(false),
                child: Text(_isFrench ? 'Annuler' : 'Cancel'),
              ),
              FilledButton.icon(
                onPressed: saving ? null : saveExam,
                icon: saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.publish_rounded),
                label: Text(_isFrench ? 'Programmer et publier' : 'Schedule and publish'),
              ),
            ],
          );
        },
      ),
    );

    titleFrController.dispose();
    titleEnController.dispose();
    instructionsController.dispose();
    if (created == true && mounted) {
      setState(() {
        _assignmentsFuture = _fetchAssignments();
      });
      _snack(_isFrench
          ? 'Épreuve programmée et publiée dans les salles compatibles.'
          : 'Exam scheduled and published to compatible classrooms.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isFrench ? 'Exercices et évaluations' : 'Exercises and assessments',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: _isFrench ? 'Actualiser' : 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createScheduledExam,
        icon: const Icon(Icons.add_rounded),
        label: Text(_isFrench ? 'Programmer une épreuve' : 'Schedule an exam'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _assignmentsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 220),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _isFrench
                          ? 'Impossible de charger les exercices.'
                          : 'Unable to load exercises.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          }

          final assignments = snapshot.data ?? [];

          if (assignments.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 220),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.assignment_outlined,
                          size: 56,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isFrench
                              ? 'Aucun exercice ou devoir disponible.'
                              : 'No exercise or assignment available.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: assignments.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final assignment = assignments[index];
                final title = _title(assignment);
                final status = assignment['status']?.toString();
                final classId = assignment['class_id']?.toString() ?? '';

                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF166534),
                      child: const Icon(
                        Icons.assignment_rounded,
                        color: Colors.white,
                      ),
                    ),
                    title: Text(
                      title.isNotEmpty
                          ? title
                          : (_isFrench
                                ? 'Devoir sans titre'
                                : 'Untitled assignment'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_statusLabel(status)),
                          if (classId.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${_isFrench ? 'Salle' : 'Class'} : $classId',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showAssignmentDetails(assignment),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
