import 'package:flutter/material.dart';
import 'dart:async';

import '../../../core/offline/connectivity_service.dart';
import '../../../core/offline/course_offline_service.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';
import '../widgets/offline_resource_tile.dart';
import 'course_detail_page.dart';
import 'daily_lesson_page.dart';
import 'chapter_quiz_page.dart';
import 'chapter_folder_page.dart';
import '../widgets/chapter_folder_card.dart';

class _FeedItem {
  final DateTime date;
  final Course? course;
  final Map<String, dynamic>? chapterContent;

  const _FeedItem({required this.date, this.course, this.chapterContent});
}

class _ChapterMediaEntry {
  final Course course;
  final CourseResource resource;

  const _ChapterMediaEntry({required this.course, required this.resource});
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
  final CourseOfflineService _offline = CourseOfflineService();
  final ResourceService _resources = ResourceService();
  final ConnectivityService _connectivity = ConnectivityService();
  StreamSubscription<bool>? _connectionSubscription;
  bool _offlineMode = false;

  late Future<List<_FeedItem>> _feedFuture;
  late Future<List<CourseChapter>> _catalogChaptersFuture;
  final Map<String, Future<List<_ChapterMediaEntry>>> _chapterMediaFutures = {};

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
      _chapterMediaFutures.clear();
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
                              ? '${chapters.length} titre(s). Ouvre un chapitre pour retrouver les cours et leurs fichiers classés par dossiers : photos, audios, vidéos et PDF.'
                              : '${chapters.length} title(s). Open a chapter to browse lessons and files grouped into folders: photos, audio, videos and PDFs.',
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

  Widget _feedList(List<_FeedItem> items, String emptyMessage) {
    final cacheKey = items
        .map((item) => item.course?.id ?? item.chapterContent?['id']?.toString() ?? '')
        .join('|');
    final mediaFuture = _chapterMediaFutures.putIfAbsent(
      cacheKey,
      () => _loadChapterMedia(items),
    );

    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<_ChapterMediaEntry>>(
        future: mediaFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final media = snapshot.data ?? const <_ChapterMediaEntry>[];
          final courses = items.where((item) =>
              item.chapterContent != null ||
              (item.course != null &&
                  (((item.course!.contentFr ?? '').trim().isNotEmpty) ||
                   ((item.course!.contentEn ?? '').trim().isNotEmpty) ||
                   ((item.course!.descriptionFr ?? '').trim().isNotEmpty) ||
                   ((item.course!.descriptionEn ?? '').trim().isNotEmpty)))).toList();
          final videos = media.where((e) => e.resource.folderKey == 'videos').toList();
          final audios = media.where((e) => e.resource.folderKey == 'audios').toList();
          final documents = media.where((e) => e.resource.folderKey == 'documents').toList();
          final exercises = media.where((e) => e.resource.folderKey == 'exercises').toList();

          Widget resourceItem(_ChapterMediaEntry entry) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.course.labelFor(_fr ? 'fr' : 'en'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    '${entry.resource.resourceType.toUpperCase()} · ${_formatDate(entry.course.publishedAt ?? entry.resource.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0))}',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                  OfflineResourceTile(
                    locale: widget.locale,
                    profile: widget.profile,
                    resource: entry.resource,
                  ),
                ],
              ),
            ),
          );

          List<Widget> courseItems() => courses.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: item.chapterContent != null
                ? _chapterContentPost(item.chapterContent!)
                : _coursePost(item.course!, showResources: false),
          )).toList();

          void openFolder(String title, List<Widget> folderItems, String empty) {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => ChapterFolderPage(
                title: title,
                items: folderItems,
                emptyMessage: empty,
              ),
            ));
          }

          final quizTitle = _fr ? 'QCM IA' : 'AI quizzes';
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            children: [
              if (_offlineMode) _offlineBanner(),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                child: Text(
                  _fr ? 'Contenu du chapitre' : 'Chapter content',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              ChapterFolderCard(
                title: _fr ? 'Cours' : 'Lessons',
                count: courses.length,
                icon: Icons.menu_book_rounded,
                countLabel: _fr ? 'élément(s)' : 'item(s)',
                onTap: () => openFolder(
                  _fr ? 'Cours' : 'Lessons',
                  courseItems(),
                  _fr ? 'Aucun cours pour le moment.' : 'No lessons available yet.',
                ),
              ),
              ChapterFolderCard(
                title: _fr ? 'Vidéos' : 'Videos',
                count: videos.length,
                icon: Icons.video_library_outlined,
                countLabel: _fr ? 'fichier(s)' : 'file(s)',
                onTap: () => openFolder(
                  _fr ? 'Vidéos' : 'Videos',
                  videos.map(resourceItem).toList(),
                  _fr ? 'Aucune vidéo pour le moment.' : 'No videos available yet.',
                ),
              ),
              ChapterFolderCard(
                title: _fr ? 'Audios' : 'Audio',
                count: audios.length,
                icon: Icons.audiotrack_rounded,
                countLabel: _fr ? 'fichier(s)' : 'file(s)',
                onTap: () => openFolder(
                  _fr ? 'Audios' : 'Audio',
                  audios.map(resourceItem).toList(),
                  _fr ? 'Aucun audio pour le moment.' : 'No audio available yet.',
                ),
              ),
              ChapterFolderCard(
                title: _fr ? 'Documents' : 'Documents',
                count: documents.length,
                icon: Icons.folder_copy_outlined,
                countLabel: _fr ? 'fichier(s)' : 'file(s)',
                onTap: () => openFolder(
                  _fr ? 'Documents' : 'Documents',
                  documents.map(resourceItem).toList(),
                  _fr ? 'Aucun document (PDF ou image) pour le moment.' : 'No PDF or image documents available yet.',
                ),
              ),
              ChapterFolderCard(
                title: _fr ? 'Exercices' : 'Exercises',
                count: exercises.length,
                icon: Icons.edit_note_rounded,
                countLabel: _fr ? 'élément(s)' : 'item(s)',
                onTap: () => openFolder(
                  _fr ? 'Exercices' : 'Exercises',
                  exercises.map(resourceItem).toList(),
                  _fr ? 'Aucun exercice pour le moment.' : 'No exercises available yet.',
                ),
              ),
              ChapterFolderCard(
                title: quizTitle,
                count: 1,
                icon: Icons.auto_awesome_rounded,
                countLabel: _fr ? 'accès' : 'entry',
                onTap: () => openFolder(
                  quizTitle,
                  [
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF166534)),
                        title: Text(_fr ? 'Évaluation générée par l’IA' : 'AI-generated assessment'),
                        subtitle: Text(_fr
                            ? 'Le QCM utilise le contenu pédagogique publié de ce chapitre.'
                            : 'The quiz uses this chapter’s published learning content.'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => ChapterQuizPage(
                            locale: widget.locale,
                            chapterId: widget.chapterId!,
                            chapterTitle: widget.chapterTitle ??
                                widget.subject.labelFor(widget.locale.languageCode),
                          ),
                        )),
                      ),
                    ),
                  ],
                  _fr ? 'Le QCM IA sera disponible lorsque le contenu du chapitre permettra sa génération.' : 'The AI quiz will be available when this chapter has enough content to generate it.',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<List<_ChapterMediaEntry>> _loadChapterMedia(List<_FeedItem> items) async {
    final entries = <_ChapterMediaEntry>[];
    for (final item in items) {
      final course = item.course;
      if (course == null) continue;
      try {
        final resources = await _loadResources(course.id);
        entries.addAll(resources.map((resource) =>
            _ChapterMediaEntry(course: course, resource: resource)));
      } catch (_) {
        // Un fichier indisponible ne doit pas masquer les autres dossiers.
      }
    }
    return entries;
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

  Widget _coursePost(Course course, {bool showResources = true}) {
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
          if (showResources) FutureBuilder<List<CourseResource>>(
            future: _loadResources(course.id),
            builder: (context, snapshot) {
              final resources = snapshot.data ?? const <CourseResource>[];
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: LinearProgressIndicator(minHeight: 2),
                );
              }
              if (resources.isEmpty) return const SizedBox.shrink();

              // File-manager style folders: students can find course photos,
              // audio, videos and PDFs without scrolling through a mixed list.
              const categories = <String, List<String>>{
                'image': ['image'],
                'audio': ['audio'],
                'video': ['video'],
                'pdf': ['pdf'],
                'documents': ['document', 'other'],
              };
              final labels = <String, String>{
                'image': _fr ? 'Photos et images' : 'Photos and images',
                'audio': _fr ? 'Audios' : 'Audio',
                'video': _fr ? 'Vidéos' : 'Videos',
                'pdf': 'PDF',
                'documents': _fr ? 'Autres fichiers' : 'Other files',
              };
              final icons = <String, IconData>{
                'image': Icons.photo_library_outlined,
                'audio': Icons.audiotrack_rounded,
                'video': Icons.video_library_outlined,
                'pdf': Icons.picture_as_pdf_outlined,
                'documents': Icons.folder_open_rounded,
              };
              final available = categories.entries.where((entry) =>
                  resources.any((resource) => entry.value.contains(resource.resourceType)));
              if (available.isEmpty) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_fr ? 'Dossiers du cours' : 'Course folders',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    ...available.map((entry) {
                      final files = resources.where((resource) =>
                          entry.value.contains(resource.resourceType)).toList();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ExpansionTile(
                          leading: Icon(icons[entry.key], color: const Color(0xFF166534)),
                          title: Text(labels[entry.key]!,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${files.length} ${_fr ? 'fichier(s)' : 'file(s)'}'),
                          children: files.map((resource) => OfflineResourceTile(
                            locale: widget.locale,
                            profile: widget.profile,
                            resource: resource,
                          )).toList(),
                        ),
                      );
                    }),
                  ],
                ),
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


  @override
  Widget build(BuildContext context) {
    final title = widget.chapterTitle ?? widget.subject.labelFor(widget.locale.languageCode);
    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800)),
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
      body: _chapterFocused
          ? FutureBuilder<List<_FeedItem>>(
              future: _feedFuture,
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
                        _fr ? 'Impossible de charger ce chapitre. Réessaie.' :
                            'Could not load this chapter. Please try again.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: FilledButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(_fr ? 'Réessayer' : 'Retry'),
                        ),
                      ),
                    ],
                  );
                }
                final items = (snapshot.data ?? const <_FeedItem>[])
                    .where(_itemMatchesFocusedChapter)
                    .toList();
                return _feedList(
                  items,
                  _fr
                      ? 'Aucun cours ni média publié pour ce chapitre pour le moment.'
                      : 'No course or media has been published for this chapter yet.',
                );
              },
            )
          : _chapterCatalog(),
    );
  }

}
