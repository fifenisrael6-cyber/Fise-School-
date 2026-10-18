import 'package:flutter/material.dart';

import '../../../core/services/assignment_service.dart';
import '../../../models/assignment.dart';
import '../../../models/user_profile.dart';

import 'assignment_detail_page.dart';

class AssignmentsPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const AssignmentsPage({
    super.key,
    required this.locale,
    required this.profile,
  });

  @override
  State<AssignmentsPage> createState() => _AssignmentsPageState();
}

class _AssignmentsPageState extends State<AssignmentsPage> {
  final AssignmentService _service = AssignmentService();

  late Future<List<Assignment>> _assignmentsFuture;

  bool get _isEnglish => widget.locale.languageCode == 'en';

  @override
  void initState() {
    super.initState();
    _loadAssignments();
  }

  void _loadAssignments() {
    _assignmentsFuture = _service.listStudentAssignments(
      studentId: widget.profile.id,
    );
  }

  Future<void> _refresh() async {
    setState(_loadAssignments);
    await _assignmentsFuture;
  }

  Future<void> _openAssignment(Assignment assignment) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AssignmentDetailPage(
          locale: widget.locale,
          profile: widget.profile,
          assignment: assignment,
        ),
      ),
    );

    if (mounted) {
      _loadAssignments();
      setState(() {});
    }
  }

  String _formatDueDate(DateTime? date) {
    if (date == null) {
      return _isEnglish ? 'No deadline' : 'Pas de date limite';
    }

    final local = date.toLocal();

    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();

    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/$year • $hour:$minute';
  }

  bool _isOverdue(Assignment assignment) {
    if (assignment.dueAt == null) {
      return false;
    }

    return assignment.dueAt!.isBefore(DateTime.now()) &&
        assignment.status != 'closed';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F6),
      appBar: AppBar(
        title: Text(
          _isEnglish ? 'Assignments' : 'Devoirs',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Assignment>>(
          future: _assignmentsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF166534)),
              );
            }

            if (snapshot.hasError) {
              return _buildError(snapshot.error);
            }

            final assignments = snapshot.data ?? const <Assignment>[];

            if (assignments.isEmpty) {
              return _buildEmptyState();
            }

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _buildHeader(assignments.length),
                const SizedBox(height: 18),
                ...assignments.map(
                  (assignment) => _buildAssignmentCard(assignment),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(int count) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF166534), Color(0xFF21844A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.assignment_rounded,
              color: Colors.white,
              size: 29,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEnglish ? 'Your assignments' : 'Vos devoirs',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isEnglish
                      ? '$count assignment${count > 1 ? 's' : ''}'
                      : '$count devoir${count > 1 ? 's' : ''}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentCard(Assignment assignment) {
    final title = assignment.titleFor(widget.locale);
    final instructions = assignment.instructionsFor(widget.locale);
    final overdue = _isOverdue(assignment);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openAssignment(assignment),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: overdue
                          ? const Color(0xFFFFE6E6)
                          : const Color(0xFFE4F2E9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      overdue
                          ? Icons.warning_amber_rounded
                          : Icons.assignment_outlined,
                      color: overdue
                          ? Colors.redAccent
                          : const Color(0xFF166534),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF166534),
                  ),
                ],
              ),
              if (instructions != null && instructions.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  instructions.trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildInfoChip(
                    icon: Icons.calendar_today_rounded,
                    text: _formatDueDate(assignment.dueAt),
                    danger: overdue,
                  ),
                  _buildInfoChip(
                    icon: Icons.grade_rounded,
                    text:
                        '${assignment.maxScore.toStringAsFixed(0)} ${_isEnglish ? 'pts' : 'pts'}',
                  ),
                  if (assignment.status == 'closed')
                    _buildStatusChip(
                      _isEnglish ? 'Closed' : 'Fermé',
                      Colors.grey,
                    ),
                  if (overdue)
                    _buildStatusChip(
                      _isEnglish ? 'Overdue' : 'En retard',
                      Colors.redAccent,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String text,
    bool danger = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: danger ? const Color(0xFFFFEEEE) : const Color(0xFFF3F6F4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: danger ? Colors.redAccent : const Color(0xFF166534),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: danger ? Colors.redAccent : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 100),
        const Icon(Icons.assignment_outlined, size: 72, color: Colors.grey),
        const SizedBox(height: 18),
        Text(
          _isEnglish ? 'No assignments yet' : 'Aucun devoir pour le moment',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          _isEnglish
              ? 'Published assignments for your class will appear here.'
              : 'Les devoirs publiés pour votre classe apparaîtront ici.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildError(Object? error) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 90),
        const Icon(
          Icons.error_outline_rounded,
          size: 64,
          color: Colors.redAccent,
        ),
        const SizedBox(height: 16),
        Text(
          _isEnglish
              ? 'Unable to load assignments.'
              : 'Impossible de charger les devoirs.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          error.toString(),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54, height: 1.4),
        ),
        const SizedBox(height: 20),
        Center(
          child: FilledButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(_isEnglish ? 'Retry' : 'Réessayer'),
          ),
        ),
      ],
    );
  }
}
