import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/assignment_service.dart';
import '../../../models/assignment.dart';
import '../../../models/user_profile.dart';
import 'teacher_qcm_edit_page.dart';

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
  late final TabController _tabController;
  final Map<String, String> _classNames = <String, String>{};

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
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
      });
    } catch (_) {
      // Keep the QCM list available even if classroom labels cannot load.
    }
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _assignmentsFuture;
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
          .select('id,student_id,status,score,submitted_at,assignment_answers(is_correct)')
          .eq('assignment_id', assignment.id);
      var correct = 0;
      var incorrect = 0;
      var answered = 0;
      final participants = <Map<String, dynamic>>[];
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw);
        final answers = (row['assignment_answers'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item));
        var studentCorrect = 0;
        var studentIncorrect = 0;
        for (final answer in answers) {
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
        if (row['status'] == 'submitted' || row['status'] == 'corrected') {
          participants.add({...row, 'correct_count': studentCorrect, 'incorrect_count': studentIncorrect});
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
          text: _fr ? 'QCM disponibles' : 'Available quizzes',
        ),
      ],
    );
    final tabView = _buildAssignmentsTab();
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
