import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/services/admin_school_service.dart';
import '../../../core/services/exam_catalog_service.dart';
import '../../../core/services/past_paper_service.dart';
import '../../../models/exam_catalog.dart';
import '../../../models/past_paper.dart';
import '../../../models/school_class.dart';
import '../widgets/class_target_picker.dart';

class AdminPastPapersPage extends StatefulWidget {
  final Locale locale;
  const AdminPastPapersPage({super.key, required this.locale});

  @override
  State<AdminPastPapersPage> createState() => _AdminPastPapersPageState();
}

class _AdminPastPapersPageState extends State<AdminPastPapersPage> {
  final _service = PastPaperService();
  bool _loading = true;
  String? _error;
  List<PastPaper> _papers = const [];
  List<ExamDefinition> _exams = const [];
  List<SchoolClass> _classes = const [];
  Map<String, List<String>> _targets = const {};

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
      final papers = await _service.list(includeUnpublished: true);
      List<ExamDefinition> exams = const [];
      try {
        exams = await ExamCatalogService().getExams();
      } catch (_) {}
      List<SchoolClass> classes = const [];
      Map<String, List<String>> targets = const {};
      try {
        classes = (await AdminSchoolService().listClasses()).where((c) => c.isActive).toList(growable: false);
        targets = await _service.listTargets();
      } catch (_) {}
      if (!mounted) {
        return;
      }
      setState(() {
        _papers = papers;
        _exams = exams;
        _classes = classes;
        _targets = targets;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _fr ? 'Chargement impossible : $e' : 'Unable to load: $e';
        _loading = false;
      });
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  String _examName(String? id) {
    if (id == null) {
      return '';
    }
    for (final e in _exams) {
      if (e.id == id) {
        return e.labelFor(widget.locale.languageCode);
      }
    }
    return '';
  }

  Future<void> _add() async {
    final subjectFr = TextEditingController();
    final subjectEn = TextEditingController();
    final session = TextEditingController();
    final yearCtl = TextEditingController(text: '${DateTime.now().year - 1}');
    String? examId;
    String? subsystem;
    String kind = 'subject';
    PlatformFile? file;
    bool allClasses = true;
    Set<String> chosen = <String>{};

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(_fr ? 'Ajouter une annale' : 'Add a past paper'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: examId,
                decoration: InputDecoration(labelText: _fr ? 'Examen' : 'Exam'),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(_fr ? 'Non précisé' : 'Not specified')),
                  ..._exams.map((e) => DropdownMenuItem<String?>(value: e.id, child: Text(e.labelFor(widget.locale.languageCode), overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) => setLocal(() => examId = v),
              ),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: subsystem,
                decoration: InputDecoration(labelText: _fr ? 'Sous-système' : 'Subsystem'),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(_fr ? 'Tous' : 'All')),
                  DropdownMenuItem<String?>(value: 'francophone', child: Text(_fr ? 'Francophone' : 'Francophone')),
                  DropdownMenuItem<String?>(value: 'anglophone', child: Text(_fr ? 'Anglophone' : 'Anglophone')),
                ],
                onChanged: (v) => setLocal(() => subsystem = v),
              ),
              TextField(controller: yearCtl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _fr ? 'Année' : 'Year')),
              TextField(controller: session, decoration: InputDecoration(labelText: _fr ? 'Session (optionnel)' : 'Session (optional)')),
              TextField(controller: subjectFr, decoration: InputDecoration(labelText: _fr ? 'Matière (français)' : 'Subject (French)')),
              TextField(controller: subjectEn, decoration: InputDecoration(labelText: _fr ? 'Matière (anglais, optionnel)' : 'Subject (English, optional)')),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: kind,
                decoration: InputDecoration(labelText: _fr ? 'Type' : 'Type'),
                items: [
                  DropdownMenuItem(value: 'subject', child: Text(_fr ? 'Sujet' : 'Paper')),
                  DropdownMenuItem(value: 'correction', child: Text(_fr ? 'Corrigé' : 'Correction')),
                ],
                onChanged: (v) => setLocal(() => kind = v ?? 'subject'),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_fr ? 'Diffuser dans' : 'Send to', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 6),
              ClassTargetPicker(
                fr: _fr,
                classes: _classes,
                allClasses: allClasses,
                selected: chosen,
                onAllChanged: (v) => setLocal(() => allClasses = v),
                onSelectionChanged: (v) => setLocal(() => chosen = v),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    withData: true,
                    type: FileType.custom,
                    allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
                  );
                  if (result != null && result.files.isNotEmpty) {
                    setLocal(() => file = result.files.first);
                  }
                },
                icon: const Icon(Icons.attach_file),
                label: Text(file?.name ?? (_fr ? 'Choisir le fichier (PDF ou image)' : 'Choose file (PDF or image)'), overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_fr ? 'Annuler' : 'Cancel')),
            FilledButton(
              onPressed: () {
                final year = int.tryParse(yearCtl.text.trim());
                if (year == null || year < 1990 || year > 2100 || subjectFr.text.trim().isEmpty || file == null) {
                  _snack(_fr ? 'Renseignez l’année, la matière et le fichier.' : 'Enter the year, subject and file.');
                  return;
                }
                if (!allClasses && chosen.isEmpty) {
                  _snack(_fr ? 'Choisissez au moins une salle.' : 'Choose at least one classroom.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(_fr ? 'Publier' : 'Publish'),
            ),
          ],
        ),
      ),
    );

    final picked = file;
    final year = int.tryParse(yearCtl.text.trim());
    final fr = subjectFr.text;
    final en = subjectEn.text;
    final sess = session.text;
    final targetIds = allClasses ? <String>[] : chosen.toList(growable: false);
    subjectFr.dispose();
    subjectEn.dispose();
    session.dispose();
    yearCtl.dispose();
    if (ok != true || picked == null || year == null) {
      return;
    }

    try {
      await _service.create(
        file: picked,
        year: year,
        subjectFr: fr,
        subjectEn: en,
        kind: kind,
        examId: examId,
        subsystem: subsystem,
        session: sess,
        classIds: targetIds,
      );
      if (!mounted) {
        return;
      }
      _snack(_fr ? 'Annale publiée.' : 'Past paper published.');
      await _load();
    } catch (e) {
      if (mounted) {
        _snack(_fr ? 'Échec de l’envoi : $e' : 'Upload failed: $e');
      }
    }
  }

  Future<void> _delete(PastPaper paper) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_fr ? 'Supprimer cette annale ?' : 'Delete this paper?'),
        content: Text(paper.subjectFor(widget.locale.languageCode)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_fr ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_fr ? 'Supprimer' : 'Delete')),
        ],
      ),
    );
    if (confirm != true) {
      return;
    }
    try {
      await _service.delete(paper);
      if (mounted) {
        await _load();
      }
    } catch (e) {
      if (mounted) {
        _snack(_fr ? 'Suppression impossible : $e' : 'Delete failed: $e');
      }
    }
  }

  String _audienceLabel(PastPaper paper) {
    final ids = _targets[paper.id];
    if (ids == null || ids.isEmpty) {
      return _fr ? 'toutes les salles' : 'all classrooms';
    }
    final names = _classes.where((c) => ids.contains(c.id)).map((c) => c.displayName).toList();
    if (names.isEmpty) {
      return _fr ? '${ids.length} salle(s)' : '${ids.length} classroom(s)';
    }
    return names.length <= 2 ? names.join(', ') : (_fr ? '${names.length} salles' : '${names.length} classrooms');
  }

  Future<void> _editAudience(PastPaper paper) async {
    final current = _targets[paper.id] ?? const <String>[];
    bool allClasses = current.isEmpty;
    Set<String> chosen = current.toSet();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(_fr ? 'Salles de diffusion' : 'Distribution'),
          content: SingleChildScrollView(
            child: ClassTargetPicker(
              fr: _fr,
              classes: _classes,
              allClasses: allClasses,
              selected: chosen,
              onAllChanged: (v) => setLocal(() => allClasses = v),
              onSelectionChanged: (v) => setLocal(() => chosen = v),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_fr ? 'Annuler' : 'Cancel')),
            FilledButton(
              onPressed: () {
                if (!allClasses && chosen.isEmpty) {
                  _snack(_fr ? 'Choisissez au moins une salle.' : 'Choose at least one classroom.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(_fr ? 'Enregistrer' : 'Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) {
      return;
    }
    try {
      await _service.setTargets(paper.id, allClasses ? const <String>[] : chosen.toList(growable: false));
      if (mounted) {
        await _load();
      }
    } catch (e) {
      if (mounted) {
        _snack(_fr ? 'Modification impossible : $e' : 'Update failed: $e');
      }
    }
  }

  Future<void> _toggle(PastPaper paper) async {
    try {
      await _service.setPublished(paper.id, !paper.isPublished);
      if (mounted) {
        await _load();
      }
    } catch (e) {
      if (mounted) {
        _snack(_fr ? 'Modification impossible : $e' : 'Update failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_fr ? 'Annales d’examens' : 'Past exam papers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(_fr ? 'Ajouter' : 'Add'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : _papers.isEmpty
                  ? Center(child: Text(_fr ? 'Aucune annale.' : 'No past papers.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        itemCount: _papers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final p = _papers[i];
                          final exam = _examName(p.examId);
                          return Card(
                            child: ListTile(
                              leading: Icon(p.isCorrection ? Icons.task_alt : Icons.description_outlined),
                              title: Text(p.subjectFor(widget.locale.languageCode), style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text([if (exam.isNotEmpty) exam, '${p.year}', _audienceLabel(p), p.isPublished ? (_fr ? 'publiée' : 'published') : (_fr ? 'masquée' : 'hidden')].join(' · ')),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'toggle') {
                                    _toggle(p);
                                  } else if (v == 'audience') {
                                    _editAudience(p);
                                  } else {
                                    _delete(p);
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(value: 'toggle', child: Text(p.isPublished ? (_fr ? 'Masquer' : 'Hide') : (_fr ? 'Publier' : 'Publish'))),
                                  PopupMenuItem(value: 'audience', child: Text(_fr ? 'Salles de diffusion' : 'Distribution')),
                                  PopupMenuItem(value: 'delete', child: Text(_fr ? 'Supprimer' : 'Delete')),
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
