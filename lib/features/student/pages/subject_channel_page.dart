import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

import '../../../core/offline/connectivity_service.dart';
import '../../../core/offline/course_offline_service.dart';
import '../../../core/offline/json_cache.dart';
import '../../../core/offline/offline_repository.dart';
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
  final Map<String, Future<List<Map<String, dynamic>>>> _chapterDirectedStudiesFutures = {};

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

  Future<List<_FeedItem>> _load({bool forceRefresh = false}) async {
    final contentCacheKey =
        'student_chapter_content_${widget.profile.id}_${widget.subject.id}';

    if (!forceRefresh) {
      try {
        final cachedCourses = (await OfflineRepository()
                .getCoursesForStudent(widget.profile.id))
            .where((course) => course.subjectId == widget.subject.id)
            .toList(growable: false);
        final cachedContent = await JsonCache.instance.read(contentCacheKey);
        if (cachedCourses.isNotEmpty || cachedContent is List) {
          final chapterContent = cachedContent is List
              ? cachedContent
                  .whereType<Map>()
                  .map((row) => Map<String, dynamic>.from(row))
                  .toList(growable: false)
              : <Map<String, dynamic>>[];
          final cachedItems = _buildFeedItems(cachedCourses, chapterContent);
          unawaited(_offline.enqueueSubject(
            userId: widget.profile.id,
            courses: cachedCourses,
          ));
          unawaited(_refreshFeedInBackground());
          return cachedItems;
        }
      } catch (_) {
        // Absence de cache au premier lancement : continuer avec Supabase.
      }
    }

    final courses = await _courses.listStudentCourses(
      widget.profile.id,
      subjectId: widget.subject.id,
    );

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
    return _buildFeedItems(courses, chapterContent);
  }

  List<_FeedItem> _buildFeedItems(
    List<Course> courses,
    List<Map<String, dynamic>> chapterContent,
  ) {
    final items = <_FeedItem>[
      for (final course in courses)
        _FeedItem(
          date: course.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          course: course,
        ),
      for (final content in chapterContent)
        _FeedItem(
          date: DateTime.tryParse(content['created_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
          chapterContent: content,
        ),
    ];
    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  Future<void> _refreshFeedInBackground() async {
    try {
      final freshItems = await _load(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _feedFuture = Future<List<_FeedItem>>.value(freshItems);
      });
    } catch (_) {
      // La copie locale reste visible si Supabase est indisponible.
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _chapterMediaFutures.clear();
      _chapterDirectedStudiesFutures.clear();
      _feedFuture = _load(forceRefresh: true);
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

  @override
  Widget build(BuildContext context) {
    final code = widget.locale.languageCode;
    final focused = _chapterFocused;

    return Scaffold(
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
            return _loadingChapterFolders(
              const <_FeedItem>[],
              const <_FeedItem>[],
            );
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
          if (!focused) return _chapterCatalog();

          return _feedList(
            <_FeedItem>[...officialCourses, ...teacherMedia],
            _fr
                ? 'Aucun cours ni média publié pour ce chapitre pour le moment.'
                : 'No course or media has been published for this chapter yet.',
          );
        },
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
    final cacheKey = items
        .map((item) => item.course?.id ?? item.chapterContent?['id']?.toString() ?? '')
        .join('|');
    final coursePosts = items.where((item) =>
        item.chapterContent != null ||
        (item.course != null &&
            (((item.course!.contentFr ?? '').trim().isNotEmpty) ||
             ((item.course!.contentEn ?? '').trim().isNotEmpty) ||
             ((item.course!.descriptionFr ?? '').trim().isNotEmpty) ||
             ((item.course!.descriptionEn ?? '').trim().isNotEmpty)))).toList();
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
            return _loadingChapterFolders(items, coursePosts);
          }
          final media = snapshot.data ?? const <_ChapterMediaEntry>[];

          bool hasExtension(String name, List<String> extensions) =>
              extensions.any(name.endsWith);

          bool isType(_ChapterMediaEntry entry, String type) {
            final resource = entry.resource;
            final resourceType = resource.resourceType.toLowerCase();
            final mime = (resource.mimeType ?? '').toLowerCase();
            final name = resource.fileName.toLowerCase();
            switch (type) {
              case 'photos':
                return resourceType == 'image' ||
                    mime.startsWith('image/') ||
                    hasExtension(name, ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.bmp']);
              case 'audio':
                return resourceType == 'audio' ||
                    mime.startsWith('audio/') ||
                    hasExtension(name, ['.mp3', '.m4a', '.aac', '.wav', '.ogg', '.opus', '.flac']);
              case 'videos':
                return resourceType == 'video' ||
                    mime.startsWith('video/') ||
                    hasExtension(name, ['.mp4', '.mov', '.mkv', '.webm', '.3gp', '.avi']);
              case 'pdf':
                return resourceType == 'pdf' ||
                    mime == 'application/pdf' ||
                    name.endsWith('.pdf');
              default:
                return false;
            }
          }

          final photos = media.where((entry) => isType(entry, 'photos')).toList();
          final audios = media.where((entry) => isType(entry, 'audio')).toList();
          final videos = media.where((entry) => isType(entry, 'videos')).toList();
          final pdfs = media.where((entry) => isType(entry, 'pdf')).toList();
          final categorized = <String>{};
          for (final entry in media) {
            if (isType(entry, 'photos') || isType(entry, 'audio') ||
                isType(entry, 'videos') || isType(entry, 'pdf')) {
              categorized.add(entry.resource.id);
            }
          }
          // Les pièces jointes qui ne sont pas photo/audio/vidéo/PDF restent
          // accessibles dans le dossier Cours au lieu de disparaître.
          final lessonAttachments = media
              .where((entry) => !categorized.contains(entry.resource.id))
              .toList();

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

          final lessonItems = <Widget>[
            ...coursePosts.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: item.chapterContent != null
                  ? _chapterContentPost(item.chapterContent!)
                  : _coursePost(item.course!, showResources: false),
            )),
            ...lessonAttachments.map(resourceItem),
          ];

          void openFolder(String title, List<Widget> folderItems, String empty) {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => ChapterFolderPage(
                title: title,
                items: folderItems,
                emptyMessage: empty,
              ),
            ));
          }

          void openQuizFolder() {
            openFolder(
              _fr ? 'QCM intelligent' : 'Smart quiz',
              [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF166534)),
                    title: Text(_fr ? 'Ouvrir le QCM intelligent' : 'Open smart quiz'),
                    subtitle: Text(_fr
                        ? 'Le QCM est généré à partir du cours publié de ce chapitre.'
                        : 'The quiz is generated from this chapter’s published lessons.'),
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
              _fr
                  ? 'Le QCM sera disponible lorsque le chapitre contiendra assez de cours publiés.'
                  : 'The quiz will be available when this chapter has enough published lesson content.',
            );
          }

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            children: [
              if (_offlineMode) _offlineBanner(),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                child: Text(
                  _fr ? 'Dossiers du chapitre' : 'Chapter folders',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              ChapterFolderCard(
                title: _fr ? 'Cours' : 'Lessons',
                count: lessonItems.length,
                icon: Icons.menu_book_rounded,
                countLabel: _fr ? 'élément(s)' : 'item(s)',
                onTap: () => openFolder(
                  _fr ? 'Cours' : 'Lessons',
                  lessonItems,
                  _fr ? 'Aucun cours publié dans ce chapitre.' : 'No published lessons in this chapter.',
                ),
              ),
                    ChapterFolderCard(
                title: 'Photos',
                count: photos.length,
                icon: Icons.photo_library_outlined,
                countLabel: _fr ? 'fichier(s)' : 'file(s)',
                onTap: () => openFolder(
                  'Photos',
                  photos.map(resourceItem).toList(),
                  _fr ? 'Aucune photo dans ce chapitre.' : 'No photos in this chapter.',
                ),
              ),
              ChapterFolderCard(
                title: 'Audio',
                count: audios.length,
                icon: Icons.audiotrack_rounded,
                countLabel: _fr ? 'fichier(s)' : 'file(s)',
                onTap: () => openFolder(
                  'Audio',
                  audios.map(resourceItem).toList(),
                  _fr ? 'Aucun fichier audio dans ce chapitre.' : 'No audio files in this chapter.',
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
                  _fr ? 'Aucune vidéo dans ce chapitre.' : 'No videos in this chapter.',
                ),
              ),
              ChapterFolderCard(
                title: 'PDF',
                count: pdfs.length,
                icon: Icons.picture_as_pdf_outlined,
                countLabel: _fr ? 'fichier(s)' : 'file(s)',
                onTap: () => openFolder(
                  'PDF',
                  pdfs.map(resourceItem).toList(),
                  _fr ? 'Aucun PDF dans ce chapitre.' : 'No PDFs in this chapter.',
                ),
              ),
              ChapterFolderCard(
                title: _fr ? 'QCM intelligent' : 'Smart quiz',
                count: 1,
                icon: Icons.auto_awesome_rounded,
                countLabel: _fr ? 'accès' : 'entry',
                onTap: openQuizFolder,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _loadingChapterFolders(
    List<_FeedItem> items,
    List<_FeedItem> coursePosts,
  ) {
    final lessonItems = coursePosts.map((item) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: item.chapterContent != null
          ? _chapterContentPost(item.chapterContent!)
          : _coursePost(item.course!, showResources: false),
    )).toList(growable: false);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      children: [
        if (_offlineMode) _offlineBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Text(
            _fr ? 'Dossiers du chapitre' : 'Chapter folders',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        ChapterFolderCard(
          title: _fr ? 'Cours' : 'Lessons',
          count: lessonItems.length,
          icon: Icons.menu_book_rounded,
          countLabel: _fr ? 'élément(s)' : 'item(s)',
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(
            builder: (_) => ChapterFolderPage(
              title: _fr ? 'Cours' : 'Lessons',
              items: lessonItems,
              emptyMessage: _fr
                  ? 'Aucun cours publié dans ce chapitre.'
                  : 'No published lessons in this chapter.',
            ),
          )),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(child: CircularProgressIndicator(color: Color(0xFF166534))),
        ),
        Center(
          child: Text(
            _fr ? 'Chargement des fichiers du chapitre…' : 'Loading chapter files…',
            style: const TextStyle(color: Colors.black54),
          ),
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _loadChapterDirectedStudies(
    String cacheKey,
    List<String> courseIds,
  ) async {
    if (courseIds.isEmpty) {
      return _fetchChapterDirectedStudies(cacheKey, courseIds);
    }
    try {
      final cached = await JsonCache.instance.read(cacheKey);
      if (cached is List) {
        unawaited(_refreshChapterDirectedStudies(cacheKey, courseIds));
        return cached
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
      }
    } catch (_) {
      // A missing or invalid cache should not block the live query.
    }
    return _fetchChapterDirectedStudies(cacheKey, courseIds);
  }

  Future<void> _refreshChapterDirectedStudies(
    String cacheKey,
    List<String> courseIds,
  ) async {
    try {
      final rows = await _fetchChapterDirectedStudies(cacheKey, courseIds);
      if (!mounted) return;
      setState(() {
        _chapterDirectedStudiesFutures[cacheKey] =
            Future<List<Map<String, dynamic>>>.value(rows);
      });
    } catch (_) {
      // Keep the last local TD list visible.
    }
  }

  Future<List<Map<String, dynamic>>> _fetchChapterDirectedStudies(
    String cacheKey,
    List<String> courseIds,
  ) async {
    dynamic query = Supabase.instance.client
        .from('directed_studies')
        .select('id,course_id,source_class_id,subject_id,title,description,storage_path,file_name,target_class_ids,created_at')
        .eq('subject_id', widget.subject.id)
        .eq('status', 'published');
    if (courseIds.isNotEmpty) {
      query = query.inFilter('course_id', courseIds);
    }
    final raw = await query
        .order('created_at', ascending: false)
        .timeout(const Duration(seconds: 8));
    final rows = raw
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    await JsonCache.instance.write(cacheKey, rows);
    return rows;
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

  /// Affiche une illustration intégrée au texte du cours.
  /// Syntaxe : ![Légende](chemin-dans-chapter-content.webp)
  Widget _courseInlineImage(String source, String caption) {
    final cleanSource = source.trim();
    final cleanCaption = caption.trim();
    Future<String> resolveUrl() async {
      if (cleanSource.startsWith('https://') || cleanSource.startsWith('http://')) return cleanSource;
      var storagePath = cleanSource;
      const bucketPrefix = 'chapter-content/';
      if (storagePath.startsWith(bucketPrefix)) storagePath = storagePath.substring(bucketPrefix.length);
      storagePath = storagePath.replaceFirst(RegExp(r'^/+'), '');
      if (storagePath.isEmpty || storagePath.contains('..')) throw const FormatException('Chemin d’illustration invalide.');
      return Supabase.instance.client.storage.from('chapter-content').createSignedUrl(storagePath, 3600);
    }

    return FutureBuilder<String>(
      future: resolveUrl(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Container(
            width: double.infinity, margin: const EdgeInsets.symmetric(vertical: 8), padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFFF7ED), border: Border.all(color: const Color(0xFFF59E0B)), borderRadius: BorderRadius.circular(8)),
            child: const Text('Illustration momentanément indisponible. Vérifiez le fichier dans le stockage du cours.', style: TextStyle(color: Color(0xFF9A3412), fontSize: 13)),
          );
        }
        return Container(
          width: double.infinity, margin: const EdgeInsets.symmetric(vertical: 10), padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                snapshot.data!, width: double.infinity, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(padding: EdgeInsets.all(16), child: Text('Impossible de charger cette illustration.')),
              ),
            ),
            if (cleanCaption.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(cleanCaption, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF475569), fontStyle: FontStyle.italic)),
            ],
          ]),
        );
      },
    );
  }

  /// Mise en page pédagogique : titres, définitions, tableaux et images en ligne.
  Widget _formattedCourseBody(String body) {
    final widgets = <Widget>[];
    var previousWasBlank = false;
    final imagePattern = RegExp(r'^!\[([^\]]*)\]\(([^)]+)\)$');
    final customImagePattern = RegExp(r'^\[\[image:([^|\]]+)(?:\|([^\]]*))?\]\]$');

    for (final raw in body.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) {
        if (widgets.isNotEmpty && !previousWasBlank) widgets.add(const SizedBox(height: 5));
        previousWasBlank = true;
        continue;
      }
      previousWasBlank = false;
      final diagramMatch = RegExp(r'^\[\[diagram:([a-z0-9_]+)\]\].firstMatch(line);
      if (diagramMatch != null) {
        widgets.add(_courseDiagramCard(diagramMatch.group(1)!));
        continue;
      }
      final markdownImage = imagePattern.firstMatch(line);
      final customImage = customImagePattern.firstMatch(line);
      if (markdownImage != null || customImage != null) {
        final match = markdownImage ?? customImage!;
        final caption = markdownImage != null ? match.group(1) ?? '' : match.group(2) ?? '';
        final source = markdownImage != null ? match.group(2) ?? '' : match.group(1) ?? '';
        widgets.add(_courseInlineImage(source, caption));
        continue;
      }

      final cells = line.split(RegExp(r'\s{3,}')).where((s) => s.trim().isNotEmpty).toList();
      final isTable = cells.length >= 2 && cells.length <= 6 && cells.every((s) => s.trim().length < 90);
      final isUpperHeading = line.length <= 90 && line.length >= 4 && line == line.toUpperCase() && RegExp(r'[A-ZÀÂÇÉÈÊËÎÏÔÙÛÜ]').hasMatch(line);
      final isSection = RegExp(r'^(?:CHAPITRE\s+\d+|[IVX]+\s*[−–-]|\d+(?:\.\d+)*\s*[.)-]\s+[A-ZÀÂÇÉÈÊËÎÏÔÙÛÜ])', caseSensitive: false).hasMatch(line) || RegExp(r'^(?:EXERCICES?|EXERCICES? DE BASE|QUESTIONS FLASH|À LA MAISON|CORRECTION|APPLICATIONS?|CONCLUSION|RÉSULTAT|SOLUTION)\s*:?', caseSensitive: false).hasMatch(line);
      final label = RegExp(r'^(Définition(?:s)?|Remarque(?:s)?|Méthode|Propriété|Théorème|Exemple|Solution|Attention|À retenir)\s*:?(.*)$', caseSensitive: false).firstMatch(line);

      if (isUpperHeading || isSection) {
        widgets.add(Container(
          width: double.infinity, margin: const EdgeInsets.only(top: 12, bottom: 7), padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: const BoxDecoration(color: Color(0xFFEFF6FF), border: Border(bottom: BorderSide(color: Color(0xFF2563EB), width: 2))),
          child: Text(line, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1D4ED8))),
        ));
      } else if (label != null) {
        widgets.add(Container(
          width: double.infinity, margin: const EdgeInsets.symmetric(vertical: 5), padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFEFF7F0), border: const Border(left: BorderSide(color: Color(0xFF16A34A), width: 4)), borderRadius: BorderRadius.circular(6)),
          child: RichText(text: TextSpan(style: const TextStyle(color: Colors.black87, fontSize: 15, height: 1.5), children: [
            TextSpan(text: '${label.group(1)} : ', style: const TextStyle(fontWeight: FontWeight.w800, decoration: TextDecoration.underline, color: Color(0xFF166534))),
            if ((label.group(2) ?? '').trim().isNotEmpty) TextSpan(text: (label.group(2) ?? '').trim()),
          ])),
        ));
      } else if (isTable) {
        widgets.add(Container(
          width: double.infinity, margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFD1D5DB)), borderRadius: BorderRadius.circular(4)),
          child: Wrap(children: [
            for (var i = 0; i < cells.length; i++) Container(
              constraints: const BoxConstraints(minWidth: 42, maxWidth: 220), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(color: i == 0 ? const Color(0xFFF3F4F6) : Colors.white, border: Border(right: BorderSide(color: const Color(0xFFD1D5DB), width: i == cells.length - 1 ? 0 : 1))),
              child: Text(cells[i].trim(), style: TextStyle(fontSize: 14, height: 1.35, fontWeight: i == 0 ? FontWeight.w700 : FontWeight.normal)),
            ),
          ]),
        ));
      } else {
        widgets.add(Padding(padding: const EdgeInsets.only(bottom: 5), child: SelectableText(line.replaceAll(RegExp(r'[ \t]{2,}'), ' '), style: const TextStyle(fontSize: 15, height: 1.55, color: Colors.black87))));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  Widget _courseDiagramCard(String kind) {
    const titles = <String, String>{
      'gravity_pair': 'Attraction gravitationnelle entre deux corps',
      'gravity_altitude': 'Champ gravitationnel autour de la Terre',
      'weight': 'Poids d’un corps',
      'geom_triangle': 'Triangle et éléments géométriques',
      'geom_right_triangle': 'Triangle rectangle',
      'geom_circle': 'Cercle et rayon',
      'geom_square': 'Carré et diagonales',
      'geom_parallel': 'Configuration de Thalès',
      'geom_coordinate': 'Repère cartésien',
      'geom_cube': 'Cube en perspective',
      'geom_pyramid': 'Pyramide à base carrée',
      'geom_cylinder': 'Cylindre',
      'geom_prism': 'Prisme droit',
      'graph_line': 'Représentation graphique d’une droite',
      'stats_bar': 'Diagramme en bâtons',
      'svt_cell': 'Échanges à travers la membrane cellulaire',
      'svt_neuron': 'Structure d’un neurone',
      'svt_synapse': 'Transmission au niveau d’une synapse',
    };
    const formulas = <String, String>{
      'gravity_pair': 'F = G × m₁ × m₂ / r²',
      'gravity_altitude': 'g(h) = G × Mₜ / (Rₜ + h)²',
      'weight': 'P = m × g',
      'geom_triangle': 'A = (base × hauteur) / 2',
      'geom_right_triangle': 'c² = a² + b²',
      'geom_circle': 'P = 2πr  •  A = πr²',
      'geom_square': 'A = c²  •  diagonale = c√2',
      'geom_parallel': 'MN ∥ BC  ⇒  AM/AB = AN/AC',
      'geom_coordinate': 'Point A(x ; y)',
      'geom_cube': 'V = a³  •  A totale = 6a²',
      'geom_pyramid': 'V = (A base × hauteur) / 3',
      'geom_cylinder': 'V = πr²h',
      'geom_prism': 'V = A base × hauteur',
      'graph_line': 'y = ax + b',
      'stats_bar': 'Hauteur des barres proportionnelle aux effectifs',
      'svt_cell': 'Entrées : eau, ions, nutriments, O₂  •  Sorties : CO₂ et déchets',
      'svt_neuron': 'Dendrites → corps cellulaire → axone → terminaisons',
      'svt_synapse': 'Message électrique → neurotransmetteurs → récepteurs',
    };
    final title = titles[kind];
    if (title == null) return const SizedBox.shrink();
    final formula = formulas[kind] ?? '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Text(_fr ? title : title, textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF164E63), fontSize: 14)),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, height: 190,
            child: CustomPaint(painter: _GravityDiagramPainter(kind))),
        const SizedBox(height: 6),
        Text(formula, textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1D4ED8), fontSize: 14)),
      ]),
    );
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
            _formattedCourseBody(body),
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
            _formattedCourseBody(description),
          ],
          if (content != null && content.isNotEmpty) ...[
            const SizedBox(height: 6),
            _formattedCourseBody(content),
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

}
/// Vector drawings generated by Flutter: no remote image or storage dependency.
/// Dessins vectoriels hors ligne utilisés par les cours de toutes les matières.
class _GravityDiagramPainter extends CustomPainter {
  final String kind;
  _GravityDiagramPainter(this.kind);

  static const blue = Color(0xFF2563EB);
  static const orange = Color(0xFFF97316);
  static const red = Color(0xFFDC2626);
  static const green = Color(0xFF16A34A);
  static const ink = Color(0xFF0F172A);
  static const grey = Color(0xFF64748B);

  void _text(Canvas c, String value, Offset at, {double size = 12, Color color = ink, bool bold = false}) {
    final p = TextPainter(
      text: TextSpan(text: value, style: TextStyle(fontSize: size, color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 180);
    p.paint(c, at);
  }

  void _line(Canvas c, Offset a, Offset b, Color color, {double width = 2, bool dashed = false}) {
    final paint = Paint()..color = color..strokeWidth = width..style = PaintingStyle.stroke;
    if (!dashed) { c.drawLine(a, b, paint); return; }
    final delta = b - a;
    final length = delta.distance;
    if (length == 0) return;
    final unit = delta / length;
    for (double d = 0; d < length; d += 10) {
      c.drawLine(a + unit * d, a + unit * math.min(d + 5, length), paint);
    }
  }

  void _arrow(Canvas c, Offset a, Offset b, Color color) {
    _line(c, a, b, color, width: 2.5);
    final angle = (b - a).direction;
    const head = 9.0;
    _line(c, b, b - Offset(head * math.cos(angle - .5), head * math.sin(angle - .5)), color);
    _line(c, b, b - Offset(head * math.cos(angle + .5), head * math.sin(angle + .5)), color);
  }

  void _point(Canvas c, Offset p, String label, {Color color = red}) {
    c.drawCircle(p, 3.5, Paint()..color = color);
    _text(c, label, p + const Offset(5, -17), size: 11, color: ink, bold: true);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final center = Offset(w * .5, h * .52);

    if (kind == 'gravity_pair') {
      final y = h * .43;
      canvas.drawCircle(Offset(w * .22, y), 27, Paint()..color = blue);
      canvas.drawCircle(Offset(w * .78, y), 35, Paint()..color = orange);
      _text(canvas, 'm₁', Offset(w * .22 - 9, y - 7), color: Colors.white, bold: true);
      _text(canvas, 'm₂', Offset(w * .78 - 10, y - 7), color: Colors.white, bold: true);
      _arrow(canvas, Offset(w * .43, y - 13), Offset(w * .30, y - 13), red);
      _arrow(canvas, Offset(w * .57, y + 13), Offset(w * .69, y + 13), red);
      _text(canvas, 'F₂₁', Offset(w * .33, y - 36), color: red, bold: true);
      _text(canvas, 'F₁₂', Offset(w * .61, y + 20), color: red, bold: true);
      _line(canvas, Offset(w * .22, y + 49), Offset(w * .78, y + 49), grey);
      _text(canvas, 'distance r', Offset(w * .43, y + 54), size: 11);
    } else if (kind == 'gravity_altitude') {
      final earth = Offset(w * .34, h * .53);
      canvas.drawCircle(earth, 53, Paint()..color = blue);
      _text(canvas, 'Terre', earth - const Offset(18, 7), size: 11, color: Colors.white, bold: true);
      canvas.drawCircle(earth, 82, Paint()..color = grey..style = PaintingStyle.stroke..strokeWidth = 1.5);
      final sat = Offset(earth.dx + 82, earth.dy - 8);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: sat, width: 22, height: 14), const Radius.circular(3)), Paint()..color = orange);
      _arrow(canvas, earth, Offset(earth.dx + 82, earth.dy), green);
      _text(canvas, 'Rₜ', earth + const Offset(-43, 25), color: Colors.white, bold: true);
      _text(canvas, 'h', earth + const Offset(43, -37), color: green, bold: true);
      _text(canvas, 'Satellite', sat + const Offset(-26, -29), size: 11, bold: true);
      _text(canvas, 'r = Rₜ + h', Offset(w * .58, h * .46), size: 14, color: blue, bold: true);
    } else if (kind == 'weight') {
      final groundY = h * .72;
      _line(canvas, Offset(8, groundY), Offset(w - 8, groundY), green, width: 4);
      canvas.drawCircle(Offset(w * .5, groundY - 48), 18, Paint()..color = orange);
      _arrow(canvas, Offset(w * .5, groundY - 25), Offset(w * .5, groundY - 2), red);
      _text(canvas, 'm', Offset(w * .5 + 24, groundY - 56), bold: true);
      _text(canvas, 'P', Offset(w * .5 + 13, groundY - 25), color: red, bold: true);
      _text(canvas, 'Sol', Offset(w * .5 - 12, groundY + 7), size: 11, color: green, bold: true);
    } else if (kind == 'geom_triangle' || kind == 'geom_right_triangle') {
      final a = Offset(w * .22, h * .78), b = Offset(w * .78, h * .78);
      final c = kind == 'geom_right_triangle' ? Offset(w * .22, h * .18) : Offset(w * .53, h * .18);
      final p = Path()..moveTo(a.dx,a.dy)..lineTo(b.dx,b.dy)..lineTo(c.dx,c.dy)..close();
      canvas.drawPath(p, Paint()..color = const Color(0x332563EB)..style = PaintingStyle.fill);
      canvas.drawPath(p, Paint()..color = blue..style = PaintingStyle.stroke..strokeWidth = 3);
      _point(canvas,a,'A'); _point(canvas,b,'B'); _point(canvas,c,'C');
      if (kind == 'geom_right_triangle') {
        _line(canvas, a + const Offset(0,-16), a + const Offset(16,-16), green);
        _line(canvas, a + const Offset(16,-16), a + const Offset(16,0), green);
        _text(canvas,'angle droit',Offset(w*.28,h*.58),size:10,color:green);
      } else {
        _line(canvas, Offset((a.dx+b.dx)/2,h*.70), Offset((a.dx+b.dx)/2,h*.78), red);
        _text(canvas,'base',Offset(w*.44,h*.82),size:11,color:red);
        _line(canvas,c,Offset(c.dx,h*.78),green,dashed:true);
        _text(canvas,'hauteur',Offset(c.dx+5,h*.48),size:10,color:green);
      }
    } else if (kind == 'geom_circle') {
      final r = math.min(w,h)*.31;
      canvas.drawCircle(center,r,Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=3);
      canvas.drawCircle(center,4,Paint()..color=red);
      final edge=center+Offset(r*.78,-r*.63);
      _line(canvas,center,edge,red,width:3);
      _text(canvas,'O',center+const Offset(-17,7),bold:true);
      _text(canvas,'r',center+Offset(r*.35,-r*.42),color:red,bold:true);
    } else if (kind == 'geom_square') {
      final rect=Rect.fromCenter(center:center,width:math.min(w,h)*.62,height:math.min(w,h)*.62);
      canvas.drawRect(rect,Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=3);
      _line(canvas,rect.topLeft,rect.bottomRight,red,width:2.5);
      _line(canvas,rect.topRight,rect.bottomLeft,green,width:2.5);
      _text(canvas,'c',Offset(rect.left-18,center.dy),color:blue,bold:true);
    } else if (kind == 'geom_parallel') {
      final a=Offset(w*.20,h*.78), b=Offset(w*.82,h*.78);
      final c=Offset(w*.31,h*.24), d=Offset(w*.70,h*.24);
      _line(canvas,a,b,blue,width:3); _line(canvas,c,d,blue,width:3);
      _line(canvas,Offset(w*.40,h*.08),Offset(w*.54,h*.94),red,width:2.5);
      _line(canvas,Offset(w*.68,h*.08),Offset(w*.78,h*.94),red,width:2.5);
      _point(canvas,Offset(w*.40,h*.64),'M'); _point(canvas,Offset(w*.54,h*.64),'N');
      _point(canvas,Offset(w*.20,h*.78),'B'); _point(canvas,Offset(w*.82,h*.78),'C');
      _text(canvas,'(MN) ∥ (BC)',Offset(w*.35,h*.06),color:green,bold:true);
    } else if (kind == 'geom_coordinate' || kind == 'graph_line') {
      final origin=Offset(w*.18,h*.82);
      _arrow(canvas,Offset(w*.08,origin.dy),Offset(w*.92,origin.dy),ink);
      _arrow(canvas,Offset(origin.dx,h*.92),Offset(origin.dx,h*.08),ink);
      for (int i=1;i<=6;i++) {
        final x=origin.dx+i*w*.105;
        _line(canvas,Offset(x,origin.dy-4),Offset(x,origin.dy+4),grey);
        final y=origin.dy-i*h*.105;
        _line(canvas,Offset(origin.dx-4,y),Offset(origin.dx+4,y),grey);
      }
      if (kind=='geom_coordinate') {
        final a=Offset(w*.60,h*.30);
        _line(canvas,a,Offset(a.dx,origin.dy),green,dashed:true);
        _line(canvas,a,Offset(origin.dx,a.dy),orange,dashed:true);
        _point(canvas,a,'A(x ; y)');
      } else {
        final a=Offset(w*.24,h*.72),b=Offset(w*.82,h*.18);
        _line(canvas,a,b,red,width:3);
        _point(canvas,a,''); _point(canvas,b,'');
      }
      _text(canvas,'x',Offset(w*.92,origin.dy+5),bold:true);
      _text(canvas,'y',Offset(origin.dx+7,h*.05),bold:true);
    } else if (kind == 'geom_cube' || kind == 'geom_prism') {
      final dx=w*.18,dy=h*.17;
      final x=w*.24,y=h*.30,bw=w*.43,bh=h*.43;
      final f=Offset(dx,-dy);
      final p1=Offset(x,y),p2=Offset(x+bw,y),p3=Offset(x+bw,y+bh),p4=Offset(x,y+bh);
      final q1=p1+f,q2=p2+f,q3=p3+f,q4=p4+f;
      for(final pair in <List<Offset>>[[p1,p2],[p2,p3],[p3,p4],[p4,p1],[q1,q2],[q2,q3],[q3,q4],[q4,q1],[p1,q1],[p2,q2],[p3,q3],[p4,q4]]) {
        _line(canvas,pair[0],pair[1],blue,width:2.5);
      }
      _text(canvas,kind=='geom_cube'?'a':'h',Offset(x+bw+dx+3,y+bh*.5),color:red,bold:true);
    } else if (kind == 'geom_pyramid') {
      final apex=Offset(w*.52,h*.12),a=Offset(w*.20,h*.72),b=Offset(w*.78,h*.72),c=Offset(w*.88,h*.48),d=Offset(w*.32,h*.48);
      _line(canvas,a,b,blue,width:2.5); _line(canvas,b,c,blue,width:2.5); _line(canvas,c,d,blue,width:2.5); _line(canvas,d,a,blue,width:2.5);
      for(final p in [a,b,c,d]) _line(canvas,apex,p,red,width:2.5);
      _line(canvas,apex,Offset(w*.54,h*.59),green,dashed:true);
      _text(canvas,'S',apex+const Offset(4,-12),bold:true); _text(canvas,'H',Offset(w*.54,h*.60),color:green,bold:true);
    } else if (kind == 'geom_cylinder') {
      final left=w*.25,right=w*.75,top=h*.20,bottom=h*.78,ry=h*.10;
      canvas.drawOval(Rect.fromLTRB(left,top-ry,right,top+ry),Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=2.5);
      _line(canvas,Offset(left,top),Offset(left,bottom),blue,width:2.5);
      _line(canvas,Offset(right,top),Offset(right,bottom),blue,width:2.5);
      canvas.drawArc(Rect.fromLTRB(left,bottom-ry,right,bottom+ry),0,math.pi, false,Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=2.5);
      canvas.drawArc(Rect.fromLTRB(left,bottom-ry,right,bottom+ry),math.pi,math.pi,false,Paint()..color=grey..style=PaintingStyle.stroke..strokeWidth=1.5);
      _line(canvas,center,Offset(w*.72,h*.42),red,width:2.5);
      _text(canvas,'r',Offset(w*.61,h*.40),color:red,bold:true); _text(canvas,'h',Offset(right+7,h*.47),color:green,bold:true);
    } else if (kind == 'svt_cell') {
      final cell=Rect.fromCenter(center:center,width:w*.48,height:h*.68);
      canvas.drawOval(cell,Paint()..color=const Color(0x3322C55E)..style=PaintingStyle.fill);
      canvas.drawOval(cell,Paint()..color=green..style=PaintingStyle.stroke..strokeWidth=3);
      canvas.drawCircle(center,24,Paint()..color=const Color(0xFF93C5FD));
      canvas.drawCircle(center,24,Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=2);
      _text(canvas,'Noyau',center+const Offset(28,-8),size:10,color:blue,bold:true);
      _text(canvas,'Membrane',Offset(w*.34,h*.12),size:10,color:green,bold:true);
      _arrow(canvas,Offset(5,h*.40),Offset(w*.25,h*.40),blue);
      _arrow(canvas,Offset(5,h*.58),Offset(w*.25,h*.58),orange);
      _arrow(canvas,Offset(w*.75,h*.47),Offset(w-5,h*.47),red);
      _text(canvas,'Entrées',Offset(3,h*.24),size:10,color:blue,bold:true);
      _text(canvas,'Sorties',Offset(w*.78,h*.27),size:10,color:red,bold:true);
    } else if (kind == 'svt_neuron') {
      final soma=Offset(w*.28,h*.50);
      canvas.drawCircle(soma,27,Paint()..color=const Color(0xFFFDE68A));
      canvas.drawCircle(soma,27,Paint()..color=orange..style=PaintingStyle.stroke..strokeWidth=2);
      canvas.drawCircle(soma,9,Paint()..color=blue);
      for(final end in [Offset(w*.08,h*.20),Offset(w*.07,h*.48),Offset(w*.10,h*.82),Offset(w*.25,h*.12),Offset(w*.34,h*.10)]) {
        _line(canvas,soma,end,green,width:2.5);
      }
      final axonStart=Offset(w*.43,h*.50), axonEnd=Offset(w*.88,h*.50);
      _line(canvas,axonStart,axonEnd,blue,width:4);
      for(int i=0;i<4;i++) {
        final x=w*(.48+i*.095);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x,h*.43,w*.065,h*.14),const Radius.circular(8)),Paint()..color=const Color(0xFFBFDBFE));
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x,h*.43,w*.065,h*.14),const Radius.circular(8)),Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=1.5);
      }
      _line(canvas,axonEnd,Offset(w*.94,h*.34),red,width:2);
      _line(canvas,axonEnd,Offset(w*.95,h*.50),red,width:2);
      _line(canvas,axonEnd,Offset(w*.94,h*.66),red,width:2);
      _text(canvas,'Dendrites',Offset(2,h*.04),size:10,color:green,bold:true);
      _text(canvas,'Corps cellulaire',Offset(w*.18,h*.78),size:10,bold:true);
      _text(canvas,'Axone + myéline',Offset(w*.48,h*.23),size:10,color:blue,bold:true);
      _text(canvas,'Terminaisons',Offset(w*.72,h*.78),size:10,color:red,bold:true);
    } else if (kind == 'svt_synapse') {
      final pre=Rect.fromLTWH(w*.12,h*.20,w*.30,h*.30);
      final post=Rect.fromLTWH(w*.58,h*.58,w*.30,h*.22);
      canvas.drawRRect(RRect.fromRectAndRadius(pre,const Radius.circular(25)),Paint()..color=const Color(0xFFBFDBFE));
      canvas.drawRRect(RRect.fromRectAndRadius(pre,const Radius.circular(25)),Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=2);
      canvas.drawRRect(RRect.fromRectAndRadius(post,const Radius.circular(18)),Paint()..color=const Color(0xFFDCFCE7));
      canvas.drawRRect(RRect.fromRectAndRadius(post,const Radius.circular(18)),Paint()..color=green..style=PaintingStyle.stroke..strokeWidth=2);
      for(int i=0;i<5;i++) {
        canvas.drawCircle(Offset(w*(.20+i*.045),h*.38),4,Paint()..color=orange);
        canvas.drawCircle(Offset(w*(.48+i*.035),h*(.48+(i%2)*.05)),3,Paint()..color=orange);
      }
      _arrow(canvas,Offset(w*.43,h*.42),Offset(w*.58,h*.62),red);
      _text(canvas,'Bouton présynaptique',Offset(w*.08,h*.06),size:10,color:blue,bold:true);
      _text(canvas,'Fente synaptique',Offset(w*.39,h*.80),size:10,color:orange,bold:true);
      _text(canvas,'Récepteurs',Offset(w*.62,h*.84),size:10,color:green,bold:true);
else if (kind == 'stats_bar') {
      final base=h*.82;
      _line(canvas,Offset(w*.12,base),Offset(w*.92,base),ink);
      final vals=[.28,.52,.40,.72,.60];
      for(int i=0;i<vals.length;i++) {
        final x=w*(.20+i*.14);
        canvas.drawRect(Rect.fromLTWH(x,base-h*vals[i]*.72,w*.075,h*vals[i]*.72),Paint()..color=[blue,green,orange,red,Color(0xFF7C3AED)][i]);
      }
      _text(canvas,'Catégories',Offset(w*.42,base+8),size:10);
      _text(canvas,'Effectif',Offset(3,h*.12),size:10);
    }
  }

  @override
  bool shouldRepaint(covariant _GravityDiagramPainter oldDelegate) => oldDelegate.kind != kind;
}
