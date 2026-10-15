import 'package:flutter/material.dart';

import '../../../core/services/evaluation_service.dart';
import '../../../core/services/grade_service.dart';
import '../../../models/evaluation.dart';
import '../../../models/grades.dart';

String _fmt(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final l = d.toLocal();
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

/// Publication contrôlée des bulletins : état des corrections, programmation, publication immédiate.
class AdminPublicationPage extends StatefulWidget {
  final Locale locale;
  const AdminPublicationPage({super.key, required this.locale});

  @override
  State<AdminPublicationPage> createState() => _AdminPublicationPageState();
}

class _AdminPublicationPageState extends State<AdminPublicationPage> {
  final _service = EvaluationService();
  final _grades = GradeService();
  List<GradePeriod> _periods = const [];
  GradePeriod? _period;
  PublicationReport? _report;
  String _policy = 'block';
  bool _loading = true;
  bool _busy = false;
  String? _error;

  bool get _fr => widget.locale.languageCode == 'fr';
  String get _lang => widget.locale.languageCode;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final periods = await _grades.listPeriods();
      if (!mounted) return;
      setState(() => _periods = periods);
      if (periods.isNotEmpty) {
        _period = periods.firstWhere((p) => !p.isPublished, orElse: () => periods.last);
        await _loadReport();
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = EvaluationService.friendlyError(e, fr: _fr);
      });
    }
  }

  Future<void> _loadReport() async {
    final p = _period;
    if (p == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _service.publicationReport(p.id);
      if (!mounted) return;
      setState(() {
        _report = r;
        _policy = r.policy;
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

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _snack(EvaluationService.friendlyError(e, fr: _fr));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _loadReport();
  }

  Future<void> _schedule() async {
    final p = _period!;
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _report?.publishAt ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
    if (t == null) return;
    final at = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    await _run(() async {
      await _service.schedulePublication(periodId: p.id, publishAt: at, policy: _policy);
      _snack(_fr ? 'Publication programmée le ${_fmt(at)}.' : 'Publication scheduled.');
    });
  }

  Future<void> _publishNow() async {
    final p = _period!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_fr ? 'Publier maintenant ?' : 'Publish now?'),
        content: Text(_fr
            ? 'Les bulletins de « ${p.labelFor(_lang)} » seront visibles par les élèves et les notifications seront envoyées.'
            : 'Report cards will become visible and students will be notified.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_fr ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_fr ? 'Publier' : 'Publish')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      final r = await _service.publishNow(p.id, policy: _policy);
      final result = r['result'];
      _snack(result == 'published'
          ? (_fr ? 'Bulletins publiés.' : 'Published.')
          : result == 'blocked'
              ? (_fr ? 'Publication bloquée : ${r['note'] ?? ''}' : 'Blocked: ${r['note'] ?? ''}')
              : (_fr ? 'Déjà publiée ou en cours.' : 'Already published or in progress.'));
    });
  }

  String _statusLabel(PublicationReport r) {
    switch (r.status) {
      case 'scheduled':
        return '${_fr ? 'Programmée' : 'Scheduled'} : ${r.publishAt == null ? '-' : _fmt(r.publishAt!)}';
      case 'published':
        return _fr ? 'Publiée' : 'Published';
      case 'blocked':
        return _fr ? 'Bloquée' : 'Blocked';
      case 'cancelled':
        return _fr ? 'Programmation annulée' : 'Cancelled';
      case 'publishing':
        return _fr ? 'Publication en cours' : 'Publishing';
      default:
        return _fr ? 'Non publiée' : 'Not published';
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'Publication des bulletins' : 'Report card publication'),
        actions: [IconButton(onPressed: _loadReport, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: _loading && r == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_periods.isEmpty) Text(_fr ? 'Aucune période.' : 'No period.'),
                if (_periods.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _period?.id,
                    decoration: InputDecoration(labelText: _fr ? 'Période' : 'Period', border: const OutlineInputBorder()),
                    items: _periods
                        .map((p) => DropdownMenuItem(value: p.id, child: Text(p.labelFor(_lang))))
                        .toList(),
                    onChanged: (id) {
                      setState(() => _period = _periods.firstWhere((p) => p.id == id));
                      _loadReport();
                    },
                  ),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!)),
                if (r != null) ..._body(r),
              ],
            ),
    );
  }

  List<Widget> _body(PublicationReport r) {
    final editable = !r.isPublished && r.status != 'publishing';
    return [
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          leading: Icon(r.isPublished ? Icons.public_rounded : Icons.schedule_rounded),
          title: Text(_statusLabel(r), style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: r.note == null ? null : Text(r.note!),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_fr ? 'État des corrections (épreuves de la période)' : 'Correction status',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('${_fr ? 'Notes validées' : 'Validated'} : ${r.validated} / ${r.scoresTotal}'),
            Text('${_fr ? 'Provisoires' : 'Provisional'} : ${r.provisional}'
                ' (${_fr ? 'à vérifier' : 'to review'} ${r.needsReview}, '
                '${_fr ? 'en attente' : 'pending'} ${r.pending}, ${_fr ? 'erreurs' : 'errors'} ${r.errors})'),
            Text('${_fr ? 'Notes au bulletin' : 'Report marks'} : ${r.gradesCount} · '
                '${_fr ? 'élèves concernés' : 'students'} ${r.studentsWithGrades}'),
            if (r.manualConflicts > 0)
              Text(_fr
                  ? '${r.manualConflicts} épreuve(s) non reportée(s) : une note manuelle existe déjà pour la matière.'
                  : '${r.manualConflicts} not synced: a manual mark already exists.'),
            if (r.syncErrors > 0)
              Text(_fr ? '${r.syncErrors} erreur(s) de report vers le bulletin.' : '${r.syncErrors} sync error(s).',
                  style: const TextStyle(color: Color(0xFFB91C1C))),
            if (r.classesWithoutGrades.isNotEmpty)
              Text('${_fr ? 'Classes sans aucune note' : 'Classes without marks'} : ${r.classesWithoutGrades.join(', ')}'),
            if (r.blocking)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _fr
                      ? '⚠ ${r.openScores} note(s) non validée(s) : la politique « bloquer » empêchera la publication.'
                      : '⚠ ${r.openScores} unvalidated mark(s): "block" policy prevents publishing.',
                  style: const TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.w700),
                ),
              ),
          ]),
        ),
      ),
      if (editable) ...[
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _policy,
          decoration: InputDecoration(
            labelText: _fr ? 'Si des notes ne sont pas validées' : 'If marks are not validated',
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(value: 'block', child: Text(_fr ? 'Bloquer la publication' : 'Block publication')),
            DropdownMenuItem(value: 'exclude', child: Text(_fr ? 'Publier sans les notes non validées' : 'Publish without them')),
          ],
          onChanged: (v) => setState(() => _policy = v ?? 'block'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _schedule,
          icon: const Icon(Icons.event_available_rounded),
          label: Text(r.status == 'scheduled'
              ? (_fr ? 'Modifier la date de publication' : 'Change publication date')
              : (_fr ? 'Programmer la publication' : 'Schedule publication')),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _publishNow,
          icon: const Icon(Icons.publish_rounded),
          label: Text(_fr ? 'Publier maintenant' : 'Publish now'),
        ),
        if (r.status == 'scheduled' || r.status == 'blocked')
          TextButton.icon(
            onPressed: _busy ? null : () => _run(() => _service.cancelPublication(_period!.id)),
            icon: const Icon(Icons.event_busy_rounded),
            label: Text(_fr ? 'Annuler la programmation' : 'Cancel schedule'),
          ),
      ],
      const SizedBox(height: 24),
    ];
  }
}
