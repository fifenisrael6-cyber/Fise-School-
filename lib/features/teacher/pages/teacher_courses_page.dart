import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final Set<String> _selectedCourseIds = <String>{};
  bool _selectionMode = false;
  final Map<String, String> _classNames = <String, String>{};

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _reload();
    _loadClassNames();
  }

  Future<void> _loadClassNames() async {
    try {
      final rows = await Supabase.instance.client.from('school_classes').select('id, display_name');
      if (!mounted) return;
      setState(() {
        _classNames
          ..clear()
          ..addEntries((rows as List).map((row) => MapEntry(row['id'].toString(), row['display_name']?.toString() ?? '')));
      });
    } catch (_) {}
  }

  void _reload() {
    _coursesFuture = _loadCoursesWithDiagnostics();
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

  void _toggleCourseSelection(Course course, bool? selected) {
    if (course.status != 'published') return;
    setState(() {
      if (selected == true) { _selectedCourseIds.add(course.id); }
      else { _selectedCourseIds.remove(course.id); }
      _selectionMode = _selectedCourseIds.isNotEmpty;
    });
  }

  Future<void> _deleteSelectedCourses() async {
    if (_selectedCourseIds.isEmpty) return;
    final selectedIds = Set<String>.from(_selectedCourseIds);
    final count = selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_isFrench ? 'Supprimer les cours sélectionnés ?' : 'Delete selected courses?'),
        content: Text(_isFrench ? 'Cette action supprimera $count cours et leurs fichiers associés.' : 'This will delete $count courses and their associated files.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_isFrench ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_isFrench ? 'Tout supprimer' : 'Delete all')),
        ],
      ),
    );
    if (confirmed != true) return;
    final selectedCourses = (await _coursesFuture).where((course) => selectedIds.contains(course.id) && course.status == 'published').toList(growable: false);
    try {
      for (final course in selectedCourses) {
        final resources = await _resources.listForCourse(course.id);
        for (final resource in resources) { await _resources.deleteResource(resource); }
        await _service.deleteCourse(course.id);
      }
      if (!mounted) return;
      setState(() { _selectedCourseIds.clear(); _selectionMode = false; _reload(); });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isFrench ? '$count cours supprimés.' : '$count courses deleted.')));
    } catch (error) {
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Suppression incomplète: $error')));
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
      appBar: AppBar(
        title: Text(_selectionMode ? (_isFrench ? 'Sélection des cours' : 'Select courses') : (_isFrench ? 'Mes médias de classe' : 'My classroom media')),
        actions: [
          if (_selectionMode)
            IconButton(tooltip: _isFrench ? 'Supprimer la sélection' : 'Delete selection', onPressed: _deleteSelectedCourses, icon: const Icon(Icons.delete_outline_rounded))
          else
            IconButton(tooltip: _isFrench ? 'Sélectionner plusieurs cours' : 'Select multiple courses', onPressed: () => setState(() => _selectionMode = true), icon: const Icon(Icons.checklist_rounded)),
        ],
      ),
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
              itemCount: courses.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (_, index) {
                final course = courses[index];

                return _CourseCard(
                  course: course,
                  locale: widget.locale,
                  className: course.classId == null ? null : _classNames[course.classId],
                  onResources: () => _manageResources(course),
                  onEdit: () => _editCourseTitle(course),
                  onDelete: () => _deleteCourse(course),
                  onArchive: course.status == 'draft'
                      ? () => _archiveCourse(course)
                      : null,
                  isFrench: _isFrench,
                  selectionMode: _selectionMode && course.status == 'published',
                  selected: _selectedCourseIds.contains(course.id),
                  onToggleSelected: (value) => _toggleCourseSelection(course, value),
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
  final String? className;
  final VoidCallback onResources;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onArchive;
  final bool isFrench;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool?> onToggleSelected;

  const _CourseCard({
    required this.course,
    required this.locale,
    required this.className,
    required this.onResources,
    required this.onEdit,
    required this.onDelete,
    required this.onArchive,
    required this.isFrench,
    required this.selectionMode,
    required this.selected,
    required this.onToggleSelected,
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
                if (selectionMode) Checkbox(value: selected, onChanged: onToggleSelected),
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
            if (className != null && className!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.meeting_room_outlined, size: 16, color: Colors.black54),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  '${isFrench ? 'Salle de classe' : 'Classroom'} : $className',
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                )),
              ]),
            ],
            const SizedBox(height: 14),
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
