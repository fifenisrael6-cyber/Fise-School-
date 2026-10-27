import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/services/chapter_learning_service.dart';
import '../../../models/chapter_learning_content.dart';
import '../../../core/utils/educational_text.dart';
import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';
import '../../../core/services/quota_service.dart';
import '../../premium/premium_gate.dart';
import 'chapter_folder_page.dart';
import '../../messages/widgets/message_media.dart';

class ChapterLearningDetailPage extends StatefulWidget {
  const ChapterLearningDetailPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.subject,
    required this.curriculum,
    required this.chapter,
    required this.chapterNumber,
  });

  final Locale locale;
  final UserProfile profile;
  final Subject subject;
  final Curriculum curriculum;
  final CourseChapter chapter;
  final int chapterNumber;

  @override
  State<ChapterLearningDetailPage> createState() =>
      _ChapterLearningDetailPageState();
}

class _ChapterLearningDetailPageState
    extends State<ChapterLearningDetailPage> {
  final ChapterLearningService _service = ChapterLearningService();
  late Future<_ChapterData> _future;
  bool _savingRead = false;
  bool _generatingQuiz = false;

  bool get _en => widget.locale.languageCode == 'en';
  String get _chapterTitle =>
      widget.chapter.labelFor(widget.locale.languageCode);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ChapterData> _load({
    bool forceRefresh = false,
    bool forceRefreshQuizzes = false,
  }) async {
    final results = await Future.wait<dynamic>([
      _service.listContent(widget.chapter.id, forceRefresh: forceRefresh),
      _service.listExercises(widget.chapter.id, forceRefresh: forceRefresh),
      _service.listQuizzes(
        widget.chapter.id,
        forceRefresh: forceRefresh || forceRefreshQuizzes,
      ),
      _service.getCounts(widget.chapter.id, forceRefresh: forceRefresh),
      _service.getProgress(
        studentId: widget.profile.id,
        chapterId: widget.chapter.id,
      ),
    ]);
    return _ChapterData(
      content: results[0] as List<ChapterLearningContentItem>,
      exercises: results[1] as List<ChapterLearningExercise>,
      quizzes: results[2] as List<ChapterLearningQuiz>,
      counts: results[3] as ChapterLearningCounts,
      progress: results[4] as ChapterLearningProgress?,
    );
  }

  Future<void> _refresh() async {
    final refreshed = _load(forceRefresh: true);
    setState(() => _future = refreshed);
    await refreshed;
  }

  Future<void> _markRead() async {
    setState(() => _savingRead = true);
    try {
      await _service.markCourseRead(
        studentId: widget.profile.id,
        chapterId: widget.chapter.id,
      );
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_en ? 'Course marked as read.' : 'Cours marqué comme lu.'),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_en
              ? 'Progress could not be saved: $error'
              : 'Progression non enregistrée : $error'),
        ));
      }
    } finally {
      if (mounted) setState(() => _savingRead = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF166534);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F6),
      appBar: AppBar(
        backgroundColor: green,
        foregroundColor: Colors.white,
        title: Text(_en ? 'Chapter' : 'Chapitre'),
      ),
      body: FutureBuilder<_ChapterData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _en ? 'Unable to load this chapter.\n${snapshot.error}'
                      : 'Impossible de charger ce chapitre.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  children: [
                    Text(widget.subject.labelFor(widget.locale.languageCode)),
                    const Icon(Icons.chevron_right, size: 18),
                    Text(widget.curriculum.labelFor(widget.locale.languageCode)),
                    const Icon(Icons.chevron_right, size: 18),
                    Text(_chapterTitle,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF166534), Color(0xFF21844A)],
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_en ? 'Chapter' : 'Chapitre'} ${widget.chapterNumber}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 6),
                      Text(_chapterTitle,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: data.progress?.courseRead == true ? 1 : 0,
                        backgroundColor: Colors.white24,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        data.progress?.courseRead == true
                            ? (_en ? 'Course read' : 'Cours lu')
                            : (_en ? 'Course not read yet' : 'Cours non lu'),
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        _pill(Icons.menu_book_outlined,
                            '${data.counts.lessons} ${_en ? 'lessons' : 'leçons'}'),
                        _pill(Icons.play_circle_outline,
                            '${data.counts.videos} ${_en ? 'videos' : 'vidéos'}'),
                        _pill(
                          Icons.quiz_outlined,
                          '${data.counts.quizzes} ${_en ? 'Smart QCM' : 'QCM intelligent'}',
                        ),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: data.content.isEmpty ? null : _markRead,
                    icon: _savingRead
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.menu_book_rounded),
                    label: Text(_en ? 'Course' : 'Cours'),
                    style: FilledButton.styleFrom(backgroundColor: green),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Icon(Icons.folder_open_rounded,
                        color: Color(0xFF166534)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _en ? 'CHAPTER FOLDERS' : 'DOSSIERS DU CHAPITRE',
                        style: const TextStyle(
                          color: Color(0xFF166534),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildResourceFolders(data),
                const SizedBox(height: 22),
              ],
            ),
          );
        },
      ),
    );
  }

  String _folderTitle(_ChapterResourceFolder folder) {
    return switch (folder) {
      _ChapterResourceFolder.course => _en ? 'Course' : 'Cours',
      _ChapterResourceFolder.pdf => 'PDF',
      _ChapterResourceFolder.images => _en ? 'Images' : 'Images',
      _ChapterResourceFolder.audio => 'Audio',
      _ChapterResourceFolder.video => _en ? 'Video' : 'Vidéo',
      _ChapterResourceFolder.exercises => _en ? 'Exercises & Smart QCM' : 'Exercices et QCM intelligent',
    };
  }

  IconData _folderIcon(_ChapterResourceFolder folder) {
    return switch (folder) {
      _ChapterResourceFolder.course => Icons.menu_book_rounded,
      _ChapterResourceFolder.pdf => Icons.picture_as_pdf_rounded,
      _ChapterResourceFolder.images => Icons.image_rounded,
      _ChapterResourceFolder.audio => Icons.audiotrack_rounded,
      _ChapterResourceFolder.video => Icons.video_library_rounded,
      _ChapterResourceFolder.exercises => Icons.quiz_rounded,
    };
  }

  List<Widget> _folderItems(_ChapterData data, _ChapterResourceFolder folder) {
    switch (folder) {
      case _ChapterResourceFolder.course:
        return data.content
            .where((item) => item.folderKey == 'course')
            .map(_contentCard).toList(growable: false);
      case _ChapterResourceFolder.pdf:
        return data.content
            .where((item) => item.folderKey == 'pdf')
            .map(_contentCard).toList(growable: false);
      case _ChapterResourceFolder.images:
        final imageEntries = data.content.where((item) => item.folderKey == 'images').toList(growable: false);
        return imageEntries.map((item) => _contentCard(item, galleryItems: imageEntries)).toList(growable: false);
      case _ChapterResourceFolder.audio:
        return data.content
            .where((item) => item.folderKey == 'audio')
            .map(_contentCard).toList(growable: false);
      case _ChapterResourceFolder.video:
        final videoEntries = data.content.where((item) => item.folderKey == 'video').toList(growable: false);
        return videoEntries.map((item) => _contentCard(item, galleryItems: videoEntries)).toList(growable: false);
      case _ChapterResourceFolder.exercises:
        return <Widget>[
          ...data.exercises.map(_exerciseFolderItem),
          ...data.quizzes.map(_quizFolderItem),
        ];
    }
  }

  Widget _buildResourceFolders(_ChapterData data) {
    const folders = <_ChapterResourceFolder>[
      _ChapterResourceFolder.course,
      _ChapterResourceFolder.pdf,
      _ChapterResourceFolder.images,
      _ChapterResourceFolder.audio,
      _ChapterResourceFolder.video,
      _ChapterResourceFolder.exercises,
    ];

    return Column(
      children: [
        for (final folder in folders)
          Builder(builder: (context) {
            final items = _folderItems(data, folder);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(_folderIcon(folder),
                    color: const Color(0xFF166534), size: 32),
                title: Text(_folderTitle(folder),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${items.length} ${_en ? 'item(s)' : 'élément(s)'}',
                ),
                trailing: folder == _ChapterResourceFolder.exercises && _generatingQuiz
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right_rounded),
                onTap: _generatingQuiz ? null : () => _openFolder(folder, data),
              ),
            );
          }),
      ],
    );
  }

  Future<void> _openFolder(
    _ChapterResourceFolder folder,
    _ChapterData currentData,
  ) async {
    if (folder != _ChapterResourceFolder.exercises) {
      final items = _folderItems(currentData, folder);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChapterFolderPage(
            title: _folderTitle(folder),
            items: items,
            emptyMessage: _en
                ? 'No content has been published in this folder yet.'
                : 'Aucun contenu n’a encore été publié dans ce dossier.',
          ),
        ),
      );
      return;
    }

    // Use the locally cached Smart QCM when one already exists. Only call
    // the AI function for an empty folder, so existing quizzes remain usable
    // offline and students do not spend network/AI quota on every folder open.
    if (currentData.quizzes.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChapterFolderPage(
            title: _folderTitle(folder),
            items: <Widget>[
              ...currentData.exercises.map(_exerciseFolderItem),
              ...currentData.quizzes.map(_quizFolderItem),
            ],
            emptyMessage: _en
                ? 'No exercise or Smart QCM has been published in this chapter yet.'
                : 'Aucun exercice ni QCM intelligent n’a encore été publié dans ce chapitre.',
          ),
        ),
      );
      return;
    }

    setState(() => _generatingQuiz = true);
    try {
      await _service.generateSmartQuiz(widget.chapter.id);
      final refreshedFuture = _load(forceRefreshQuizzes: true);
      setState(() => _future = refreshedFuture);
      final refreshed = await refreshedFuture;
      if (!mounted) return;
      final exerciseItems = <Widget>[
        ...refreshed.exercises.map(_exerciseFolderItem),
        ...refreshed.quizzes.map(_quizFolderItem),
      ];
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChapterFolderPage(
            title: _folderTitle(folder),
            items: exerciseItems,
            emptyMessage: _en
                ? 'No exercise or Smart QCM could be loaded for this chapter.'
                : 'Aucun exercice ni QCM intelligent n’a pu être chargé pour ce chapitre.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_en
                ? 'Smart QCM generation failed: $error'
                : 'Échec de génération du QCM intelligent : $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingQuiz = false);
    }
  }

  Widget _exerciseFolderItem(ChapterLearningExercise exercise) {
    final statement = exercise.statementFor(widget.locale.languageCode).trim();
    final difficulty = _en
        ? exercise.difficultyLabelEn
        : exercise.difficultyLabelFr;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.edit_note_rounded, color: Color(0xFF166534)),
        title: Text(
          statement.isEmpty
              ? (_en ? 'Exercise' : 'Exercice')
              : statement,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(difficulty),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(_en ? 'Exercise' : 'Exercice'),
            content: SingleChildScrollView(
              child: Text(statement.isEmpty
                  ? (_en ? 'No statement available.' : 'Énoncé indisponible.')
                  : statement),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(_en ? 'Close' : 'Fermer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quizFolderItem(ChapterLearningQuiz quiz) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.quiz_outlined, color: Color(0xFF166534)),
        title: Text(quiz.titleFor(widget.locale.languageCode),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${quiz.questionCount} ${_en ? 'questions' : 'questions'}'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () async {
          final allowed = await PremiumGate.ensure(
            context,
            profile: widget.profile,
            feature: QuotaFeature.qcm,
            resourceId: quiz.id,
            offlineFallback: true,
          );
          if (!allowed || !mounted) return;
          Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ChapterInteractiveQuizPage(
              quiz: quiz,
              locale: widget.locale,
              profile: widget.profile,
            ),
          ));
        },
      ),
    );
  }

  Future<String?> _resolveChapterGalleryUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    const legacyPrefix = 'legacy-course-resource:';
    if (path.startsWith(legacyPrefix)) {
      return Supabase.instance.client.storage
          .from('cours-fichiers')
          .createSignedUrl(path.substring(legacyPrefix.length), 900);
    }
    return Supabase.instance.client.storage
        .from('chapter-content')
        .createSignedUrl(path, 900);
  }

  Widget _contentCard(ChapterLearningContentItem item, {List<ChapterLearningContentItem>? galleryItems}) {
    final title = item.titleFor(widget.locale.languageCode);
    final icon = switch (item.type) {
      ChapterLearningContentType.course => Icons.menu_book_outlined,
      ChapterLearningContentType.video => Icons.play_circle_outline,
      ChapterLearningContentType.pdf => Icons.picture_as_pdf_outlined,
      ChapterLearningContentType.image => Icons.image_outlined,
      ChapterLearningContentType.audio => Icons.audiotrack_outlined,
    };
    final body = item.bodyFor(widget.locale.languageCode);
    return Card(
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF166534)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: body == null || body.trim().isEmpty
            ? null
            : Text(body, maxLines: 3, overflow: TextOverflow.ellipsis),
        trailing: item.type != ChapterLearningContentType.course
            ? const Icon(Icons.open_in_new)
            : null,
        onTap: () async {
          if ((item.folderKey == 'images' || item.folderKey == 'video') &&
              galleryItems != null && galleryItems.isNotEmpty) {
            final supportDirectory = await getApplicationSupportDirectory();
            final userId = widget.profile.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
            final mediaItems = galleryItems
                .where((entry) {
                  final storagePath = (entry.storagePath ?? '').trim();
                  final external = (entry.externalUrl ?? '').toLowerCase();
                  if (storagePath.isNotEmpty) return true;
                  if (external.isEmpty) return false;
                  if (entry.folderKey == 'video' &&
                      (external.contains('youtube.com') ||
                          external.contains('youtu.be') ||
                          external.contains('vimeo.com'))) return false;
                  return true;
                })
                .map((entry) {
                  final storagePath = (entry.storagePath ?? '').trim();
                  final external = (entry.externalUrl ?? '').trim().toLowerCase();
                  final source = storagePath.isNotEmpty ? storagePath : external;
                  final embedded = entry.folderKey == 'video' &&
                      (source.contains('youtube.com') ||
                          source.contains('youtu.be') ||
                          source.contains('vimeo.com'));
                  final safeId = entry.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
                  final localPath = source.isNotEmpty && !embedded
                      ? p.join(supportDirectory.path, 'offline', 'chapter_media', userId, '$safeId.bin')
                      : null;
                  return MessageMediaGalleryItem(
                    name: entry.titleFor(widget.locale.languageCode),
                    type: entry.folderKey == 'video' ? 'video/mp4' : 'image/jpeg',
                    localPath: localPath,
                    remotePath: entry.storagePath ?? entry.externalUrl,
                    cacheScope: widget.profile.id,
                  );
                })
                .toList(growable: false);
            final currentPath = item.storagePath ?? item.externalUrl;
            final initialIndex = mediaItems.indexWhere((entry) =>
                entry.remotePath == currentPath);
            if (mediaItems.isNotEmpty && initialIndex >= 0) {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MediaGalleryViewerPage(
                  items: mediaItems,
                  initialIndex: initialIndex,
                  resolveUrl: _resolveChapterGalleryUrl,
                ),
              ));
              return;
            }
          }
          if (body != null && body.trim().isNotEmpty) {
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    child: Text(body, style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            );
          } else {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ChapterContentViewerPage(
                item: item,
                locale: widget.locale,
              ),
            ));
          }
        },
      ),
    );
  }

  Widget _pill(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white)),
        ]),
      );

  Widget _notice(String text) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text, textAlign: TextAlign.center),
      );
}

enum _ChapterResourceFolder { course, pdf, images, audio, video, exercises }

class _ChapterData {
  const _ChapterData({
    required this.content,
    required this.exercises,
    required this.quizzes,
    required this.counts,
    required this.progress,
  });

  final List<ChapterLearningContentItem> content;
  final List<ChapterLearningExercise> exercises;
  final List<ChapterLearningQuiz> quizzes;
  final ChapterLearningCounts counts;
  final ChapterLearningProgress? progress;
}


/// Lecteur intégré des contenus de chapitre. Les PDF privés sont servis via
/// une URL Supabase signée; les vidéos MP4 sont lues dans l'application.
class ChapterContentViewerPage extends StatefulWidget {
  const ChapterContentViewerPage({super.key, required this.item, required this.locale});
  final ChapterLearningContentItem item;
  final Locale locale;

  @override
  State<ChapterContentViewerPage> createState() => _ChapterContentViewerPageState();
}

class _ChapterContentViewerPageState extends State<ChapterContentViewerPage> {
  PdfControllerPinch? _pdf;
  VideoPlayerController? _video;
  WebViewController? _webView;
  AudioPlayer? _audioPlayer;
  PlayerState _audioState = PlayerState.stopped;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  StreamSubscription<PlayerState>? _audioStateSubscription;
  StreamSubscription<Duration>? _audioPositionSubscription;
  StreamSubscription<Duration>? _audioDurationSubscription;
  Uint8List? _bytes;
  File? _mediaFile;
  String? _mediaUrl;
  bool _loading = true;
  String? _error;
  bool get _en => widget.locale.languageCode == 'en';

  Future<String?> _url() async {
    final path = widget.item.storagePath;
    if (path != null && path.isNotEmpty) {
      if (path.startsWith('http://') || path.startsWith('https://')) return path;
      const legacyPrefix = 'legacy-course-resource:';
      if (path.startsWith(legacyPrefix)) {
        final legacyPath = path.substring(legacyPrefix.length);
        return Supabase.instance.client.storage
            .from('cours-fichiers')
            .createSignedUrl(legacyPath, 900);
      }
      return Supabase.instance.client.storage
          .from('chapter-content')
          .createSignedUrl(path, 900);
    }
    return widget.item.externalUrl;
  }

  String? _embeddedVideoUrl(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host == 'youtu.be') {
      final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
      return id.isEmpty ? null : 'https://www.youtube-nocookie.com/embed/$id?playsinline=1&rel=0';
    }
    if (host.contains('youtube.com')) {
      final id = uri.queryParameters['v'] ??
          (uri.pathSegments.length >= 2 && uri.pathSegments.first == 'embed'
              ? uri.pathSegments[1]
              : null);
      return id == null || id.isEmpty
          ? null
          : 'https://www.youtube-nocookie.com/embed/$id?playsinline=1&rel=0';
    }
    if (host.contains('vimeo.com')) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final id = segments.reversed.firstWhere(
        (segment) => int.tryParse(segment) != null,
        orElse: () => '',
      );
      return id.isEmpty ? null : 'https://player.vimeo.com/video/$id';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<File> _localMediaFile() async {
    final directory = await getApplicationSupportDirectory();
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'offline-guest';
    final safeUser = userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final safeId = widget.item.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File(p.join(directory.path, 'offline', 'chapter_media', safeUser, '$safeId.bin'));
  }

  Future<void> _open() async {
    try {
      final rawMediaSource = ((widget.item.storagePath?.trim().isNotEmpty == true)
          ? widget.item.storagePath!
          : widget.item.externalUrl ?? '').toLowerCase();
      final isEmbeddedVideo = rawMediaSource.contains('youtube.com') ||
          rawMediaSource.contains('youtu.be') ||
          rawMediaSource.contains('vimeo.com');
      final cacheable = widget.item.folderKey == 'pdf' ||
          widget.item.folderKey == 'images' ||
          widget.item.folderKey == 'audio' ||
          (widget.item.folderKey == 'video' &&
              rawMediaSource.isNotEmpty &&
              !isEmbeddedVideo);
      if (cacheable) {
        final local = await _localMediaFile();
        if (await local.exists() && await local.length() > 0) {
          _mediaFile = local;
          if (widget.item.folderKey == 'pdf') {
            _bytes = await local.readAsBytes();
            _pdf = PdfControllerPinch(document: PdfDocument.openData(_bytes!));
          } else if (widget.item.folderKey == 'images') {
            _bytes = await local.readAsBytes();
          } else if (widget.item.folderKey == 'audio') {
            await _prepareAudio(DeviceFileSource(local.path));
          } else if (widget.item.folderKey == 'video') {
            _video = VideoPlayerController.file(local);
            await _video!.initialize();
          }
          _mediaUrl = local.uri.toString();
        }
      }

      if (_mediaFile == null) {
        final url = await _url();
        if (url == null || url.isEmpty) {
          throw Exception(_en ? 'No file URL.' : 'Aucun lien de fichier.');
        }
        _mediaUrl = url;
        if (widget.item.folderKey == 'pdf' ||
            widget.item.folderKey == 'images') {
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw Exception('HTTP ${response.statusCode}');
          }
          _bytes = response.bodyBytes;
          if (cacheable) {
            final local = await _localMediaFile();
            await local.parent.create(recursive: true);
            await local.writeAsBytes(_bytes!, flush: true);
            _mediaFile = local;
          }
          if (widget.item.folderKey == 'pdf') {
            _pdf = PdfControllerPinch(document: PdfDocument.openData(_bytes!));
          }
        } else if (widget.item.folderKey == 'audio') {
          await _prepareAudio(UrlSource(url));
          if (cacheable) unawaited(_cacheVideoInBackground(url));
        } else if (widget.item.folderKey == 'video') {
          final uri = Uri.parse(url);
          final host = uri.host.toLowerCase();
          if (host.contains('youtube.com') || host == 'youtu.be' || host.contains('vimeo.com')) {
            final embedUrl = _embeddedVideoUrl(uri);
            if (embedUrl == null) {
              throw Exception(_en ? 'Unsupported video link.' : 'Lien vidéo non pris en charge.');
            }
            _webView = WebViewController()
              ..setJavaScriptMode(JavaScriptMode.unrestricted)
              ..setBackgroundColor(const Color(0xFF000000))
              ..loadRequest(Uri.parse(embedUrl));
          } else {
            _video = VideoPlayerController.networkUrl(uri);
            await _video!.initialize();
            if (cacheable) unawaited(_cacheVideoInBackground(url));
          }
        }
      }
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _prepareAudio(Source source) async {
    final player = AudioPlayer();
    _audioPlayer = player;
    _audioStateSubscription = player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _audioState = state);
    });
    _audioPositionSubscription = player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _audioPosition = position);
    });
    _audioDurationSubscription = player.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _audioDuration = duration);
    });
    await player.setSource(source);
  }

  String _formatAudioDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${duration.inHours > 0 ? '${duration.inHours}:' : ''}$minutes:$seconds';
  }

  Future<void> _cacheVideoInBackground(String url) async {
    final client = http.Client();
    try {
      final local = await _localMediaFile();
      if (await local.exists() && await local.length() > 0) return;
      final response = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        return;
      }
      await local.parent.create(recursive: true);
      final temporary = File('${local.path}.part');
      if (await temporary.exists()) await temporary.delete();
      await response.stream.pipe(temporary.openWrite());
      if (await temporary.exists() && await temporary.length() > 0) {
        if (await local.exists()) await local.delete();
        await temporary.rename(local.path);
      } else if (await temporary.exists()) {
        await temporary.delete();
      }
    } catch (_) {
      // Streaming playback continues even when the offline copy cannot be saved.
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    _pdf?.dispose();
    _video?.dispose();
    _audioStateSubscription?.cancel();
    _audioPositionSubscription?.cancel();
    _audioDurationSubscription?.cancel();
    _audioPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.item.titleFor(widget.locale.languageCode);
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)));
    } else if (widget.item.folderKey == 'pdf') {
      body = _pdf == null ? Center(child: Text(_en ? 'PDF unavailable.' : 'PDF indisponible.')) : PdfViewPinch(controller: _pdf!);
    } else if (widget.item.folderKey == 'images' && (_mediaFile != null || _mediaUrl != null)) {
      body = Center(
        child: InteractiveViewer(
          child: _mediaFile != null
              ? Image.file(
                  _mediaFile!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Text(_en ? 'Image could not be opened.' : 'Impossible d’ouvrir l’image.'),
                )
              : Image.network(
                  _mediaUrl!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Text(_en ? 'Image could not be opened.' : 'Impossible d’ouvrir l’image.'),
                ),
        ),
      );
    } else if (widget.item.folderKey == 'audio' && _audioPlayer != null) {
      final durationMs = _audioDuration.inMilliseconds;
      final positionMs = _audioPosition.inMilliseconds.clamp(0, durationMs > 0 ? durationMs : 0);
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.audio_file_rounded, size: 88),
              const SizedBox(height: 20),
              Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Slider(
                value: positionMs.toDouble(),
                max: durationMs > 0 ? durationMs.toDouble() : 1,
                onChanged: durationMs <= 0 ? null : (value) => _audioPlayer!.seek(Duration(milliseconds: value.round())),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(_formatAudioDuration(_audioPosition)),
                Text(_formatAudioDuration(_audioDuration)),
              ]),
              IconButton(
                iconSize: 64,
                onPressed: () async {
                  if (_audioState == PlayerState.playing) {
                    await _audioPlayer!.pause();
                  } else {
                    await _audioPlayer!.resume();
                  }
                },
                icon: Icon(_audioState == PlayerState.playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
              ),
            ],
          ),
        ),
      );
    } else if ((widget.item.folderKey == 'video' || widget.item.folderKey == 'audio') && _webView != null) {
      body = WebViewWidget(controller: _webView!);
    } else if (widget.item.folderKey == 'video' && _video != null) {
      body = Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        AspectRatio(aspectRatio: _video!.value.aspectRatio > 0 ? _video!.value.aspectRatio : 16 / 9, child: VideoPlayer(_video!)),
        VideoProgressIndicator(_video!, allowScrubbing: true),
        IconButton(iconSize: 42, onPressed: () => setState(() => _video!.value.isPlaying ? _video!.pause() : _video!.play()), icon: Icon(_video!.value.isPlaying ? Icons.pause_circle : Icons.play_circle)),
      ]));
    } else {
      body = Center(child: Text(_en ? 'Media could not be opened.' : 'Impossible d’ouvrir ce média.'));
    }
    return Scaffold(appBar: AppBar(title: Text(title)), body: body);
  }
}


class ChapterInteractiveQuizPage extends StatefulWidget {
  const ChapterInteractiveQuizPage({super.key, required this.quiz, required this.locale, this.profile});
  final UserProfile? profile;
  final ChapterLearningQuiz quiz;
  final Locale locale;

  @override
  State<ChapterInteractiveQuizPage> createState() => _ChapterInteractiveQuizPageState();
}

class _ChapterInteractiveQuizPageState extends State<ChapterInteractiveQuizPage> {
  final ChapterLearningService _service = ChapterLearningService();
  late Future<List<ChapterLearningQuizQuestion>> _future;
  final Map<String, int> _answers = {};
  bool _busy = false;
  Map<String, dynamic>? _result;
  String? _error;
  bool get _en => widget.locale.languageCode == 'en';

  @override
  void initState() {
    super.initState();
    _future = _service.listQuizQuestions(widget.quiz.id);
  }

  Future<void> _submit(List<ChapterLearningQuizQuestion> questions) async {
    if (_answers.length != questions.length) {
      setState(() => _error = _en ? 'Answer every question first.' : 'Réponds à toutes les questions.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final result = await _service.submitQuiz(quizId: widget.quiz.id, answers: Map<String, int>.from(_answers));
      if (mounted) setState(() => _result = result);
    } catch (e) {
      final denied = e.toString().contains('QUOTA_EXCEEDED') || e.toString().contains('PREMIUM_REQUIRED');
      if (denied && widget.profile != null && mounted) {
        setState(() => _busy = false);
        final ok = await PremiumGate.openForServerDenial(context, profile: widget.profile!, feature: QuotaFeature.qcm);
        if (ok && mounted) { await _submit(questions); }
        return;
      }
      if (mounted) setState(() => _error = (_en ? 'Submission failed. Check connection and database migration. ' : 'Échec de validation. Vérifie la connexion et la migration. ') + e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.quiz.titleFor(widget.locale.languageCode))),
    body: FutureBuilder<List<ChapterLearningQuizQuestion>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(snapshot.error.toString())));
        final questions = snapshot.data ?? const <ChapterLearningQuizQuestion>[];
        if (questions.isEmpty) return Center(child: Text(_en ? 'No questions published.' : 'Aucune question publiée.'));
        final score = _result?['score'];
        final correct = _result?['correct_answers'];
        final total = _result?['total_questions'];
        return ListView(padding: const EdgeInsets.all(16), children: [
          if (_result != null) Card(color: const Color(0xFFE4F2E9), child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text((_en ? 'Score: ' : 'Résultat : ') + score.toString() + '% (' + correct.toString() + '/' + total.toString() + ')',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          )),
          if (_result != null && _result!['review'] is List)
            for (final rawReview in (_result!['review'] as List))
              if (rawReview is Map)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Builder(builder: (context) {
                      final review = Map<String, dynamic>.from(rawReview);
                      final questionId = review['question_id']?.toString();
                      final questionIndex = questions.indexWhere((q) => q.id == questionId);
                      if (questionIndex < 0) return const SizedBox.shrink();
                      final question = questions[questionIndex];
                      final options = question.optionsFor(widget.locale.languageCode);
                      final selected = (review['selected_option_index'] as num?)?.toInt();
                      final correctIndex = (review['correct_option_index'] as num?)?.toInt();
                      final explanation = (widget.locale.languageCode == 'en'
                          ? review['explanation_en']
                          : review['explanation_fr']) as String?;
                      final selectedText = selected != null && selected >= 0 && selected < options.length
                          ? options[selected] : (_en ? 'No answer' : 'Aucune réponse');
                      final correctText = correctIndex != null && correctIndex >= 0 && correctIndex < options.length
                          ? options[correctIndex] : (_en ? 'Correction unavailable' : 'Corrigé indisponible');
                      final isCorrect = review['is_correct'] == true;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${questionIndex + 1}. ${readableEducationalText(question.promptFor(widget.locale.languageCode))}',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                color: isCorrect ? Colors.green.shade700 : Colors.red.shade700,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isCorrect
                                      ? (_en ? 'Correct' : 'Bonne réponse')
                                      : (_en ? 'Incorrect' : 'Mauvaise réponse'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: isCorrect ? Colors.green.shade800 : Colors.red.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('${_en ? 'Your answer' : 'Ta réponse'}: ${readableEducationalText(selectedText)}'),
                          Text('${_en ? 'Correct answer' : 'Bonne réponse'}: ${readableEducationalText(correctText)}',
                            style: TextStyle(fontWeight: FontWeight.w700,
                              color: isCorrect ? Colors.green.shade800 : Colors.red.shade700)),
                          if (explanation != null && explanation.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text('${_en ? 'Explanation' : 'Explication'}: ${readableEducationalText(explanation)}'),
                          ],
                        ],
                      );
                    }),
                  ),
                ),
          for (var i = 0; i < questions.length; i++) Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(padding: const EdgeInsets.all(12), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((i + 1).toString() + '. ' + readableEducationalText(questions[i].promptFor(widget.locale.languageCode)), style: const TextStyle(fontWeight: FontWeight.w800)),
                for (var j = 0; j < questions[i].optionsFor(widget.locale.languageCode).length; j++)
                  RadioListTile<int>(
                    contentPadding: EdgeInsets.zero,
                    value: j,
                    groupValue: _answers[questions[i].id],
                    title: Text(readableEducationalText(questions[i].optionsFor(widget.locale.languageCode)[j])),
                    onChanged: _result != null ? null : (value) { if (value != null) setState(() => _answers[questions[i].id] = value); },
                  ),
              ],
            )),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          if (_result == null) FilledButton(
            onPressed: _busy ? null : () => _submit(questions),
            child: _busy ? const CircularProgressIndicator() : Text(_en ? 'Submit quiz' : 'Valider le quiz'),
          ),
          if (_result != null) OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(_en ? 'Finish' : 'Terminer')),
        ]);
      },
    ),
  );
}
