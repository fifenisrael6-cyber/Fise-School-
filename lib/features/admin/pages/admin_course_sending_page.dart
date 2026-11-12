import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/pedagogy_service.dart';
import 'course_notebook_editor_page.dart';

/// Espace dédié à l'envoi de cours par l'administrateur.
/// Un cours distinct est enregistré pour chaque salle et chaque chapitre,
/// conformément aux règles de visibilité élèves de Supabase.
class AdminCourseSendingPage extends StatefulWidget {
  final Locale locale;

  const AdminCourseSendingPage({super.key, required this.locale});

  @override
  State<AdminCourseSendingPage> createState() => _AdminCourseSendingPageState();
}

class _AdminCourseSendingPageState extends State<AdminCourseSendingPage> {
  final SupabaseClient _db = Supabase.instance.client;
  final CourseService _courses = CourseService();
  final ResourceService _resources = ResourceService();


  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _curricula = [];
  List<Map<String, dynamic>> _chapters = [];
  List<Map<String, dynamic>> _compatibleClasses = [];
  List<Map<String, dynamic>> _courseRows = [];

  String? _referenceClassId;
  String? _subjectId;
  String? _curriculumId;
  final Set<String> _targetClassIds = {};
  final Set<String> _chapterIds = {};

  bool _loading = true;
  bool _loadingChoices = false;
  bool _saving = false;
  bool _publish = true;
  String _filter = 'all';
  String? _error;

  bool get _fr => widget.locale.languageCode == 'fr';
  String _t(String fr, String en) => _fr ? fr : en;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadPage() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final classes = List<Map<String, dynamic>>.from(
        await _db
            .from('school_classes')
            .select('id,display_name,name,subsystem,sector,exam_level_id,series_id,specialty_id')
            .eq('is_active', true)
            .order('display_name'),
      );
      final courses = List<Map<String, dynamic>>.from(
        await _db
            .from('courses')
            .select('id,title_fr,title_en,description_fr,description_en,content_fr,content_en,status,created_at,class_id,subject_id,curriculum_id,chapter_id,teacher_id,smart_lesson_enabled,minimum_exercise_score,pages_json,school_classes(display_name,name),subjects(name_fr,name_en)')
            .order('updated_at', ascending: false),
      );
      if (!mounted) return;
      setState(() {
        _classes = classes;
        _courseRows = courses;
        _loading = false;
      });
      if (_referenceClassId == null && classes.isNotEmpty) {
        await _onReferenceClassChanged(classes.first['id'].toString());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Map<String, dynamic>? get _referenceClass {
    for (final item in _classes) {
      if (item['id']?.toString() == _referenceClassId) return item;
    }
    return null;
  }

  String _className(Map<String, dynamic> item) =>
      (item['display_name'] ?? item['name'] ?? '').toString();

  String _subjectName(Map<String, dynamic> item) {
    final fr = (item['name_fr'] ?? '').toString();
    final en = (item['name_en'] ?? '').toString();
    return _fr ? (fr.isNotEmpty ? fr : en) : (en.isNotEmpty ? en : fr);
  }

  String _curriculumName(Map<String, dynamic> item) {
    final fr = (item['title_fr'] ?? '').toString();
    final en = (item['title_en'] ?? '').toString();
    return _fr ? (fr.isNotEmpty ? fr : en) : (en.isNotEmpty ? en : fr);
  }

  String _chapterName(Map<String, dynamic> item) {
    final fr = (item['title_fr'] ?? '').toString();
    final en = (item['title_en'] ?? '').toString();
    return _fr ? (fr.isNotEmpty ? fr : en) : (en.isNotEmpty ? en : fr);
  }

  bool _sameAcademicContext(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    return a['subsystem'] == b['subsystem'] &&
        a['sector'] == b['sector'] &&
        a['exam_level_id'] == b['exam_level_id'] &&
        a['series_id'] == b['series_id'] &&
        a['specialty_id'] == b['specialty_id'];
  }

  Future<void> _onReferenceClassChanged(String? classId) async {
    if (classId == null) return;
    final selected = _classes.where((c) => c['id'].toString() == classId);
    if (selected.isEmpty) return;

    setState(() {
      _referenceClassId = classId;
      _subjectId = null;
      _curriculumId = null;
      _subjects = [];
      _curricula = [];
      _chapters = [];
      _compatibleClasses = [];
      _targetClassIds
        ..clear()
        ..add(classId);
      _chapterIds.clear();
      _loadingChoices = true;
    });

    try {
      final rows = await _db
          .from('class_subjects')
          .select('subject_id,subjects(id,name_fr,name_en,code)')
          .eq('class_id', classId)
          .eq('is_active', true)
          .order('position');
      final subjects = <Map<String, dynamic>>[];
      for (final row in rows) {
        final raw = row['subjects'];
        if (raw is Map) subjects.add(Map<String, dynamic>.from(raw));
      }
      if (!mounted) return;
      setState(() => _subjects = subjects);
      if (subjects.isNotEmpty) {
        await _onSubjectChanged(subjects.first['id']?.toString());
      } else {
        setState(() => _loadingChoices = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingChoices = false);
        _showMessage(_t('Chargement des matières impossible : ', 'Unable to load subjects: ') + e.toString());
      }
    }
  }

  Future<void> _onSubjectChanged(String? subjectId) async {
    final reference = _referenceClass;
    if (subjectId == null || reference == null) return;
    setState(() {
      _subjectId = subjectId;
      _curriculumId = null;
      _curricula = [];
      _chapters = [];
      _compatibleClasses = [];
      _chapterIds.clear();
      _targetClassIds
        ..clear()
        ..add(_referenceClassId!);
      _loadingChoices = true;
    });

    try {
      final rawCurricula = await _db
          .from('curricula')
          .select('id,title_fr,title_en,is_catalog_container,exam_level_id,series_id,specialty_id')
          .eq('subject_id', subjectId)
          .eq('subsystem', reference['subsystem'])
          .eq('sector', reference['sector'])
          .eq('is_active', true)
          .order('title_fr');
      var curricula = List<Map<String, dynamic>>.from(rawCurricula)
          .where((item) =>
              item['exam_level_id'] == reference['exam_level_id'] &&
              item['series_id'] == reference['series_id'] &&
              item['specialty_id'] == reference['specialty_id'])
          .toList();
      final containers = curricula
          .where((item) => item['is_catalog_container'] == true)
          .toList();
      if (containers.isNotEmpty) curricula = containers;

      final assignedRows = await _db
          .from('class_subjects')
          .select('class_id')
          .eq('subject_id', subjectId)
          .eq('is_active', true);
      final assignedIds = assignedRows
          .map((row) => row['class_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final compatible = _classes
          .where((item) =>
              assignedIds.contains(item['id']?.toString()) &&
              _sameAcademicContext(item, reference))
          .toList();

      if (!mounted) return;
      setState(() {
        _curricula = curricula;
        _compatibleClasses = compatible;
        _targetClassIds
          ..clear()
          ..add(_referenceClassId!);
        _loadingChoices = false;
      });
      if (curricula.isNotEmpty) {
        await _onCurriculumChanged(curricula.first['id']?.toString());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingChoices = false);
      _showMessage(_t('Chargement du programme impossible : ', 'Unable to load curriculum: ') + e.toString());
    }
  }

  Future<void> _onCurriculumChanged(String? curriculumId) async {
    if (curriculumId == null) return;
    setState(() {
      _curriculumId = curriculumId;
      _chapters = [];
      _chapterIds.clear();
      _loadingChoices = true;
    });
    try {
      final rows = await _db
          .from('course_chapters')
          .select('id,title_fr,title_en,position')
          .eq('curriculum_id', curriculumId)
          .eq('is_active', true)
          .order('position');
      final chapters = List<Map<String, dynamic>>.from(rows);
      if (!mounted) return;
      setState(() {
        _chapters = chapters;
        if (chapters.isNotEmpty) {
          _chapterIds.add(chapters.first['id'].toString());
        }
        _loadingChoices = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingChoices = false);
      _showMessage(_t('Chargement des chapitres impossible : ', 'Unable to load chapters: ') + e.toString());
    }
  }

  Future<void> _openNotebookEditor() async {
    if (_chapterIds.isEmpty) {
      _showMessage(_t('Sélectionnez au moins un chapitre.', 'Select at least one chapter.'));
      return;
    }
    final selected = _chapters.where((item) => _chapterIds.contains(item['id']?.toString())).toList();
    if (selected.isEmpty) return;
    final chapter = selected.first;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CourseNotebookEditorPage(
          locale: widget.locale,
          chapterId: chapter['id'].toString(),
          courseContext: {
            'class_ids': _targetClassIds.toList(growable: false),
            'subject_id': _subjectId,
            'teacher_id': _db.auth.currentUser?.id,
            'curriculum_id': _curriculumId,
            'chapter_id': chapter['id'].toString(),
            'publish': _publish,
          },
        ),
      ),
    );
    if (saved == true && mounted) {
      await _loadCourses();
      _showMessage(_t('Cahier enregistré dans le chapitre sélectionné.', 'Notebook saved in the selected chapter.'));
    }
  }

  Future<void> _loadCourses() async {
    final rows = await _db
        .from('courses')
        .select('id,title_fr,title_en,description_fr,description_en,content_fr,content_en,status,created_at,class_id,subject_id,curriculum_id,chapter_id,teacher_id,smart_lesson_enabled,minimum_exercise_score,pages_json,school_classes(display_name,name),subjects(name_fr,name_en)')
        .order('updated_at', ascending: false);
    if (!mounted) return;
    setState(() => _courseRows = List<Map<String, dynamic>>.from(rows));
  }

  Future<void> _deleteCourse(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Supprimer ce cours ?', 'Delete this course?')),
        content: Text(_t(
          'Le cours, ses documents et ses leçons associées seront supprimés. Cette action est définitive.',
          'The course, its files and associated lessons will be deleted. This action cannot be undone.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_t('Annuler', 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('Supprimer', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final resources = await _resources.listForCourse(row['id'].toString());
      for (final resource in resources) {
        await _resources.deleteResource(resource);
      }
      await _courses.deleteCourse(row['id'].toString());
      await _loadCourses();
      _showMessage(_t('Cours supprimé.', 'Course deleted.'));
    } catch (e) {
      _showMessage(_t('Suppression impossible : ', 'Unable to delete course: ') + e.toString());
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildSendingForm() {
    final reference = _referenceClass;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTitle(
              _t('1. Choisir le programme', '1. Choose the programme'),
              _t('La salle de référence détermine les matières et le programme compatibles.', 'The reference classroom determines compatible subjects and curriculum.'),
            ),
            DropdownButtonFormField<String>(
              key: ValueKey(_referenceClassId),
              initialValue: _referenceClassId,
              isExpanded: true,
              decoration: InputDecoration(labelText: _t('Salle de référence', 'Reference classroom')),
              items: _classes.map((item) => DropdownMenuItem<String>(
                value: item['id'].toString(),
                child: Text(_className(item), overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: _saving ? null : _onReferenceClassChanged,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(_subjectId),
              initialValue: _subjectId,
              isExpanded: true,
              decoration: InputDecoration(labelText: _t('Matière', 'Subject')),
              items: _subjects.map((item) => DropdownMenuItem<String>(
                value: item['id'].toString(),
                child: Text(_subjectName(item), overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: _saving ? null : _onSubjectChanged,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(_curriculumId),
              initialValue: _curriculumId,
              isExpanded: true,
              decoration: InputDecoration(labelText: _t('Programme', 'Curriculum')),
              items: _curricula.map((item) => DropdownMenuItem<String>(
                value: item['id'].toString(),
                child: Text(_curriculumName(item), overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: _saving ? null : _onCurriculumChanged,
            ),
            if (_loadingChoices) const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
            const SizedBox(height: 16),
            _sectionTitle(
              _t('2. Choisir les chapitres', '2. Choose chapters'),
              _t('Plusieurs chapitres peuvent recevoir le même contenu.', 'You can send the same content to several chapters.'),
            ),
            if (_chapters.isEmpty)
              Text(_t('Aucun chapitre actif dans ce programme.', 'No active chapters in this curriculum.'))
            else
              ..._chapters.map((chapter) {
                final id = chapter['id'].toString();
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _chapterIds.contains(id),
                  title: Text(_chapterName(chapter)),
                  onChanged: _saving ? null : (checked) {
                    setState(() {
                      if (checked == true) {
                        _chapterIds.add(id);
                      } else {
                        _chapterIds.remove(id);
                      }
                    });
                  },
                );
              }),
            const Divider(height: 28),
            _sectionTitle(
              _t('3. Choisir les salles destinataires', '3. Choose target classrooms'),
              _t('Seules les salles du même programme et auxquelles la matière est affectée sont proposées.', 'Only classrooms with the same curriculum context and assigned subject are listed.'),
            ),
            if (_compatibleClasses.isEmpty)
              Text(_t('Aucune salle compatible trouvée.', 'No compatible classroom found.'))
            else
              ..._compatibleClasses.map((item) {
                final id = item['id'].toString();
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _targetClassIds.contains(id),
                  title: Text(_className(item)),
                  onChanged: _saving ? null : (checked) {
                    setState(() {
                      if (checked == true) {
                        _targetClassIds.add(id);
                      } else {
                        _targetClassIds.remove(id);
                      }
                    });
                  },
                );
              }),
            const Divider(height: 28),
            _sectionTitle(
              _t('4. Rédiger le cours', '4. Write the course'),
              _t('Le texte sera enregistré dans le cours correspondant à chaque salle et chaque chapitre.', 'The text will be saved in the course for each selected classroom and chapter.'),
            ),
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_t(
                'Tous les cours sont maintenant créés dans le cahier A4. Rédigez le cours en continu : les pages se créent automatiquement selon la place disponible. L’ancien formulaire de texte et d’envoi de PDF n’est plus utilisé.',
                'All lessons are now created in the A4 notebook. Write continuously: pages are generated automatically from available space. The old text and PDF upload form is no longer used.',
              )),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _publish,
              onChanged: _saving ? null : (value) => setState(() => _publish = value),
              title: Text(_t('Publier immédiatement chez les élèves', 'Publish immediately to students')),
              subtitle: Text(_t('Désactivez pour enregistrer le cours en brouillon.', 'Turn off to save the course as a draft.')),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _saving || reference == null || _chapterIds.isEmpty || _targetClassIds.isEmpty
                  ? null
                  : _openNotebookEditor,
              icon: const Icon(Icons.menu_book_rounded),
              label: Text(_t('Créer le cours en pages A4', 'Create A4 notebook course')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editCoursePages(Map<String, dynamic> row) async {
    final chapterId = row['chapter_id']?.toString() ?? '';
    if (chapterId.isEmpty) {
      _showMessage(_t('Ce cours doit être associé à un chapitre avant de créer ses pages.', 'This course must be linked to a chapter before adding pages.'));
      return;
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CourseNotebookEditorPage(
          locale: widget.locale,
          chapterId: chapterId,
          existingCourse: row,
          courseContext: {
            'class_ids': [row['class_id']?.toString() ?? ''],
            'subject_id': row['subject_id'],
            'teacher_id': row['teacher_id'],
            'curriculum_id': row['curriculum_id'],
            'chapter_id': chapterId,
          },
        ),
      ),
    );
    if (saved == true && mounted) await _loadCourses();
  }

  Widget _buildExistingCourses() {
    final visible = _courseRows.where((row) {
      if (_filter == 'published') return row['status'] == 'published';
      if (_filter == 'draft') return row['status'] == 'draft';
      if (_filter == 'archived') return row['status'] == 'archived';
      return true;
    }).toList();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: Text(_t('Cours déjà envoyés', 'Previously sent courses'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
              IconButton(
                tooltip: _t('Actualiser', 'Refresh'),
                onPressed: _saving ? null : _loadCourses,
                icon: const Icon(Icons.refresh),
              ),
            ]),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: Text(_t('Tous', 'All')), selected: _filter == 'all', onSelected: (_) => setState(() => _filter = 'all')),
              ChoiceChip(label: Text(_t('Publiés', 'Published')), selected: _filter == 'published', onSelected: (_) => setState(() => _filter = 'published')),
              ChoiceChip(label: Text(_t('Brouillons', 'Drafts')), selected: _filter == 'draft', onSelected: (_) => setState(() => _filter = 'draft')),
              ChoiceChip(label: Text(_t('Archivés', 'Archived')), selected: _filter == 'archived', onSelected: (_) => setState(() => _filter = 'archived')),
            ]),
            const SizedBox(height: 8),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(_t('Aucun cours dans cette catégorie.', 'No courses in this category.')),
              )
            else
              ...visible.map((row) {
                final rawClass = row['school_classes'];
                final rawSubject = row['subjects'];
                final schoolClass = rawClass is Map ? Map<String, dynamic>.from(rawClass) : <String, dynamic>{};
                final subject = rawSubject is Map ? Map<String, dynamic>.from(rawSubject) : <String, dynamic>{};
                final title = _fr
                    ? ((row['title_fr'] ?? row['title_en'])?.toString() ?? '')
                    : ((row['title_en'] ?? row['title_fr'])?.toString() ?? '');
                final status = row['status']?.toString() ?? 'draft';
                final statusLabel = status == 'published'
                    ? _t('Publié', 'Published')
                    : status == 'archived'
                        ? _t('Archivé', 'Archived')
                        : _t('Brouillon', 'Draft');
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Icon(status == 'published' ? Icons.menu_book : Icons.edit_note),
                  ),
                  title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${schoolClass['display_name'] ?? schoolClass['name'] ?? ''} • ${_subjectName(subject)}\\n$statusLabel'),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) {
                      if (action == 'pages') _editCoursePages(row);
                      if (action == 'delete') _deleteCourse(row);
                    },
                    itemBuilder: (_) => [
                      if ((row['chapter_id']?.toString() ?? '').isNotEmpty)
                        PopupMenuItem(value: 'pages', child: Text(_t('Modifier les pages A4', 'Edit A4 pages'))),
                      PopupMenuItem(value: 'delete', child: Text(_t('Supprimer', 'Delete'))),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('Envoi des cours', 'Send courses')),
        actions: [
          IconButton(
            tooltip: _t('Actualiser', 'Refresh'),
            onPressed: _loading || _saving ? null : _loadPage,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.icon(onPressed: _loadPage, icon: const Icon(Icons.refresh), label: Text(_t('Réessayer', 'Retry'))),
                    ]),
                  ),
                )
              : _classes.isEmpty
                  ? Center(child: Text(_t('Créez d’abord une salle active.', 'Create an active classroom first.')))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(children: [
                              const Icon(Icons.send_rounded, size: 30),
                              const SizedBox(width: 12),
                              Expanded(child: Text(
                                _t(
                                  'Choisissez plusieurs chapitres et plusieurs salles, rédigez ou importez le cours, puis publiez-le pour les élèves concernés.',
                                  'Choose multiple chapters and classrooms, write or import the course, then publish it to the selected students.',
                                ),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              )),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildSendingForm(),
                        const SizedBox(height: 20),
                        _buildExistingCourses(),
                      ],
                    ),
    );
  }
}
