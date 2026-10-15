import 'package:flutter/material.dart';

import '../../../core/offline/course_offline_service.dart';
import '../../../core/offline/offline_resource_viewer.dart';
import '../../../core/services/evaluation_service.dart';
import '../../../models/evaluation.dart';
import '../../../models/pedagogy.dart';

String _fmt(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final l = d.toLocal();
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

String _num(double? v) => v == null ? '-' : v.toStringAsFixed(2);

class TeacherEvaluationReviewPage extends StatefulWidget {
  final Locale locale;
  final TeacherEvaluation evaluation;

  const TeacherEvaluationReviewPage({super.key, required this.locale, required this.evaluation});

  @override
  State<TeacherEvaluationReviewPage> createState() => _TeacherEvaluationReviewPageState();
}

class _TeacherEvaluationReviewPageState extends State<TeacherEvaluationReviewPage> {
  final _service = EvaluationService();
  List<ReviewRow> _rows = const [];
  bool _loading = true;
  String? _error;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.listReview(widget.evaluation.id);
      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  Future<void> _openPaper() async {
    final userId = _service.currentUserId;
    if (userId == null) {
      _snack(_fr ? 'Session indisponible.' : 'Session unavailable.');
      return;
    }
    final cacheId = 'evaluation-${widget.evaluation.id}';
    final offline = CourseOfflineService();
    try {
      final cached = await offline.getLocal(userId, cacheId);
      final paper = cached == null
          ? await _service.teacherPaper(widget.evaluation.id)
          : null;
      if (cached == null && paper == null) {
        _snack(_fr ? 'Le PDF de cette épreuve est introuvable.' : 'The exam PDF was not found.');
        return;
      }
      final fileName = paper?.name ?? cached!.fileName;
      final localPath = await offline.openExternalFile(
        userId: userId,
        resourceId: cacheId,
        courseId: 'evaluations',
        fileName: fileName,
        mimeType: 'application/pdf',
        signedUrlProvider: () {
          if (paper == null) throw StateError('evaluation-paper-path-unavailable');
          return _service.openPaperUrl(paper.path);
        },
      );
      if (!mounted) return;
      final resource = CourseResource(
        id: cacheId,
        courseId: 'evaluations',
        resourceType: 'pdf',
        storagePath: paper?.path ?? '',
        fileName: fileName,
        titleFr: widget.evaluation.title,
        titleEn: widget.evaluation.title,
        mimeType: 'application/pdf',
      );
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OfflineResourceViewer(
            locale: widget.locale,
            userId: userId,
            resource: resource,
            localPath: localPath,
          ),
        ),
      );
    } catch (error) {
      _snack(EvaluationService.friendlyError(error, fr: _fr));
    }
  }

  Future<void> _validateReady() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_fr ? 'Valider les corrections terminées ?' : 'Validate finished corrections?'),
        content: Text(_fr
            ? 'Seules les corrections sans doute (statut « terminée ») sont validées. Celles à vérifier restent à traiter une par une.'
            : 'Only corrections without doubt are validated. Those flagged for review stay pending.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_fr ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_fr ? 'Valider' : 'Validate')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await _service.validateReady(widget.evaluation.id);
      _snack(_fr
          ? '${r['validated']} note(s) validée(s), ${r['failed']} en échec.'
          : '${r['validated']} validated, ${r['failed']} failed.');
      _load();
    } catch (e) {
      _snack(EvaluationService.friendlyError(e, fr: _fr));
    }
  }

  Future<void> _close() async {
    try {
      await _service.closeEvaluation(widget.evaluation.id);
      _snack(_fr ? 'Épreuve clôturée.' : 'Exam closed.');
    } catch (e) {
      _snack(EvaluationService.friendlyError(e, fr: _fr));
    }
  }

  (String, Color) _status(ReviewRow r) {
    if (!r.submitted) return (_fr ? 'Non remise' : 'Not submitted', Colors.grey);
    if (r.validated) return (_fr ? 'Validée' : 'Validated', const Color(0xFF166534));
    switch (r.correctionStatus) {
      case 'needs_review':
        return (_fr ? 'À vérifier' : 'Needs review', const Color(0xFFB45309));
      case 'error':
        return (_fr ? 'Erreur de correction' : 'Correction error', const Color(0xFFB91C1C));
      case 'done':
        return (_fr ? 'Correction proposée' : 'Proposed', const Color(0xFF1D4ED8));
      case 'processing':
        return (_fr ? 'En cours' : 'Processing', Colors.blueGrey);
      default:
        return (_fr ? 'En attente' : 'Pending', Colors.blueGrey);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.evaluation.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: _fr ? 'Ouvrir le PDF de l’épreuve' : 'Open exam PDF',
            onPressed: _openPaper,
            icon: const Icon(Icons.picture_as_pdf_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'validate') _validateReady();
              if (v == 'close') _close();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'validate', child: Text(_fr ? 'Valider les corrections terminées' : 'Validate finished')),
              PopupMenuItem(value: 'close', child: Text(_fr ? 'Clôturer l’épreuve' : 'Close exam')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(padding: const EdgeInsets.all(24), children: [Text(_error!)])
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final r = _rows[i];
                      final (label, color) = _status(r);
                      final score = r.validated ? r.finalScore : r.provisionalScore;
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          title: Text(r.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text([
                            r.className,
                            if (r.submitted && r.submittedAt != null)
                              '${_fr ? 'Reçue' : 'Received'} ${_fmt(r.submittedAt!)}'
                                  '${r.isLate ? ' · ${_fr ? 'EN RETARD' : 'LATE'} ${r.lateMinutes} min' : ''}',
                            if (r.submitted) '${r.photoCount} photo(s)',
                            if (r.reviewReasons.isNotEmpty && !r.validated) r.reviewReasons.join(' · '),
                            if ((r.lastError ?? '').isNotEmpty && r.correctionStatus == 'error') r.lastError!,
                          ].join('\n')),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                              if (r.submitted)
                                Text(
                                  '${_num(score)} / ${r.maxScore.toStringAsFixed(r.maxScore % 1 == 0 ? 0 : 1)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontStyle: r.validated ? FontStyle.normal : FontStyle.italic,
                                  ),
                                ),
                            ],
                          ),
                          onTap: r.submitted && r.submissionId != null
                              ? () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TeacherSubmissionReviewPage(
                                        locale: widget.locale,
                                        submissionId: r.submissionId!,
                                      ),
                                    ),
                                  );
                                  if (mounted) _load();
                                }
                              : null,
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _QEdit {
  final ReviewQuestion q;
  final TextEditingController points;
  final TextEditingController comment;

  _QEdit(this.q)
      : points = TextEditingController(
            text: (q.finalPoints ?? (q.needsReview ? null : q.aiPoints))?.toString() ?? ''),
        comment = TextEditingController(text: q.teacherComment ?? '');
}

class TeacherSubmissionReviewPage extends StatefulWidget {
  final Locale locale;
  final String submissionId;

  const TeacherSubmissionReviewPage({super.key, required this.locale, required this.submissionId});

  @override
  State<TeacherSubmissionReviewPage> createState() => _TeacherSubmissionReviewPageState();
}

class _TeacherSubmissionReviewPageState extends State<TeacherSubmissionReviewPage> {
  final _service = EvaluationService();
  final _comment = TextEditingController();
  final _manual = TextEditingController();
  SubmissionDetail? _detail;
  List<_QEdit> _edits = const [];
  Map<String, String> _urls = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _service.submissionDetail(widget.submissionId);
      final urls = <String, String>{};
      for (final p in d.photos) {
        try {
          urls[p.id] = await _service.photoUrl(p.storagePath);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _detail = d;
        _urls = urls;
        _edits = d.questions.map(_QEdit.new).toList(growable: false);
        _comment.text = (d.score['teacher_comment'] ?? '').toString();
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

  Future<void> _save({required bool validate}) async {
    final d = _detail!;
    final questions = <Map<String, dynamic>>[];
    for (final e in _edits) {
      final raw = e.points.text.trim().replaceAll(',', '.');
      final pts = raw.isEmpty ? null : double.tryParse(raw);
      if (raw.isNotEmpty && (pts == null || pts < 0 || pts > e.q.maxPoints)) {
        return _snack(_fr
            ? '${e.q.label} : points entre 0 et ${e.q.maxPoints}.'
            : '${e.q.label}: points between 0 and ${e.q.maxPoints}.');
      }
      questions.add({
        'question_key': e.q.key,
        'final_points': pts,
        'teacher_comment': e.comment.text.trim(),
      });
    }
    double? manual;
    if (_manual.text.trim().isNotEmpty) {
      manual = double.tryParse(_manual.text.trim().replaceAll(',', '.'));
      if (manual == null) return _snack(_fr ? 'Note manuelle invalide.' : 'Invalid manual mark.');
    }
    setState(() => _saving = true);
    try {
      final r = await _service.reviewSubmission(
        submissionId: d.submissionId,
        questions: manual == null ? questions : const [],
        comment: _comment.text.trim(),
        validate: validate,
        manualScore: manual,
      );
      _snack(validate
          ? (_fr ? 'Note validée : ${_num((r['final_score'] as num?)?.toDouble())}' : 'Validated')
          : (_fr ? 'Modifications enregistrées.' : 'Saved.'));
      await _load();
    } catch (e) {
      _snack(EvaluationService.friendlyError(e, fr: _fr));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reopen() async {
    final c = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_fr ? 'Rouvrir la note' : 'Reopen the mark'),
        content: TextField(
          controller: c,
          decoration: InputDecoration(labelText: _fr ? 'Motif (obligatoire)' : 'Reason (required)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_fr ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(_fr ? 'Rouvrir' : 'Reopen')),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    try {
      await _service.reopen(widget.submissionId, reason);
      await _load();
    } catch (e) {
      _snack(EvaluationService.friendlyError(e, fr: _fr));
    }
  }

  Future<void> _retry() async {
    try {
      await _service.retryCorrection(widget.submissionId);
      _snack(_fr ? 'Correction relancée.' : 'Correction restarted.');
      await _load();
    } catch (e) {
      _snack(EvaluationService.friendlyError(e, fr: _fr));
    }
  }

  void _zoom(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
          body: InteractiveViewer(maxScale: 6, child: Center(child: Image.network(url))),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return Scaffold(
      appBar: AppBar(title: Text(d?.studentName ?? (_fr ? 'Remise' : 'Submission'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || d == null
              ? Padding(padding: const EdgeInsets.all(24), child: Text(_error ?? ''))
              : ListView(padding: const EdgeInsets.all(16), children: _content(d)),
    );
  }

  List<Widget> _content(SubmissionDetail d) {
    final validated = d.validated;
    final reasons = (d.correction['review_reasons'] is List)
        ? (d.correction['review_reasons'] as List).map((e) => e.toString()).toList()
        : <String>[];
    final quality = d.correction['image_quality'];
    return [
      Text(d.evaluationTitle, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      if (d.submittedAt != null)
        Text('${_fr ? 'Reçue' : 'Received'} ${_fmt(d.submittedAt!)}'
            '${d.isLate ? ' — ${_fr ? 'EN RETARD' : 'LATE'} ${d.lateMinutes} min' : ''}'),
      Text('${_fr ? 'Correction IA' : 'AI correction'} : ${d.correctionStatus}'
          '${d.correction['ai_model'] != null ? ' (${d.correction['ai_model']})' : ''}'),
      if (reasons.isNotEmpty)
        Card(
          color: const Color(0xFFFFFBEB),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('${_fr ? 'À vérifier' : 'To check'} :\n• ${reasons.join('\n• ')}'),
          ),
        ),
      if ((d.correction['last_error'] ?? '').toString().isNotEmpty)
        Text(d.correction['last_error'].toString(), style: const TextStyle(color: Color(0xFFB91C1C))),
      if (d.correctionStatus == 'error')
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(_fr ? 'Relancer la correction' : 'Retry correction'),
          ),
        ),
      if (quality is List && quality.isNotEmpty)
        Text(
          '${_fr ? 'Qualité des images' : 'Image quality'} : '
          '${quality.map((q) => '#${(q as Map)['photo']}: ${q['quality']}').join(' · ')}',
        ),
      const SizedBox(height: 12),
      SizedBox(
        height: 120,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final p in d.photos)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: _urls[p.id] == null ? null : () => _zoom(_urls[p.id]!),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _urls[p.id] == null
                        ? const SizedBox(width: 90, child: ColoredBox(color: Colors.black12))
                        : Image.network(_urls[p.id]!, width: 90, height: 120, fit: BoxFit.cover),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (d.questions.isEmpty)
        Text(_fr
            ? 'Aucune question extraite : saisissez la note manuellement après lecture des photos.'
            : 'No question extracted: enter the mark manually after reading the photos.'),
      for (final e in _edits) _questionCard(e, validated),
      if (!validated) ...[
        const SizedBox(height: 8),
        TextField(
          controller: _manual,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: _fr
                ? 'Note manuelle sur ${d.maxScore} (remplace le détail par question)'
                : 'Manual mark out of ${d.maxScore} (overrides per-question)',
            border: const OutlineInputBorder(),
          ),
        ),
      ],
      const SizedBox(height: 8),
      TextField(
        controller: _comment,
        enabled: !validated,
        maxLines: 2,
        decoration: InputDecoration(labelText: _fr ? 'Commentaire à l’élève' : 'Comment to student', border: const OutlineInputBorder()),
      ),
      const SizedBox(height: 10),
      Card(
        child: ListTile(
          title: Text(
            '${_fr ? 'Note proposée' : 'Proposed'} : ${_num((d.score['provisional_score'] as num?)?.toDouble())}'
            ' / ${d.maxScore}',
          ),
          subtitle: Text(
            '${_fr ? 'Après vos corrections' : 'After your edits'} : ${_num((d.score['raw_score'] as num?)?.toDouble())}'
            '${((d.score['penalty_percent'] as num?) ?? 0) > 0 ? '\n${_fr ? 'Pénalité de retard' : 'Late penalty'} : ${d.score['penalty_percent']} %' : ''}'
            '${validated ? '\n${_fr ? 'Note validée' : 'Validated'} : ${_num((d.score['final_score'] as num?)?.toDouble())}' : ''}',
          ),
        ),
      ),
      if (!validated)
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => _save(validate: false),
              child: Text(_fr ? 'Enregistrer' : 'Save'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: _saving ? null : () => _save(validate: true),
              child: Text(_fr ? 'Valider la note' : 'Validate'),
            ),
          ),
        ])
      else
        OutlinedButton.icon(
          onPressed: _reopen,
          icon: const Icon(Icons.lock_open_rounded),
          label: Text(_fr ? 'Rouvrir pour modifier' : 'Reopen to edit'),
        ),
      if (d.history.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(_fr ? 'Historique' : 'History', style: const TextStyle(fontWeight: FontWeight.w800)),
        for (final h in d.history)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${h['change_type']} · ${_fmt(DateTime.parse(h['created_at'].toString()))}'),
            subtitle: Text([
              if (h['old_final'] != null || h['new_final'] != null) '${h['old_final'] ?? '-'} → ${h['new_final'] ?? '-'}',
              if ((h['reason'] ?? '').toString().isNotEmpty) h['reason'].toString(),
            ].join(' · ')),
          ),
      ],
      const SizedBox(height: 24),
    ];
  }

  Widget _questionCard(_QEdit e, bool locked) {
    final q = e.q;
    final warn = q.needsReview;
    return Card(
      color: warn ? const Color(0xFFFFFBEB) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${q.label}  (/ ${q.maxPoints.toStringAsFixed(q.maxPoints % 1 == 0 ? 0 : 1)})',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            q.legible
                ? (q.answer.isEmpty ? (_fr ? '(réponse vide)' : '(empty)') : q.answer)
                : (_fr ? '⚠ Réponse illisible — non notée par l’IA' : '⚠ Unreadable — not graded by AI'),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (q.aiPoints != null) '${_fr ? 'IA' : 'AI'} ${q.aiPoints}',
              if (q.confidence != null) '${_fr ? 'confiance' : 'confidence'} ${(q.confidence! * 100).round()} %',
              if (q.ambiguous) (_fr ? 'ambiguë' : 'ambiguous'),
              ...q.flags,
            ].join(' · '),
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          if ((q.feedback ?? '').isNotEmpty) Text(q.feedback!, style: const TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(
              width: 100,
              child: TextField(
                controller: e.points,
                enabled: !locked,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: _fr ? 'Points' : 'Points', border: const OutlineInputBorder(), isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: e.comment,
                enabled: !locked,
                decoration: InputDecoration(labelText: _fr ? 'Remarque' : 'Remark', border: const OutlineInputBorder(), isDense: true),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
