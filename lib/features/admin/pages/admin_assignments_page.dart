import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminAssignmentsPage extends StatefulWidget {
  final Locale locale;

  const AdminAssignmentsPage({super.key, required this.locale});

  @override
  State<AdminAssignmentsPage> createState() => _AdminAssignmentsPageState();
}

class _AdminAssignmentsPageState extends State<AdminAssignmentsPage> {
  final SupabaseClient _client = Supabase.instance.client;

  late Future<List<Map<String, dynamic>>> _assignmentsFuture;

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _assignmentsFuture = _fetchAssignments();
  }

  Future<List<Map<String, dynamic>>> _fetchAssignments() async {
    final response = await _client
        .from('assignments')
        .select(
          'id,course_id,lesson_id,teacher_id,class_id,title_fr,title_en,'
          'instructions_fr,instructions_en,due_at,status,max_score,created_at',
        )
        .order('created_at', ascending: false);

    return (response as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _assignmentsFuture = _fetchAssignments();
    });

    await _assignmentsFuture;
  }

  String _title(Map<String, dynamic> assignment) {
    final titleFr = assignment['title_fr']?.toString().trim() ?? '';
    final titleEn = assignment['title_en']?.toString().trim() ?? '';

    if (_isFrench) {
      return titleFr.isNotEmpty ? titleFr : titleEn;
    }

    return titleEn.isNotEmpty ? titleEn : titleFr;
  }

  String _instructions(Map<String, dynamic> assignment) {
    final fr = assignment['instructions_fr']?.toString().trim() ?? '';
    final en = assignment['instructions_en']?.toString().trim() ?? '';

    if (_isFrench) {
      return fr.isNotEmpty ? fr : en;
    }

    return en.isNotEmpty ? en : fr;
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'published':
        return _isFrench ? 'Publié' : 'Published';
      case 'draft':
        return _isFrench ? 'Brouillon' : 'Draft';
      case 'closed':
        return _isFrench ? 'Fermé' : 'Closed';
      case 'archived':
        return _isFrench ? 'Archivé' : 'Archived';
      default:
        return status?.isNotEmpty == true
            ? status!
            : (_isFrench ? 'Inconnu' : 'Unknown');
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'published':
        return Colors.green;
      case 'closed':
        return Colors.redAccent;
      case 'archived':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  String _formatDueDate(String? value) {
    if (value == null || value.isEmpty) {
      return _isFrench ? 'Aucune échéance' : 'No deadline';
    }

    final date = DateTime.tryParse(value);

    if (date == null) {
      return value;
    }

    final localDate = date.toLocal();

    final day = localDate.day.toString().padLeft(2, '0');
    final month = localDate.month.toString().padLeft(2, '0');
    final year = localDate.year.toString();
    final hour = localDate.hour.toString().padLeft(2, '0');
    final minute = localDate.minute.toString().padLeft(2, '0');

    return '$day/$month/$year $hour:$minute';
  }

  void _showAssignmentDetails(Map<String, dynamic> assignment) {
    final title = _title(assignment);
    final instructions = _instructions(assignment);
    final status = assignment['status']?.toString();
    final maxScore = assignment['max_score']?.toString() ?? '';
    final dueAt = assignment['due_at']?.toString();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isNotEmpty
                      ? title
                      : (_isFrench
                            ? 'Devoir sans titre'
                            : 'Untitled assignment'),
                  style: Theme.of(sheetContext).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      avatar: Icon(
                        Icons.circle,
                        size: 12,
                        color: _statusColor(status),
                      ),
                      label: Text(_statusLabel(status)),
                    ),
                    if (maxScore.isNotEmpty)
                      Chip(
                        avatar: const Icon(
                          Icons.star_outline_rounded,
                          size: 18,
                        ),
                        label: Text(
                          _isFrench
                              ? 'Note max : $maxScore'
                              : 'Max score: $maxScore',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (dueAt != null && dueAt.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_rounded),
                    title: Text(_isFrench ? 'Échéance' : 'Deadline'),
                    subtitle: Text(_formatDueDate(dueAt)),
                  ),
                const SizedBox(height: 8),
                Text(
                  instructions.isNotEmpty
                      ? instructions
                      : (_isFrench ? 'Aucune consigne.' : 'No instructions.'),
                  style: const TextStyle(height: 1.45),
                ),
                const SizedBox(height: 16),
                _buildTechnicalInfo(sheetContext, assignment),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTechnicalInfo(
    BuildContext context,
    Map<String, dynamic> assignment,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isFrench ? 'Références' : 'References',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          _infoLine(
            context,
            _isFrench ? 'ID du devoir' : 'Assignment ID',
            assignment['id']?.toString() ?? '',
          ),
          _infoLine(
            context,
            _isFrench ? 'Cours' : 'Course',
            assignment['course_id']?.toString() ?? '',
          ),
          _infoLine(
            context,
            _isFrench ? 'Leçon' : 'Lesson',
            assignment['lesson_id']?.toString() ?? '',
          ),
          _infoLine(
            context,
            _isFrench ? 'Enseignant' : 'Teacher',
            assignment['teacher_id']?.toString() ?? '',
          ),
          _infoLine(
            context,
            _isFrench ? 'Salle' : 'Classroom',
            assignment['class_id']?.toString() ?? '',
          ),
        ],
      ),
    );
  }

  Widget _infoLine(BuildContext context, String label, String value) {
    if (value.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isFrench
              ? 'La création des exercices sera reliée au formulaire existant.'
              : 'Exercise creation will be connected to the existing form.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isFrench ? 'Exercices et évaluations' : 'Exercises and assessments',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: _isFrench ? 'Actualiser' : 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showComingSoon,
        icon: const Icon(Icons.add_rounded),
        label: Text(_isFrench ? 'Nouvel exercice' : 'New exercise'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _assignmentsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 220),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _isFrench
                          ? 'Impossible de charger les exercices.'
                          : 'Unable to load exercises.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          }

          final assignments = snapshot.data ?? [];

          if (assignments.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 220),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.assignment_outlined,
                          size: 56,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isFrench
                              ? 'Aucun exercice ou devoir disponible.'
                              : 'No exercise or assignment available.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: assignments.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final assignment = assignments[index];
                final title = _title(assignment);
                final status = assignment['status']?.toString();
                final classId = assignment['class_id']?.toString() ?? '';

                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF166534),
                      child: const Icon(
                        Icons.assignment_rounded,
                        color: Colors.white,
                      ),
                    ),
                    title: Text(
                      title.isNotEmpty
                          ? title
                          : (_isFrench
                                ? 'Devoir sans titre'
                                : 'Untitled assignment'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_statusLabel(status)),
                          if (classId.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${_isFrench ? 'Salle' : 'Class'} : $classId',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showAssignmentDetails(assignment),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
