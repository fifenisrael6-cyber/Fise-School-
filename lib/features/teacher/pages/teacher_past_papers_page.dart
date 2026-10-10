import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/services/exam_catalog_service.dart';
import '../../../core/services/past_paper_service.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../models/exam_catalog.dart';
import '../../../models/past_paper.dart';
import '../../../models/school_class.dart';
import '../../../models/user_profile.dart';

/// Teacher-only upload and management of past exam papers, scoped to assigned rooms.
class TeacherPastPapersPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const TeacherPastPapersPage({
    super.key,
    required this.locale,
    required this.profile,
  });

  @override
  State<TeacherPastPapersPage> createState() => _TeacherPastPapersPageState();
}

class _TeacherPastPapersPageState extends State<TeacherPastPapersPage> {
  final _papers = PastPaperService();
  final _courses = CourseService();
  bool _loading = true;
  String? _error;
  List<SchoolClass> _classes = [];
  List<ExamDefinition> _exams = [];
  List<PastPaper> _items = [];

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
      final classes = (await _courses.listTeacherClasses(widget.profile.id))
          .where((c) => c.isActive)
          .toList(growable: false);
      List<ExamDefinition> exams = const [];
      try {
        exams = await ExamCatalogService().getExams();
      } catch (_) {
        // Exam catalog is optional; papers can still be uploaded without it.
      }
      final papers = await _papers.list(includeUnpublished: true);
      if (!mounted) return;
      setState(() {
        _classes = classes;
        _exams = exams;
        _items = papers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _fr ? 'Chargement impossible : $e' : 'Unable to load: $e';
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    if (_classes.isEmpty) {
      _message(_fr ? 'Aucune salle ne vous est affectée.' : 'No classroom is assigned to you.');
      return;
    }
    final subjectFr = TextEditingController();
    final subjectEn = TextEditingController();
    final yearCtl = TextEditingController(text: '${DateTime.now().year - 1}');
    final sessionCtl = TextEditingController();
    String? examId;
    String kind = 'subject';
    PlatformFile? file;
    final selected = <String>{};
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
                    decoration: InputDecoration(labelText: _fr ? 'Examen' : 'Exam'),
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
                  Align(alignment: Alignment.centerLeft, child: Text(_fr ? 'Salles destinataires (obligatoire)' : 'Recipient classrooms (required)', style: const TextStyle(fontWeight: FontWeight.w700))),
                  ..._classes.map((room) => CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: selected.contains(room.id),
                    title: Text(room.displayName),
                    onChanged: (v) => refresh(() {
                      if (v == true) { selected.add(room.id); } else { selected.remove(room.id); }
                    }),
                  )),
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
                  Text(_fr ? 'Le document sera publié uniquement dans les salles sélectionnées.' : 'The document will be published only to the selected classrooms.'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_fr ? 'Annuler' : 'Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext,
                file != null && file!.bytes != null && yearCtl.text.trim().isNotEmpty &&
                subjectFr.text.trim().isNotEmpty && selected.isNotEmpty),
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
      final subsystemValues = _classes.where((c) => selected.contains(c.id)).map((c) => c.subsystem.name).toSet();
      if (subsystemValues.length != 1) {
        _message(_fr ? 'Sélectionnez des salles d’un seul sous-système par épreuve.' : 'Select classrooms from only one subsystem per paper.');
        return;
      }
      await _papers.create(
        file: file!,
        year: year,
        subjectFr: subjectFr.text.trim(),
        subjectEn: subjectEn.text.trim(),
        kind: kind,
        examId: examId,
        subsystem: subsystemValues.first,
        session: sessionCtl.text.trim(),
        classIds: selected.toList(growable: false),
      );
      if (!mounted) return;
      _message(_fr ? 'Épreuve envoyée aux salles sélectionnées.' : 'Exam paper sent to selected classrooms.');
      await _load();
    } catch (e) {
      _message('${_fr ? 'Échec de l’envoi' : 'Upload failed'}: $e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_fr ? 'Annales d’examens' : 'Past exam papers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
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
                              leading: Icon(paper.kind == 'correction' ? Icons.fact_check_outlined : Icons.picture_as_pdf_outlined),
                              title: Text(paper.subjectFor(widget.locale.languageCode)),
                              subtitle: Text('${_examName(paper)} • ${paper.year} • ${paper.fileName}'),
                              trailing: Icon(paper.isPublished ? Icons.check_circle_outline : Icons.visibility_off_outlined),
                            ));
                          },
                        ),
                ),
    );
  }
}
