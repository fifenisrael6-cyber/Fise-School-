import 'package:flutter/material.dart';

import '../../../core/services/evaluation_service.dart';
import '../../../models/evaluation.dart';
import '../../teacher/pages/teacher_evaluation_review_page.dart';

String _adminEvalDate(DateTime value) {
  final d = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// Vue d'administration des épreuves officielles et du suivi Gemini.
/// L'IA propose une correction ; l'administration peut ouvrir le dossier
/// de l'épreuve pour examiner les erreurs, relancer une correction et vérifier
/// l'état de validation. Les règles d'accès restent contrôlées par Supabase.
class AdminEvaluationAiPage extends StatefulWidget {
  final Locale locale;

  const AdminEvaluationAiPage({super.key, required this.locale});

  @override
  State<AdminEvaluationAiPage> createState() => _AdminEvaluationAiPageState();
}

class _AdminEvaluationAiPageState extends State<AdminEvaluationAiPage> {
  final _service = EvaluationService();
  List<TeacherEvaluation> _items = const [];
  bool _loading = true;
  String? _error;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _load(forceRefresh: true);
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = (await _service.listTeacherEvaluations(forceRefresh: forceRefresh)).toList();
      if (!mounted) return;
      // Priorité aux évaluations avec erreurs Gemini, puis aux corrections
      // à examiner par un humain.
      items.sort((a, b) {
        final aPriority = a.errorCount > 0 ? 0 : (a.toReviewCount > 0 ? 1 : 2);
        final bPriority = b.errorCount > 0 ? 0 : (b.toReviewCount > 0 ? 1 : 2);
        if (aPriority != bPriority) return aPriority.compareTo(bPriority);
        return b.dueAt.compareTo(a.dueAt);
      });
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = EvaluationService.friendlyError(e, fr: _fr);
      });
    }
  }

  int get _submitted => _items.fold(0, (sum, item) => sum + item.submittedCount);
  int get _needsReview => _items.fold(0, (sum, item) => sum + item.toReviewCount);
  int get _validated => _items.fold(0, (sum, item) => sum + item.validatedCount);
  int get _errors => _items.fold(0, (sum, item) => sum + item.errorCount);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'Corrections IA des épreuves' : 'AI exam correction monitoring'),
        actions: [
          IconButton(
            tooltip: _fr ? 'Actualiser depuis le serveur' : 'Refresh from server',
            onPressed: _loading ? null : () => _load(forceRefresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(forceRefresh: true),
        child: _loading && _items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: 260),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fr ? 'Tableau de suivi Gemini' : 'Gemini monitoring dashboard',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(_fr
                              ? 'Gemini propose les notes à partir du PDF et des photos. Une note reste provisoire tant que la validation requise n’a pas été faite.'
                              : 'Gemini proposes marks from the PDF and submitted photos. Marks remain provisional until the required review is complete.'),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _MetricChip(label: _fr ? 'Remises' : 'Submitted', value: _submitted, icon: Icons.upload_file_rounded),
                              _MetricChip(label: _fr ? 'À examiner' : 'To review', value: _needsReview, icon: Icons.fact_check_outlined),
                              _MetricChip(label: _fr ? 'Validées' : 'Validated', value: _validated, icon: Icons.verified_outlined),
                              _MetricChip(label: _fr ? 'Erreurs IA' : 'AI errors', value: _errors, icon: Icons.error_outline_rounded, danger: _errors > 0),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!),
                      ),
                    ),
                  if (!_loading && _items.isEmpty && _error == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
                      child: Column(
                        children: [
                          const Icon(Icons.assignment_turned_in_outlined, size: 48),
                          const SizedBox(height: 10),
                          Text(
                            _fr ? 'Aucune épreuve officielle pour le moment.' : 'No official exams yet.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _fr
                                ? 'Les épreuves PDF publiées par les enseignants apparaîtront ici.'
                                : 'PDF exams published by teachers will appear here.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  for (final item in _items) _evaluationCard(item),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _evaluationCard(TeacherEvaluation item) {
    final hasError = item.errorCount > 0;
    final hasReview = item.toReviewCount > 0;
    final color = hasError
        ? const Color(0xFFB91C1C)
        : hasReview
            ? const Color(0xFFB45309)
            : item.validatedCount > 0
                ? const Color(0xFF166534)
                : Theme.of(context).colorScheme.primary;
    final status = hasError
        ? (_fr ? 'Erreur(s) Gemini à relancer' : 'Gemini error(s) to retry')
        : hasReview
            ? (_fr ? 'Validation / vérification nécessaire' : 'Review / validation needed')
            : item.submittedCount > 0 && item.validatedCount >= item.submittedCount
                ? (_fr ? 'Corrections validées' : 'Corrections validated')
                : item.status == 'closed'
                    ? (_fr ? 'Clôturée' : 'Closed')
                    : (_fr ? 'Suivi en cours' : 'In progress');

    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          foregroundColor: color,
          child: Icon(hasError ? Icons.error_outline_rounded : Icons.auto_awesome_rounded),
        ),
        title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${item.subjectFr} · ${item.classes.join(', ')}\n'
            '${_fr ? 'Échéance' : 'Deadline'} : ${_adminEvalDate(item.dueAt)}\n'
            '${_fr ? 'Remises' : 'Submitted'} : ${item.submittedCount}  ·  '
            '${_fr ? 'À vérifier' : 'To review'} : ${item.toReviewCount}  ·  '
            '${_fr ? 'Validées' : 'Validated'} : ${item.validatedCount}'
            '${item.errorCount > 0 ? '  ·  ${_fr ? 'Erreurs' : 'Errors'} : ${item.errorCount}' : ''}\n'
            '$status',
            style: TextStyle(color: color),
          ),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () async {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => TeacherEvaluationReviewPage(
                locale: widget.locale,
                evaluation: item,
              ),
            ),
          );
          if (mounted) _load(forceRefresh: true);
        },
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final bool danger;

  const _MetricChip({
    required this.label,
    required this.value,
    required this.icon,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFB91C1C) : Theme.of(context).colorScheme.primary;
    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text('$label : $value'),
    );
  }
}
