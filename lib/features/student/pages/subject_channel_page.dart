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
import 'chapter_quiz_page.dart';

class _FeedItem {
  final DateTime date;
  final Course? course;
  final Assignment? assignment;
  final Map<String, dynamic>? chapterContent;

  const _FeedItem({required this.date, this.course, this.assignment, this.chapterContent});
}

/// Fil d'une matière : cours publiés, documents, photos et QCM de l'enseignant,
/// affichés comme un canal (le plus récent en bas).
class SubjectChannelPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final Subject subject;
  final String? chapterId;
  final String? chapterTitle;

  const SubjectChannelPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.subject,
    this.chapterId,
    this.chapterTitle,
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
  late Future<List<CourseChapter>> _catalogChaptersFuture;

  bool get _fr => widget.locale.languageCode == 'fr';
  bool get _chapterFocused => widget.chapterId != null;

  @override
  void initState() {
    super.initState();
    _catalogChaptersFuture = _courses.listStudentCatalogChapters(
      widget.profile.id,
      subjectId: widget.subject.id,
    );
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

    // Official chapter content is an independent source. If its query fails,
    // keep already-loaded teacher media and QCM visible instead of hiding the feed.
    var chapterContent = <Map<String, dynamic>>[];
    try {
      chapterContent = await _courses.listStudentChapterContent(
        widget.profile.id,
        subjectId: widget.subject.id,
      );
    } catch (_) {
      chapterContent = <Map<String, dynamic>>[];
    }

    // Opening a subject is the automatic offline-download trigger.
    unawaited(_offline.enqueueSubject(userId: widget.profile.id, courses: courses));

    final items = <_FeedItem>[
      for (final course in courses)
        _FeedItem(date: course.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0), course: course),
      for (final content in chapterContent)
        _FeedItem(
          date: DateTime.tryParse(content['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
          chapterContent: content,
        ),
    ];

    // Du plus récent au plus ancien : la liste est affichée à l'envers
    // pour que le plus récent soit en bas, comme dans une conversation.
    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  Future<void> _refresh() async {
    setState(() {
      _feedFuture = _load();
      _catalogChaptersFuture = _courses.listStudentCatalogChapters(
        widget.profile.id,
        subjectId: widget.subject.id,
      );
    });
    await _feedFuture;
    if (!_chapterFocused) await _catalogChaptersFuture;
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d/$m/${local.year} $h:$min';
  }

  bool _itemMatchesFocusedChapter(_FeedItem item) {
    final chapterId = widget.chapterId;
    if (chapterId == null) return true;
    if (item.chapterContent != null) {
      return item.chapterContent!['chapter_id']?.toString() == chapterId;
    }
    if (item.course != null) {
      return item.course!.chapterId == chapterId;
    }
    return false;
  }

  Widget _chapterCatalog() {
    return FutureBuilder<List<CourseChapter>>(
      future: _catalogChaptersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.error_outline_rounded, size: 44),
              const SizedBox(height: 12),
              Text(
                _fr
                    ? 'Impossible de charger les titres des chapitres. Réessaie en actualisant.'
                    : 'Could not load chapter titles. Pull down to try again.',
                textAlign: TextAlign.center,
              ),
            ],
          );
        }
        final chapters = snapshot.data ?? const <CourseChapter>[];
        return RefreshIndicator(
          onRefresh: _refresh,
          child: chapters.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.16),
                    const Icon(Icons.menu_book_outlined, size: 54),
                    const SizedBox(height: 14),
                    Text(
                      _fr
                          ? 'Les titres des chapitres de cette matière restent à importer et à vérifier dans le programme officiel. Aucun cours ni fichier n’a été ajouté.'
                          : 'Chapter titles for this subject still need to be imported and checked against the official syllabus. No lesson or file has been added.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  children: [
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.bookmarks_outlined, color: Color(0xFF166534)),
                        title: Text(
                          _fr ? 'Chapitres de la matière' : 'Subject chapters',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          _fr
                              ? '${chapters.length} titre(s). Chaque chapitre ouvre sa propre page ; les cours et médias seront ajoutés plus tard.'
                              : '${chapters.length} title(s). Each chapter opens its own page; lessons and media will be added later.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...chapters.asMap().entries.map((entry) {
                      final chapter = entry.value;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF166534).withValues(alpha: 0.10),
                            foregroundColor: const Color(0xFF166534),
                            child: Text('${entry.key + 1}'),
                          ),
                          title: Text(
                            chapter.labelFor(widget.locale.languageCode),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SubjectChannelPage(
                                locale: widget.locale,
                                profile: widget.profile,
                                subject: widget.subject,
                                chapterId: chapter.id,
                                chapterTitle: chapter.labelFor(widget.locale.languageCode),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
        );
      },
    );
  }

  Widget _aiEvaluations() {
    if (_chapterFocused) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 36, color: Color(0xFF166534)),
                  const SizedBox(height: 12),
                  Text(_fr ? 'QCM généré par l’IA' : 'AI-generated quiz',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(_fr
                    ? 'Le QCM est généré à partir du contenu pédagogique publié de ce chapitre. Si la source est trop courte, aucune question ne sera inventée.'
                    : 'The quiz is generated from this chapter’s published learning content. If the source is too short, no questions will be invented.'),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ChapterQuizPage(
                          locale: widget.locale,
                          chapterId: widget.chapterId!,
                          chapterTitle: widget.chapterTitle ?? widget.subject.labelFor(widget.locale.languageCode),
                        ),
                      )),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(_fr ? 'Ouvrir le QCM IA' : 'Open AI quiz'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return FutureBuilder<List<CourseChapter>>(
      future: _catalogChaptersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(_fr ? 'Impossible de charger les évaluations.' : 'Could not load evaluations.'));
        }
        final chapters = snapshot.data ?? const <CourseChapter>[];
        if (chapters.isEmpty) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_fr ? 'Aucun chapitre disponible pour les évaluations.' : 'No chapters are available for evaluations.', textAlign: TextAlign.center),
          ));
        }
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          itemCount: chapters.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final chapter = chapters[index];
            final title = chapter.labelFor(widget.locale.languageCode);
            return Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.auto_awesome_rounded)),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(_fr ? 'QCM généré automatiquement à partir du cours publié' : 'Quiz generated automatically from the published lesson'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => ChapterQuizPage(locale: widget.locale, chapterId: chapter.id, chapterTitle: title),
              )),
            ));
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.locale.languageCode;
    final focused = _chapterFocused;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
        title: Text(
          widget.chapterTitle ?? widget.subject.labelFor(code),
          style: const TextStyle(fontWeight: FontWeight.w800),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        bottom: TabBar(
          isScrollable: true,
          tabs: [
            Tab(
              text: focused
                  ? (_fr ? 'Cours et médias' : 'Courses & media')
                  : (_fr ? 'Chapitres' : 'Chapters'),
              icon: Icon(focused ? Icons.menu_book_rounded : Icons.bookmarks_rounded),
            ),
            Tab(
              text: _fr ? 'Évaluations IA' : 'AI evaluations',
              icon: const Icon(Icons.auto_awesome_rounded),
            ),
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
          final scopedContent = items.where(_itemMatchesFocusedChapter).toList();
          final officialCourses = scopedContent
              .where((item) => item.chapterContent != null ||
                  (item.course != null && _isOfficialCourse(item.course!)))
              .toList();
          final teacherMedia = scopedContent
              .where((item) => item.course != null && !_isOfficialCourse(item.course!))
              .toList();
          final tabChildren = <Widget>[];
          if (!focused) {
            tabChildren.add(_chapterCatalog());
          } else {
            tabChildren.add(
              _feedList(
                <_FeedItem>[...officialCourses, ...teacherMedia],
                _fr
                    ? 'Aucun cours ni média publié pour ce chapitre pour le moment.'
                    : 'No course or media has been published for this chapter yet.',
              ),
            );
          }
          tabChildren.add(_aiEvaluations());

          return TabBarView(children: tabChildren);
        },
      ),
      ),
    );
  }

  bool _isOfficialCourse(Course course) {
    // The courses table is the teacher-authored feed. Teacher media may be
    // published by an earlier app version and still carry curriculum/chapter
    // IDs, so neither status nor those IDs make a course an official lesson.
    // Official admin-published chapter lessons are loaded separately from
    // chapter_content_items above. Keep every courses-table post in media.
    return false;
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
                ...items.map((item) => item.chapterContent != null
                    ? _chapterContentPost(item.chapterContent!)
                    : item.course != null
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
    List<CourseResource> resources;
    try {
      resources = await _resources.listForCourse(courseId);
    } catch (_) {
      // Offline mode is a fallback for a failed remote resource read only.
      return _offline.resourcesForCourse(widget.profile.id, courseId);
    }

    // Warming the offline cache is a separate best-effort task. Its failure
    // must never throw away photos/PDFs that were already fetched successfully.
    try {
      final course = await _courses.getCourse(courseId);
      unawaited(_offline.enqueueCourse(userId: widget.profile.id, course: course));
    } catch (_) {
      // Keep the live resource list visible.
    }
    return resources;
  }

  Widget _chapterContentPost(Map<String, dynamic> item) {
    final code = widget.locale.languageCode;
    final title = ((code == 'en' ? item['title_en'] : item['title_fr']) ??
            item['title_fr'] ?? item['title_en'] ?? '')
        .toString()
        .trim();
    final body = ((code == 'en' ? item['body_text_en'] : item['body_text_fr']) ??
            item['body_text_fr'] ?? item['body_text_en'] ?? '')
        .toString()
        .trim();
    final chapter = ((code == 'en' ? item['chapter_title_en'] : item['chapter_title_fr']) ??
            item['chapter_title_fr'] ?? item['chapter_title_en'] ?? '')
        .toString()
        .trim();

    return _bubble(
      date: DateTime.tryParse(item['created_at']?.toString() ?? '') ?? DateTime.now(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.menu_book_rounded, size: 18, color: Color(0xFF166534)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title.isEmpty ? (_fr ? 'Cours officiel' : 'Official lesson') : title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ],
          ),
          if (chapter.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(chapter, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF166534))),
          ],
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(body),
          ],
          if ((item['chapter_id']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChapterQuizPage(
                      locale: widget.locale,
                      chapterId: item['chapter_id'].toString(),
                      chapterTitle: chapter.isNotEmpty ? chapter : title,
                    ),
                  ),
                ),
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(_fr ? 'Quiz intelligent' : 'Smart quiz'),
              ),
            ),
          ],
        ],
      ),
    );
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
