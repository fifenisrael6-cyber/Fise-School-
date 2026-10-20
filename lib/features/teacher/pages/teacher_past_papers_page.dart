import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/offline/json_cache.dart';
import '../../../core/services/exam_catalog_service.dart';
import '../../../core/services/past_paper_service.dart';
import '../../../core/services/photo_service.dart';
import '../../../models/exam_catalog.dart';
import '../../../models/past_paper.dart';
import '../../../models/user_profile.dart';
import '../../student/pages/past_paper_viewer_page.dart';

/// Teacher upload and management of past exam papers, distributed to candidates of the selected exam.
class TeacherPastPapersPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final List<PickedAttachment> initialSharedAttachments;

  const TeacherPastPapersPage({
    super.key,
    required this.locale,
    required this.profile,
    this.initialSharedAttachments = const [],
  });

  @override
  State<TeacherPastPapersPage> createState() => _TeacherPastPapersPageState();
}

class _TeacherPastPapersPageState extends State<TeacherPastPapersPage> {
  final _papers = PastPaperService();
  bool _loading = true;
  String? _error;
  List<ExamDefinition> _exams = [];
  List<PastPaper> _items = [];

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.initialSharedAttachments.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _add(initialAttachment: widget.initialSharedAttachments.first);
      });
    }
  }

  String get _papersCacheKey => 'teacher_past_papers_${widget.profile.id}';

  Map<String, dynamic> _paperToCache(PastPaper paper) => {
    'id': paper.id,
    'exam_id': paper.examId,
    'subsystem': paper.subsystem,
    'exam_year': paper.year,
    'session_label': paper.session,
    'subject_fr': paper.subjectFr,
    'subject_en': paper.subjectEn,
    'kind': paper.kind,
    'file_path': paper.filePath,
    'file_name': paper.fileName,
    'is_published': paper.isPublished,
  };

  List<PastPaper> _decodeCachedPapers(Object? raw) {
    if (raw is! List) return const <PastPaper>[];
    return raw.whereType<Map>().map(
      (row) => PastPaper.fromMap(Map<String, dynamic>.from(row)),
    ).toList(growable: false);
  }

  Future<void> _load() async {
    final cached = await JsonCache.instance.read(_papersCacheKey);
    final hasCached = cached is List;
    if (mounted) {
      setState(() {
        if (hasCached) _items = _decodeCachedPapers(cached);
        _loading = !hasCached;
        _error = null;
      });
    }
    try {
      List<ExamDefinition> exams = const [];
      try {
        exams = await ExamCatalogService().getExams().timeout(const Duration(seconds: 8));
      } catch (_) {
        // Exam catalog is optional; cached paper metadata remains usable offline.
      }
      final papers = await _papers.list(includeUnpublished: true)
          .timeout(const Duration(seconds: 12));
      await JsonCache.instance.write(
        _papersCacheKey,
        papers.map(_paperToCache).toList(growable: false),
      );
      if (!mounted) return;
      setState(() {
        _exams = exams;
        _items = papers;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = hasCached ? null : (_fr ? 'Chargement impossible : $e' : 'Unable to load: $e');
        _loading = false;
      });
    }
  }

  Future<void> _add({PickedAttachment? initialAttachment}) async {
    final subjectFr = TextEditingController();
    final subjectEn = TextEditingController();
    final yearCtl = TextEditingController(text: '${DateTime.now().year - 1}');
    final sessionCtl = TextEditingController();
    String? examId;
    String kind = 'subject';
    PlatformFile? file = initialAttachment == null
        ? null
        : PlatformFile(
            name: initialAttachment.name,
            size: initialAttachment.bytes.length,
            bytes: initialAttachment.bytes,
          );
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(_fr ? 'Envoyer une épreuve' : 'Upload an exam paper'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: examId,
                    decoration: InputDecoration(labelText: _fr ? 'Examen (obligatoire)' : 'Exam (required)'),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text(_fr ? 'Autre / non précisé' : 'Other / not specified')),
                      ..._exams.map((e) => DropdownMenuItem<String?>(value: e.id, child: Text(e.labelFor(widget.locale.languageCode), overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (v) => refresh(() => examId = v),
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: yearCtl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _fr ? 'Année de l’épreuve' : 'Exam year')),
                  TextField(controller: sessionCtl, decoration: InputDecoration(labelText: _fr ? 'Session (facultatif)' : 'Session (optional)')),
                  TextField(controller: subjectFr, decoration: InputDecoration(labelText: 'Matière (français)')),
                  TextField(controller: subjectEn, decoration: InputDecoration(labelText: 'Subject (English)')),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: InputDecoration(labelText: _fr ? 'Type de document' : 'Document type'),
                    items: [
                      DropdownMenuItem(value: 'subject', child: Text(_fr ? 'Épreuve / sujet' : 'Exam paper')),
                      DropdownMenuItem(value: 'correction', child: Text(_fr ? 'Corrigé' : 'Answer key')),
                    ],
                    onChanged: (v) => refresh(() => kind = v ?? 'subject'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
                        withData: true,
                      );
                      if (result != null && result.files.isNotEmpty) {
                        refresh(() => file = result.files.first);
                      }
                    },
                    icon: const Icon(Icons.attach_file),
                    label: Text(file?.name ?? (_fr ? 'Choisir un PDF ou une image' : 'Choose a PDF or image')),
                  ),
                  Text(_fr ? 'Tous les élèves préparant cet examen pourront consulter cette annale.' : 'All students preparing this exam will be able to access this paper.'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_fr ? 'Annuler' : 'Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext,
                file != null && file!.bytes != null && examId != null &&
                yearCtl.text.trim().isNotEmpty && subjectFr.text.trim().isNotEmpty),
              child: Text(_fr ? 'Envoyer' : 'Upload'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || file == null) return;
    final year = int.tryParse(yearCtl.text.trim());
    if (year == null || year < 1990 || year > 2100) {
      _message(_fr ? 'Année invalide.' : 'Invalid year.');
      return;
    }
    try {
      await _papers.create(
        file: file!,
        year: year,
        subjectFr: subjectFr.text.trim(),
        subjectEn: subjectEn.text.trim(),
        kind: kind,
        examId: examId,
        subsystem: widget.profile.subsystem,
        session: sessionCtl.text.trim(),
      );
      if (!mounted) return;
      _message(_fr ? 'Annale publiée pour les candidats de l’examen choisi.' : 'Past paper published for candidates of the selected exam.');
      await _load();
    } catch (e) {
      _message('${_fr ? 'Échec de l’envoi' : 'Upload failed'}: $e');
    }
  }

  Future<void> _edit(PastPaper paper) async {
    final subjectFr = TextEditingController(text: paper.subjectFr);
    final subjectEn = TextEditingController(text: paper.subjectEn);
    final yearCtl = TextEditingController(text: paper.year.toString());
    final sessionCtl = TextEditingController(text: paper.session ?? '');
    String? examId = paper.examId;
    String kind = paper.kind;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(_fr ? 'Modifier l’annale' : 'Edit past paper'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: examId,
                    decoration: InputDecoration(labelText: _fr ? 'Examen' : 'Exam'),
                    items: _exams.map((e) => DropdownMenuItem<String?>(
                      value: e.id,
                      child: Text(e.labelFor(widget.locale.languageCode), overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (value) => refresh(() => examId = value),
                  ),
                  TextField(
                    controller: yearCtl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: _fr ? 'Année' : 'Year'),
                  ),
                  TextField(
                    controller: sessionCtl,
                    decoration: InputDecoration(labelText: _fr ? 'Session' : 'Session'),
                  ),
                  TextField(controller: subjectFr, decoration: const InputDecoration(labelText: 'Matière (français)')),
                  TextField(controller: subjectEn, decoration: const InputDecoration(labelText: 'Subject (English)')),
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: InputDecoration(labelText: _fr ? 'Type' : 'Type'),
                    items: [
                      DropdownMenuItem(value: 'subject', child: Text(_fr ? 'Épreuve / sujet' : 'Exam paper')),
                      DropdownMenuItem(value: 'correction', child: Text(_fr ? 'Corrigé' : 'Answer key')),
                    ],
                    onChanged: (value) => refresh(() => kind = value ?? 'subject'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_fr ? 'Annuler' : 'Cancel'),
            ),
            FilledButton(
              onPressed: examId == null || yearCtl.text.trim().isEmpty || subjectFr.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text(_fr ? 'Enregistrer' : 'Save'),
            ),
          ],
        ),
      ),
    );

    final subjectFrValue = subjectFr.text.trim();
    final subjectEnValue = subjectEn.text.trim();
    final sessionValue = sessionCtl.text.trim();
    final year = int.tryParse(yearCtl.text.trim());
    final subsystem = widget.profile.subsystem ?? paper.subsystem;
    subjectFr.dispose();
    subjectEn.dispose();
    yearCtl.dispose();
    sessionCtl.dispose();

    if (accepted != true) return;
    if (examId == null || subsystem == null || year == null || year < 1990 || year > 2100) {
      _message(_fr
          ? 'Examen, sous-système ou année invalide. Vérifiez votre profil enseignant.'
          : 'Invalid exam, subsystem, or year. Check your teacher profile.');
      return;
    }

    try {
      await _papers.updateMetadata(
        id: paper.id,
        examId: examId!,
        subsystem: subsystem,
        year: year,
        subjectFr: subjectFrValue,
        subjectEn: subjectEnValue,
        kind: kind,
        session: sessionValue,
      );
      _message(_fr ? 'Annale modifiée.' : 'Past paper updated.');
      await _load();
    } catch (error) {
      _message('${_fr ? 'Modification impossible' : 'Update failed'}: $error');
    }
  }

  Future<void> _delete(PastPaper paper) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_fr ? 'Supprimer cette annale ?' : 'Delete this past paper?'),
        content: Text(_fr
            ? 'Le fichier et son entrée seront supprimés.'
            : 'The file and its record will be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_fr ? 'Annuler' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_fr ? 'Supprimer' : 'Delete'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await _papers.delete(paper);
      _message(_fr ? 'Annale supprimée.' : 'Past paper deleted.');
      await _load();
    } catch (error) {
      _message('${_fr ? 'Suppression impossible' : 'Delete failed'}: $error');
    }
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  String _examName(PastPaper p) {
    for (final exam in _exams) {
      if (exam.id == p.examId) return exam.labelFor(widget.locale.languageCode);
    }
    return p.examId == null ? (_fr ? 'Examen non précisé' : 'Exam not specified') : '';
  }

  Future<void> _openPaper(PastPaper paper) async {
    final name = paper.fileName.toLowerCase();
    final isPdf = name.endsWith('.pdf');
    final isImage = ['.png', '.jpg', '.jpeg', '.webp'].any(name.endsWith);
    if (!isPdf && !isImage) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_fr ? 'Format non pris en charge.' : 'Unsupported file format.')),
      );
      return;
    }
    try {
      final localPath = await _papers.download(paper);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PastPaperViewerPage(
            locale: widget.locale,
            localPath: localPath,
            fileName: paper.fileName,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_fr ? 'Impossible d’ouvrir ce fichier.' : 'Unable to open this file.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_fr ? 'Annales d’examens' : 'Past exam papers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(
          initialAttachment: widget.initialSharedAttachments.isEmpty
              ? null
              : widget.initialSharedAttachments.first,
        ),
        icon: const Icon(Icons.upload_file_rounded),
        label: Text(_fr ? 'Envoyer une épreuve' : 'Upload paper'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(children: [const SizedBox(height: 100), Icon(Icons.history_edu_outlined, size: 64, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 16), Center(child: Text(_fr ? 'Aucune épreuve envoyée pour le moment.' : 'No exam papers uploaded yet.'))])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                          itemCount: _items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final paper = _items[index];
                            return Card(child: ListTile(
                              onTap: () => _openPaper(paper),
                               leading: Icon(paper.kind == 'correction' ? Icons.fact_check_outlined : Icons.picture_as_pdf_outlined),
                              title: Text(paper.subjectFor(widget.locale.languageCode)),
                              subtitle: Text('${_examName(paper)} • ${paper.year} • ${paper.fileName}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(paper.isPublished ? Icons.check_circle_outline : Icons.visibility_off_outlined),
                                  PopupMenuButton<String>(
                                    tooltip: _fr ? 'Gérer l’annale' : 'Manage past paper',
                                    onSelected: (value) {
                                      if (value == 'edit') _edit(paper);
                                      if (value == 'delete') _delete(paper);
                                    },
                                    itemBuilder: (_) => [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text(_fr ? 'Modifier' : 'Edit'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text(_fr ? 'Supprimer' : 'Delete'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ));
                          },
                        ),
                ),
    );
  }
}
