import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/assignment_service.dart';
import '../../../models/assignment.dart';
import '../../../models/user_profile.dart';

/// Teacher QCM workspace. Existing course-linked assignments remain available.
class TeacherQcmHubPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final bool embedded;

  const TeacherQcmHubPage({
    super.key,
    required this.locale,
    required this.profile,
    this.embedded = false,
  });

  @override
  State<TeacherQcmHubPage> createState() => _TeacherQcmHubPageState();
}

class _TeacherQcmHubPageState extends State<TeacherQcmHubPage> with SingleTickerProviderStateMixin {
  final AssignmentService _service = AssignmentService();
  late Future<List<Assignment>> _assignmentsFuture;
  late Future<List<Map<String, dynamic>>> _aiQuizzesFuture;
  late final TabController _tabController;
  final Map<String, String> _classNames = <String, String>{};
  bool _retryingAi = false;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _reload();
    _loadClassNames();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _reload() {
    _assignmentsFuture = _service.listTeacherAssignments(
      teacherId: widget.profile.id,
    );
    _aiQuizzesFuture = _loadAiQuizzes();
  }

  Future<List<Map<String, dynamic>>> _loadAiQuizzes() async {
    final client = Supabase.instance.client;
    final courseRows = await client
        .from('courses')
        .select('chapter_id,class_id')
        .eq('teacher_id', widget.profile.id)
        .eq('status', 'published');
    final classIdsByChapter = <String, Set<String>>{};
    final chapterIds = <String>{};
    for (final raw in courseRows) {
      final row = Map<String, dynamic>.from(raw);
      final chapterId = row['chapter_id']?.toString() ?? '';
      if (chapterId.isEmpty) continue;
      chapterIds.add(chapterId);
      final classId = row['class_id']?.toString() ?? '';
      if (classId.isNotEmpty) {
        classIdsByChapter.putIfAbsent(chapterId, () => <String>{}).add(classId);
      }
    }
    if (chapterIds.isEmpty) return const <Map<String, dynamic>>[];

    final ids = chapterIds.toList(growable: false);
    final results = await Future.wait<dynamic>([
      client
          .from('chapter_quizzes')
          .select('id,chapter_id,title_fr,title_en,description_fr,description_en,position')
          .inFilter('chapter_id', ids)
          .eq('is_published', true)
          .isFilter('created_by', null)
          .order('position'),
      client
          .from('course_chapters')
          .select('id,title_fr,title_en')
          .inFilter('id', ids),
    ]);
    final chapters = <String, Map<String, dynamic>>{
      for (final raw in results[1] as List)
        (raw['id'] ?? '').toString(): Map<String, dynamic>.from(raw),
    };
    final quizzes = <Map<String, dynamic>>[];
    for (final raw in results[0] as List) {
      final quiz = Map<String, dynamic>.from(raw);
      final chapterId = quiz['chapter_id']?.toString() ?? '';
      final chapter = chapters[chapterId] ?? const <String, dynamic>{};
      final classLabels = (classIdsByChapter[chapterId] ?? <String>{})
          .map((id) => _classNames[id])
          .whereType<String>()
          .where((name) => name.trim().isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      quizzes.add({
        ...quiz,
        'chapter_title_fr': chapter['title_fr']?.toString() ?? '',
        'chapter_title_en': chapter['title_en']?.toString() ?? '',
        'class_labels': classLabels,
      });
    }
    return quizzes;
  }

  Future<void> _loadClassNames() async {
    try {
      final rows = await Supabase.instance.client
          .from('school_classes')
          .select('id, display_name')
          .eq('is_active', true);
      if (!mounted) return;
      setState(() {
        _classNames
          ..clear()
          ..addEntries(
            rows.map((row) => MapEntry(
                  row['id'].toString(),
                  (row['display_name'] ?? '').toString(),
                )),
          );
        _aiQuizzesFuture = _loadAiQuizzes();
      });
    } catch (_) {
      // Keep the QCM list available even if classroom labels cannot load.
    }
  }

  Future<void> _retryAiGeneration() async {
    if (_retryingAi) return;
    setState(() => _retryingAi = true);
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('courses')
          .select('chapter_id')
          .eq('teacher_id', widget.profile.id)
          .eq('status', 'published');
      final chapterIds = (rows as List)
          .map((row) => row['chapter_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      if (chapterIds.isEmpty) {
        throw StateError(_fr
            ? 'Aucun cours publié avec un chapitre n’a été trouvé.'
            : 'No published course with a chapter was found.');
      }
      final published = await client
          .from('chapter_quizzes')
          .select('chapter_id')
          .inFilter('chapter_id', chapterIds.toList())
          .eq('is_published', true)
          .isFilter('created_by', null);
      final existingIds = (published as List)
          .map((row) => row['chapter_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final missingIds = chapterIds.difference(existingIds);
      if (missingIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_fr
                ? 'Chaque chapitre publié possède déjà un QCM IA.'
                : 'Every published chapter already has an AI QCM.'),
          ));
        }
        return;
      }

      var generated = 0;
      final errors = <String>[];
      for (final chapterId in missingIds) {
        try {
          final response = await client.functions.invoke(
            'chapter-quiz',
            body: {'chapter_id': chapterId},
          );
          final data = response.data;
          if (data is Map && data['error'] != null) {
            errors.add(data['error'].toString());
          } else {
            generated++;
          }
        } catch (error) {
          errors.add(error.toString());
        }
      }
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(errors.isEmpty
            ? (_fr
                ? 'Génération IA relancée pour $generated chapitre(s).'
                : 'AI generation retried for $generated chapter(s).')
            : (_fr
                ? 'Génération terminée : $generated réussite(s), ${errors.length} erreur(s).'
                : 'Generation finished: $generated succeeded, ${errors.length} error(s).')),
        duration: const Duration(seconds: 5),
      ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_fr ? 'Relance impossible' : 'Retry failed'}: $error'),
        ));
      }
    } finally {
      if (mounted) setState(() => _retryingAi = false);
    }
  }

  Future<void> _refresh() async {
    setState(_reload);
    await Future.wait<dynamic>([_assignmentsFuture, _aiQuizzesFuture]);
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'published':
        return _fr ? 'Publié' : 'Published';
      case 'closed':
        return _fr ? 'Fermé' : 'Closed';
      default:
        return _fr ? 'Brouillon' : 'Draft';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'published':
        return const Color(0xFF166534);
      case 'closed':
        return Colors.grey;
      default:
        return Colors.orange.shade800;
    }
  }

  Future<void> _deleteAssignment(Assignment assignment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_fr ? 'Supprimer ce QCM ?' : 'Delete this quiz?'),
        content: Text(_fr
          ? 'Le QCM sera supprimé même s’il a déjà été diffusé ou réalisé. Les questions, réponses et résultats des élèves associés seront également supprimés. Cette action est irréversible.'
          : 'This quiz will be deleted even if it has already been published or completed. Its questions, student answers, and results will also be deleted. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_fr ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_fr ? 'Supprimer' : 'Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteAssignment(assignment.id);
      if (mounted) {
        setState(_reload);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_fr ? 'QCM supprimé.' : 'Quiz deleted.')),
        );
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_fr ? 'Suppression impossible' : 'Delete failed'}: $error')),
      );
    }
  }

  Future<void> _showResults(Assignment assignment) async {
    try {
      final rows = await Supabase.instance.client
          .from('assignment_submissions')
          .select('id,student_id,status,score,submitted_at,assignment_answers(is_correct),assignment_private_grades(score,status,details)')
          .eq('assignment_id', assignment.id);
      var correct = 0;
      var incorrect = 0;
      var answered = 0;
      final participants = <Map<String, dynamic>>[];
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw);
        final answers = (row['assignment_answers'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
        final rawPrivateGrades = row['assignment_private_grades'];
        final privateGrade = rawPrivateGrades is List && rawPrivateGrades.isNotEmpty
            ? Map<String, dynamic>.from(rawPrivateGrades.first as Map)
            : rawPrivateGrades is Map
                ? Map<String, dynamic>.from(rawPrivateGrades)
                : <String, dynamic>{};
        final privateDetails = (privateGrade['details'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item));
        var studentCorrect = 0;
        var studentIncorrect = 0;
        var gradedAnswers = 0;
        for (final answer in answers) {
          if (answer['is_correct'] == true) {
            correct++;
            studentCorrect++;
            answered++;
            gradedAnswers++;
          } else if (answer['is_correct'] == false) {
            incorrect++;
            studentIncorrect++;
            answered++;
            gradedAnswers++;
          }
        }
        // AI marks remain private from students until publication, but the
        // assigned teacher can review them from this results panel beforehand.
        if (gradedAnswers == 0 && privateGrade['status'] == 'graded') {
          for (final answer in privateDetails) {
            if (answer['is_correct'] == true) {
              correct++;
              studentCorrect++;
              answered++;
            } else if (answer['is_correct'] == false) {
              incorrect++;
              studentIncorrect++;
              answered++;
            }
          }
        }
        if (row['status'] == 'submitted' || row['status'] == 'corrected') {
          participants.add({
            ...row,
            'score': row['score'] ?? (privateGrade['status'] == 'graded' ? privateGrade['score'] : null),
            'correct_count': studentCorrect,
            'incorrect_count': studentIncorrect,
            'ai_correction_status': privateGrade['status'],
          });
        }
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_fr ? 'Résultats du QCM' : 'Quiz results'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('${_fr ? 'Participants ayant remis' : 'Submitted participants'} : ${participants.length}'),
                Text('${_fr ? 'Bonnes réponses' : 'Correct answers'} : $correct'),
                Text('${_fr ? 'Mauvaises réponses' : 'Incorrect answers'} : $incorrect'),
                if (answered == 0) Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_fr ? 'Aucune réponse corrigée disponible pour le moment.' : 'No graded answers available yet.'),
                ),
                const Divider(),
                for (final participant in participants)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${_fr ? 'Élève' : 'Student'} · ${participant['student_id']}'),
                    subtitle: Text('${_fr ? 'Bonnes' : 'Correct'} : ${participant['correct_count']} · ${_fr ? 'Mauvaises' : 'Incorrect'} : ${participant['incorrect_count']}'),
                    trailing: participant['score'] == null ? null : Text('${participant['score']} / ${assignment.maxScore}'),
                  ),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: Text(_fr ? 'Fermer' : 'Close'))],
        ),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_fr ? 'Impossible de charger les résultats' : 'Could not load results'}: $error')),
      );
    }
  }

  String _deadline(DateTime? date) {
    if (date == null) return _fr ? 'Sans date limite' : 'No deadline';
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final tabs = TabBar(
      controller: _tabController,
      tabs: [
        Tab(
          icon: const Icon(Icons.auto_awesome_rounded),
          text: _fr ? 'QCM générés par l’IA' : 'AI-generated QCMs',
        ),
        Tab(
          icon: const Icon(Icons.assignment_outlined),
          text: _fr ? 'Devoirs et évaluations' : 'Assignments and assessments',
        ),
      ],
    );
    final tabView = TabBarView(
      controller: _tabController,
      children: [
        _buildAiQuizzesTab(),
        _buildAssignmentsTab(),
      ],
    );
    if (widget.embedded) {
      return Column(
        children: [
          Material(color: Theme.of(context).colorScheme.surface, child: tabs),
          Expanded(child: tabView),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'Espace QCM' : 'Quiz workspace'),
        bottom: tabs,
      ),
      body: tabView,
    );
  }

  Widget _buildAiQuizzesTab() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _aiQuizzesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 180),
                Center(child: CircularProgressIndicator()),
              ],
            );
          }
          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.cloud_off_rounded, size: 42),
                const SizedBox(height: 12),
                Text(
                  _fr
                      ? 'Impossible de charger les QCM IA. Vérifiez la connexion puis réessayez.'
                      : 'Could not load AI QCMs. Check the connection and try again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Center(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(_reload),
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(_fr ? 'Réessayer' : 'Retry'),
                  ),
                ),
              ],
            );
          }
          final quizzes = snapshot.data ?? const <Map<String, dynamic>>[];
          if (quizzes.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 60),
                const Icon(Icons.auto_awesome_rounded, size: 54),
                const SizedBox(height: 12),
                Text(
                  _fr
                      ? 'Aucun QCM IA pour le moment. Publiez un cours dans un chapitre pour déclencher sa génération automatique, ou relancez la génération pour vos cours déjà publiés.'
                      : 'No AI QCM yet. Publish course content in a chapter to trigger automatic generation, or retry generation for courses already published.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                Center(
                  child: FilledButton.icon(
                    onPressed: _retryingAi ? null : _retryAiGeneration,
                    icon: _retryingAi
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(_retryingAi
                        ? (_fr ? 'Génération en cours…' : 'Generating…')
                        : (_fr ? 'Relancer la génération IA' : 'Retry AI generation')),
                  ),
                ),
              ],
            );
          }
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: quizzes.length,
            itemBuilder: (context, index) {
              final quiz = quizzes[index];
              final titleFr = quiz['title_fr']?.toString().trim() ?? '';
              final titleEn = quiz['title_en']?.toString().trim() ?? '';
              final chapterFr = quiz['chapter_title_fr']?.toString().trim() ?? '';
              final chapterEn = quiz['chapter_title_en']?.toString().trim() ?? '';
              final title = _fr
                  ? (titleFr.isNotEmpty ? titleFr : titleEn)
                  : (titleEn.isNotEmpty ? titleEn : titleFr);
              final chapter = _fr
                  ? (chapterFr.isNotEmpty ? chapterFr : chapterEn)
                  : (chapterEn.isNotEmpty ? chapterEn : chapterFr);
              final labels = (quiz['class_labels'] as List? ?? const [])
                  .map((value) => value.toString())
                  .where((value) => value.trim().isNotEmpty)
                  .join(', ');
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.auto_awesome_rounded),
                  ),
                  title: Text(
                    title.isEmpty ? (_fr ? 'QCM IA' : 'AI QCM') : title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text([
                      if (chapter.isNotEmpty) '${_fr ? 'Chapitre' : 'Chapter'} : $chapter',
                      if (labels.isNotEmpty) '${_fr ? 'Salles' : 'Classes'} : $labels',
                      _fr ? 'Généré automatiquement par l’IA' : 'Automatically generated by AI',
                    ].join('\n')),
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.verified_rounded, color: Color(0xFF166534)),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildAssignmentsTab() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Assignment>>(
        future: _assignmentsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: 180),
                Center(child: CircularProgressIndicator()),
              ],
            );
          }
          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.cloud_off_rounded, size: 42),
                const SizedBox(height: 12),
                Text(
                  _fr
                      ? 'Impossible de charger vos QCM. Vérifiez la connexion puis réessayez.'
                      : 'Could not load your quizzes. Check the connection and try again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Center(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(_reload),
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(_fr ? 'Réessayer' : 'Retry'),
                  ),
                ),
              ],
            );
          }

          final assignments = snapshot.data ?? const <Assignment>[];
          if (assignments.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 60),
                const Icon(Icons.assignment_outlined, size: 54),
                const SizedBox(height: 12),
                Text(
                  _fr
                      ? 'Aucun QCM disponible. Les QCM sont générés automatiquement par l’IA à partir des cours publiés.'
                      : 'No quizzes available. AI quizzes are generated automatically from published lessons.',
                  textAlign: TextAlign.center,
                ),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: assignments.length,
            itemBuilder: (context, index) {
              final assignment = assignments[index];
              final title = assignment.titleFor(widget.locale).trim();
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.assignment_rounded),
                  ),
                  title: Text(
                    title.isEmpty
                        ? (_fr ? 'QCM sans titre' : 'Untitled quiz')
                        : title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${_fr ? 'Salle' : 'Class'}: ${_classNames[assignment.classId] ?? (_fr ? 'Salle non disponible' : 'Class unavailable')}\n${_deadline(assignment.dueAt)}',
                    ),
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    tooltip: _fr ? 'Gérer le QCM' : 'Manage quiz',
                    onSelected: (action) {
                      if (action == 'results') _showResults(assignment);
                      if (action == 'delete') _deleteAssignment(assignment);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'results', child: Text(_fr ? 'Voir les résultats' : 'View results')),
                      PopupMenuItem(value: 'delete', child: Text(_fr ? 'Supprimer' : 'Delete')),
                    ],
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 92),
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                      decoration: BoxDecoration(
                        color: _statusColor(assignment.status).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _statusLabel(assignment.status),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _statusColor(assignment.status),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
