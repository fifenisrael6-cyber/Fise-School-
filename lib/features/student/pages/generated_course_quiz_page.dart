import 'package:flutter/material.dart';

import '../../../core/services/generated_course_quiz_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';

class GeneratedCourseQuizPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final Course course;
  final Lesson? lesson;

  const GeneratedCourseQuizPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.course,
    this.lesson,
  });

  @override
  State<GeneratedCourseQuizPage> createState() => _GeneratedCourseQuizPageState();
}

class _GeneratedCourseQuizPageState extends State<GeneratedCourseQuizPage> {
  final GeneratedCourseQuizService _service = GeneratedCourseQuizService();
  Map<String, dynamic>? _quiz;
  Map<String, dynamic>? _result;
  final Map<String, int> _answers = {};
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  bool get _en => widget.locale.languageCode == 'en';

  @override
  void initState() {
    super.initState();
    _loadQuiz();
  }

  Future<void> _loadQuiz() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final quiz = await _service.generate(
        courseId: widget.course.id,
        lessonId: widget.lesson?.id,
        language: _en ? 'en' : 'fr',
      );
      if (!mounted) return;
      setState(() {
        _quiz = quiz;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final quiz = _quiz;
    if (quiz == null || _submitting || _result != null) return;
    setState(() => _submitting = true);
    try {
      final result = await _service.submit(
        quizId: quiz['quizId'].toString(),
        answers: _answers,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _submitting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_en
              ? 'Correction requires an internet connection. Your answers are still on this screen.'
              : 'La correction nécessite une connexion Internet. Tes réponses restent affichées sur cet écran.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _en
        ? (widget.lesson?.titleEn ?? widget.course.titleEn)
        : (widget.lesson?.titleFr ?? widget.course.titleFr);
    final questions = (_quiz?['questions'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
    final corrections = (_result?['corrections'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF064D2B),
        foregroundColor: Colors.white,
        title: Text(_en ? 'Automatic lesson quiz' : 'QCM automatique'),
      ),
      body: _loading
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF166534)),
                    const SizedBox(height: 18),
                    Text(_en
                        ? 'Preparing questions from your lesson…'
                        : 'Préparation des questions à partir de ta leçon…'),
                  ],
                ),
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.quiz_outlined, size: 52, color: Color(0xFF166534)),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _loadQuiz,
                          icon: const Icon(Icons.refresh),
                          label: Text(_en ? 'Try again' : 'Réessayer'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.auto_awesome, color: Color(0xFF166534), size: 30),
                            const SizedBox(height: 8),
                            Text(
                              (_quiz?['title'] ?? (_en ? 'Revision quiz' : 'QCM de révision')).toString(),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(title),
                            if (_quiz?['cachedOffline'] == true) ...[
                              const SizedBox(height: 10),
                              Text(
                                _en
                                    ? 'Offline copy: connect to the internet to submit and get your correction.'
                                    : 'Copie hors ligne : connecte-toi à Internet pour envoyer tes réponses et recevoir la correction.',
                                style: const TextStyle(color: Color(0xFF92400E)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_result != null)
                      Card(
                        color: const Color(0xFFDCFCE7),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            _en
                                ? 'Your score: ${_result!['score']}/${_result!['total']}'
                                : 'Ton score : ${_result!['score']}/${_result!['total']}',
                            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    for (var i = 0; i < questions.length; i++)
                      _buildQuestionCard(i, questions[i], corrections),
                    const SizedBox(height: 12),
                    if (_result == null)
                      FilledButton.icon(
                        onPressed: _submitting || questions.isEmpty ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check_circle_outline),
                        label: Text(_submitting
                            ? (_en ? 'Correcting…' : 'Correction…')
                            : (_en ? 'Submit answers and correct' : 'Valider et corriger')),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF166534),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.done),
                        label: Text(_en ? 'Finish' : 'Terminer'),
                      ),
                  ],
                ),
    );
  }

  Widget _buildQuestionCard(
    int index,
    Map<String, dynamic> question,
    List<Map<String, dynamic>> corrections,
  ) {
    final id = question['id'].toString();
    final options = (question['options'] as List? ?? const []).map((value) => value.toString()).toList();
    final correction = corrections.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['questionId']?.toString() == id,
      orElse: () => null,
    );
    final correctIndex = correction?['correctIndex'] is num
        ? (correction!['correctIndex'] as num).toInt()
        : -1;
    final isCorrect = correction?['correct'] == true;

    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${index + 1}. ${question['prompt'] ?? ''}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (var optionIndex = 0; optionIndex < options.length; optionIndex++)
              RadioListTile<int>(
                value: optionIndex,
                groupValue: _result == null ? _answers[id] : (correction?['selectedIndex'] as int?),
                onChanged: _result != null
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _answers[id] = value);
                      },
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(options[optionIndex]),
              ),
            if (correction != null) ...[
              const SizedBox(height: 8),
              Text(
                isCorrect
                    ? (_en ? 'Correct answer' : 'Bonne réponse')
                    : '${_en ? 'Correct answer' : 'Bonne réponse'}: ${options.length > correctIndex && correctIndex >= 0 ? options[correctIndex] : ''}',
                style: TextStyle(
                  color: isCorrect ? const Color(0xFF166534) : const Color(0xFFB91C1C),
                  fontWeight: FontWeight.w800,
                ),
              ),
              if ((correction['explanation'] ?? '').toString().trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(correction['explanation'].toString()),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
