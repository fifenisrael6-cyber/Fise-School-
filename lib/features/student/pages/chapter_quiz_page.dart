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
                      quiz?.labelFor(widget.locale) ?? widget.chapterTitle,
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
                              Text(question.promptFor(widget.locale.languageCode),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              const SizedBox(height: 8),
                              ...List.generate(question.optionsFor(widget.locale.languageCode).length, (index) {
                                final options = question.optionsFor(widget.locale.languageCode);
                                return RadioListTile<int>(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  value: index,
                                  groupValue: _answers[question.id],
                                  title: Text(options[index]),
                                  onChanged: _submitting ? null : (value) {
                                    if (value != null) setState(() => _answers[question.id] = value);
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
