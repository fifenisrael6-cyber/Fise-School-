import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/offline/json_cache.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../core/services/photo_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';
import 'create_course_page.dart';
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
  final ResourceService _resources = ResourceService();

  late Future<List<Course>> _coursesFuture;
  final TextEditingController _courseSearchController = TextEditingController();

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _coursesFuture = _loadCoursesWithDiagnostics();
  }

  @override
  void dispose() {
    _courseSearchController.dispose();
    super.dispose();
  }

  String get _offlineCacheKey => 'teacher_courses_${widget.profile.id}';

  Map<String, dynamic> _courseToCache(Course course) => {
    'id': course.id,
    'curriculum_id': course.curriculumId,
    'chapter_id': course.chapterId,
    'subject_id': course.subjectId,
    'teacher_id': course.teacherId,
    'class_id': course.classId,
    'title_fr': course.titleFr,
    'title_en': course.titleEn,
    'description_fr': course.descriptionFr,
    'description_en': course.descriptionEn,
    'content_fr': course.contentFr,
    'content_en': course.contentEn,
    'smart_lesson_enabled': course.smartLessonEnabled,
    'minimum_exercise_score': course.minimumExerciseScore,
    'status': course.status,
    'published_at': course.publishedAt?.toIso8601String(),
  };

  List<Course> _decodeCachedCourses(Object? raw) {
    if (raw is! List) return const <Course>[];
    return raw.whereType<Map>().map(
      (row) => Course.fromMap(Map<String, dynamic>.from(row)),
    ).toList(growable: false);
  }

  Future<List<Course>> _loadCoursesWithDiagnostics() async {
    // Priorité à la copie locale : l'écran ne doit pas attendre le réseau
    // lorsque l'enseignant a déjà ouvert cette page sur cet appareil.
    final cached = await JsonCache.instance.read(_offlineCacheKey);
    if (cached is List) {
      unawaited(_refreshCoursesInBackground());
      return _decodeCachedCourses(cached);
    }

    try {
      final courses = await _service
          .listTeacherCourses(widget.profile.id)
          .timeout(const Duration(seconds: 12));
      await JsonCache.instance.write(
        _offlineCacheKey,
        courses.map(_courseToCache).toList(growable: false),
      );
      return courses;
    } catch (error, stackTrace) {
      debugPrint('[Mes médias de classe] Supabase load failed: $error');
      debugPrintStack(label: '[Mes médias de classe] stack trace', stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> _refreshCoursesInBackground() async {
    try {
      final courses = await _service
          .listTeacherCourses(widget.profile.id)
          .timeout(const Duration(seconds: 12));
      await JsonCache.instance.write(
        _offlineCacheKey,
        courses.map(_courseToCache).toList(growable: false),
      );
      if (mounted) {
        setState(() {
          _coursesFuture = Future<List<Course>>.value(courses);
        });
      }
    } catch (error) {
      debugPrint('[Mes médias de classe] Background refresh skipped: $error');
    }
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

  Future<void> _editCourseTitle(Course course) async {
    final frController = TextEditingController(text: course.titleFr);
    final enController = TextEditingController(text: course.titleEn);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_isFrench ? 'Modifier la publication' : 'Edit post'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: frController, decoration: const InputDecoration(labelText: 'Titre français')),
          const SizedBox(height: 12),
          TextField(controller: enController, decoration: const InputDecoration(labelText: 'English title')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_isFrench ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_isFrench ? 'Enregistrer' : 'Save')),
        ],
      ),
    );
    if (confirmed != true) {
      frController.dispose();
      enController.dispose();
      return;
    }
    try {
      await _service.updateCourseTitle(id: course.id, titleFr: frController.text, titleEn: enController.text);
      if (mounted) {
        setState(_reload);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isFrench ? 'Publication modifiée.' : 'Post updated.')));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      frController.dispose();
      enController.dispose();
    }
  }

  Future<void> _deleteCourse(Course course) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_isFrench ? 'Supprimer cette publication ?' : 'Delete this post?'),
        content: Text(_isFrench
          ? 'La publication et tous ses fichiers multimédias seront supprimés définitivement.'
          : 'This post and all its media files will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_isFrench ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_isFrench ? 'Supprimer' : 'Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final resources = await _resources.listForCourse(course.id);
      for (final resource in resources) {
        await _resources.deleteResource(resource);
      }
      await _service.deleteCourse(course.id);
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isFrench ? 'Publication supprimée.' : 'Post deleted.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_isFrench ? 'Suppression incomplète' : 'Delete incomplete'}: $error')),
      );
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
      appBar: AppBar(title: Text(_isFrench ? 'Mes médias de classe' : 'My classroom media')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createCourse,
        icon: const Icon(Icons.perm_media_rounded),
        label: Text(_isFrench ? 'Partager des médias' : 'Share media'),
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
                  '${texts.pedagogyLoadError}\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final courses = snapshot.data ?? const <Course>[];
          final query = _courseSearchController.text.trim().toLowerCase();
          final visibleCourses = query.isEmpty
              ? courses
              : courses.where((course) => '${course.labelFor(widget.locale.languageCode)} ${course.titleFr} ${course.titleEn} ${course.descriptionFr ?? ''} ${course.descriptionEn ?? ''}'.toLowerCase().contains(query)).toList(growable: false);

          if (courses.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _isFrench ? 'Aucune photo ou vidéo partagée pour le moment.' : 'No photos or videos shared yet.',
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
              itemCount: visibleCourses.length + (visibleCourses.isEmpty ? 2 : 1),
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (_, index) {
                if (index == 0) {
                  return TextField(
                    controller: _courseSearchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: _isFrench ? 'Rechercher un cours ou un média…' : 'Search a course or media…',
                      border: const OutlineInputBorder(),
                      suffixIcon: _courseSearchController.text.isEmpty ? null : IconButton(
                        tooltip: _isFrench ? 'Effacer' : 'Clear',
                        onPressed: () { _courseSearchController.clear(); setState(() {}); },
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  );
                }
                final filteredIndex = index - 1;
                if (filteredIndex >= visibleCourses.length) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_isFrench ? 'Aucun résultat pour cette recherche.' : 'No search results.'),
                  );
                }
                final course = visibleCourses[filteredIndex];

                return _CourseCard(
                  course: course,
                  locale: widget.locale,
                  onResources: () => _manageResources(course),
                  onEdit: () => _editCourseTitle(course),
                  onDelete: () => _deleteCourse(course),
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
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onArchive;
  final bool isFrench;

  const _CourseCard({
    required this.course,
    required this.locale,
    required this.onResources,
    required this.onEdit,
    required this.onDelete,
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
                  ? 'Partagez des photos et des vidéos avec les élèves de la classe sélectionnée.'
                  : 'Share photos and videos with students in the selected classroom.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
OutlinedButton.icon(
                  onPressed: onResources,
                  icon: const Icon(Icons.attach_file_rounded),
                  label: Text(isFrench ? 'Photos / vidéos' : 'Photos / videos'),
                ),
                IconButton(
                  onPressed: onEdit,
                  tooltip: isFrench ? 'Modifier' : 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  onPressed: onDelete,
                  tooltip: isFrench ? 'Supprimer' : 'Delete',
                  icon: const Icon(Icons.delete_outline_rounded),
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
