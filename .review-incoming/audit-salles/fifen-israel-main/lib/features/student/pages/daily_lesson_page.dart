import 'package:flutter/material.dart';

import '../../../core/services/smart_course_service.dart';
import '../../../models/smart_learning.dart';
import '../../../models/user_profile.dart';

class DailyLessonPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final String? subjectId;

  const DailyLessonPage({
    super.key,
    required this.locale,
    required this.profile,
    this.subjectId,
  });

  @override
  State<DailyLessonPage> createState() => _DailyLessonPageState();
}

class _DailyLessonPageState extends State<DailyLessonPage> {
  final SmartCourseService _service = SmartCourseService();
  late Future<SmartLesson?> _future;
  SmartLesson? _lesson;
  SmartExerciseResult? _result;
  final Map<String, int> _answers = {};
  bool _submitting = false;
  String? _message;

  bool get _fr => widget.locale.languageCode != 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _service.loadDailyLesson(subjectId: widget.subjectId);
  }

  Future<void> _submit() async {
    final lesson = _lesson;
    if (lesson == null || _answers.length < lesson.questions.length) {
      setState(() => _message = _fr
          ? 'Répondez aux 4 questions avant de valider.'
          : 'Answer all 4 questions before submitting.');
      return;
    }
    setState(() {
      _submitting = true;
      _message = null;
    });
    try {
      final result = await _service.submitAnswers(lesson: lesson, answers: _answers);
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        if (result == null) {
          _message = _fr
              ? 'Réponses enregistrées hors connexion. La correction sera disponible à la reconnexion.'
              : 'Answers saved offline. The correction will be available when you reconnect.';
        } else {
          _result = result;
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _message = _fr
            ? 'La correction est temporairement indisponible. Réessayez avec une connexion stable.'
            : 'The correction service is temporarily unavailable. Try again with a stable connection.';
      });
    }
  }

  Future<void> _reportError() async {
    final lesson = _lesson;
    if (lesson == null) {
      return;
    }
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_fr ? 'Signaler une erreur' : 'Report an error'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: _fr ? 'Décrivez brièvement le problème.' : 'Briefly describe the problem.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_fr ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: Text(_fr ? 'Envoyer' : 'Send')),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) {
      return;
    }
    try {
      await _service.reportError(lesson.id, reason);
      if (mounted) {
        setState(() => _message = _fr ? 'Merci. Le signalement a été envoyé.' : 'Thanks. Your report was sent.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = _fr ? 'Le signalement n’a pas pu être envoyé.' : 'The report could not be sent.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'Leçon du jour' : 'Lesson of the day'),
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<SmartLesson?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(message: _fr ? 'La leçon du jour est temporairement indisponible.' : 'The daily lesson is temporarily unavailable.', french: _fr, onRetry: () => setState(_load));
          }
          final lesson = snapshot.data;
          if (lesson == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _fr ? 'Aucune leçon n’est prête pour votre prochain cours.' : 'No lesson is ready for your next class yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (_lesson?.id != lesson.id) {
            _lesson = lesson;
            _loadCachedResult(lesson.id);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Card(
                elevation: 0,
                color: const Color(0xFFF0FDF4),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_stories_rounded, color: Color(0xFF166534), size: 32),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_fr ? 'Leçon courte basée uniquement sur le contenu validé du cours.' : 'A short lesson based only on approved course content.', style: const TextStyle(fontWeight: FontWeight.w700))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SelectableText(
                lesson.text,
                style: const TextStyle(fontSize: 16, height: 1.55),
              ),
              const SizedBox(height: 26),
              Text(_fr ? 'Exercice' : 'Exercise', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              ...List.generate(
                lesson.questions.length,
                (index) => _QuestionCard(
                  number: index + 1,
                  question: lesson.questions[index],
                  selected: _answers[lesson.questions[index].id],
                  onChanged: (value) => setState(() {
                    final id = lesson.questions[index].id;
                    if (value == null) {
                      _answers.remove(id);
                    } else {
                      _answers[id] = value;
                    }
                  }),
                  french: _fr,
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFFF4D6), borderRadius: BorderRadius.circular(12)),
                  child: Text(_message!),
                ),
              ],
              if (_result != null) ...[
                const SizedBox(height: 16),
                _ResultCard(result: _result!, french: _fr),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_circle_outline_rounded),
                label: Text(_fr ? 'Valider l’exercice' : 'Submit exercise'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _reportError,
                icon: const Icon(Icons.flag_outlined),
                label: Text(_fr ? 'Signaler une erreur' : 'Report an error'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _loadCachedResult(String lessonId) async {
    final result = await _service.loadCachedResult(lessonId);
    if (mounted && result != null) {
      setState(() => _result = result);
    }
  }
}

class _QuestionCard extends StatelessWidget {
  final int number;
  final SmartQuestion question;
  final int? selected;
  final ValueChanged<int?> onChanged;
  final bool french;

  const _QuestionCard({required this.number, required this.question, required this.selected, required this.onChanged, required this.french});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$number. ${question.question}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          RadioGroup<int>(
            groupValue: selected,
            onChanged: onChanged,
            child: Column(
              children: List.generate(
                question.choices.length,
                (index) => RadioListTile<int>(
                  dense: true,
                  value: index,
                  title: Text(question.choices[index]),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final SmartExerciseResult result;
  final bool french;
  const _ResultCard({required this.result, required this.french});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: result.passed ? const Color(0xFFF0FDF4) : const Color(0xFFFFF7ED),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${result.score} %', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Color(0xFF166534))),
          const SizedBox(height: 5),
          Text(result.passed
              ? (french ? 'Leçon suivante débloquée.' : 'Next lesson unlocked.')
              : (french ? 'Vous pouvez refaire l’exercice.' : 'You can retry the exercise.')),
          const SizedBox(height: 12),
          for (final item in result.correction) ...[
            Text('${item['id']}: ${item['explanation'] ?? ''}', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
          ],
        ]),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final bool french;
  const _ErrorState({required this.message, required this.onRetry, required this.french});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 56),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(french ? 'Réessayer' : 'Try again'),
            ),
          ]),
        ),
      );
}
