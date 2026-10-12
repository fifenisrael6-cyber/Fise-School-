import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/chapter_learning_service.dart';

/// L'administration publie les cours dans les chapitres du seul périmètre
/// traité pour cette première étape : enseignement général francophone.
class AdminChapterContentPage extends StatefulWidget {
  final Locale locale;
  const AdminChapterContentPage({super.key, required this.locale});

  @override
  State<AdminChapterContentPage> createState() => _AdminChapterContentPageState();
}

class _AdminChapterContentPageState extends State<AdminChapterContentPage> {
  final _client = Supabase.instance.client;
  final _learning = ChapterLearningService();
  List<Map<String, dynamic>> classes = [];
  List<Map<String, dynamic>> subjects = [];
  List<Map<String, dynamic>> curricula = [];
  List<Map<String, dynamic>> chapters = [];
  List<Map<String, dynamic>> contents = [];
  Map<String, dynamic>? classroom, subject, curriculum, chapter;
  bool loading = true;
  String? error;

  bool get fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    loadClasses();
  }

  String label(Map<String, dynamic> row, String frKey, String enKey) {
    final f = row[frKey]?.toString().trim() ?? '';
    final e = row[enKey]?.toString().trim() ?? '';
    return fr ? (f.isNotEmpty ? f : e) : (e.isNotEmpty ? e : f);
  }

  Future<void> loadClasses() async {
    setState(() { loading = true; error = null; });
    try {
      classes = List<Map<String, dynamic>>.from(await _client
          .from('school_classes')
          .select('id,display_name,name,subsystem,sector,exam_level_id,series_id,specialty_id')
          .eq('is_active', true)
          .eq('subsystem', 'francophone')
          .eq('sector', 'general')
          .order('display_name'));
      classroom = classes.isEmpty ? null : classes.first;
      await loadSubjects();
      if (mounted) setState(() => loading = false);
    } catch (e) {
      if (mounted) setState(() { loading = false; error = e.toString(); });
    }
  }

  Future<void> loadSubjects() async {
    subjects = []; curricula = []; chapters = []; contents = [];
    subject = null; curriculum = null; chapter = null;
    if (classroom == null) { if (mounted) setState(() {}); return; }
    final rows = await _client.from('class_subjects')
        .select('subject_id,position,subjects!inner(id,name_fr,name_en,subsystem,sector,is_active)')
        .eq('class_id', classroom!['id'])
        .eq('is_active', true)
        .eq('subjects.is_active', true)
        .eq('subjects.subsystem', 'francophone')
        .eq('subjects.sector', 'general')
        .order('position');
    subjects = List<Map<String, dynamic>>.from(rows)
        .map((row) => Map<String, dynamic>.from(row['subjects'] as Map)).toList();
    subject = subjects.isEmpty ? null : subjects.first;
    await loadCurricula();
    if (mounted) setState(() {});
  }

  Future<void> loadCurricula() async {
    curricula = []; chapters = []; contents = [];
    curriculum = null; chapter = null;
    if (classroom == null || subject == null) { if (mounted) setState(() {}); return; }
    dynamic query = _client.from('curricula').select(
      'id,title_fr,title_en,subject_id,subsystem,sector,exam_level_id,series_id,specialty_id,is_catalog_container')
      .eq('subject_id', subject!['id'])
      .eq('subsystem', 'francophone')
      .eq('sector', 'general')
      .eq('is_active', true)
      .eq('is_catalog_container', true);
    for (final key in ['exam_level_id', 'series_id', 'specialty_id']) {
      final value = classroom![key];
      query = value == null ? query.isFilter(key, null) : query.eq(key, value);
    }
    curricula = List<Map<String, dynamic>>.from(await query.order('title_fr'));
    curriculum = curricula.isEmpty ? null : curricula.first;
    await loadChapters();
  }

  Future<void> loadChapters() async {
    chapters = []; contents = []; chapter = null;
    if (curriculum == null) { if (mounted) setState(() {}); return; }
    chapters = List<Map<String, dynamic>>.from(await _client.from('course_chapters')
        .select('id,curriculum_id,title_fr,title_en,position,is_active')
        .eq('curriculum_id', curriculum!['id'])
        .eq('is_active', true).order('position'));
    chapter = chapters.isEmpty ? null : chapters.first;
    await loadContents();
  }

  Future<void> loadContents() async {
    contents = [];
    if (chapter != null) {
      contents = List<Map<String, dynamic>>.from(await _client.from('chapter_content_items')
          .select('id,chapter_id,content_type,title_fr,title_en,body_text_fr,body_text_en,external_url,storage_path,position,is_published')
          .eq('chapter_id', chapter!['id']).order('position'));
    }
    if (mounted) setState(() {});
  }

  Future<void> editContent({Map<String, dynamic>? existing}) async {
    final target = chapter;
    final userId = _client.auth.currentUser?.id;
    if (target == null || userId == null) {
      snack(fr ? 'Choisissez un chapitre et reconnectez-vous.' : 'Choose a chapter and sign in again.');
      return;
    }
    final titleFr = TextEditingController(text: existing?['title_fr']?.toString() ?? '');
    final titleEn = TextEditingController(text: existing?['title_en']?.toString() ?? '');
    final bodyFr = TextEditingController(text: existing?['body_text_fr']?.toString() ?? '');
    final bodyEn = TextEditingController(text: existing?['body_text_en']?.toString() ?? '');
    final externalUrl = TextEditingController(text: existing?['external_url']?.toString() ?? '');
    String type = existing?['content_type']?.toString() ?? 'course';
    bool published = existing?['is_published'] == true;
    bool saving = false;
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(builder: (context, setSheetState) =>
        Padding(
          padding: EdgeInsets.fromLTRB(18, 8, 18, MediaQuery.of(context).viewInsets.bottom + 24),
          child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(existing == null ? (fr ? 'Ajouter un cours au chapitre' : 'Add chapter content') : (fr ? 'Modifier le contenu' : 'Edit content'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: InputDecoration(labelText: fr ? 'Type de contenu' : 'Content type'),
                items: [
                  DropdownMenuItem(value: 'course', child: Text(fr ? 'Cours' : 'Course')),
                  DropdownMenuItem(value: 'lesson', child: Text(fr ? 'Leçon' : 'Lesson')),
                  DropdownMenuItem(value: 'text', child: Text(fr ? 'Texte complémentaire' : 'Additional text')),
                ],
                onChanged: saving ? null : (v) { if (v != null) setSheetState(() => type = v); },
              ),
              const SizedBox(height: 10),
              TextField(controller: titleFr, decoration: const InputDecoration(labelText: 'Titre français *')),
              const SizedBox(height: 10),
              TextField(controller: titleEn, decoration: const InputDecoration(labelText: 'English title *')),
              const SizedBox(height: 10),
              TextField(controller: bodyFr, minLines: 4, maxLines: 12, decoration: InputDecoration(labelText: fr ? 'Contenu du cours en français' : 'Course content in French')),
              const SizedBox(height: 10),
              TextField(controller: bodyEn, minLines: 4, maxLines: 12, decoration: const InputDecoration(labelText: 'Course content in English')),
              const SizedBox(height: 10),
              TextField(controller: externalUrl, keyboardType: TextInputType.url, decoration: InputDecoration(labelText: fr ? 'Lien externe facultatif' : 'Optional external link')),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: published,
                onChanged: saving ? null : (v) => setSheetState(() => published = v),
                title: Text(fr ? 'Publier pour les élèves' : 'Publish for students')),
              FilledButton.icon(
                onPressed: saving ? null : () async {
                  if (titleFr.text.trim().isEmpty || titleEn.text.trim().isEmpty) {
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      SnackBar(content: Text(fr ? 'Renseignez les deux titres.' : 'Enter both titles.')),
                    );
                    return;
                  }
                  setSheetState(() => saving = true);
                  try {
                    int maxPosition = -1;
                    for (final row in contents) {
                      final p = int.tryParse(row['position']?.toString() ?? '') ?? -1;
                      if (p > maxPosition) maxPosition = p;
                    }
                    await _learning.saveContent(
                      id: existing?['id']?.toString(),
                      chapterId: target['id'].toString(),
                      type: type,
                      titleFr: titleFr.text,
                      titleEn: titleEn.text,
                      bodyTextFr: bodyFr.text.trim().isEmpty ? null : bodyFr.text.trim(),
                      bodyTextEn: bodyEn.text.trim().isEmpty ? null : bodyEn.text.trim(),
                      externalUrl: externalUrl.text.trim().isEmpty ? null : externalUrl.text.trim(),
                      storagePath: existing?['storage_path']?.toString(),
                      position: existing == null ? maxPosition + 1 : (int.tryParse(existing['position']?.toString() ?? '') ?? maxPosition + 1),
                      visible: published,
                      createdBy: userId,
                    );
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                    await loadContents();
                    if (mounted) snack(fr ? 'Contenu enregistré.' : 'Content saved.');
                  } catch (e) {
                    setSheetState(() => saving = false);
                    if (sheetContext.mounted) ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                },
                icon: const Icon(Icons.save_rounded),
                label: Text(fr ? 'Enregistrer' : 'Save'),
              ),
            ],
          )),
        )),
    );
    titleFr.dispose(); titleEn.dispose(); bodyFr.dispose(); bodyEn.dispose(); externalUrl.dispose();
  }

  Future<void> deleteContent(Map<String, dynamic> item) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(fr ? 'Supprimer ce contenu ?' : 'Delete this content?'),
      content: Text(label(item, 'title_fr', 'title_en')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(fr ? 'Annuler' : 'Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(fr ? 'Supprimer' : 'Delete')),
      ],
    ));
    if (yes != true) return;
    try { await _learning.deleteContent(item['id'].toString()); await loadContents(); }
    catch (e) { snack((fr ? 'Suppression impossible : ' : 'Delete failed: ') + e.toString()); }
  }

  void snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(fr ? 'Contenus des chapitres' : 'Chapter content'),
      actions: [IconButton(onPressed: loadClasses, icon: const Icon(Icons.refresh_rounded))]),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: chapter == null ? null : () => editContent(),
      icon: const Icon(Icons.add_rounded), label: Text(fr ? 'Ajouter un cours' : 'Add course')),
    body: loading ? const Center(child: CircularProgressIndicator())
      : error != null ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(error!, textAlign: TextAlign.center)))
      : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          DropdownButtonFormField<Map<String, dynamic>>(
            initialValue: classroom, isExpanded: true,
            decoration: InputDecoration(labelText: fr ? 'Salle francophone générale' : 'Francophone general classroom'),
            items: classes.map((r) => DropdownMenuItem(value: r, child: Text(r['display_name']?.toString() ?? r['name']?.toString() ?? ''))).toList(),
            onChanged: (v) async { setState(() { classroom = v; loading = true; }); try { await loadSubjects(); if (mounted) setState(() => loading = false); } catch (e) { if (mounted) setState(() { loading = false; error = e.toString(); }); } },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<Map<String, dynamic>>(
            initialValue: subject, isExpanded: true,
            decoration: InputDecoration(labelText: fr ? 'Matière' : 'Subject'),
            items: subjects.map((r) => DropdownMenuItem(value: r, child: Text(label(r, 'name_fr', 'name_en')))).toList(),
            onChanged: (v) async { setState(() { subject = v; loading = true; }); try { await loadCurricula(); if (mounted) setState(() => loading = false); } catch (e) { if (mounted) setState(() { loading = false; error = e.toString(); }); } },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<Map<String, dynamic>>(
            initialValue: curriculum, isExpanded: true,
            decoration: InputDecoration(labelText: fr ? 'Programme de la salle' : 'Class curriculum'),
            items: curricula.map((r) => DropdownMenuItem(value: r, child: Text(label(r, 'title_fr', 'title_en')))).toList(),
            onChanged: (v) async { setState(() { curriculum = v; loading = true; }); try { await loadChapters(); if (mounted) setState(() => loading = false); } catch (e) { if (mounted) setState(() { loading = false; error = e.toString(); }); } },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<Map<String, dynamic>>(
            initialValue: chapter, isExpanded: true,
            decoration: InputDecoration(labelText: fr ? 'Chapitre' : 'Chapter'),
            items: chapters.map((r) => DropdownMenuItem(value: r, child: Text((r['position']?.toString() ?? '') + '. ' + label(r, 'title_fr', 'title_en')))).toList(),
            onChanged: (v) async { setState(() { chapter = v; loading = true; }); try { await loadContents(); if (mounted) setState(() => loading = false); } catch (e) { if (mounted) setState(() { loading = false; error = e.toString(); }); } },
          ),
        ]))),
        const SizedBox(height: 10),
        if (chapter == null)
          Padding(padding: const EdgeInsets.all(24), child: Text(fr ? 'Aucun chapitre disponible pour cette matière et cette salle.' : 'No chapter is available for this subject and classroom.', textAlign: TextAlign.center))
        else if (contents.isEmpty)
          Padding(padding: const EdgeInsets.all(24), child: Text(fr ? 'Aucun contenu dans ce chapitre. Ajoutez le cours ou la leçon ici.' : 'This chapter has no content yet. Add a course or lesson here.', textAlign: TextAlign.center))
        else
          ...contents.map((item) => Card(child: ListTile(
            leading: Icon(item['is_published'] == true ? Icons.menu_book_rounded : Icons.edit_note_rounded, color: const Color(0xFF166534)),
            title: Text(label(item, 'title_fr', 'title_en'), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text((item['content_type']?.toString() ?? '') + ' • ' + (item['is_published'] == true ? (fr ? 'Publié' : 'Published') : (fr ? 'Brouillon' : 'Draft'))),
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'edit') await editContent(existing: item);
                if (v == 'toggle') { try { await _learning.setContentVisible(item['id'].toString(), item['is_published'] != true); await loadContents(); } catch (e) { snack(e.toString()); } }
                if (v == 'delete') await deleteContent(item);
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(fr ? 'Modifier' : 'Edit')),
                PopupMenuItem(value: 'toggle', child: Text(item['is_published'] == true ? (fr ? 'Dépublier' : 'Unpublish') : (fr ? 'Publier' : 'Publish'))),
                PopupMenuItem(value: 'delete', child: Text(fr ? 'Supprimer' : 'Delete')),
              ],
            ),
          ))),
      ]),
  );
}
