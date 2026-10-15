import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/offline/course_offline_service.dart';
import '../../../core/offline/offline_resource_viewer.dart';
import '../../../core/services/evaluation_service.dart';
import '../../../models/evaluation.dart';
import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';

String _fmt(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final l = d.toLocal();
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

String _remaining(Duration d, bool fr) {
  if (d.isNegative) return fr ? 'Délai dépassé' : 'Deadline passed';
  final days = d.inDays;
  final h = d.inHours % 24;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (days > 0) return fr ? '${days} j ${h} h ${m} min' : '${days}d ${h}h ${m}m';
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// Espace d'évaluation de l'élève : épreuves PDF reçues, remises et résultats.
class StudentEvaluationsPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const StudentEvaluationsPage({super.key, required this.locale, required this.profile});

  @override
  State<StudentEvaluationsPage> createState() => _StudentEvaluationsPageState();
}

class _StudentEvaluationsPageState extends State<StudentEvaluationsPage> {
  final _service = EvaluationService();
  StudentEvaluationList? _data;
  String? _error;
  bool _loading = true;

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
      final data = await _service.listMine();
      if (!mounted) return;
      setState(() {
        _data = data;
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

  @override
  Widget build(BuildContext context) {
    final items = _data?.items ?? const <StudentEvaluation>[];
    final offset = _data?.serverOffset ?? Duration.zero;
    return Scaffold(
      appBar: AppBar(title: Text(_fr ? 'Mes épreuves' : 'My exams')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(padding: const EdgeInsets.all(24), children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    Center(
                      child: FilledButton(
                        onPressed: _load,
                        child: Text(_fr ? 'Réessayer' : 'Retry'),
                      ),
                    ),
                  ])
                : items.isEmpty
                    ? ListView(padding: const EdgeInsets.all(24), children: [
                        Text(
                          _fr ? 'Aucune épreuve pour le moment.' : 'No exam yet.',
                          textAlign: TextAlign.center,
                        ),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _card(items[i], offset),
                      ),
      ),
    );
  }

  Widget _card(StudentEvaluation e, Duration offset) {
    final now = DateTime.now().add(offset);
    String status;
    Color color;
    if (e.result != null) {
      status = _fr ? 'Résultat disponible' : 'Result available';
      color = const Color(0xFF166534);
    } else if (e.submitted) {
      status = _fr ? 'Remise envoyée — correction en cours' : 'Submitted — being corrected';
      color = const Color(0xFF1D4ED8);
    } else if (now.isBefore(e.startsAt)) {
      status = '${_fr ? 'Début' : 'Starts'} : ${_fmt(e.startsAt)}';
      color = Colors.grey;
    } else if (now.isAfter(e.dueAt)) {
      status = _fr ? 'Délai dépassé' : 'Deadline passed';
      color = const Color(0xFFB91C1C);
    } else {
      status = '${_fr ? 'À remettre avant' : 'Due'} ${_fmt(e.dueAt)}';
      color = const Color(0xFFB45309);
    }
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.fact_check_rounded),
        title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${e.subjectFor(_fr)}\n$status', style: TextStyle(color: color)),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StudentEvaluationDetailPage(
                locale: widget.locale,
                profile: widget.profile,
                evaluation: e,
                serverOffset: offset,
              ),
            ),
          );
          if (mounted) _load();
        },
      ),
    );
  }
}

class _Shot {
  final Uint8List? bytes;
  final String ext;
  String? photoId;
  String? path;
  String? remoteUrl;
  String state; // uploading | done | error
  String? error;

  _Shot({this.bytes, this.ext = 'jpg', this.photoId, this.path, this.state = 'uploading'});
}

class StudentEvaluationDetailPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final StudentEvaluation evaluation;
  final Duration serverOffset;

  const StudentEvaluationDetailPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.evaluation,
    required this.serverOffset,
  });

  @override
  State<StudentEvaluationDetailPage> createState() => _StudentEvaluationDetailPageState();
}

class _StudentEvaluationDetailPageState extends State<StudentEvaluationDetailPage> {
  final _service = EvaluationService();
  final _picker = ImagePicker();
  final List<_Shot> _shots = [];
  Timer? _timer;
  Duration _left = Duration.zero;
  EvalSubmissionInfo? _submission;
  bool _sending = false;
  bool _busy = false;

  StudentEvaluation get _e => widget.evaluation;
  bool get _fr => widget.locale.languageCode == 'fr';
  DateTime get _now => DateTime.now().add(widget.serverOffset);
  bool get _started => !_now.isBefore(_e.startsAt);
  bool get _pastDue => !_now.isBefore(_e.dueAt);
  bool get _acceptsLate => _e.latePolicy != 'reject';
  bool get _closedForUpload {
    if (_e.status == 'closed') return true;
    if (!_pastDue) return false;
    if (_acceptsLate) return false;
    // Tolérance d'envoi pour une remise commencée avant l'échéance.
    final grace = _e.dueAt.add(Duration(minutes: _e.lateGraceMinutes));
    return !_now.isBefore(grace) || _shots.isEmpty;
  }

  @override
  void initState() {
    super.initState();
    _submission = _e.submission;
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    final sub = _e.submission;
    if (sub != null && !sub.isSubmitted) _loadDraftPhotos(sub.id);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _left = _e.dueAt.difference(_now));
  }

  Future<void> _loadDraftPhotos(String submissionId) async {
    try {
      final photos = await _service.listMyPhotos(submissionId);
      for (final photo in photos) {
        if (!_shots.any((shot) => shot.photoId == photo.id)) {
          _shots.add(_Shot(
            photoId: photo.id,
            path: photo.storagePath,
            state: 'done',
          ));
        }
      }
      if (mounted) setState(() {});
      unawaited(_loadDraftPhotoUrls(photos));
    } catch (_) {}
  }

  Future<void> _loadDraftPhotoUrls(List<ReviewPhoto> photos) async {
    for (final photo in photos) {
      try {
        final url = await _service.photoUrl(photo.storagePath);
        if (!mounted) return;
        for (final shot in _shots) {
          if (shot.photoId == photo.id) {
            shot.remoteUrl = url;
            break;
          }
        }
        setState(() {});
      } catch (_) {
        // La métadonnée locale reste visible; l'ouverture dira si le fichier
        // doit encore être téléchargé avec Internet.
      }
    }
  }

  Future<void> _openShot(_Shot shot) async {
    if (shot.bytes != null) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(_fr ? 'Photo de la remise' : 'Submission photo')),
          body: InteractiveViewer(
            minScale: 0.5,
            maxScale: 6,
            child: Center(child: Image.memory(shot.bytes!, fit: BoxFit.contain)),
          ),
        ),
      ));
      return;
    }
    final photoId = shot.photoId;
    final storagePath = shot.path;
    if (photoId == null || storagePath == null) return;
    final fileName = storagePath.split('/').last;
    final lower = fileName.toLowerCase();
    final mimeType = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
    try {
      final localPath = await CourseOfflineService().openExternalFile(
        userId: widget.profile.id,
        resourceId: 'evaluation-photo-' + photoId,
        courseId: 'evaluation-photos',
        fileName: fileName,
        mimeType: mimeType,
        signedUrlProvider: () => _service.photoUrl(storagePath),
      );
      if (!mounted) return;
      final resource = CourseResource(
        id: 'evaluation-photo-' + photoId,
        courseId: 'evaluation-photos',
        resourceType: 'image',
        storagePath: storagePath,
        fileName: fileName,
        titleFr: fileName,
        titleEn: fileName,
        mimeType: mimeType,
      );
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => OfflineResourceViewer(
          locale: widget.locale,
          userId: widget.profile.id,
          resource: resource,
          localPath: localPath,
        ),
      ));
    } catch (_) {
      if (mounted) _snack(_fr
          ? 'Ouvrez cette photo une première fois avec Internet pour la garder hors ligne.'
          : 'Open this photo online once to keep it available offline.');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _openPdf() async {
    if (!_started) return;
    final cacheId = 'evaluation-${_e.id}';
    final offline = CourseOfflineService();
    final path = _e.pdfPath;
    try {
      final cached = await offline.getLocal(widget.profile.id, cacheId);
      if (cached == null && (path == null || path.trim().isEmpty)) {
        _snack(_fr ? 'Le PDF de cette épreuve n’est pas disponible.' : 'The exam PDF is unavailable.');
        return;
      }
      final fileName = _e.pdfName?.trim().isNotEmpty == true
          ? _e.pdfName!.trim()
          : '${_e.title}.pdf';
      final localPath = await offline.openExternalFile(
        userId: widget.profile.id,
        resourceId: cacheId,
        courseId: 'evaluations',
        fileName: fileName,
        mimeType: 'application/pdf',
        signedUrlProvider: () {
          if (path == null || path.trim().isEmpty) {
            throw StateError('evaluation-paper-path-unavailable');
          }
          return _service.openPaperUrl(path);
        },
      );
      if (!mounted) return;
      final resource = CourseResource(
        id: cacheId,
        courseId: 'evaluations',
        resourceType: 'pdf',
        storagePath: path ?? '',
        fileName: fileName,
        titleFr: _e.title,
        titleEn: _e.title,
        mimeType: 'application/pdf',
      );
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OfflineResourceViewer(
            locale: widget.locale,
            userId: widget.profile.id,
            resource: resource,
            localPath: localPath,
          ),
        ),
      );
    } catch (error) {
      _snack(EvaluationService.friendlyError(error, fr: _fr));
    }
  }

  Future<void> _addPhotos(ImageSource source) async {
    if (_busy) return;
    List<XFile> files;
    try {
      if (source == ImageSource.camera) {
        final f = await _picker.pickImage(source: source, imageQuality: 80, maxWidth: 2400);
        files = f == null ? [] : [f];
      } else {
        files = await _picker.pickMultiImage(imageQuality: 80, maxWidth: 2400);
      }
    } catch (e) {
      _snack(EvaluationService.friendlyError(e, fr: _fr));
      return;
    }
    if (files.isEmpty) return;
    setState(() => _busy = true);
    try {
      var sub = _submission;
      if (sub == null) {
        final id = await _service.startSubmission(_e.id);
        sub = EvalSubmissionInfo(id: id, status: 'draft');
        _submission = sub;
      }
      for (final f in files) {
        final bytes = await f.readAsBytes();
        final dot = f.name.lastIndexOf('.');
        final shot = _Shot(bytes: bytes, ext: dot >= 0 ? f.name.substring(dot + 1) : 'jpg');
        setState(() => _shots.add(shot));
        await _upload(shot);
      }
    } catch (e) {
      _snack(EvaluationService.friendlyError(e, fr: _fr));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload(_Shot shot) async {
    setState(() {
      shot.state = 'uploading';
      shot.error = null;
    });
    try {
      final r = await _service.uploadPhoto(
        evaluationId: _e.id,
        bytes: shot.bytes!,
        extension: shot.ext,
        position: _shots.indexOf(shot) + 1,
      );
      shot.photoId = r.photoId;
      shot.path = r.path;
      shot.state = 'done';
    } catch (e) {
      shot.state = 'error';
      shot.error = EvaluationService.friendlyError(e, fr: _fr);
    }
    if (mounted) setState(() {});
  }

  Future<void> _remove(_Shot shot) async {
    if (shot.photoId != null && shot.path != null) {
      try {
        await _service.removePhoto(photoId: shot.photoId!, path: shot.path!);
      } catch (e) {
        _snack(EvaluationService.friendlyError(e, fr: _fr));
        return;
      }
    }
    setState(() => _shots.remove(shot));
  }

  Future<void> _send() async {
    if (_shots.isEmpty || _shots.any((s) => s.state != 'done')) {
      _snack(_fr
          ? 'Attendez la fin de l’envoi des photos ou relancez celles en erreur.'
          : 'Wait for the uploads to finish or retry failed photos.');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_fr ? 'Envoyer ma remise ?' : 'Send my submission?'),
        content: Text(_fr
            ? 'Après l’envoi, vous ne pourrez plus modifier vos ${_shots.length} photo(s).'
            : 'After sending, you cannot change your ${_shots.length} photo(s).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_fr ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_fr ? 'Envoyer' : 'Send')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _sending = true);
    try {
      final info = await _service.submit(_e.id);
      if (!mounted) return;
      setState(() => _submission = EvalSubmissionInfo(
            id: _submission?.id ?? '',
            status: 'submitted',
            submittedAt: info.submittedAt,
            isLate: info.isLate,
            lateMinutes: info.lateMinutes,
            photoCount: _shots.length,
          ));
      _snack(_fr ? 'Remise reçue.' : 'Submission received.');
    } catch (e) {
      _snack(EvaluationService.friendlyError(e, fr: _fr));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = _submission;
    final submitted = sub?.isSubmitted == true;
    return Scaffold(
      appBar: AppBar(title: Text(_e.title, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_e.subjectFor(_fr), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('${_fr ? 'Début' : 'Start'} : ${_fmt(_e.startsAt)}'),
          Text('${_fr ? 'Date limite' : 'Deadline'} : ${_fmt(_e.dueAt)}'),
          Text('${_fr ? 'Barème' : 'Out of'} : ${_e.maxScore.toStringAsFixed(_e.maxScore % 1 == 0 ? 0 : 1)}'),
          Text(_lateRule()),
          if ((_e.instructions ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_e.instructions!),
          ],
          const SizedBox(height: 12),
          if (!submitted)
            Card(
              child: ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(!_started
                    ? (_fr ? 'L’épreuve n’a pas commencé' : 'Not started yet')
                    : (_fr ? 'Temps restant' : 'Time left')),
                subtitle: Text(
                  !_started ? _fmt(_e.startsAt) : _remaining(_left, _fr),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _left.inMinutes < 10 && _started ? const Color(0xFFB91C1C) : null,
                  ),
                ),
              ),
            ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded),
              title: Text(_e.pdfName ?? (_fr ? 'Épreuve (PDF)' : 'Exam (PDF)')),
              subtitle: Text(_started
                  ? (_fr ? 'Ouvrir ou télécharger' : 'Open or download')
                  : (_fr ? 'Disponible au début de l’épreuve' : 'Available when the exam starts')),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: _started && _e.pdfPath != null ? _openPdf : null,
            ),
          ),
          const SizedBox(height: 8),
          if (submitted) _receipt(sub!) else ..._uploadSection(),
          if (_e.result != null) ..._result(_e.result!),
        ],
      ),
    );
  }

  String _lateRule() {
    switch (_e.latePolicy) {
      case 'accept_flagged':
        return _fr ? 'Remise tardive : acceptée, signalée en retard.' : 'Late: accepted, flagged as late.';
      case 'accept_penalty':
        return _fr
            ? 'Remise tardive : acceptée avec pénalité de ${_e.latePenaltyPercent.toStringAsFixed(0)} %.'
            : 'Late: accepted with a ${_e.latePenaltyPercent.toStringAsFixed(0)}% penalty.';
      default:
        return _fr
            ? 'Aucune remise après la date limite (tolérance d’envoi : ${_e.lateGraceMinutes} min si déjà commencé).'
            : 'No submission after the deadline (${_e.lateGraceMinutes} min grace if already started).';
    }
  }

  Widget _receipt(EvalSubmissionInfo sub) {
    return Card(
      color: const Color(0xFFECFDF5),
      child: ListTile(
        leading: const Icon(Icons.check_circle_rounded, color: Color(0xFF166534)),
        title: Text(_fr ? 'Remise reçue' : 'Submission received'),
        subtitle: Text([
          if (sub.submittedAt != null) '${_fr ? 'Reçue le' : 'Received'} ${_fmt(sub.submittedAt!)}',
          if (sub.isLate) (_fr ? 'En retard de ${sub.lateMinutes} min' : '${sub.lateMinutes} min late'),
          if (_e.result == null) (_fr ? 'La correction est en cours.' : 'Correction in progress.'),
        ].join('\n')),
      ),
    );
  }

  List<Widget> _uploadSection() {
    if (!_started) return const [];
    if (_closedForUpload && _shots.isEmpty) {
      return [
        Card(
          child: ListTile(
            leading: const Icon(Icons.lock_clock_rounded),
            title: Text(_fr ? 'Remise fermée' : 'Submission closed'),
            subtitle: Text(_fr ? 'La date limite est dépassée.' : 'The deadline has passed.'),
          ),
        ),
      ];
    }
    return [
      Text(_fr ? 'Mes photographies' : 'My photos', style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _addPhotos(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_rounded),
            label: Text(_fr ? 'Prendre une photo' : 'Take a photo'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _addPhotos(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_rounded),
            label: Text(_fr ? 'Galerie' : 'Gallery'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (_shots.isEmpty)
        Text(_fr
            ? 'Composez vos réponses sur papier, photographiez chaque page (bien éclairée, à plat), puis ajoutez les photos.'
            : 'Write your answers on paper, photograph each page (well lit, flat), then add the photos.'),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [for (final s in _shots) _thumb(s)],
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: (_sending || _busy || _shots.isEmpty) ? null : _send,
        icon: _sending
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.send_rounded),
        label: Text(_fr ? 'Envoyer ma remise' : 'Send my submission'),
      ),
    ];
  }

  Widget _thumb(_Shot s) {
    Widget image;
    if (s.bytes != null) {
      image = Image.memory(s.bytes!, fit: BoxFit.cover);
    } else if (s.remoteUrl != null) {
      image = Image.network(s.remoteUrl!, fit: BoxFit.cover);
    } else {
      image = const ColoredBox(color: Colors.black12);
    }
    return Stack(fit: StackFit.expand, children: [
      GestureDetector(onTap: () => _openShot(s), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: image)),
      if (s.state == 'uploading')
        const ColoredBox(color: Colors.black38, child: Center(child: CircularProgressIndicator())),
      if (s.state == 'error')
        ColoredBox(
          color: Colors.black54,
          child: Center(
            child: IconButton(
              tooltip: s.error,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              onPressed: () => _upload(s),
            ),
          ),
        ),
      Positioned(
        top: 0,
        right: 0,
        child: IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.cancel_rounded, color: Colors.white),
          onPressed: s.state == 'uploading' ? null : () => _remove(s),
        ),
      ),
    ]);
  }

  List<Widget> _result(EvalResult r) {
    String f(double? v) => v == null ? '-' : v.toStringAsFixed(2);
    return [
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${_fr ? 'Ma note' : 'My mark'} : ${f(r.finalScore)} / ${r.maxScore.toStringAsFixed(r.maxScore % 1 == 0 ? 0 : 1)}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            if (r.penaltyPercent > 0)
              Text(_fr
                  ? 'Pénalité de retard appliquée : ${r.penaltyPercent.toStringAsFixed(0)} %'
                  : 'Late penalty applied: ${r.penaltyPercent.toStringAsFixed(0)}%'),
            if ((r.comment ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(r.comment!),
            ],
            const Divider(height: 24),
            for (final q in r.questions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${q.label} — ${f(q.points)} / ${q.maxPoints.toStringAsFixed(q.maxPoints % 1 == 0 ? 0 : 1)}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  if ((q.feedback ?? '').isNotEmpty) Text(q.feedback!),
                ]),
              ),
          ]),
        ),
      ),
    ];
  }
}
