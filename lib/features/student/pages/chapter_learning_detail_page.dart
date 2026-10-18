import 'dart:io';
import 'dart:typed_data';

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
import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';
import '../../../core/services/quota_service.dart';
import '../../premium/premium_gate.dart';
import 'chapter_folder_page.dart';

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

  bool get _en => widget.locale.languageCode == 'en';
  String get _chapterTitle =>
      widget.chapter.labelFor(widget.locale.languageCode);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ChapterData> _load() async {
    final results = await Future.wait<dynamic>([
      _service.listContent(widget.chapter.id),
      _service.listExercises(widget.chapter.id),
      _service.listQuizzes(widget.chapter.id),
      _service.getCounts(widget.chapter.id),
      _service.getProgress(
        studentId: widget.profile.id,
        chapterId: widget.chapter.id,
      ),
    ]);
    final exercises = results[1] as List<ChapterLearningExercise>;
    final completed = await _service.completedExerciseIds(
      studentId: widget.profile.id,
      exerciseIds: exercises.map((exercise) => exercise.id).toList(),
    );
    return _ChapterData(
      content: results[0] as List<ChapterLearningContentItem>,
      exercises: exercises,
      quizzes: results[2] as List<ChapterLearningQuiz>,
      counts: results[3] as ChapterLearningCounts,
      progress: results[4] as ChapterLearningProgress?,
      completedExerciseIds: completed,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
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
          final total = data.exercises.length;
          final completed = data.completedExerciseIds.length;
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
                        _pill(Icons.quiz_outlined,
                            '${data.counts.quizzes} quiz'),
                        _pill(Icons.edit_note,
                            '${completed}/${total} ${_en ? 'exercises' : 'exercices'}'),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: data.quizzes.isEmpty
                          ? null
                          : () => _showQuizzes(data.quizzes),
                      icon: const Icon(Icons.quiz_outlined),
                      label: const Text('Quiz'),
                    ),
                  ),
                ]),
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
      _ChapterResourceFolder.course => _en ? 'Courses and lessons' : 'Cours et leçons',
      _ChapterResourceFolder.documents => _en ? 'Documents (PDF and images)' : 'Documents (PDF et images)',
      _ChapterResourceFolder.audio => _en ? 'Audio files' : 'Fichiers audio',
      _ChapterResourceFolder.video => _en ? 'Videos' : 'Vidéos',
      _ChapterResourceFolder.exercises => _en ? 'Exercises' : 'Exercices',
      _ChapterResourceFolder.quizzes => _en ? 'AI quizzes' : 'QCM IA',
    };
  }

  List<Widget> _folderItems(_ChapterData data, _ChapterResourceFolder folder) {
    switch (folder) {
      case _ChapterResourceFolder.course:
        return data.content
            .where((item) => item.type == ChapterLearningContentType.course)
            .map(_contentCard).toList(growable: false);
      case _ChapterResourceFolder.documents:
        return data.content
            .where((item) => item.type == ChapterLearningContentType.pdf ||
                item.type == ChapterLearningContentType.image)
            .map(_contentCard).toList(growable: false);
      case _ChapterResourceFolder.audio:
        return data.content
            .where((item) => item.type == ChapterLearningContentType.audio)
            .map(_contentCard).toList(growable: false);
      case _ChapterResourceFolder.video:
        return data.content
            .where((item) => item.type == ChapterLearningContentType.video)
            .map(_contentCard).toList(growable: false);
      case _ChapterResourceFolder.exercises:
        return data.exercises
            .map((exercise) => _exerciseCard(
                exercise, data.completedExerciseIds.contains(exercise.id)))
            .toList(growable: false);
      case _ChapterResourceFolder.quizzes:
        return data.quizzes.map(_quizFolderItem).toList(growable: false);
    }
  }

  Widget _buildResourceFolders(_ChapterData data) {
    const folders = <_ChapterResourceFolder>[
      _ChapterResourceFolder.course,
      _ChapterResourceFolder.documents,
      _ChapterResourceFolder.audio,
      _ChapterResourceFolder.video,
      _ChapterResourceFolder.exercises,
      _ChapterResourceFolder.quizzes,
    ];

    return Column(
      children: [
        for (final folder in folders)
          Builder(builder: (context) {
            final items = _folderItems(data, folder);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.folder_rounded,
                    color: Color(0xFF166534), size: 34),
                title: Text(_folderTitle(folder),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${items.length} ${_en ? 'item(s)' : 'élément(s)'}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ChapterFolderPage(
                      title: _folderTitle(folder),
                      items: items,
                      emptyMessage: _en
                          ? 'No content has been published in this folder yet.'
                          : 'Aucun contenu n’a encore été publié dans ce dossier.',
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
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

  Widget _contentCard(ChapterLearningContentItem item) {
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
        onTap: () {
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

  Widget _exerciseCard(ChapterLearningExercise exercise, bool isCompleted) {
    final title = _en ? 'Exercise' : 'Exercice';
    final level = _en
        ? exercise.difficultyLabelEn
        : exercise.difficultyLabelFr;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            Chip(label: Text(level)),
            Checkbox(
              value: isCompleted,
              onChanged: (value) => _toggleExercise(exercise, value ?? false),
            ),
          ]),
          const SizedBox(height: 8),
          Text(exercise.statementFor(widget.locale.languageCode)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _revealCorrection(exercise),
            icon: const Icon(Icons.lightbulb_outline),
            label: Text(_en ? 'Show correction' : 'Voir le corrigé'),
          ),
        ]),
      ),
    );
  }

  Future<void> _toggleExercise(
    ChapterLearningExercise exercise,
    bool completed,
  ) async {
    try {
      await _service.markExerciseCompleted(
        studentId: widget.profile.id,
        exerciseId: exercise.id,
        completed: completed,
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_en
            ? 'Progress could not be saved: $error'
            : 'Progression non enregistrée : $error'),
      ));
    }
  }

  Future<void> _revealCorrection(ChapterLearningExercise exercise) async {
    try {
      final correction = await _service.getExerciseCorrection(exercise.id);
      if (!mounted) return;
      if (correction == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_en
              ? 'The correction is not available yet.'
              : 'Le corrigé n’est pas encore disponible.'),
        ));
        return;
      }
      final text = [
        correction.correctionFor(widget.locale.languageCode),
        correction.explanationFor(widget.locale.languageCode) ?? '',
      ].where((value) => value.trim().isNotEmpty).join('\n\n');
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(_en ? 'Correction' : 'Corrigé'),
          content: SingleChildScrollView(child: Text(text)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_en ? 'Close' : 'Fermer'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_en
            ? 'Could not load the correction. Check your connection.'
            : 'Impossible de charger le corrigé. Vérifie la connexion.'),
      ));
    }
  }

  void _showQuizzes(List<ChapterLearningQuiz> quizzes) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text(_en ? 'Quizzes' : 'Quiz',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            for (final quiz in quizzes)
              ListTile(
                leading: const Icon(Icons.quiz_outlined),
                title: Text(quiz.titleFor(widget.locale.languageCode)),
                subtitle: Text('${quiz.questionCount} ${_en ? 'questions' : 'questions'}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final nav = Navigator.of(context);
                  nav.pop();
                  // Quota QCM : 2 / 24 h pour un élève gratuit (vérifié côté serveur).
                  final allowed = await PremiumGate.ensure(
                    this.context,
                    profile: widget.profile,
                    feature: QuotaFeature.qcm,
                    resourceId: quiz.id,
                  );
                  if (!allowed || !mounted) return;
                  nav.push(MaterialPageRoute(
                    builder: (_) => ChapterInteractiveQuizPage(
                      quiz: quiz,
                      locale: widget.locale,
                      profile: widget.profile,
                    ),
                  ));
                },
              ),
          ],
        ),
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

enum _ChapterResourceFolder { course, documents, audio, video, exercises, quizzes }

class _ChapterData {
  const _ChapterData({
    required this.content,
    required this.exercises,
    required this.quizzes,
    required this.counts,
    required this.progress,
    required this.completedExerciseIds,
  });

  final List<ChapterLearningContentItem> content;
  final List<ChapterLearningExercise> exercises;
  final List<ChapterLearningQuiz> quizzes;
  final ChapterLearningCounts counts;
  final ChapterLearningProgress? progress;
  final Set<String> completedExerciseIds;
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
  Uint8List? _bytes;
  File? _mediaFile;
  String? _mediaUrl;
  bool _loading = true;
  String? _error;
  bool get _en => widget.locale.languageCode == 'en';

  Future<String?> _url() async {
    final path = widget.item.storagePath;
    if (path != null && path.isNotEmpty) {
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
      final cacheable = widget.item.type == ChapterLearningContentType.pdf ||
          widget.item.type == ChapterLearningContentType.image;
      if (cacheable) {
        final local = await _localMediaFile();
        if (await local.exists() && await local.length() > 0) {
          _mediaFile = local;
          _bytes = await local.readAsBytes();
          if (widget.item.type == ChapterLearningContentType.pdf) {
            _pdf = PdfControllerPinch(document: PdfDocument.openData(_bytes!));
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
        if (widget.item.type == ChapterLearningContentType.pdf ||
            widget.item.type == ChapterLearningContentType.image) {
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
          if (widget.item.type == ChapterLearningContentType.pdf) {
            _pdf = PdfControllerPinch(document: PdfDocument.openData(_bytes!));
          }
        } else if (widget.item.type == ChapterLearningContentType.audio) {
          final safeUrl = url.replaceAll('&', '&amp;').replaceAll('"', '&quot;');
          _webView = WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..setBackgroundColor(const Color(0xFFF5F8F6))
            ..loadHtmlString('<html><body style="font-family:sans-serif;padding:24px"><audio controls autoplay style="width:100%" src="$safeUrl"></audio></body></html>');
        } else if (widget.item.type == ChapterLearningContentType.video) {
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
          }
        }
      }
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _pdf?.dispose();
    _video?.dispose();
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
    } else if (widget.item.type == ChapterLearningContentType.pdf) {
      body = _pdf == null ? Center(child: Text(_en ? 'PDF unavailable.' : 'PDF indisponible.')) : PdfViewPinch(controller: _pdf!);
    } else if (widget.item.type == ChapterLearningContentType.image && (_mediaFile != null || _mediaUrl != null)) {
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
    } else if ((widget.item.type == ChapterLearningContentType.video || widget.item.type == ChapterLearningContentType.audio) && _webView != null) {
      body = WebViewWidget(controller: _webView!);
    } else if (widget.item.type == ChapterLearningContentType.video && _video != null) {
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
                          Text('${questionIndex + 1}. ${question.promptFor(widget.locale.languageCode)}',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Text('${_en ? 'Your answer' : 'Ta réponse'}: $selectedText'),
                          Text('${_en ? 'Correct answer' : 'Bonne réponse'}: $correctText',
                            style: TextStyle(fontWeight: FontWeight.w700,
                              color: isCorrect ? Colors.green.shade800 : Colors.red.shade700)),
                          if (explanation != null && explanation.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text('${_en ? 'Explanation' : 'Explication'}: $explanation'),
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
                Text((i + 1).toString() + '. ' + questions[i].promptFor(widget.locale.languageCode), style: const TextStyle(fontWeight: FontWeight.w800)),
                for (var j = 0; j < questions[i].optionsFor(widget.locale.languageCode).length; j++)
                  RadioListTile<int>(
                    contentPadding: EdgeInsets.zero,
                    value: j,
                    groupValue: _answers[questions[i].id],
                    title: Text(questions[i].optionsFor(widget.locale.languageCode)[j]),
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
