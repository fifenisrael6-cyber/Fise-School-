import 'package:flutter/material.dart';
import 'dart:async';

import '../../../core/offline/connectivity_service.dart';
import '../../../core/offline/course_offline_service.dart';
import '../../../core/services/assignment_service.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../models/assignment.dart';
import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';
import '../widgets/offline_resource_tile.dart';
import 'assignment_detail_page.dart';
import 'course_detail_page.dart';
import 'daily_lesson_page.dart';

class _FeedItem {
  final DateTime date;
  final Course? course;
  final Assignment? assignment;

  const _FeedItem({required this.date, this.course, this.assignment});
}

/// Fil d'une matière : cours publiés, documents, photos et QCM de l'enseignant,
/// affichés comme un canal (le plus récent en bas).
class SubjectChannelPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final Subject subject;

  const SubjectChannelPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.subject,
  });

  @override
  State<SubjectChannelPage> createState() => _SubjectChannelPageState();
}

class _SubjectChannelPageState extends State<SubjectChannelPage> {
  final CourseService _courses = CourseService();
  final AssignmentService _assignments = AssignmentService();
  final CourseOfflineService _offline = CourseOfflineService();
  final ResourceService _resources = ResourceService();
  final ConnectivityService _connectivity = ConnectivityService();
  StreamSubscription<bool>? _connectionSubscription;
  bool _offlineMode = false;

  late Future<List<_FeedItem>> _feedFuture;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _feedFuture = _load();
    _connectionSubscription = _connectivity.connectionStream.listen((online) {
      if (mounted) {
        setState(() => _offlineMode = !online);
      }
    });
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    super.dispose();
  }

  Future<List<_FeedItem>> _load() async {
    final courses = await _courses.listStudentCourses(
      widget.profile.id,
      subjectId: widget.subject.id,
    );

    var assignments = const <Assignment>[];
    try {
      assignments = await _assignments.listStudentAssignments(
        studentId: widget.profile.id,
        subjectId: widget.subject.id,
      );
    } catch (_) {
      assignments = const <Assignment>[];
    }

    // Opening a subject is the automatic offline-download trigger.
    unawaited(_offline.enqueueSubject(userId: widget.profile.id, courses: courses));

    final items = <_FeedItem>[
      for (final course in courses)
        _FeedItem(date: course.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0), course: course),
      for (final assignment in assignments)
        _FeedItem(
          date: assignment.publishedAt ?? assignment.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          assignment: assignment,
        ),
    ];

    // Du plus récent au plus ancien : la liste est affichée à l'envers
    // pour que le plus récent soit en bas, comme dans une conversation.
    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  Future<void> _refresh() async {
    setState(() => _feedFuture = _load());
    await _feedFuture;
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d/$m/${local.year} $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.locale.languageCode;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
        title: Text(
          widget.subject.labelFor(code),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        bottom: TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: _fr ? 'Cours officiels' : 'Official lessons', icon: const Icon(Icons.menu_book_rounded)),
            Tab(text: _fr ? 'Photos et vidéos' : 'Photos and videos', icon: const Icon(Icons.perm_media_rounded)),
            Tab(text: _fr ? 'QCM' : 'Quizzes', icon: const Icon(Icons.quiz_rounded)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _fr ? 'Leçon du jour' : 'Lesson of the day',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DailyLessonPage(
                  locale: widget.locale,
                  profile: widget.profile,
                  subjectId: widget.subject.id,
                ),
              ),
            ),
            icon: const Icon(Icons.auto_stories_outlined),
          ),
        ],
      ),
      body: FutureBuilder<List<_FeedItem>>(
        future: _feedFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('${snapshot.error}', textAlign: TextAlign.center),
              ),
            );
          }
          final items = snapshot.data ?? const <_FeedItem>[];
          final officialCourses = items
              .where((item) => item.course != null && _isOfficialCourse(item.course!))
              .toList();
          final teacherMedia = items
              .where((item) => item.course != null && !_isOfficialCourse(item.course!))
              .toList();
          final quizzes = items.where((item) => item.assignment != null).toList();

          return TabBarView(
            children: [
              _feedList(
                officialCourses,
                _fr ? 'Les cours écrits et les PDF publiés par l’administration apparaîtront ici.' : 'Written lessons and PDFs published by the administration will appear here.',
              ),
              _feedList(
                teacherMedia,
                _fr ? 'Aucune photo ou vidéo partagée par l’enseignant pour le moment.' : 'No photos or videos shared by the teacher yet.',
              ),
              _feedList(
                quizzes,
                _fr ? 'Aucun QCM publié dans cette matière pour le moment.' : 'No quiz has been published for this subject yet.',
              ),
            ],
          );
        },
      ),
      ),
    );
  }

  bool _isOfficialCourse(Course course) {
    // L'administration rattache ses cours au programme/chapitre et peut
    // publier du texte. Les enseignants publient seulement des médias.
    return course.curriculumId != null ||
        course.chapterId != null ||
        (course.contentFr?.trim().isNotEmpty ?? false) ||
        (course.contentEn?.trim().isNotEmpty ?? false);
  }

  Widget _feedList(List<_FeedItem> items, String emptyMessage) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.22),
                Icon(
                  Icons.menu_book_outlined,
                  size: 54,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(height: 12),
                Text(emptyMessage, textAlign: TextAlign.center),
              ],
            )
          : ListView(
              reverse: true,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              children: [
                if (_offlineMode) _offlineBanner(),
                ...items.map((item) => item.course != null
                    ? _coursePost(item.course!)
                    : _quizPost(item.assignment!)),
              ],
            ),
    );
  }

  Widget _offlineBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFFFFF4D6), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Icon(Icons.cloud_off_rounded, size: 20, color: Color(0xFF8A5A00)),
        const SizedBox(width: 8),
        Expanded(child: Text(_fr ? 'Vous êtes hors ligne. Les fichiers déjà téléchargés restent accessibles.' : 'You are offline. Previously downloaded files remain available.', style: const TextStyle(fontSize: 12))),
      ]),
    );
  }

  Widget _bubble({required Widget child, required DateTime date}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                _formatDate(date),
                style: const TextStyle(fontSize: 10, color: Colors.black45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<CourseResource>> _loadResources(String courseId) async {
    try {
      final resources = await _resources.listForCourse(courseId);
      // Keep the offline cache warm without making the online page depend on it.
      unawaited(_offline.enqueueCourse(userId: widget.profile.id, course: await _courses.getCourse(courseId)));
      return resources;
    } catch (_) {
      return _offline.resourcesForCourse(widget.profile.id, courseId);
    }
  }

  Widget _coursePost(Course course) {
    final code = widget.locale.languageCode;
    final content = (code == 'en' ? course.contentEn : course.contentFr)?.trim();
    final description = (code == 'en' ? course.descriptionEn : course.descriptionFr)?.trim();

    return _bubble(
      date: course.publishedAt ?? DateTime.now(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.menu_book_rounded, size: 18, color: Color(0xFF166534)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  course.labelFor(code),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ],
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(description),
          ],
          if (content != null && content.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(content),
          ],
          FutureBuilder<List<CourseResource>>(
            future: _loadResources(course.id),
            builder: (context, snapshot) {
              final resources = snapshot.data ?? const <CourseResource>[];
              if (resources.isEmpty) {
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: resources.map((resource) => OfflineResourceTile(
                  locale: widget.locale, profile: widget.profile, resource: resource,
                )).toList(),
              );
            },
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CourseDetailPage(
                    locale: widget.locale,
                    profile: widget.profile,
                    course: course,
                  ),
                ),
              ),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(_fr ? 'Ouvrir le cours' : 'Open course'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quizPost(Assignment assignment) {
    final due = assignment.dueAt;

    return _bubble(
      date: assignment.publishedAt ?? assignment.createdAt ?? DateTime.now(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.quiz_rounded, size: 18, color: Color(0xFF166534)),
              const SizedBox(width: 6),
              Text(
                'QCM',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.green.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            assignment.titleFor(widget.locale),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          if (due != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${_fr ? 'À rendre avant le' : 'Due'} ${_formatDate(due)}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          const SizedBox(height: 6),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AssignmentDetailPage(
                  locale: widget.locale,
                  profile: widget.profile,
                  assignment: assignment,
                ),
              ),
            ),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(
              assignment.status == 'closed'
                  ? (_fr ? 'Voir' : 'View')
                  : (_fr ? 'Répondre au QCM' : 'Answer the quiz'),
            ),
          ),
        ],
      ),
    );
  }
}
