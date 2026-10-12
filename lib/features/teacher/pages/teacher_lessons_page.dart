import 'package:flutter/material.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';
import 'create_lesson_page.dart';

/// Gestion des leçons d'un cours par son enseignant, brouillons inclus.
class TeacherLessonsPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final Course course;

  const TeacherLessonsPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.course,
  });

  @override
  State<TeacherLessonsPage> createState() => _TeacherLessonsPageState();
}

class _TeacherLessonsPageState extends State<TeacherLessonsPage> {
  final LessonService _service = LessonService();
  late Future<List<Lesson>> _lessonsFuture;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _lessonsFuture = _service.listAllLessons(widget.course.id);
  }

  Future<void> _openEditor([Lesson? lesson]) async {
    try {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => CreateLessonPage(
            locale: widget.locale,
            profile: widget.profile,
            course: widget.course,
            lesson: lesson,
          ),
        ),
      );
      if (!mounted) return;
      if (saved == true) setState(_reload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_fr
            ? 'Impossible d’ouvrir la leçon : $error'
            : 'Could not open lesson: $error'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppTexts(widget.locale);
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'Leçons du cours' : 'Course lessons'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add_rounded),
        label: Text(_fr ? 'Nouvelle leçon' : 'New lesson'),
      ),
      body: FutureBuilder<List<Lesson>>(
        future: _lessonsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(strings.pedagogyLoadError, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => setState(_reload),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(_fr ? 'Réessayer' : 'Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          final lessons = snapshot.data ?? const <Lesson>[];
          if (lessons.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.menu_book_outlined, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      _fr
                          ? 'Aucune leçon pour ce cours. Appuyez sur « Nouvelle leçon » pour créer et publier la première.'
                          : 'No lessons for this course yet. Tap “New lesson” to create and publish one.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              setState(_reload);
              await _lessonsFuture;
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: lessons.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final lesson = lessons[index];
                final title = lesson.labelFor(widget.locale.languageCode).trim();
                final published = lesson.isPublished;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(published ? Icons.menu_book_rounded : Icons.edit_note_rounded),
                    ),
                    title: Text(
                      title.isEmpty
                          ? (_fr ? 'Leçon sans titre' : 'Untitled lesson')
                          : title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      published
                          ? (_fr ? 'Publiée — visible par les élèves' : 'Published — visible to students')
                          : (_fr ? 'Brouillon — non visible par les élèves' : 'Draft — hidden from students'),
                    ),
                    trailing: IconButton(
                      tooltip: _fr ? 'Modifier / publier' : 'Edit / publish',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _openEditor(lesson),
                    ),
                    onTap: () => _openEditor(lesson),
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
