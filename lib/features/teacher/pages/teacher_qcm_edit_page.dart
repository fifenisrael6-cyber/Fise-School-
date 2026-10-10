import 'package:flutter/material.dart';

import '../../../core/services/assignment_service.dart';
import '../../../models/assignment.dart';

class TeacherQcmEditPage extends StatefulWidget {
  final Locale locale;
  final Assignment assignment;

  const TeacherQcmEditPage({
    super.key,
    required this.locale,
    required this.assignment,
  });

  @override
  State<TeacherQcmEditPage> createState() => _TeacherQcmEditPageState();
}

class _QcmQuestionDraft {
  final String? id;
  final TextEditingController prompt;
  final List<TextEditingController> options;
  int correctIndex;

  _QcmQuestionDraft({
    this.id,
    String prompt = '',
    List<String> options = const ['', '', '', ''],
    this.correctIndex = 0,
  })  : prompt = TextEditingController(text: prompt),
        options = List.generate(
          4,
          (index) => TextEditingController(
            text: index < options.length ? options[index] : '',
          ),
        );

  void dispose() {
    prompt.dispose();
    for (final option in options) {
      option.dispose();
    }
  }
}

class _TeacherQcmEditPageState extends State<TeacherQcmEditPage> {
  final AssignmentService _service = AssignmentService();
  late final TextEditingController _title;
  late final TextEditingController _instructions;
  final List<_QcmQuestionDraft> _questions = [];
  List<AssignmentQuestion> _originalQuestions = const [];
  bool _loading = true;
  bool _saving = false;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.assignment.titleFor(widget.locale));
    _instructions = TextEditingController(
      text: widget.assignment.instructionsFor(widget.locale) ?? '',
    );
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _instructions.dispose();
    for (final question in _questions) {
      question.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _service.listQuestions(widget.assignment.id);
      if (!mounted) return;
      _originalQuestions = rows;
      for (final question in rows) {
        final options = question.options.take(4).toList();
        final correct = options.indexOf(question.correctAnswer ?? '');
        _questions.add(_QcmQuestionDraft(
          id: question.id,
          prompt: question.questionFor(widget.locale),
          options: options,
          correctIndex: correct < 0 ? 0 : correct,
        ));
      }
      if (_questions.isEmpty) _questions.add(_QcmQuestionDraft());
      setState(() => _loading = false);
    } catch (error) {
      if (mounted) setState(() => _loading = false);
      if (mounted) _message('${_fr ? 'Impossible de charger les questions' : 'Could not load questions'}: $error');
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      _message(_fr ? 'Le titre est obligatoire.' : 'A title is required.');
      return;
    }
    for (var i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final filled = q.options.where((o) => o.text.trim().isNotEmpty).length;
      if (q.prompt.text.trim().isEmpty || filled < 2 ||
          q.options[q.correctIndex].text.trim().isEmpty) {
        _message(_fr
          ? 'La question ${i + 1} doit avoir un énoncé, deux choix au minimum et une bonne réponse.'
          : 'Question ${i + 1} needs text, at least two choices, and a correct answer.');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      await _service.saveAssignment(
        id: widget.assignment.id,
        courseId: widget.assignment.courseId,
        subjectId: widget.assignment.subjectId,
        lessonId: widget.assignment.lessonId,
        teacherId: widget.assignment.teacherId,
        classId: widget.assignment.classId,
        titleFr: widget.locale.languageCode == 'fr' ? _title.text.trim() : widget.assignment.titleFr,
        titleEn: widget.locale.languageCode == 'en' ? _title.text.trim() : widget.assignment.titleEn,
        instructionsFr: widget.locale.languageCode == 'fr' ? _instructions.text.trim() : widget.assignment.instructionsFr,
        instructionsEn: widget.locale.languageCode == 'en' ? _instructions.text.trim() : widget.assignment.instructionsEn,
        dueAt: widget.assignment.dueAt,
        status: widget.assignment.status,
        maxScore: _questions.length.toDouble(),
      );

      final keptIds = <String>{};
      for (var i = 0; i < _questions.length; i++) {
        final draft = _questions[i];
        final options = draft.options
            .map((controller) => controller.text.trim())
            .where((text) => text.isNotEmpty)
            .toList(growable: false);
        final correctText = draft.options[draft.correctIndex].text.trim();
        AssignmentQuestion? old;
        if (draft.id != null) {
          for (final item in _originalQuestions) {
            if (item.id == draft.id) {
              old = item;
              break;
            }
          }
        }
        final frPrompt = widget.locale.languageCode == 'fr'
            ? draft.prompt.text.trim()
            : old?.questionFr ?? draft.prompt.text.trim();
        final enPrompt = widget.locale.languageCode == 'en'
            ? draft.prompt.text.trim()
            : old?.questionEn ?? draft.prompt.text.trim();
        final saved = await _service.saveQuestion(
          id: draft.id,
          assignmentId: widget.assignment.id,
          position: i + 1,
          questionFr: frPrompt,
          questionEn: enPrompt,
          questionType: 'qcm',
          points: 1,
          options: options,
          correctAnswer: correctText,
        );
        keptIds.add(saved.id);
      }

      for (final old in _originalQuestions) {
        if (!keptIds.contains(old.id)) {
          await _service.deleteQuestion(old.id);
        }
      }
      if (mounted) {
        _message(_fr ? 'QCM et questions modifiés.' : 'Quiz and questions updated.');
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) _message('${_fr ? 'Enregistrement impossible' : 'Save failed'}: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _questionCard(int index) {
    final question = _questions[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${_fr ? 'Question' : 'Question'} ${index + 1}',
              style: const TextStyle(fontWeight: FontWeight.w800))),
            if (_questions.length > 1)
              IconButton(
                tooltip: _fr ? 'Retirer la question' : 'Remove question',
                onPressed: _saving ? null : () => setState(() {
                  _questions.removeAt(index).dispose();
                }),
                icon: const Icon(Icons.delete_outline),
              ),
          ]),
          TextField(
            controller: question.prompt,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: _fr ? 'Énoncé' : 'Question',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < question.options.length; i++)
            Row(children: [
              Radio<int>(
                value: i,
                groupValue: question.correctIndex,
                onChanged: _saving ? null : (value) {
                  if (value != null) setState(() => question.correctIndex = value);
                },
              ),
              Expanded(child: TextField(
                controller: question.options[i],
                decoration: InputDecoration(
                  labelText: '${_fr ? 'Réponse' : 'Answer'} ${String.fromCharCode(65 + i)}',
                  isDense: true,
                ),
              )),
            ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_fr ? 'Modifier le QCM' : 'Edit quiz')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _title,
                  decoration: InputDecoration(
                    labelText: _fr ? 'Titre du QCM' : 'Quiz title',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _instructions,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: _fr ? 'Consignes' : 'Instructions',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < _questions.length; i++) _questionCard(i),
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => setState(() => _questions.add(_QcmQuestionDraft())),
                  icon: const Icon(Icons.add),
                  label: Text(_fr ? 'Ajouter une question' : 'Add a question'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: Text(_fr ? 'Enregistrer les modifications' : 'Save changes'),
                ),
              ],
            ),
    );
  }
}
