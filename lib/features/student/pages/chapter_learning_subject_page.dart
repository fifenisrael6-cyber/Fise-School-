import 'package:flutter/material.dart';

import '../../../core/services/chapter_learning_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';
import 'chapter_learning_detail_page.dart';
import 'subject_channel_page.dart';
import '../../../core/services/quota_service.dart';
import '../../premium/premium_gate.dart';

class ChapterLearningSubjectPage extends StatefulWidget {
  const ChapterLearningSubjectPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.subject,
  });

  final Locale locale;
  final UserProfile profile;
  final Subject subject;

  @override
  State<ChapterLearningSubjectPage> createState() =>
      _ChapterLearningSubjectPageState();
}

class _ChapterLearningSubjectPageState
    extends State<ChapterLearningSubjectPage> {
  final ChapterLearningService _learning = ChapterLearningService();
  late Future<_SubjectData> _future;
  late Future<ChapterLearningCounts> _countsFuture;

  bool get _en => widget.locale.languageCode == 'en';
  String _label(Curriculum value) => value.labelFor(widget.locale.languageCode);
  String _chapterLabel(CourseChapter value) =>
      value.labelFor(widget.locale.languageCode);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SubjectData> _load({bool forceRefresh = false}) async {
    final curricula = await _learning.listCurricula(
      widget.subject.id,
      profile: widget.profile,
      forceRefresh: forceRefresh,
    );
    // Load each curriculum's chapter list in parallel instead of blocking on
    // one network round-trip per folder.
    final chapterLists = await Future.wait(
      curricula.map((curriculum) => _learning.listChapters(
        curriculum.id,
        forceRefresh: forceRefresh,
      )),
    );
    final groups = <_CurriculumWithChapters>[];
    final allChapters = <CourseChapter>[];
    for (var index = 0; index < curricula.length; index++) {
      final chapters = chapterLists[index];
      groups.add(_CurriculumWithChapters(curricula[index], chapters));
      allChapters.addAll(chapters);
    }

    // Do not block the chapter list on a request per resource type for
    // every chapter. Large programmes can contain dozens of chapters; waiting
    // for all their counts here caused the whole page to appear stuck/empty.
    // Load statistics separately after the programme folders are visible.
    _countsFuture = _loadCounts(allChapters, forceRefresh: forceRefresh);

    return _SubjectData(
      groups: groups,
      chapters: allChapters,
      counts: const ChapterLearningCounts(),
    );
  }

  Future<ChapterLearningCounts> _loadCounts(
    List<CourseChapter> chapters, {
    bool forceRefresh = false,
  }) async {
    final chapterCounts = await Future.wait(
      chapters.map((chapter) => _learning.getCounts(
        chapter.id,
        forceRefresh: forceRefresh,
      )),
    );
    var lessons = 0;
    var videos = 0;
    var pdfs = 0;
    var images = 0;
    var audios = 0;
    var quizzes = 0;
    var exercises = 0;
    for (final counts in chapterCounts) {
      lessons += counts.lessons;
      videos += counts.videos;
      pdfs += counts.pdfs;
      images += counts.images;
      audios += counts.audios;
      quizzes += counts.quizzes;
      exercises += counts.exercises;
    }
    return ChapterLearningCounts(
      lessons: lessons,
      videos: videos,
      pdfs: pdfs,
      images: images,
      audios: audios,
      quizzes: quizzes,
      exercises: exercises,
    );
  }

  Future<void> _refresh() async {
    final refreshed = _load(forceRefresh: true);
    setState(() => _future = refreshed);
    await refreshed;
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF166534);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F6),
      appBar: AppBar(
        backgroundColor: green,
        foregroundColor: Colors.white,
        title: Text(widget.subject.labelFor(widget.locale.languageCode)),
      ),
      body: FutureBuilder<_SubjectData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return _error(snapshot.error.toString());

          final data = snapshot.data!;
          final groups = data.groups;
          final chapters = data.chapters;
          if (groups.isEmpty || chapters.isEmpty) return _empty();

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
                      const Icon(Icons.menu_book_rounded,
                          color: Colors.white, size: 34),
                      const SizedBox(height: 12),
                      Text(
                        widget.subject.labelFor(widget.locale.languageCode),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _en
                            ? '${chapters.length} chapters in the programme'
                            : '${chapters.length} chapitres au programme',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      FutureBuilder<ChapterLearningCounts>(
                        future: _countsFuture,
                        builder: (context, countSnapshot) {
                          final counts = countSnapshot.data ??
                              const ChapterLearningCounts();
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _stat(Icons.menu_book_outlined,
                                  _en ? 'Lessons' : 'Leçons', counts.lessons),
                              _stat(Icons.play_circle_outline,
                                  _en ? 'Videos' : 'Vidéos', counts.videos),
                              _stat(Icons.picture_as_pdf_outlined,
                                  'PDF', counts.pdfs),
                              _stat(Icons.image_outlined,
                                  _en ? 'Photos' : 'Photos', counts.images),
                              _stat(Icons.audiotrack_outlined,
                                  _en ? 'Audio' : 'Audio', counts.audios),
                              _stat(Icons.quiz_outlined,
                                  _en ? 'Smart QCM' : 'QCM intelligent',
                                  counts.quizzes),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _en
                            ? 'Statistics update automatically when content is published.'
                            : 'Les statistiques se mettent à jour dès qu’un contenu est publié.',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SubjectChannelPage(
                        locale: widget.locale,
                        profile: widget.profile,
                        subject: widget.subject,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.dynamic_feed_outlined),
                  label: Text(_en
                      ? 'Recent teacher posts'
                      : 'Cours et publications de l’enseignant'),
                ),
                const SizedBox(height: 22),
                Text(
                  _en ? 'ON THE PROGRAMME' : 'AU PROGRAMME',
                  style: const TextStyle(
                    color: green,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 10),
                for (final group in groups) ...[
                  if (groups.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 6),
                      child: Text(
                        _label(group.curriculum),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  for (var i = 0; i < group.chapters.length; i++)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE4F2E9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.folder_rounded,
                            color: green,
                            size: 30,
                          ),
                        ),
                        title: Text(
                          _chapterLabel(group.chapters[i]),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _en
                                  ? 'Chapter folder ${i + 1} • open resources'
                                  : 'Dossier du chapitre ${i + 1} • ouvrir les ressources',
                            ),
                            if (group.chapters[i].needsTitleVerification)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  _en
                                      ? 'Title mapping needs verification'
                                      : 'Titre à vérifier pour cette classe',
                                  style: const TextStyle(
                                    color: Color(0xFF9A6700),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final chapter = group.chapters[i];
                          final allowed = await PremiumGate.ensure(
                            context,
                            profile: widget.profile,
                            feature: QuotaFeature.lesson,
                            resourceId: chapter.id,
                            offlineFallback: true,
                          );
                          if (!allowed || !context.mounted) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChapterLearningDetailPage(
                                locale: widget.locale,
                                profile: widget.profile,
                                subject: widget.subject,
                                curriculum: group.curriculum,
                                chapter: chapter,
                                chapterNumber: i + 1,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () async {
                    final first = groups.first.chapters.first;
                    final allowed = await PremiumGate.ensure(
                      context,
                      profile: widget.profile,
                      feature: QuotaFeature.lesson,
                      resourceId: first.id,
                      offlineFallback: true,
                    );
                    if (!allowed || !context.mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChapterLearningDetailPage(
                          locale: widget.locale,
                          profile: widget.profile,
                          subject: widget.subject,
                          curriculum: groups.first.curriculum,
                          chapter: first,
                          chapterNumber: 1,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(_en ? 'Start the pack' : 'Commencer le pack'),
                  style: FilledButton.styleFrom(
                    backgroundColor: green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stat(IconData icon, String label, int count) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 17),
          const SizedBox(width: 6),
          Text('$count $label',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.menu_book_outlined,
                size: 52, color: Color(0xFF166534)),
            const SizedBox(height: 12),
            Text(
              _en
                  ? 'The programme for this subject has not been published yet.'
                  : 'Le programme de cette matière n’est pas encore publié.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SubjectChannelPage(
                    locale: widget.locale,
                    profile: widget.profile,
                    subject: widget.subject,
                  ),
                ),
              ),
              icon: const Icon(Icons.dynamic_feed_outlined),
              label: Text(_en ? 'Open teacher posts' : 'Voir les cours publiés'),
            ),
          ]),
        ),
      );

  Widget _error(String error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              _en ? 'Unable to load the programme.' : 'Impossible de charger le programme.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: _refresh,
                child: Text(_en ? 'Retry' : 'Réessayer')),
          ]),
        ),
      );
}

class _CurriculumWithChapters {
  const _CurriculumWithChapters(this.curriculum, this.chapters);
  final Curriculum curriculum;
  final List<CourseChapter> chapters;
}

class _SubjectData {
  const _SubjectData({
    required this.groups,
    required this.chapters,
    required this.counts,
  });
  final List<_CurriculumWithChapters> groups;
  final List<CourseChapter> chapters;
  final ChapterLearningCounts counts;
}
