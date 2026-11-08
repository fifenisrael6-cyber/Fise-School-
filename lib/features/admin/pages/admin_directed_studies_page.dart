import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Administrator-only CRUD for Supabase directed-study PDF records.
class AdminDirectedStudiesPage extends StatefulWidget {
  const AdminDirectedStudiesPage({super.key, required this.locale});
  final Locale locale;
  @override
  State<AdminDirectedStudiesPage> createState() => _AdminDirectedStudiesPageState();
}

class _AdminDirectedStudiesPageState extends State<AdminDirectedStudiesPage> {
  final _client = Supabase.instance.client;
  final _title = TextEditingController();
  final _description = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _courses = [];
  Map<String, dynamic>? _course;
  PlatformFile? _file;
  bool _loading = true;
  bool _saving = false;
  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _title.dispose(); _description.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        _client.from('directed_studies').select('id,course_id,chapter_id,subject_id,teacher_id,title,description,storage_path,file_name,status,published_at,created_at,courses(title_fr,title_en,chapter_id),school_classes(display_name,name),subjects(name_fr,name_en)').order('created_at', ascending: false),
        _client.from('courses').select('id,title_fr,title_en,class_id,subject_id,teacher_id,chapter_id,status,school_classes(display_name,name),subjects(name_fr,name_en)').neq('status', 'archived').order('created_at', ascending: false),
      ]);
      if (!mounted) return;
      setState(() { _items = List<Map<String, dynamic>>.from(results[0] as List); _courses = List<Map<String, dynamic>>.from(results[1] as List); _loading = false; });
    } catch (error) {
      if (mounted) setState(() { _loading = false; _snack(_fr ? 'Chargement impossible : $error' : 'Unable to load: $error'); });
    }
  }

  String _courseTitle(Map<String, dynamic> row) => (widget.locale.languageCode == 'en' ? row['title_en'] : row['title_fr'])?.toString() ?? row['title_fr']?.toString() ?? '';
  String _nested(dynamic row, String key) => row is Map ? row[key]?.toString() ?? '' : '';
  void _snack(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf'], withData: true);
    if (result != null && result.files.isNotEmpty && mounted) setState(() => _file = result.files.single);
  }

  Future<void> _create() async {
    _title.clear(); _description.clear(); _file = null; _course = null;
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (sheet) => StatefulBuilder(builder: (context, setSheet) => Padding(
      padding: EdgeInsets.fromLTRB(18, 8, 18, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_fr ? 'Nouveau TD PDF' : 'New TD PDF', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        DropdownButtonFormField<Map<String, dynamic>>(
          value: _course,
          isExpanded: true,
          decoration: InputDecoration(labelText: _fr ? 'Cours / classe / matière / chapitre' : 'Course / classroom / subject / chapter'),
          items: _courses.map((course) => DropdownMenuItem(value: course, child: Text('${_courseTitle(course)} • ${_nested(course['school_classes'], 'display_name')} • ${_nested(course['subjects'], 'name_fr')} • ${course['chapter_id'] == null ? (_fr ? 'sans chapitre' : 'no chapter') : (_fr ? 'chapitre associé' : 'linked chapter')}', overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (value) => setSheet(() => _course = value),
        ),
        const SizedBox(height: 10),
        TextField(controller: _title, decoration: InputDecoration(labelText: _fr ? 'Titre *' : 'Title *')),
        const SizedBox(height: 10),
        TextField(controller: _description, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: _fr ? 'Consignes (facultatif)' : 'Instructions (optional)')),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: () async { await _pickPdf(); setSheet(() {}); }, icon: const Icon(Icons.picture_as_pdf), label: Text(_file?.name ?? (_fr ? 'Choisir un PDF' : 'Choose PDF'))),
        const SizedBox(height: 12),
        FilledButton(onPressed: _saving ? null : () async {
          final selected = _course; final file = _file; final bytes = file?.bytes;
          if (selected == null || _title.text.trim().isEmpty || file == null || bytes == null || bytes.isEmpty) { _snack(_fr ? 'Sélectionnez un cours, un titre et un PDF valide.' : 'Select a course, title and valid PDF.'); return; }
          final userId = _client.auth.currentUser?.id;
          if (userId == null) { _snack(_fr ? 'Session absente.' : 'No authenticated session.'); return; }
          setSheet(() => _saving = true);
          final path = '$userId/admin-${DateTime.now().microsecondsSinceEpoch}-${file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}';
          try {
            await _client.storage.from('directed-study-files').uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'application/pdf', upsert: false));
            await _client.from('directed_studies').insert({
              'course_id': selected['id'], 'chapter_id': selected['chapter_id'],
              'source_class_id': selected['class_id'], 'subject_id': selected['subject_id'],
              'teacher_id': selected['teacher_id'], 'title': _title.text.trim(),
              'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
              'storage_path': path, 'file_name': file.name,
              'requested_class_ids': [selected['class_id']], 'status': 'published',
              'published_at': DateTime.now().toUtc().toIso8601String(),
            });
            if (sheet.mounted) Navigator.pop(sheet);
            _snack(_fr ? 'TD publié dans Supabase.' : 'TD published to Supabase.');
            await _load();
          } catch (error) {
            try { await _client.storage.from('directed-study-files').remove([path]); } catch (_) {}
            _snack(_fr ? 'Publication impossible : $error' : 'Publish failed: $error');
            setSheet(() => _saving = false);
          }
        }, child: Text(_saving ? (_fr ? 'Publication…' : 'Publishing…') : (_fr ? 'Publier le TD' : 'Publish TD'))),
      ])),
    )));
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final title = TextEditingController(text: row['title']?.toString() ?? '');
    final description = TextEditingController(text: row['description']?.toString() ?? '');
    var status = row['status']?.toString() ?? 'published';
    await showDialog<void>(context: context, builder: (dialog) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
      title: Text(_fr ? 'Modifier le TD' : 'Edit TD'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: InputDecoration(labelText: _fr ? 'Titre' : 'Title')),
        TextField(controller: description, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: _fr ? 'Consignes' : 'Instructions')),
        DropdownButtonFormField<String>(value: status, items: [DropdownMenuItem(value: 'published', child: Text(_fr ? 'Publié' : 'Published')), DropdownMenuItem(value: 'draft', child: Text(_fr ? 'Brouillon' : 'Draft'))], onChanged: (value) { if (value != null) setDialog(() => status = value); }),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: Text(_fr ? 'Annuler' : 'Cancel')), FilledButton(onPressed: () async {
        try {
          await _client.from('directed_studies').update({'title': title.text.trim(), 'description': description.text.trim().isEmpty ? null : description.text.trim(), 'status': status, 'published_at': status == 'published' ? DateTime.now().toUtc().toIso8601String() : null}).eq('id', row['id']);
          if (dialog.mounted) Navigator.pop(dialog);
          await _load();
        } catch (error) { _snack(_fr ? 'Modification impossible : $error' : 'Update failed: $error'); }
      }, child: Text(_fr ? 'Enregistrer' : 'Save'))],
    )));
    title.dispose(); description.dispose();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final yes = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
      title: Text(_fr ? 'Supprimer ce TD ?' : 'Delete this TD?'),
      content: Text(row['title']?.toString() ?? ''),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(_fr ? 'Annuler' : 'Cancel')), FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(_fr ? 'Supprimer' : 'Delete'))],
    ));
    if (yes != true) return;
    try {
      await _client.from('directed_studies').delete().eq('id', row['id']);
      final path = row['storage_path']?.toString();
      if (path != null && path.isNotEmpty) { try { await _client.storage.from('directed-study-files').remove([path]); } catch (_) {} }
      _snack(_fr ? 'TD supprimé.' : 'TD deleted.');
      await _load();
    } catch (error) { _snack(_fr ? 'Suppression impossible : $error' : 'Delete failed: $error'); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_fr ? 'Gestion des TD PDF' : 'TD PDF management'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: Text(_fr ? 'Ajouter un TD' : 'Add TD')),
    body: _loading ? const Center(child: CircularProgressIndicator()) : _items.isEmpty
      ? Center(child: Text(_fr ? 'Aucun TD dans Supabase.' : 'No TDs in Supabase.'))
      : ListView.builder(padding: const EdgeInsets.all(12), itemCount: _items.length, itemBuilder: (context, index) {
        final row = _items[index];
        final room = row['school_classes']; final subject = row['subjects']; final course = row['courses'];
        final date = DateTime.tryParse((row['published_at'] ?? row['created_at'] ?? '').toString());
        return Card(child: ListTile(
          leading: const Icon(Icons.picture_as_pdf, color: Color(0xFF166534)),
          title: Text(row['title']?.toString() ?? ''),
          subtitle: Text(['${_nested(subject, 'name_fr')}', '${_nested(room, 'display_name')}', if (course is Map) _courseTitle(course), row['status'], if (date != null) '${date.day}/${date.month}/${date.year}', if ((row['description'] ?? '').toString().isNotEmpty) row['description'].toString()].join(' • '), maxLines: 3, overflow: TextOverflow.ellipsis),
          trailing: PopupMenuButton<String>(onSelected: (value) { if (value == 'edit') _edit(row); if (value == 'delete') _delete(row); }, itemBuilder: (_) => [PopupMenuItem(value: 'edit', child: Text(_fr ? 'Modifier / publier' : 'Edit / publish')), PopupMenuItem(value: 'delete', child: Text(_fr ? 'Supprimer' : 'Delete'))]),
        ));
      }),
  );
}
