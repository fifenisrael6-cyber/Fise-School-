import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/offline/connectivity_service.dart';
import '../../../core/offline/course_offline_service.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';
import '../widgets/offline_resource_tile.dart';
import 'lesson_page.dart';

class CourseDetailPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final Course course;

  const CourseDetailPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.course,
  });

  @override
  State<CourseDetailPage> createState() => _CourseDetailPageState();
}

class _CourseDetailPageState extends State<CourseDetailPage> {
  final LessonService _lessonService = LessonService();
  final CourseOfflineService _offline = CourseOfflineService();
  final ConnectivityService _connectivity = ConnectivityService();
  StreamSubscription<bool>? _connectionSubscription;
  bool _offlineMode = false;

  late Future<List<Lesson>> _lessonsFuture;

  String get _courseTitle {
    return widget.locale.languageCode == 'en'
        ? widget.course.titleEn
        : widget.course.titleFr;
  }

  String? get _courseDescription {
    final value = widget.locale.languageCode == 'en'
        ? widget.course.descriptionEn
        : widget.course.descriptionFr;

    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return value.trim();
  }

  @override
  void initState() {
    super.initState();
    _loadLessons();
    _prepareOffline();
    _connectionSubscription = _connectivity.connectionStream.listen((online) {
      if (mounted) {
        setState(() => _offlineMode = !online);
      }
    });
  }

  Future<void> _prepareOffline() async {
    await _offline.enqueueCourse(userId: widget.profile.id, course: widget.course);
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    super.dispose();
  }

  Future<List<CourseResource>> _loadResources() async {
    try {
      final resources = await ResourceService().listForCourse(widget.course.id);
      unawaited(_offline.enqueueCourse(userId: widget.profile.id, course: widget.course));
      return resources;
    } catch (_) {
      return _offline.resourcesForCourse(widget.profile.id, widget.course.id);
    }
  }

  void _loadLessons() {
    _lessonsFuture = _lessonService.listCourseLessons(widget.course.id);
  }

  Future<void> _refresh() async {
    setState(_loadLessons);
    await _lessonsFuture;
  }

  Future<void> _openLesson(Lesson lesson) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LessonPage(
          locale: widget.locale,
          profile: widget.profile,
          course: widget.course,
          lesson: lesson,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEnglish = widget.locale.languageCode == 'en';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F6),
      appBar: AppBar(
        title: Text(
          isEnglish ? 'Course' : 'Cours',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Lesson>>(
          future: _lessonsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF166534)),
              );
            }

            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 100),
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 64,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isEnglish
                        ? 'Unable to load lessons.'
                        : 'Impossible de charger les leçons.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    snapshot.error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(isEnglish ? 'Retry' : 'Réessayer'),
                    ),
                  ),
                ],
              );
            }

            final lessons = snapshot.data ?? const <Lesson>[];

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _buildCourseHeader(isEnglish),
                if (_offlineMode) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFFF4D6), borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.cloud_off_rounded, color: Color(0xFF8A5A00)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(isEnglish ? 'You are offline. Downloaded course files remain available.' : 'Vous êtes hors ligne. Les fichiers téléchargés restent disponibles.')),
                    ]),
                  ),
                ],
                const SizedBox(height: 18),
                FutureBuilder<List<CourseResource>>(
                  future: _loadResources(),
                  builder: (context, resourceSnapshot) {
                    final resources = resourceSnapshot.data ?? const <CourseResource>[];
                    if (resources.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isEnglish ? 'Course files' : 'Fichiers du cours', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ...resources.map((resource) => OfflineResourceTile(locale: widget.locale, profile: widget.profile, resource: resource)),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Icon(
                      Icons.menu_book_rounded,
                      color: Color(0xFF166534),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isEnglish ? 'Lessons' : 'Leçons',
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE4F2E9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${lessons.length}',
                        style: const TextStyle(
                          color: Color(0xFF166534),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (lessons.isEmpty)
                  _buildEmptyState(isEnglish)
                else
                  ...List.generate(
                    lessons.length,
                    (index) =>
                        _buildLessonCard(lessons[index], index, isEnglish),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCourseHeader(bool isEnglish) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF166534), Color(0xFF21844A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.school_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _courseTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (_courseDescription != null) ...[
            const SizedBox(height: 12),
            Text(
              _courseDescription!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.90),
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLessonCard(Lesson lesson, int index, bool isEnglish) {
    final title = isEnglish ? lesson.titleEn : lesson.titleFr;

    final content = isEnglish
        ? (lesson.contentEn ?? '')
        : (lesson.contentFr ?? '');

    final preview = content.trim().isEmpty
        ? (isEnglish
              ? 'Open this lesson to start learning.'
              : 'Ouvrez cette leçon pour commencer.')
        : content.trim();

    final limitedPreview = preview.length > 130
        ? '${preview.substring(0, 130)}...'
        : preview;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openLesson(lesson),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFE4F2E9),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Color(0xFF166534),
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      limitedPreview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time_rounded,
                          size: 16,
                          color: Color(0xFF166534),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${lesson.estimatedMinutes} min',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF166534),
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isEnglish) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          const Icon(Icons.menu_book_outlined, size: 58, color: Colors.grey),
          const SizedBox(height: 14),
          Text(
            isEnglish
                ? 'No published lessons yet.'
                : 'Aucune leçon publiée pour le moment.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            isEnglish
                ? 'The teacher will add lessons to this course.'
                : 'L’enseignant ajoutera les leçons à ce cours.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, height: 1.4),
          ),
        ],
      ),
    );
  }
}
