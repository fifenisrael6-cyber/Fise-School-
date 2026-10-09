import 'package:flutter/material.dart';

import '../../../core/services/assignment_service.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/school_class.dart';
import '../../../models/user_profile.dart';
import '../widgets/class_subject_picker.dart';

class _QuestionDraft {
  final TextEditingController question = TextEditingController();
  final List<TextEditingController> options = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  int correctIndex = 0;

  void dispose() {
    question.dispose();
    for (final option in options) {
      option.dispose();
    }
  }
}

/// Espace de construction de QCM : l'enseignant choisit les classes et la
/// matière, construit ses questions, puis publie dans chaque classe choisie.
class QcmBuilderPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final bool examMode;

  const QcmBuilderPage({super.key, required this.locale, required this.profile, this.examMode = false});

  @override
  State<QcmBuilderPage> createState() => _QcmBuilderPageState();
}

class _QcmBuilderPageState extends State<QcmBuilderPage> {
  final AssignmentService _service = AssignmentService();
  final _title = TextEditingController();
  final _instructions = TextEditingController();
  final List<_QuestionDraft> _questions = [_QuestionDraft()];

  List<SchoolClass> _classes = const [];
  Subject? _subject;
  DateTime? _dueAt;
  bool _saving = false;

  bool get _fr => widget.locale.languageCode == 'fr';
  bool get _examMode => widget.examMode;

  @override
  void dispose() {
    _title.dispose();
    _instructions.dispose();
    for (final question in _questions) {
      question.dispose();
    }
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 18, minute: 0),
    );
    if (time == null || !mounted) {
      return;
    }
    setState(() {
      _dueAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  String? _validate() {
    if (_classes.isEmpty) {
      return _fr ? 'Choisissez au moins une classe.' : 'Choose at least one class.';
    }
    if (_subject == null) {
      return _fr ? 'Choisissez la matière.' : 'Choose the subject.';
    }
    if (_title.text.trim().isEmpty) {
      return _examMode ? (_fr ? 'Donnez un titre à l’examen.' : 'Give the exam a title.') : (_fr ? 'Donnez un titre au QCM.' : 'Give the quiz a title.');
    }
    for (var i = 0; i < _questions.length; i++) {
      final question = _questions[i];
      if (question.question.text.trim().isEmpty) {
        return _fr ? 'Question ${i + 1} : énoncé manquant.' : 'Question ${i + 1}: missing text.';
      }
      final filled = question.options.where((o) => o.text.trim().isNotEmpty).length;
      if (filled < 2) {
        return _fr
            ? 'Question ${i + 1} : au moins deux réponses.'
            : 'Question ${i + 1}: at least two answers.';
      }
      if (question.options[question.correctIndex].text.trim().isEmpty) {
        return _fr
            ? 'Question ${i + 1} : choisissez une bonne réponse remplie.'
            : 'Question ${i + 1}: pick a filled correct answer.';
      }
    }
    return null;
  }

  Future<void> _publish(String status) async {
    final problem = _validate();
    if (problem != null) {
      _snack(problem);
      return;
    }

    setState(() => _saving = true);

    var done = 0;
    final errors = <String>[];
    try {
      await CourseService().authorizeTeacherClasses(
        _classes.map((schoolClass) => schoolClass.id).toList(growable: false),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('${_fr ? 'Accès aux salles refusé' : 'Classroom access denied'}: $error');
      }
      return;
    }
    final title = _title.text.trim();
    final instructions = _instructions.text.trim();

    for (final schoolClass in _classes) {
      try {
        final assignment = await _service.saveAssignment(
          subjectId: _subject!.id,
          teacherId: widget.profile.id,
          classId: schoolClass.id,
          titleFr: title,
          titleEn: title,
          instructionsFr: instructions.isEmpty ? null : instructions,
          instructionsEn: instructions.isEmpty ? null : instructions,
          dueAt: _dueAt,
          status: 'draft',
          maxScore: _questions.length.toDouble(),
        );

        for (var i = 0; i < _questions.length; i++) {
          final draft = _questions[i];
          final options = <String>[];
          String? correct;
          for (var j = 0; j < draft.options.length; j++) {
            final text = draft.options[j].text.trim();
            if (text.isEmpty) {
              continue;
            }
            options.add(text);
            if (j == draft.correctIndex) {
              correct = text;
            }
          }
          await _service.saveQuestion(
            assignmentId: assignment.id,
            position: i + 1,
            questionFr: draft.question.text.trim(),
            questionEn: draft.question.text.trim(),
            questionType: 'qcm',
            points: 1,
            options: options,
            correctAnswer: correct,
          );
        }

        if (status == 'published') {
          await _service.publishAssignment(assignment.id);
        }
        done++;
      } catch (error) {
        errors.add('${schoolClass.displayName}: $error');
      }
    }

    if (!mounted) {
      return;
    }
    setState(() => _saving = false);

    if (errors.isNotEmpty) {
      _snack('${_fr ? 'Erreur' : 'Error'} (${errors.length}/${_classes.length})\n${errors.first}');
      if (done == 0) {
        return;
      }
    } else {
      _snack(status == 'published'
          ? (_examMode ? (_fr ? 'Examen publié dans $done salle(s).' : 'Exam published to $done classroom(s).') : (_fr ? 'QCM publié dans $done classe(s).' : 'Quiz published in $done class(es).'))
          : (_fr ? 'Brouillon enregistré.' : 'Draft saved.'));
    }

    Navigator.pop(context, true);
  }

  Widget _questionCard(int index) {
    final draft = _questions[index];
    final letters = ['A', 'B', 'C', 'D', 'E', 'F'];

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_fr ? 'Question' : 'Question'} ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (_questions.length > 1)
                  IconButton(
                    tooltip: _fr ? 'Supprimer' : 'Delete',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                              _questions.removeAt(index).dispose();
                            }),
                  ),
              ],
            ),
            TextField(
              controller: draft.question,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: _fr ? 'Énoncé' : 'Question text',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            for (var j = 0; j < draft.options.length; j++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: _fr ? 'Bonne réponse' : 'Correct answer',
                      onPressed: () => setState(() => draft.correctIndex = j),
                      icon: Icon(
                        draft.correctIndex == j
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: draft.correctIndex == j ? const Color(0xFF166534) : null,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: draft.options[j],
                        decoration: InputDecoration(
                          labelText: '${_fr ? 'Réponse' : 'Answer'} ${letters[j]}',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              _fr
                  ? 'Touchez le rond pour marquer la bonne réponse.'
                  : 'Tap the circle to mark the correct answer.',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_examMode ? (_fr ? 'Créer un examen' : 'Create an exam') : (_fr ? 'Nouveau QCM' : 'New quiz'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ClassSubjectPicker(
            locale: widget.locale,
            teacherId: widget.profile.id,
            includeCompatibleClasses: true,
            onChanged: (classes, subject) {
              setState(() {
                _classes = classes;
                _subject = subject;
              });
            },
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: _examMode ? (_fr ? 'Titre de l’examen' : 'Exam title') : (_fr ? 'Titre du QCM' : 'Quiz title'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _instructions,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: _fr ? 'Consignes (facultatif)' : 'Instructions (optional)',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _saving ? null : _pickDueDate,
            icon: const Icon(Icons.event_rounded),
            label: Text(
              _dueAt == null
                  ? (_fr ? 'Date limite (facultatif)' : 'Deadline (optional)')
                  : '${_dueAt!.day.toString().padLeft(2, '0')}/${_dueAt!.month.toString().padLeft(2, '0')}/${_dueAt!.year} '
                      '${_dueAt!.hour.toString().padLeft(2, '0')}:${_dueAt!.minute.toString().padLeft(2, '0')}',
            ),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < _questions.length; i++) _questionCard(i),
          OutlinedButton.icon(
            onPressed: _saving ? null : () => setState(() => _questions.add(_QuestionDraft())),
            icon: const Icon(Icons.add_rounded),
            label: Text(_fr ? 'Ajouter une question' : 'Add a question'),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _publish('draft'),
                  child: Text(_fr ? 'Brouillon' : 'Draft'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : () => _publish('published'),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_fr ? 'Publier' : 'Publish'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
