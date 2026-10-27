import 'package:flutter/material.dart';

import '../../../core/services/chapter_learning_service.dart';
import '../../../models/chapter_learning_content.dart';
import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';
import 'chapter_quiz_page.dart';

/// One subject-level place for published exercises from every chapter.
/// AI quizzes use the existing chapter-quiz function and stay chapter-scoped.
class ChapterTdQcmPage extends StatefulWidget {
  const ChapterTdQcmPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.subject,
    required this.chapters,
  });

  final Locale locale;
  final UserProfile profile;
  final Subject subject;
  final List<CourseChapter> chapters;

  @override
  State<ChapterTdQcmPage> createState() => _ChapterTdQcmPageState();
}

class _ChapterTdQcmPageState extends State<ChapterTdQcmPage> {
  final ChapterLearningService _service = ChapterLearningService();
  final Map<String, Future<List<ChapterLearningExercise>>> _exerciseFutures = {};
  final Set<String> _openingQuiz = <String>{};

  bool get _en => widget.locale.languageCode == 'en';

  Future<List<ChapterLearningExercise>> _exercisesFor(String chapterId) {
    return _exerciseFutures.putIfAbsent(
      chapterId,
      () => _service.listExercises(chapterId),
    );
  }

  Future<void> _openQuiz(CourseChapter chapter) async {
    if (_openingQuiz.contains(chapter.id)) return;
    setState(() => _openingQuiz.add(chapter.id));
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ChapterQuizPage(
            locale: widget.locale,
            chapterId: chapter.id,
            chapterTitle: chapter.labelFor(widget.locale.languageCode),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingQuiz.remove(chapter.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
        title: Text(_en ? 'Exercises & AI QCM' : 'TD et QCM intelligent'),
      ),
      body: widget.chapters.isEmpty
          ? Center(child: Text(_en ? 'No chapters available.' : 'Aucun chapitre disponible.'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF166534), Color(0xFF21844A)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.subject.labelFor(widget.locale.languageCode),
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(
                        _en
                            ? 'All published exercises are grouped here by chapter. The AI quiz uses the selected chapter’s course and published resources.'
                            : 'Tous les TD publiés sont regroupés ici par chapitre. Le QCM IA utilise le cours et les ressources publiées du chapitre choisi.',
                        style: const TextStyle(color: Colors.white, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                for (var index = 0; index < widget.chapters.length; index++)
                  _chapterCard(widget.chapters[index], index + 1),
              ],
            ),
    );
  }

  Widget _chapterCard(CourseChapter chapter, int number) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFE4F2E9),
                  foregroundColor: const Color(0xFF166534),
                  child: Text('$number'),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  chapter.labelFor(widget.locale.languageCode),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              ],
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<ChapterLearningExercise>>(
              future: _exercisesFor(chapter.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Row(children: [
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text(_en ? 'Loading exercises…' : 'Chargement des TD…'),
                  ]);
                }
                if (snapshot.hasError) {
                  return Text(_en ? 'Exercises could not be loaded.' : 'Impossible de charger les TD.',
                      style: const TextStyle(color: Colors.black54));
                }
                final exercises = snapshot.data ?? const <ChapterLearningExercise>[];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_en ? '${exercises.length} published exercise(s)' : '${exercises.length} TD publié(s)',
                        style: const TextStyle(color: Color(0xFF166534), fontWeight: FontWeight.w700)),
                    if (exercises.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _en ? 'No exercise has been published for this chapter yet.' : 'Aucun TD publié pour ce chapitre pour le moment.',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      )
                    else
                      ...exercises.map((exercise) {
                        final statement = exercise.statementFor(widget.locale.languageCode).trim();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.assignment_outlined, color: Color(0xFF166534)),
                          title: Text(statement.isEmpty ? (_en ? 'Exercise' : 'Exercice') : statement),
                          subtitle: Text(_en ? exercise.difficultyLabelEn : exercise.difficultyLabelFr),
                        );
                      }),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openingQuiz.contains(chapter.id) ? null : () => _openQuiz(chapter),
                icon: _openingQuiz.contains(chapter.id)
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome_rounded),
                label: Text(_openingQuiz.contains(chapter.id)
                    ? (_en ? 'Preparing the quiz…' : 'Préparation du QCM…')
                    : (_en ? 'Start this chapter’s AI QCM' : 'Faire le QCM IA de ce chapitre')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
