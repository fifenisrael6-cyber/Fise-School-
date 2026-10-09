import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/offline/course_offline_service.dart';
import '../../../core/offline/offline_resource_viewer.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../core/widgets/rich_lesson_text.dart';
import '../../ai/pages/ai_page.dart';
import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';

class LessonPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final Course course;
  final Lesson lesson;

  const LessonPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.course,
    required this.lesson,
  });

  @override
  State<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends State<LessonPage> {
  final ProgressService _progressService = ProgressService();
  final ResourceService _resourceService = ResourceService();
  final CourseOfflineService _offline = CourseOfflineService();

  LessonProgress? _progress;
  List<CourseResource> _resources = const [];

  String? _subjectName;
  bool _openingAi = false;

  bool _loading = true;
  bool _loadingResource = false;
  bool _completing = false;
  String? _errorMessage;

  bool get isEnglish => widget.locale.languageCode == 'en';

  String get title {
    final value = isEnglish ? widget.lesson.titleEn : widget.lesson.titleFr;

    if (value.trim().isNotEmpty) {
      return value.trim();
    }

    return isEnglish ? 'Lesson' : 'Leçon';
  }

  String? get objectives {
    final value = isEnglish
        ? widget.lesson.objectivesEn
        : widget.lesson.objectivesFr;

    return _clean(value);
  }

  String? get content {
    final value = isEnglish ? widget.lesson.contentEn : widget.lesson.contentFr;

    return _clean(value);
  }

  String? get examples {
    final value = isEnglish
        ? widget.lesson.examplesEn
        : widget.lesson.examplesFr;

    return _clean(value);
  }

  String? get summary {
    final value = isEnglish ? widget.lesson.summaryEn : widget.lesson.summaryFr;

    return _clean(value);
  }

  int get progressPercent {
    final value = _progress?.progressPercent ?? 0;
    return value.clamp(0, 100);
  }

  bool get isCompleted => progressPercent >= 100;

  @override
  void initState() {
    super.initState();
    _loadLessonData();
  }

  String? _clean(String? value) {
    if (value == null) {
      return null;
    }

    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      return null;
    }

    return trimmed;
  }

  Future<void> _loadLessonData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _progressService.get(widget.profile.id, widget.lesson.id),
        _resourceService.listForLesson(widget.lesson.id),
      ]);

      final progress = results[0] as LessonProgress?;
      final resources = results[1] as List<CourseResource>;

      LessonProgress? openedProgress = progress;

      if (progress == null || progress.status != 'completed') {
        openedProgress = await _progressService.open(
          studentId: widget.profile.id,
          lessonId: widget.lesson.id,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _progress = openedProgress;
        _resources = resources;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage = error.toString();
      });
    }
  }

  /// Nom de la matière (chargé seulement quand l'élève ouvre l'IA).
  Future<String?> _loadSubjectName() async {
    if (_subjectName != null) {
      return _subjectName;
    }
    try {
      final row = await Supabase.instance.client
          .from('subjects')
          .select('name_fr,name_en')
          .eq('id', widget.course.subjectId)
          .maybeSingle();
      if (row != null) {
        final value = (isEnglish ? row['name_en'] : row['name_fr']) as String?;
        if (value != null && value.trim().isNotEmpty) {
          _subjectName = value.trim();
        }
      }
    } catch (_) {
      // L'IA reste utilisable sans le nom de la matière.
    }
    return _subjectName;
  }

  /// Texte de la leçon transmis à l'IA (borné, pour une connexion faible).
  String _lessonTextForAi() {
    final parts = <String>[
      if (objectives case final value?) '${isEnglish ? 'Objectives' : 'Objectifs'} : $value',
      if (content case final value?) value,
      if (examples case final value?) '${isEnglish ? 'Examples' : 'Exemples'} : $value',
      if (summary case final value?) '${isEnglish ? 'Summary' : 'Résumé'} : $value',
    ];
    final joined = parts.join('\n\n');
    return joined.length <= 6000 ? joined : joined.substring(0, 6000);
  }

  Future<void> _openAi([String? prompt]) async {
    if (_openingAi) {
      return;
    }
    setState(() => _openingAi = true);
    final subject = await _loadSubjectName();
    if (!mounted) {
      return;
    }
    setState(() => _openingAi = false);

    final courseTitle = widget.course.labelFor(isEnglish ? 'en' : 'fr').trim();
    final lessonContext = AiLessonContext(
      className: widget.profile.className,
      series: widget.profile.track,
      subject: subject,
      chapter: courseTitle.isEmpty ? null : courseTitle,
      lessonTitle: title,
      lessonContent: _lessonTextForAi(),
    );

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiPage(
          locale: widget.locale,
          profile: widget.profile,
          lessonContext: lessonContext,
          initialPrompt: prompt,
        ),
      ),
    );
  }

  Widget _buildAiCard() {
    final prompts = isEnglish
        ? const {
            'Explain this part': 'Explain this part of the lesson to me, step by step.',
            'I did not understand': 'I did not understand this lesson. Explain it more simply, with an example.',
            'Lesson quiz': 'Make me a 5-question multiple choice quiz on this lesson, with answers at the end.',
          }
        : const {
            'Explique cette partie': 'Explique-moi cette partie de la leçon, étape par étape.',
            'Je n’ai pas compris': 'Je n’ai pas compris cette leçon. Explique-la plus simplement, avec un exemple.',
            'QCM sur la leçon': 'Fais-moi un QCM de 5 questions sur cette leçon, avec la correction à la fin.',
          };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFF166534)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isEnglish ? 'Need help with this lesson?' : 'Besoin d’aide sur cette leçon ?',
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF166534),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: prompts.entries
                .map(
                  (entry) => ActionChip(
                    label: Text(entry.key),
                    onPressed: _openingAi ? null : () => _openAi(entry.value),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openingAi ? null : () => _openAi(),
              icon: _openingAi
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chat_bubble_outline_rounded),
              label: Text(isEnglish ? 'Ask the AI assistant' : 'Demander à l’assistant IA'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF166534),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _completeLesson() async {
    if (_completing || isCompleted) {
      return;
    }

    setState(() {
      _completing = true;
    });

    try {
      final progress = await _progressService.complete(
        studentId: widget.profile.id,
        lessonId: widget.lesson.id,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _progress = progress;
        _completing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEnglish
                ? 'Lesson completed successfully.'
                : 'Leçon terminée avec succès.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _completing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEnglish
                ? 'Unable to complete the lesson.'
                : 'Impossible de terminer la leçon.',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _openResource(CourseResource resource) async {
    if (_loadingResource) {
      return;
    }

    setState(() {
      _loadingResource = true;
    });

    try {
      final local = await _offline.getLocal(widget.profile.id, resource.id);
      if (local != null && local.status == 'done') {
        await _offline.markOpened(widget.profile.id, resource.id);
        if (!mounted) {
          return;
        }
        await Navigator.push(context, MaterialPageRoute(builder: (_) => OfflineResourceViewer(
          locale: widget.locale, userId: widget.profile.id, resource: resource, localPath: local.localPath,
        )));
      } else {
        if (resource.storagePath.isEmpty) {
          throw Exception();
        }
        final url = await _resourceService.createSignedUrl(resource.storagePath);
        // Keep the existing online fallback only when no local copy exists.
        final uri = Uri.parse(url);
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          throw Exception();
        }
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEnglish
                ? 'Unable to open this resource.'
                : 'Impossible d’ouvrir cette ressource.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingResource = false;
        });
      }
    }
  }

  IconData _resourceIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'image':
        return Icons.image_rounded;
      case 'video':
        return Icons.play_circle_fill_rounded;
      case 'audio':
        return Icons.headphones_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _resourceColor(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return const Color(0xFFDC2626);
      case 'image':
        return const Color(0xFF2563EB);
      case 'video':
        return const Color(0xFF7C3AED);
      case 'audio':
        return const Color(0xFF0F766E);
      default:
        return const Color(0xFF166534);
    }
  }

  String _resourceTitle(CourseResource resource) {
    final value = isEnglish ? resource.titleEn : resource.titleFr;

    if (value.trim().isNotEmpty) {
      return value.trim();
    }

    return resource.fileName;
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF166534), Color(0xFF22C55E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              isEnglish
                  ? 'LESSON ${widget.lesson.position}'
                  : 'LEÇON ${widget.lesson.position}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          if (widget.lesson.estimatedMinutes != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 18,
                  color: Colors.white70,
                ),
                const SizedBox(width: 7),
                Text(
                  '${widget.lesson.estimatedMinutes} min',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    final percent = progressPercent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFDF4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up_rounded, color: Color(0xFF166534)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isEnglish ? 'Your progress' : 'Ta progression',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF166534),
                  ),
                ),
              ),
              Text(
                '$percent%',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF166534),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 9,
              backgroundColor: const Color(0xFFD1FAE5),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF16A34A),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isCompleted
                ? (isEnglish
                      ? 'This lesson is completed.'
                      : 'Cette leçon est terminée.')
                : (isEnglish
                      ? 'Read the lesson carefully, then mark it as completed.'
                      : 'Lis attentivement la leçon, puis marque-la comme terminée.'),
            style: const TextStyle(color: Colors.black54, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildContentSection({
    required String title,
    required String content,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF166534)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          RichLessonText(text: content),
        ],
      ),
    );
  }

  Widget _buildResourcesSection() {
    if (_resources.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.attach_file_rounded, color: Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isEnglish
                    ? 'No additional resources for this lesson.'
                    : 'Aucune ressource supplémentaire pour cette leçon.',
                style: const TextStyle(color: Colors.grey, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _resources.map((resource) {
        final color = _resourceColor(resource.resourceType);

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(_resourceIcon(resource.resourceType), color: color),
            ),
            title: Text(
              _resourceTitle(resource),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                resource.fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            trailing: IconButton(
              tooltip: isEnglish ? 'Open' : 'Ouvrir',
              onPressed: _loadingResource
                  ? null
                  : () => _openResource(resource),
              icon: const Icon(Icons.open_in_new_rounded),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF166534)),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 54,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 16),
              Text(
                isEnglish
                    ? 'Unable to load this lesson.'
                    : 'Impossible de charger cette leçon.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadLessonData,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(isEnglish ? 'Retry' : 'Réessayer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF166534),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF166534),
      onRefresh: _loadLessonData,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildHeader(),
          const SizedBox(height: 18),
          _buildProgressCard(),
          const SizedBox(height: 22),
          if (objectives case final value?)
            _buildContentSection(
              title: isEnglish ? 'Objectives' : 'Objectifs',
              content: value,
              icon: Icons.flag_rounded,
            ),
          if (content case final value?)
            _buildContentSection(
              title: isEnglish ? 'Course content' : 'Contenu du cours',
              content: value,
              icon: Icons.menu_book_rounded,
            ),
          if (examples case final value?)
            _buildContentSection(
              title: isEnglish ? 'Examples' : 'Exemples',
              content: value,
              icon: Icons.lightbulb_rounded,
            ),
          if (summary case final value?)
            _buildContentSection(
              title: isEnglish ? 'Summary' : 'Résumé',
              content: value,
              icon: Icons.summarize_rounded,
            ),
          _buildAiCard(),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  isEnglish ? 'RESOURCES' : 'RESSOURCES',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
            ],
          ),
          const SizedBox(height: 16),
          _buildResourcesSection(),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _completing || isCompleted ? null : _completeLesson,
              icon: _completing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      isCompleted
                          ? Icons.check_circle_rounded
                          : Icons.check_rounded,
                    ),
              label: Text(
                isCompleted
                    ? (isEnglish ? 'Lesson completed' : 'Leçon terminée')
                    : (isEnglish
                          ? 'Mark as completed'
                          : 'Marquer comme terminée'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF166534),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFDCFCE7),
                disabledForegroundColor: const Color(0xFF166534),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF064D2B),
        foregroundColor: Colors.white,
        title: Text(
          isEnglish ? 'Lesson' : 'Leçon',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }
}
