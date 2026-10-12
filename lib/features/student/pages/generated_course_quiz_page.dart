import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GeneratedCourseQuizPage extends StatefulWidget {
  final Locale locale;
  final String quizId;
  final String title;
  final List<Map<String, dynamic>> questions;

  const GeneratedCourseQuizPage({
    super.key,
    required this.locale,
    required this.quizId,
    required this.title,
    required this.questions,
  });

  @override
  State<GeneratedCourseQuizPage> createState() => _GeneratedCourseQuizPageState();
}

class _GeneratedCourseQuizPageState extends State<GeneratedCourseQuizPage> {
  final Map<String, int> _answers = {};
  List<Map<String, dynamic>>? _corrections;
  bool _submitting = false;
  int? _score;
  int? _total;

  bool get _en => widget.locale.languageCode == 'en';

  Future<void> _submit() async {
    if (_answers.length != widget.questions.length) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_en ? 'Answer every question first.' : 'Répondez à toutes les questions avant de valider.'),
      ));
      return;
    }
    setState(() => _submitting = true);
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'course-quiz',
        body: {'action': 'submit', 'quiz_id': widget.quizId, 'answers': _answers},
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['error'] != null) throw StateError(data['error'].toString());
      final raw = data['corrections'] as List? ?? const [];
      if (!mounted) return;
      setState(() {
        _score = (data['score'] as num?)?.toInt() ?? 0;
        _total = (data['total'] as num?)?.toInt() ?? raw.length;
        _corrections = raw.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_score != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _en ? 'Your score: $_score / $_total' : 'Votre résultat : $_score / $_total',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ...widget.questions.map((question) {
            final id = question['id']?.toString() ?? '';
            final prompt = question['prompt']?.toString() ?? '';
            final options = (question['options'] as List? ?? const []).map((v) => v.toString()).toList();
            final correction = _corrections?.where((row) => row['questionId']?.toString() == id).firstOrNull;
            final correctIndex = (correction?['correctIndex'] as num?)?.toInt();
            return Card(
              margin: const EdgeInsets.only(bottom: 14),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(prompt, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 8),
                    ...List.generate(options.length, (index) => RadioListTile<int>(
                      contentPadding: EdgeInsets.zero,
                      value: index,
                      groupValue: _answers[id],
                      onChanged: _corrections == null ? (value) {
                        if (value != null) setState(() => _answers[id] = value);
                      } : null,
                      title: Text(options[index]),
                    )),
                    if (correction != null) ...[
                      const Divider(),
                      Text(
                        correction['correct'] == true
                            ? (_en ? 'Correct answer' : 'Bonne réponse')
                            : (_en ? 'Incorrect — correct answer: ' : 'Incorrect — bonne réponse : ') +
                                (correctIndex != null && correctIndex >= 0 && correctIndex < options.length ? options[correctIndex] : ''),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: correction['correct'] == true ? Colors.green.shade800 : Colors.red.shade800,
                        ),
                      ),
                      if ((correction['explanation']?.toString() ?? '').trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(correction['explanation'].toString()),
                        ),
                    ],
                  ],
                ),
              ),
            );
          }),
          if (_corrections == null)
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline),
              label: Text(_en ? 'Check my answers' : 'Corriger mes réponses'),
            ),
        ],
      ),
    );
  }
}
