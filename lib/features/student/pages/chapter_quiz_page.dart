import 'package:flutter/material.dart';

import '../../../core/services/chapter_learning_service.dart';
import '../../../models/chapter_learning_content.dart';
import '../../../core/utils/educational_text.dart';

class ChapterQuizPage extends StatefulWidget {
  final Locale locale;
  final String chapterId;
  final String chapterTitle;

  const ChapterQuizPage({
    super.key,
    required this.locale,
    required this.chapterId,
    required this.chapterTitle,
  });

  @override
  State<ChapterQuizPage> createState() => _ChapterQuizPageState();
}

class _ChapterQuizPageState extends State<ChapterQuizPage> {
  final ChapterLearningService _service = ChapterLearningService();
  bool _loading = true;
  bool _generating = false;
  bool _submitting = false;
  String? _error;
  ChapterLearningQuiz? _quiz;
  List<ChapterLearningQuizQuestion> _questions = const [];
  final Map<String, int> _answers = {};
  final Map<String, Map<String, dynamic>> _instantFeedback = {};
  final Set<String> _checkingAnswers = {};
  final Set<String> _lockedAnswers = {};
  Map<String, dynamic>? _result;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      var quizzes = await _service.listQuizzes(widget.chapterId);
      ChapterLearningQuiz? quiz;
      List<ChapterLearningQuizQuestion> questions = const [];

      if (quizzes.isNotEmpty) {
        quiz = quizzes.first;
        questions = await _service.listQuizQuestions(quiz.id);
      }

      // Every Smart QCM must contain five AI-generated questions. Generate
      // on demand when the folder is empty or its saved quiz is incomplete.
      if (quizzes.isEmpty || questions.length < 5) {
        if (mounted) setState(() => _generating = true);
        await _service.generateSmartQuiz(widget.chapterId);
        quizzes = await _service.listQuizzes(
          widget.chapterId,
          forceRefresh: true,
        );
        if (quizzes.isNotEmpty) {
          quiz = quizzes.first;
          questions = await _service.listQuizQuestions(quiz.id);
        } else {
          quiz = null;
          questions = const [];
        }
      }

      if (quiz == null || questions.length < 5) {
        throw StateError(_fr
            ? 'L’IA n’a pas pu préparer les cinq questions du QCM. Vérifiez la connexion et réessayez.'
            : 'AI could not prepare all five quiz questions. Check your connection and retry.');
      }

      final savedRows = await _service.listLockedQuizAnswers(quiz.id);
      final savedAnswers = <String, int>{};
      final savedFeedback = <String, Map<String, dynamic>>{};
      for (final row in savedRows) {
        final questionId = row['question_id']?.toString();
        final selected = row['selected_option_index'];
        if (questionId == null || selected is! num) continue;
        savedAnswers[questionId] = selected.toInt();
        savedFeedback[questionId] = row;
      }

      if (!mounted) return;
      setState(() {
        _quiz = quiz;
        _questions = questions;
        _answers
          ..clear()
          ..addAll(savedAnswers);
        _instantFeedback
          ..clear()
          ..addAll(savedFeedback);
        _lockedAnswers
          ..clear()
          ..addAll(savedAnswers.keys);
        _checkingAnswers.clear();
        _loading = false;
        _generating = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Bad state: ', '');
        _loading = false;
        _generating = false;
      });
    }
  }

  Future<void> _checkAnswer(
    ChapterLearningQuizQuestion question,
    int selectedIndex,
  ) async {
    if (!mounted ||
        _lockedAnswers.contains(question.id) ||
        _checkingAnswers.contains(question.id)) {
      return;
    }
    setState(() {
      _answers[question.id] = selectedIndex;
      _checkingAnswers.add(question.id);
    });
    try {
      final feedback = await _service.checkQuizAnswer(
        questionId: question.id,
        selectedIndex: selectedIndex,
      );
      if (!mounted) return;
      setState(() {
        _instantFeedback[question.id] = feedback;
        _lockedAnswers.add(question.id);
        _checkingAnswers.remove(question.id);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _answers.remove(question.id);
        _checkingAnswers.remove(question.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _fr
                ? 'Réponse non enregistrée. Vérifiez la connexion puis cochez de nouveau. ($error)'
                : 'Answer not saved. Check your connection and select again. ($error)',
          ),
        ),
      );
    }
  }

  Future<void> _submit() async {
    final quiz = _quiz;
    if (quiz == null || _answers.length != _questions.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_fr ? 'Répondez à toutes les questions.' : 'Answer every question first.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final raw = await _service.submitQuiz(quizId: quiz.id, answers: _answers);
      Map<String, dynamic>? result;
      if (raw is Map) result = Map<String, dynamic>.from(raw);
      if (result == null || result['score'] == null) {
        throw StateError(_fr ? 'La correction n’a pas retourné de résultat.' : 'The correction returned no result.');
      }
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_fr ? 'Envoi impossible' : 'Submission failed'}: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quiz = _quiz;
    return Scaffold(
      appBar: AppBar(title: Text(_fr ? 'Quiz intelligent' : 'Smart quiz')),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 14),
                  Text(
                    _generating
                        ? (_fr
                            ? 'Génération du QCM intelligent…'
                            : 'Generating the smart quiz…')
                        : (_fr ? 'Chargement du QCM…' : 'Loading quiz…'),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.quiz_outlined, size: 52),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _error = null;
                          });
                          _load();
                        },
                        icon: const Icon(Icons.refresh),
                        label: Text(_fr ? 'Réessayer' : 'Retry'),
                      ),
                    ]),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      quiz?.titleFor(widget.locale.languageCode) ?? widget.chapterTitle,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(widget.chapterTitle, style: const TextStyle(color: Colors.black54)),
                    if (_result == null) ...[
                      const SizedBox(height: 12),
                      for (final question in _questions)
                        Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(readableEducationalText(question.promptFor(widget.locale.languageCode)),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              const SizedBox(height: 8),
                              ...List.generate(question.optionsFor(widget.locale.languageCode).length, (index) {
                                final options = question.optionsFor(widget.locale.languageCode);
                                final feedback = _instantFeedback[question.id];
                                final correctIndex = feedback?['correct_option_index'] is num
                                    ? (feedback!['correct_option_index'] as num).toInt()
                                    : null;
                                final locked = _lockedAnswers.contains(question.id);
                                final isCorrectOption = correctIndex == index;
                                final isSelected = _answers[question.id] == index;
                                final optionColor = feedback == null
                                    ? null
                                    : isCorrectOption
                                        ? const Color(0xFF2E7D32)
                                        : isSelected
                                            ? const Color(0xFFC62828)
                                            : null;
                                return RadioListTile<int>(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  value: index,
                                  groupValue: _answers[question.id],
                                  title: Text(readableEducationalText(options[index]), style: TextStyle(
                                    color: optionColor,
                                    fontWeight: (isSelected || isCorrectOption) && feedback != null
                                        ? FontWeight.w700
                                        : FontWeight.normal,
                                  )),
                                  tileColor: feedback != null && (isSelected || isCorrectOption)
                                      ? (isCorrectOption
                                          ? const Color(0x1A2E7D32)
                                          : const Color(0x1AC62828))
                                      : null,
                                  activeColor: optionColor,
                                  selected: isSelected,
                                  secondary: _checkingAnswers.contains(question.id)
                                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                      : _instantFeedback[question.id] == null
                                          ? null
                                          : Icon(
                                              isCorrectOption ? Icons.check_circle : (isSelected ? Icons.cancel : Icons.circle_outlined),
                                              color: isCorrectOption ? const Color(0xFF2E7D32) : (isSelected ? const Color(0xFFC62828) : Colors.black26),
                                            ),
                                  onChanged: (_submitting || locked || _checkingAnswers.contains(question.id)) ? null : (value) {
                                    if (value != null) {
                                      _checkAnswer(question, value);
                                    }
                                  },
                                );
                              }),
                            ]),
                          ),
                        ),
                      FilledButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check_circle_outline),
                        label: Text(_fr ? 'Corriger mes réponses' : 'Submit answers'),
                      ),
                    ] else ...[
                      Card(
                        color: const Color(0xFFF0FDF4),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${_result!['score']} %',
                              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF166534))),
                            Text('${_result!['correct_answers']} / ${_result!['total_questions']} ${_fr ? 'bonnes réponses' : 'correct answers'}'),
                            const SizedBox(height: 12),
                            for (final item in (_result!['review'] as List? ?? const []))
                              if (item is Map) Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  '${item['is_correct'] == true ? '✓' : '✗'}  ${_fr ? 'Question' : 'Question'} · ${readableEducationalText((item[_fr ? 'explanation_fr' : 'explanation_en'] ?? '').toString())}',
                                ),
                              ),
                          ]),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back),
                        label: Text(_fr ? 'Retour au cours' : 'Back to lesson'),
                      ),
                    ],
                  ],
                ),
    );
  }
}
