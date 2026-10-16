import 'package:flutter/material.dart';

import '../../../core/services/chapter_learning_service.dart';
import '../../../models/chapter_learning.dart';

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
  bool _submitting = false;
  String? _error;
  ChapterQuiz? _quiz;
  List<ChapterQuizQuestion> _questions = const [];
  final Map<String, int> _answers = {};
  final Map<String, Map<String, dynamic>> _instantFeedback = {};
  final Set<String> _checkingAnswers = {};
  Map<String, dynamic>? _result;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final quizzes = await _service.listQuizzes(widget.chapterId);
      if (quizzes.isEmpty) {
        throw StateError(_fr
            ? 'Aucun QCM disponible. Vérifiez que le cours publié contient assez de texte, puis réessayez.'
            : 'No quiz is available. Ensure the published lesson has enough text, then try again.');
      }
      final quiz = quizzes.first;
      final questions = await _service.listQuizQuestions(quiz.id);
      if (questions.isEmpty) {
        throw StateError(_fr ? 'Le QCM ne contient aucune question.' : 'The quiz has no questions.');
      }
      if (!mounted) return;
      setState(() {
        _quiz = quiz;
        _questions = questions;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Bad state: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _checkAnswer(ChapterQuizQuestion question, int selectedIndex) async {
    try {
      final feedback = await _service.checkQuizAnswer(
        quizId: question.quizId,
        questionId: question.id,
        selectedOptionIndex: selectedIndex,
      );
      if (!mounted) return;
      setState(() {
        _checkingAnswers.remove(question.id);
        _instantFeedback[question.id] = feedback;
        final lockedIndex = feedback['selected_option_index'];
        if (lockedIndex is num) _answers[question.id] = lockedIndex.toInt();
      });
      final correct = feedback['is_correct'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(correct
              ? (_fr ? 'Bonne réponse !' : 'Correct answer!')
              : (_fr ? 'Mauvaise réponse.' : 'Incorrect answer.')),
          backgroundColor: correct ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingAnswers.remove(question.id);
        _answers.remove(question.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_fr
            ? 'Impossible de vérifier cette réponse. Vérifie ta connexion.'
            : 'Unable to check this answer. Check your connection.')),
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
      if (raw is List && raw.isNotEmpty && raw.first is Map) {
        result = Map<String, dynamic>.from(raw.first as Map);
      }
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
          ? const Center(child: CircularProgressIndicator())
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
                      quiz?.labelFor(widget.locale.languageCode) ?? widget.chapterTitle,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(widget.chapterTitle, style: const TextStyle(color: Colors.black54)),
                    if (_result == null) ...[
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              (_fr ? 'Progression hebdomadaire : ' : 'Weekly progress: ') + _instantFeedback.length.toString() + ' / ' + _questions.length.toString() + (_fr ? ' réponses' : ' answers'),
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(value: _questions.isEmpty ? 0 : _instantFeedback.length / _questions.length),
                            if (_instantFeedback.isNotEmpty)
                              Text((_fr ? 'Bonnes réponses : ' : 'Correct answers: ') + _instantFeedback.values.where((v) => v['is_correct'] == true).length.toString() + ' / ' + _instantFeedback.length.toString() + (_fr ? ' · Réinitialisation chaque lundi' : ' · Resets every Monday')),
                          ]),
                        ),
                      ),
                      for (final question in _questions)
                        Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(question.promptFor(widget.locale.languageCode),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              const SizedBox(height: 8),
                              ...List.generate(question.optionsFor(widget.locale.languageCode).length, (index) {
                                final options = question.optionsFor(widget.locale.languageCode);
                                final feedback = _instantFeedback[question.id];
                                final locked = feedback != null;
                                final correctIndex = feedback?['correct_option_index'];
                                final isCorrectOption = correctIndex is num && correctIndex.toInt() == index;
                                final isWrongChoice = locked && _answers[question.id] == index && feedback['is_correct'] != true;
                                return RadioListTile<int>(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  value: index,
                                  groupValue: _answers[question.id],
                                  tileColor: isCorrectOption ? const Color(0xFFE8F5E9) : (isWrongChoice ? const Color(0xFFFFEBEE) : null),
                                  title: Text(options[index], style: TextStyle(
                                    color: isCorrectOption ? const Color(0xFF2E7D32) : (isWrongChoice ? const Color(0xFFC62828) : null),
                                    fontWeight: isCorrectOption || isWrongChoice ? FontWeight.w700 : FontWeight.normal,
                                  )),
                                  secondary: _checkingAnswers.contains(question.id)
                                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                      : isCorrectOption
                                          ? const Icon(Icons.check_circle, color: Color(0xFF2E7D32))
                                          : isWrongChoice ? const Icon(Icons.cancel, color: Color(0xFFC62828)) : null,
                                  onChanged: _submitting || locked || _checkingAnswers.contains(question.id) ? null : (value) {
                                    if (value != null && !_answers.containsKey(question.id)) {
                                      setState(() {
                                        _answers[question.id] = value;
                                        _checkingAnswers.add(question.id);
                                      });
                                      _checkAnswer(question, value);
                                    }
                                  },
                                );
                              }),
                              if (_instantFeedback[question.id] != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0FDF4),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    (_instantFeedback[question.id]!['is_correct'] == true
                                      ? (_fr ? 'Bonne réponse !' : 'Correct answer!')
                                      : (_fr ? 'Mauvaise réponse. La bonne réponse est en vert.' : 'Incorrect. The correct answer is green.')) +
                                    (((_instantFeedback[question.id]![_fr ? 'explanation_fr' : 'explanation_en'] ?? '').toString().trim().isEmpty)
                                      ? ''
                                      : '\n' + _instantFeedback[question.id]![_fr ? 'explanation_fr' : 'explanation_en'].toString()),
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
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
                                  '${item['is_correct'] == true ? '✓' : '✗'}  ${_fr ? 'Question' : 'Question'} · ${(item[_fr ? 'explanation_fr' : 'explanation_en'] ?? '').toString()}',
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
