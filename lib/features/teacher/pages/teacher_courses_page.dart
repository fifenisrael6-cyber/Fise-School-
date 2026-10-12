import 'package:flutter/material.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../core/services/photo_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';
import 'create_course_page.dart';
import 'teacher_lessons_page.dart';
import 'teacher_resource_page.dart';

class TeacherCoursesPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final List<PickedAttachment> initialSharedAttachments;

  const TeacherCoursesPage({
    super.key,
    required this.locale,
    required this.profile,
    this.initialSharedAttachments = const [],
  });

  @override
  State<TeacherCoursesPage> createState() => _TeacherCoursesPageState();
}

class _TeacherCoursesPageState extends State<TeacherCoursesPage> {
  final CourseService _service = CourseService();

  late Future<List<Course>> _coursesFuture;

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _coursesFuture = _service.listTeacherCourses(widget.profile.id);
  }

  Future<void> _createCourse() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CreateCoursePage(locale: widget.locale, profile: widget.profile, initialSharedAttachments: widget.initialSharedAttachments),
      ),
    );

    if (!mounted) {
      return;
    }

    setState(_reload);
  }

  Future<void> _manageResources(Course course) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => TeacherResourcePage(
      locale: widget.locale, profile: widget.profile, course: course,
    )));
    if (!mounted) {
      return;
    }
    setState(_reload);
  }

  Future<void> _manageLessons(Course course) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => TeacherLessonsPage(
      locale: widget.locale, profile: widget.profile, course: course,
    )));
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _publishCourse(Course course) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_isFrench ? 'Publier le cours ?' : 'Publish course?'),
        content: Text(_isFrench
            ? 'Le cours et les ressources ajoutées seront visibles aux élèves de la classe ciblée.'
            : 'The course and its uploaded resources will become visible to students in the selected class.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_isFrench ? 'Annuler' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_isFrench ? 'Publier' : 'Publish'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.publishCourse(course.id);
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isFrench ? 'Cours publié avec succès.' : 'Course published successfully.'),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isFrench
            ? 'La publication a échoué : $error'
            : 'Publishing failed: $error'),
      ));
    }
  }

  Future<void> _archiveCourse(Course course) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_isFrench ? 'Archiver le cours' : 'Archive course'),
          content: Text(
            _isFrench
                ? 'Voulez-vous vraiment archiver ce cours ?'
                : 'Do you really want to archive this course?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: Text(_isFrench ? 'Annuler' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: Text(_isFrench ? 'Archiver' : 'Archive'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _service.archiveCourse(course.id);

      if (!mounted) {
        return;
      }

      setState(_reload);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isFrench ? 'Cours archivé.' : 'Course archived.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppTexts(widget.locale).pedagogyLoadError}\n$error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final texts = AppTexts(widget.locale);

    return Scaffold(
      appBar: AppBar(title: Text(_isFrench ? 'Mes cours et ressources' : 'My courses and resources')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createCourse,
        icon: const Icon(Icons.library_add_rounded),
        label: Text(_isFrench ? 'Créer un cours' : 'Create a course'),
      ),
      body: FutureBuilder<List<Course>>(
        future: _coursesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  texts.pedagogyLoadError,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final courses = snapshot.data ?? const <Course>[];

          if (courses.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _isFrench ? 'Aucun cours pour le moment. Créez un cours, ajoutez vos leçons et joignez des PDF, photos, vidéos ou audios.' : 'No courses yet. Create a course, add lessons and attach PDFs, photos, videos or audio.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(_reload);
              await _coursesFuture;
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              itemCount: courses.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (_, index) {
                final course = courses[index];

                return _CourseCard(
                  course: course,
                  locale: widget.locale,
                  onResources: () => _manageResources(course),
                  onLessons: () => _manageLessons(course),
                  onPublish: course.status == 'draft'
                      ? () => _publishCourse(course)
                      : null,
                  onArchive: course.status == 'draft'
                      ? () => _archiveCourse(course)
                      : null,
                  isFrench: _isFrench,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  final Course course;
  final Locale locale;
  final VoidCallback onResources;
  final VoidCallback onLessons;
  final VoidCallback? onPublish;
  final VoidCallback? onArchive;
  final bool isFrench;

  const _CourseCard({
    required this.course,
    required this.locale,
    required this.onResources,
    required this.onLessons,
    required this.onPublish,
    required this.onArchive,
    required this.isFrench,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _statusIcon(course.status),
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    course.labelFor(locale.languageCode),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _StatusChip(status: course.status, isFrench: isFrench),
              ],
            ),
            const SizedBox(height: 14),
            const SizedBox(height: 8),
            Text(
              isFrench
                  ? 'Publiez vos cours, gérez les leçons et partagez des PDF, photos, vidéos ou fichiers audio avec la classe sélectionnée.'
                  : 'Publish courses, manage lessons and share PDFs, photos, videos or audio files with the selected class.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onLessons,
                  icon: const Icon(Icons.menu_book_rounded),
                  label: Text(isFrench ? 'Leçons' : 'Lessons'),
                ),
                OutlinedButton.icon(
                  onPressed: onResources,
                  icon: const Icon(Icons.attach_file_rounded),
                  label: Text(isFrench ? 'Ressources PDF / médias' : 'PDF / media resources'),
                ),
                if (onPublish != null)
                  FilledButton.icon(
                    onPressed: onPublish,
                    icon: const Icon(Icons.publish_rounded),
                    label: Text(isFrench ? 'Publier' : 'Publish'),
                  ),
                if (onArchive != null)
                  IconButton(
                    onPressed: onArchive,
                    tooltip: isFrench ? 'Archiver' : 'Archive',
                    icon: const Icon(Icons.archive_outlined),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'published':
        return Icons.public;
      case 'archived':
        return Icons.archive_outlined;
      default:
        return Icons.edit_note;
    }
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final bool isFrench;

  const _StatusChip({required this.status, required this.isFrench});

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'published' => isFrench ? 'Publié' : 'Published',
      'archived' => isFrench ? 'Archivé' : 'Archived',
      _ => isFrench ? 'Brouillon' : 'Draft',
    };

    final icon = switch (status) {
      'published' => Icons.public,
      'archived' => Icons.archive_outlined,
      _ => Icons.edit_note,
    };

    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}
