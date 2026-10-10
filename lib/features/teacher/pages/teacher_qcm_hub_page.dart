import 'package:flutter/material.dart';

import '../../../core/services/assignment_service.dart';
import '../../../models/assignment.dart';
import '../../../models/user_profile.dart';
import 'create_assignment_page.dart';
import 'qcm_builder_page.dart';

/// Teacher QCM workspace. Existing course-linked assignments remain available.
class TeacherQcmHubPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const TeacherQcmHubPage({
    super.key,
    required this.locale,
    required this.profile,
  });

  @override
  State<TeacherQcmHubPage> createState() => _TeacherQcmHubPageState();
}

class _TeacherQcmHubPageState extends State<TeacherQcmHubPage> with SingleTickerProviderStateMixin {
  final AssignmentService _service = AssignmentService();
  late Future<List<Assignment>> _assignmentsFuture;
  late final TabController _tabController;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _reload();
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

  Future<void> _refresh() async {
    setState(_reload);
    await _assignmentsFuture;
  }

  Future<void> _openCreator({required bool linkedToCourse}) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => linkedToCourse
            ? CreateAssignmentPage(
                locale: widget.locale,
                profile: widget.profile,
              )
            : QcmBuilderPage(
                locale: widget.locale,
                profile: widget.profile,
              ),
      ),
    );
    if (!mounted) return;
    if (created == true) {
      setState(_reload);
      _tabController.animateTo(1);
    }
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

  String _deadline(DateTime? date) {
    if (date == null) return _fr ? 'Sans date limite' : 'No deadline';
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(_fr ? 'Espace QCM' : 'Quiz workspace'),
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                icon: const Icon(Icons.add_task_rounded),
                text: _fr ? 'Créer / envoyer' : 'Create / send',
              ),
              Tab(
                icon: const Icon(Icons.assignment_rounded),
                text: _fr ? 'Mes QCM' : 'My quizzes',
              ),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildCreateTab(),
            _buildAssignmentsTab(),
          ],
        ),
    );
  }

  Widget _buildCreateTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.quiz_rounded,
                  size: 34,
                  color: Color(0xFF166534),
                ),
                const SizedBox(height: 10),
                Text(
                  _fr ? 'Créer et envoyer un QCM' : 'Create and send a quiz',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _fr
                      ? 'Choisissez les salles compatibles avec votre profil, la matière, les questions et les bonnes réponses, puis publiez le QCM pour les élèves inscrits dans ces salles.'
                      : 'Choose classrooms compatible with your profile, subject, questions and correct answers, then publish the quiz for students enrolled in those classrooms.',
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _openCreator(linkedToCourse: false),
                    icon: const Icon(Icons.send_rounded),
                    label: Text(_fr ? 'Nouveau QCM' : 'New quiz'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.menu_book_rounded,
                  size: 32,
                  color: Color(0xFF166534),
                ),
                const SizedBox(height: 10),
                Text(
                  _fr ? 'Devoir lié à un cours' : 'Course-linked assignment',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _fr
                      ? 'Conservez aussi le parcours existant pour créer un devoir à partir d’un cours et d’une leçon.'
                      : 'Keep using the existing flow to create an assignment from a course and lesson.',
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () => _openCreator(linkedToCourse: true),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(_fr ? 'Créer un devoir lié' : 'Create linked assignment'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAssignmentsTab() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Assignment>>(
        future: _assignmentsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const ListView(
              physics: AlwaysScrollableScrollPhysics(),
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
                      ? 'Aucun QCM pour le moment. Créez un QCM dans le premier onglet.'
                      : 'No quizzes yet. Create one in the first tab.',
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
                      '${_fr ? 'Salle' : 'Class'}: ${assignment.classId}\n${_deadline(assignment.dueAt)}',
                    ),
                  ),
                  isThreeLine: true,
                  trailing: Container(
                    constraints: const BoxConstraints(maxWidth: 92),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
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
              );
            },
          );
        },
      ),
    );
  }
}
