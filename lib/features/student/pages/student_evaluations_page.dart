import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/course_offline_service.dart';
import '../../../core/offline/connectivity_service.dart';
import '../../../core/offline/json_cache.dart';
import '../../../core/services/evaluation_service.dart';
import '../../../core/services/photo_service.dart';
import '../../../models/evaluation.dart';
import '../../../models/user_profile.dart';
import '../../messages/widgets/message_media.dart';

/// Calendar of official exams. Supabase RLS limits this list to the student's
/// real classroom (and compatible general classes); the PDF is time-gated too.
class StudentEvaluationsPage extends StatefulWidget {
  const StudentEvaluationsPage({
    super.key,
    required this.locale,
    required this.profile,
  });

  final Locale locale;
  final UserProfile profile;

  @override
  State<StudentEvaluationsPage> createState() => _StudentEvaluationsPageState();
}

class _StudentEvaluationsPageState extends State<StudentEvaluationsPage> {
  final SupabaseClient _db = Supabase.instance.client;
  final EvaluationService _evaluationService = EvaluationService();
  final PhotoService _photoService = PhotoService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  List<StudentEvaluation> _automatedEvaluations = [];
  Duration _serverOffset = Duration.zero;
  String? _submittingId;
  Map<String, Map<String, dynamic>> _exams = {};
  Map<String, Map<String, dynamic>> _subjects = {};
  Map<String, Map<String, dynamic>> _classes = {};
  String? _openingId;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final userId = widget.profile.id;
      final activeClassKey = 'student_active_class_id_' + userId;
      String? activeClassId;
      var online = true;
      try { online = await ConnectivityService().isOnline(); } catch (_) {}
      if (online) {
        try {
          final memberships = await _db
              .from('class_students')
              .select('class_id, joined_at')
              .eq('student_id', userId)
              .eq('is_active', true)
              .order('joined_at', ascending: false)
              .limit(1)
              .timeout(const Duration(seconds: 3));
          activeClassId = memberships.isEmpty ? null : memberships.first['class_id']?.toString();
          await JsonCache.instance.write(activeClassKey, {'class_id': activeClassId ?? ''});
        } catch (_) {
          final pointer = await JsonCache.instance.read(activeClassKey);
          if (pointer is Map) activeClassId = pointer['class_id']?.toString();
        }
      } else {
        final pointer = await JsonCache.instance.read(activeClassKey);
        if (pointer is Map) activeClassId = pointer['class_id']?.toString();
      }
      if (activeClassId != null && activeClassId!.isEmpty) activeClassId = null;

      final cacheKey = 'student_evaluations_' + userId + '_' + (activeClassId ?? 'no-class');
      final payload = await JsonCache.instance.cachedRead<Map<String, dynamic>>(
        key: cacheKey,
        fetch: () async {
          final results = await Future.wait<dynamic>([
            _db.from('assignments')
                .select('id,title_fr,title_en,instructions_fr,instructions_en,class_id,subject_id,exam_id,starts_at,due_at,results_publish_at,evaluation_file_path,evaluation_file_name,status')
                .not('exam_id', 'is', null)
                .inFilter('status', ['published', 'closed'])
                .order('starts_at'),
            _db.from('exams').select('id,name_fr,name_en'),
            _db.from('subjects').select('id,name_fr,name_en'),
            _db.from('school_classes').select('id,display_name,name'),
          ]).timeout(const Duration(seconds: 8));
          return <String, dynamic>{
            'rows': (results[0] as List).map((r) => Map<String, dynamic>.from(r)).toList(),
            'exams': (results[1] as List).map((r) => Map<String, dynamic>.from(r)).toList(),
            'subjects': (results[2] as List).map((r) => Map<String, dynamic>.from(r)).toList(),
            'classes': (results[3] as List).map((r) => Map<String, dynamic>.from(r)).toList(),
          };
        },
        decode: (raw) => Map<String, dynamic>.from(raw as Map),
      );

      StudentEvaluationList? automated;
      try {
        automated = await _evaluationService.listMine(forceRefresh: true);
      } catch (_) {
        // Keep the cached official calendar available if automated results are offline.
      }
      if (!mounted) return;
      setState(() {
        _rows = (payload['rows'] as List? ?? const [])
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList(growable: false);
        _exams = {
          for (final r in (payload['exams'] as List? ?? const []).whereType<Map>())
            r['id'].toString(): Map<String, dynamic>.from(r),
        };
        _subjects = {
          for (final r in (payload['subjects'] as List? ?? const []).whereType<Map>())
            r['id'].toString(): Map<String, dynamic>.from(r),
        };
        _classes = {
          for (final r in (payload['classes'] as List? ?? const []).whereType<Map>())
            r['id'].toString(): Map<String, dynamic>.from(r),
        };
        _automatedEvaluations = automated?.items ?? [];
        _serverOffset = automated?.serverOffset ?? Duration.zero;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _label(Map<String, dynamic>? row, String frKey, String enKey) {
    if (row == null) return '';
    final first = row[_fr ? frKey : enKey]?.toString().trim() ?? '';
    final other = row[_fr ? enKey : frKey]?.toString().trim() ?? '';
    return first.isNotEmpty ? first : other;
  }

  DateTime? _parse(dynamic value) => DateTime.tryParse(value?.toString() ?? '');

  String _date(dynamic value) {
    final parsed = _parse(value);
    if (parsed == null) return _fr ? 'Date non définie' : 'Date not set';
    final d = parsed.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _title(Map<String, dynamic> row) {
    final value = _label(row, 'title_fr', 'title_en');
    if (value.isNotEmpty) return value;
    final exam = _label(_exams[row['exam_id']?.toString()], 'name_fr', 'name_en');
    final subject = _label(_subjects[row['subject_id']?.toString()], 'name_fr', 'name_en');
    return [exam, subject].where((v) => v.isNotEmpty).join(' — ');
  }

  bool _isOpen(Map<String, dynamic> row) {
    final start = _parse(row['starts_at']);
    final end = _parse(row['due_at']);
    final now = DateTime.now();
    return start != null && end != null && !now.isBefore(start) && now.isBefore(end);
  }

  String _state(Map<String, dynamic> row) {
    final start = _parse(row['starts_at']);
    final end = _parse(row['due_at']);
    final now = DateTime.now();
    if (start != null && now.isBefore(start)) return _fr ? 'À venir' : 'Upcoming';
    if (end != null && !now.isBefore(end)) return _fr ? 'Épreuve terminée' : 'Exam ended';
    return _fr ? 'En cours' : 'In progress';
  }

  Future<void> _openPdf(Map<String, dynamic> row) async {
    final id = row['id'].toString();
    final path = row['evaluation_file_path']?.toString() ?? '';
    if (path.trim().isEmpty) {
      _show(_fr ? 'Le PDF n’a pas encore été ajouté par l’enseignant.' : 'The teacher has not attached the PDF yet.');
      return;
    }
    if (!_isOpen(row)) {
      _show(_fr ? 'Le sujet protégé est accessible uniquement pendant la période de l’épreuve.' : 'The protected paper is available only during the scheduled exam window.');
      return;
    }
    setState(() => _openingId = id);
    try {
      final fileName = row['evaluation_file_name']?.toString().trim().isNotEmpty == true
          ? row['evaluation_file_name'].toString().trim()
          : '$id.pdf';
      final localPath = await CourseOfflineService().openExternalFile(
        userId: widget.profile.id,
        resourceId: 'evaluation-$id-paper',
        courseId: 'evaluations-$id',
        fileName: fileName,
        mimeType: 'application/pdf',
        signedUrlProvider: () => _db.storage.from('assignment-files').createSignedUrl(path, 180),
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MediaPdfViewerPage(localPath: localPath, title: fileName),
      ));
    } catch (e) {
      _show((_fr ? 'Sujet inaccessible : ' : 'Paper unavailable: ') + e.toString());
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  bool _automatedIsOpen(StudentEvaluation evaluation) {
    final now = DateTime.now().add(_serverOffset);
    return !now.isBefore(evaluation.startsAt) && now.isBefore(evaluation.dueAt);
  }

  Future<void> _openAutomatedPdf(StudentEvaluation evaluation) async {
    final path = evaluation.pdfPath?.trim() ?? '';
    if (path.isEmpty) {
      _show(_fr ? 'Le sujet PDF n’est pas encore publié.' : 'The exam PDF has not been published yet.');
      return;
    }
    if (!_automatedIsOpen(evaluation)) {
      _show(_fr ? 'Le sujet est accessible uniquement pendant l’épreuve.' : 'The exam paper is available only during the exam window.');
      return;
    }
    setState(() => _openingId = evaluation.id);
    try {
      final fileName = '${evaluation.id}.pdf';
      final localPath = await CourseOfflineService().openExternalFile(
        userId: widget.profile.id,
        resourceId: 'evaluation-${evaluation.id}-paper',
        courseId: 'evaluations-${evaluation.id}',
        fileName: fileName,
        mimeType: 'application/pdf',
        signedUrlProvider: () => _evaluationService.openPaperUrl(path),
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MediaPdfViewerPage(localPath: localPath, title: fileName),
      ));
    } catch (e) {
      _show((_fr ? 'Sujet inaccessible : ' : 'Paper unavailable: ') + e.toString());
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  Future<void> _openCorrectionPdf(StudentEvaluation evaluation) async {
    setState(() => _openingId = evaluation.id);
    try {
      final correction = await _evaluationService.releasedCorrectionPdf(evaluation.id);
      if (correction == null) {
        _show(_fr ? 'Le PDF de correction est encore en préparation.' : 'The correction PDF is still being prepared.');
        return;
      }
      final fileName = '${evaluation.id}-correction.pdf';
      final localPath = await CourseOfflineService().openExternalFile(
        userId: widget.profile.id,
        resourceId: 'evaluation-${evaluation.id}-correction-${correction.path.split('/').last}',
        courseId: 'evaluations-${evaluation.id}',
        fileName: fileName,
        mimeType: 'application/pdf',
        signedUrlProvider: () => _evaluationService.openCorrectionPdfUrl(correction.path),
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MediaPdfViewerPage(localPath: localPath, title: fileName),
      ));
    } catch (e) {
      _show((_fr ? 'Correction PDF indisponible : ' : 'Correction PDF unavailable: ') + e.toString());
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  Future<void> _submitCopy(StudentEvaluation evaluation) async {
    if (!_automatedIsOpen(evaluation) || evaluation.submitted) {
      _show(_fr ? 'Cette épreuve n’accepte plus de nouvelle remise.' : 'This exam is no longer accepting submissions.');
      return;
    }
    final picked = <XFile>[];
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(_fr ? 'Remettre la copie' : 'Submit your paper'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_fr
                    ? 'Photographie toutes les pages dans l’ordre. Les images seront envoyées une fois que tu confirmes.'
                    : 'Photograph every page in order. Photos are uploaded only after you confirm.'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: picked.length >= 40 ? null : () async {
                        final file = await _photoService.takePhoto(maxWidth: 2000);
                        if (file != null && dialogContext.mounted) {
                          setDialogState(() => picked.add(file));
                        }
                      },
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(_fr ? 'Photo' : 'Camera'),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton.icon(
                      onPressed: picked.length >= 40 ? null : () async {
                        final file = await _photoService.pickFromGallery(maxWidth: 2000);
                        if (file != null && dialogContext.mounted) {
                          setDialogState(() => picked.add(file));
                        }
                      },
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(_fr ? 'Galerie' : 'Gallery'),
                    )),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_fr ? '${picked.length}/40 page(s) ajoutée(s)' : '${picked.length}/40 page(s) added'),
                if (picked.isNotEmpty)
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      itemCount: picked.length,
                      itemBuilder: (_, index) => ListTile(
                        dense: true,
                        leading: Text('${index + 1}.'),
                        title: Text(picked[index].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          tooltip: _fr ? 'Retirer' : 'Remove',
                          icon: const Icon(Icons.close),
                          onPressed: () => setDialogState(() => picked.removeAt(index)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_fr ? 'Annuler' : 'Cancel'),
            ),
            FilledButton.icon(
              onPressed: picked.isEmpty ? null : () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.send),
              label: Text(_fr ? 'Envoyer la copie' : 'Submit paper'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || picked.isEmpty || !mounted) return;

    setState(() => _submittingId = evaluation.id);
    try {
      final submissionId = await _evaluationService.startSubmission(evaluation.id);
      final existing = await _db
          .from('evaluation_photos')
          .select('position')
          .eq('submission_id', submissionId)
          .order('position');
      var position = 0;
      for (final row in existing as List) {
        final value = (row['position'] as num?)?.toInt() ?? 0;
        if (value > position) position = value;
      }
      for (final file in picked) {
        if (position >= 40) {
          throw StateError(_fr ? 'La limite de 40 pages est atteinte.' : 'The 40-page limit has been reached.');
        }
        position++;
        final bytes = await file.readAsBytes();
        final extension = file.name.contains('.') ? file.name.split('.').last : 'jpg';
        await _evaluationService.uploadPhoto(
          evaluationId: evaluation.id,
          bytes: bytes,
          extension: extension,
          position: position,
        );
      }
      await _evaluationService.submit(evaluation.id);
      _show(_fr
          ? 'Copie envoyée. La correction IA est en cours de traitement.'
          : 'Paper submitted. AI correction is being processed.');
      await _load();
    } catch (e) {
      _show((_fr ? 'Envoi de la copie impossible : ' : 'Could not submit paper: ') +
          EvaluationService.friendlyError(e, fr: _fr));
    } finally {
      if (mounted) setState(() => _submittingId = null);
    }
  }

  Widget _automatedCard(StudentEvaluation evaluation) {
    final isOpen = _automatedIsOpen(evaluation);
    final hasPdf = (evaluation.pdfPath ?? '').trim().isNotEmpty;
    final busy = _openingId == evaluation.id;
    final submitting = _submittingId == evaluation.id;
    final result = evaluation.result;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFE4F2E9),
                child: Icon(Icons.fact_check_outlined, color: Color(0xFF166534)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(evaluation.title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 8),
            Text('${_fr ? 'Matière' : 'Subject'} : ${evaluation.subjectFor(_fr)}'),
            Text('${_fr ? 'Début' : 'Starts'} : ${_date(evaluation.startsAt.toIso8601String())}'),
            Text('${_fr ? 'Fin' : 'Ends'} : ${_date(evaluation.dueAt.toIso8601String())}'),
            const SizedBox(height: 6),
            Chip(
              avatar: Icon(evaluation.submitted ? Icons.check_circle : (isOpen ? Icons.play_circle_outline : Icons.schedule), size: 18),
              label: Text(evaluation.submitted
                  ? (_fr ? 'Copie remise' : 'Paper submitted')
                  : (!isOpen
                      ? (DateTime.now().add(_serverOffset).isBefore(evaluation.startsAt)
                          ? (_fr ? 'À venir' : 'Upcoming')
                          : (_fr ? 'Épreuve terminée' : 'Exam ended'))
                      : (_fr ? 'Épreuve en cours' : 'Exam in progress'))),
            ),
            if (hasPdf && isOpen)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : () => _openAutomatedPdf(evaluation),
                  icon: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(busy ? (_fr ? 'Ouverture…' : 'Opening…') : (_fr ? 'Ouvrir le sujet PDF' : 'Open exam PDF')),
                ),
              )
            else if (!hasPdf)
              Text(
                evaluation.status == 'published' &&
                        DateTime.now().add(_serverOffset).isBefore(evaluation.startsAt)
                    ? (_fr
                        ? 'Sujet protégé : il sera accessible à l’heure prévue.'
                        : 'Protected paper: it will be available at the scheduled start.')
                    : (_fr
                        ? 'Sujet PDF en attente de publication par l’enseignant.'
                        : 'Waiting for the teacher to publish the exam PDF.'),
                style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
              ),
            if (isOpen && !evaluation.submitted)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: submitting ? null : () => _submitCopy(evaluation),
                  icon: submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload_file_outlined),
                  label: Text(submitting ? (_fr ? 'Envoi en cours…' : 'Submitting…') : (_fr ? 'Remettre ma copie' : 'Submit my paper')),
                ),
              ),
            if (evaluation.submitted && result == null)
              Text(_fr
                  ? 'Copie reçue. La note et la correction seront visibles après validation et à la date de publication prévue.'
                  : 'Paper received. The score and correction will appear after validation and at the scheduled release time.'),
            if (result != null) ...[
              const Divider(height: 24),
              Text(
                '${_fr ? 'Note' : 'Score'} : ${result.finalScore?.toStringAsFixed(2) ?? '—'}/${result.maxScore.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : () => _openCorrectionPdf(evaluation),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(_fr ? 'Ouvrir ma copie corrigée (PDF)' : 'Open my corrected copy (PDF)'),
                ),
              ),
              if ((result.comment ?? '').trim().isNotEmpty) Text(result.comment!),
              ...result.questions.map((question) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${question.label} — ${question.points?.toStringAsFixed(2) ?? '—'}/${question.maxPoints.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                  if ((question.feedback ?? '').trim().isNotEmpty) Text(question.feedback!),
                ]),
              )),
            ],
          ],
        ),
      ),
    );
  }

  void _show(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'Calendrier des évaluations' : 'Exam schedule'),
        actions: [IconButton(onPressed: _load, tooltip: _fr ? 'Actualiser' : 'Refresh', icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : _rows.isEmpty && _automatedEvaluations.isEmpty
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(
                      _fr ? 'Aucune évaluation officielle programmée pour vos salles.' : 'No official exams are scheduled for your classrooms.',
                      textAlign: TextAlign.center,
                    )))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: _automatedEvaluations.length + _rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, index) {
                          if (index < _automatedEvaluations.length) {
                            return _automatedCard(_automatedEvaluations[index]);
                          }
                          final row = _rows[index - _automatedEvaluations.length];
                          final subject = _label(_subjects[row['subject_id']?.toString()], 'name_fr', 'name_en');
                          final schoolClass = _classes[row['class_id']?.toString()];
                          final className = schoolClass?['display_name']?.toString() ?? schoolClass?['name']?.toString() ?? '';
                          final hasPdf = (row['evaluation_file_path']?.toString() ?? '').trim().isNotEmpty;
                          final isOpen = _isOpen(row);
                          final busy = _openingId == row['id'].toString();
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    CircleAvatar(
                                      backgroundColor: const Color(0xFFE4F2E9),
                                      child: Icon(Icons.event_note, color: const Color(0xFF166534)),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(_title(row), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                                  ]),
                                  const SizedBox(height: 10),
                                  if (className.isNotEmpty) Text('${_fr ? 'Classe' : 'Class'} : $className'),
                                  if (subject.isNotEmpty) Text('${_fr ? 'Matière' : 'Subject'} : $subject'),
                                  const SizedBox(height: 6),
                                  Text('${_fr ? 'Début' : 'Starts'} : ${_date(row['starts_at'])}'),
                                  Text('${_fr ? 'Fin' : 'Ends'} : ${_date(row['due_at'])}'),
                                  Text('${_fr ? 'Résultats' : 'Results'} : ${_date(row['results_publish_at'])}'),
                                  const SizedBox(height: 10),
                                  Chip(
                                    avatar: Icon(isOpen ? Icons.play_circle_outline : Icons.schedule, size: 18),
                                    label: Text(_state(row)),
                                  ),
                                  if (hasPdf)
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: busy ? null : () => _openPdf(row),
                                        icon: busy
                                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                            : const Icon(Icons.picture_as_pdf_outlined),
                                        label: Text(busy ? (_fr ? 'Ouverture…' : 'Opening…') : (_fr ? 'Ouvrir le sujet PDF' : 'Open exam PDF')),
                                      ),
                                    )
                                  else
                                    Text(
                                      _fr ? 'Sujet PDF en attente de publication par l’enseignant.' : 'The teacher has not published the exam PDF yet.',
                                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
                                    ),
                                  if (hasPdf && !isOpen)
                                    Text(
                                      _fr ? 'Le PDF sera accessible uniquement pendant la période programmée.' : 'The PDF is available only during the scheduled window.',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
