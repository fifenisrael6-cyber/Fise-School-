
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/pedagogy_service.dart';
import '../../../core/services/course_pdf_page_service.dart';
import 'school_classes_page.dart';
import 'admin_chapter_content_page.dart';
import 'course_notebook_editor_page.dart';
import '../../../models/pedagogy.dart';

class AdminCoursesPage extends StatefulWidget {
  final Locale locale;
  const AdminCoursesPage({super.key, required this.locale});

  @override
  State<AdminCoursesPage> createState() => _AdminCoursesPageState();
}

class _AdminCoursesPageState extends State<AdminCoursesPage> {
  final SupabaseClient _client = Supabase.instance.client;
  final ResourceService _resources = ResourceService();
  final ImagePicker _picker = ImagePicker();

  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _catalogLoading = false;
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
      final rows = await _client
          .from('courses')
          .select('id,title_fr,title_en,description_fr,description_en,status,created_at,class_id,subject_id,teacher_id,school_classes(display_name,name),subjects(name_fr,name_en,code)')
          .order('created_at', ascending: false);
      if (!mounted) {
        return;
      }
      setState(() {
        _items = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _name(Map<String, dynamic> row) {
    final fr = row['title_fr']?.toString().trim() ?? '';
    final en = row['title_en']?.toString().trim() ?? '';
    return _fr ? (fr.isNotEmpty ? fr : en) : (en.isNotEmpty ? en : fr);
  }

  String _nestedName(dynamic raw, String keyFr, String keyEn) {
    if (raw is! Map) {
      return '';
    }
    final fr = raw[keyFr]?.toString() ?? '';
    final en = raw[keyEn]?.toString() ?? '';
    return _fr ? (fr.isNotEmpty ? fr : en) : (en.isNotEmpty ? en : fr);
  }

  Future<void> _applyCatalog() async {
    setState(() => _catalogLoading = true);
    try {
      final result = await _client.rpc('admin_apply_base_subject_catalog');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_fr
            ? 'Catalogue de base appliqué aux salles. Vous pouvez ajuster chaque salle ensuite.'
            : 'Base catalogue applied to classrooms. You can adjust each classroom afterwards.')),
      );
      debugPrint('Catalog rows affected: $result');
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_fr ? 'Impossible d’appliquer le catalogue : $e' : 'Unable to apply catalogue: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _catalogLoading = false);
      }
    }
  }

  /// Ne propose que le programme qui correspond exactement à la salle choisie.
  /// Cela évite de publier un cours dans une autre classe, un autre sous-système
  /// ou une autre filière/série simplement parce que la matière porte le même nom.
  Future<List<Map<String, dynamic>>> _curriculaForClass(
    String subjectId,
    Map<String, dynamic> schoolClass,
  ) async {
    final rows = await _client
        .from('curricula')
        .select()
        .eq('subject_id', subjectId)
        .eq('is_active', true)
        .eq('subsystem', schoolClass['subsystem'])
        .eq('sector', schoolClass['sector'])
        .order('title_fr');
    bool sameContext(Map<String, dynamic> curriculum) =>
        curriculum['exam_level_id'] == schoolClass['exam_level_id'] &&
        curriculum['series_id'] == schoolClass['series_id'] &&
        curriculum['specialty_id'] == schoolClass['specialty_id'];
    final matching = List<Map<String, dynamic>>.from(rows)
        .where(sameContext)
        .toList(growable: false);
    final containers = matching
        .where((row) => row['is_catalog_container'] == true)
        .toList(growable: false);
    return containers.isNotEmpty ? containers : matching;
  }

  Future<void> _createCourse() async {
    final classes = List<Map<String, dynamic>>.from(
      await _client
          .from('school_classes')
          .select('id,display_name,name,subsystem,sector,exam_level_id,series_id,specialty_id,is_active')
          .eq('is_active', true)
          .order('display_name'),
    );
    if (!mounted) return;
    if (classes.isEmpty) {
      _snack(_fr ? 'Créez d’abord une salle active.' : 'Create an active classroom first.');
      return;
    }

    Map<String, dynamic>? selectedClass = classes.first;
    List<Map<String, dynamic>> subjects = [];
    Map<String, dynamic>? selectedSubject;
    List<Map<String, dynamic>> curricula = [];
    Map<String, dynamic>? selectedCurriculum;
    List<Map<String, dynamic>> chapters = [];
    Map<String, dynamic>? selectedChapter;
    bool published = true;
    bool opening = false;

    Future<void> loadSubjects(StateSetter setDialog) async {
      final rows = await _client
          .from('class_subjects')
          .select('subject_id,subjects(id,name_fr,name_en,code)')
          .eq('class_id', selectedClass!['id'])
          .eq('is_active', true)
          .order('position');
      subjects = List<Map<String, dynamic>>.from(rows);
      selectedSubject = subjects.isEmpty
          ? null
          : Map<String, dynamic>.from(subjects.first['subjects'] as Map);
      curricula = [];
      chapters = [];
      selectedCurriculum = null;
      selectedChapter = null;
      if (selectedSubject != null) {
        curricula = await _curriculaForClass(
          selectedSubject!['id'].toString(),
          selectedClass!,
        );
        selectedCurriculum = curricula.isEmpty ? null : curricula.first;
        if (selectedCurriculum != null) {
          chapters = List<Map<String, dynamic>>.from(
            await _client
                .from('course_chapters')
                .select()
                .eq('curriculum_id', selectedCurriculum!['id'])
                .eq('is_active', true)
                .order('position'),
          );
          selectedChapter = chapters.isEmpty ? null : chapters.first;
        }
      }
      setDialog(() {});
    }

    await loadSubjects((_) {});
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setDialog) => Padding(
          padding: EdgeInsets.fromLTRB(
            20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _fr ? 'Créer un cours en cahier A4' : 'Create an A4 notebook course',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<Map<String, dynamic>>(
                  initialValue: selectedClass,
                  decoration: InputDecoration(
                    labelText: _fr ? 'Salle de classe' : 'Classroom',
                  ),
                  items: classes.map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c['display_name']?.toString() ??
                        c['name']?.toString() ?? ''),
                  )).toList(),
                  onChanged: opening ? null : (value) async {
                    selectedClass = value;
                    if (value != null) await loadSubjects(setDialog);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Map<String, dynamic>>(
                  initialValue: selectedSubject,
                  decoration: InputDecoration(
                    labelText: _fr ? 'Matière de cette salle' : 'Subject in this classroom',
                  ),
                  items: subjects.map((row) {
                    final item = Map<String, dynamic>.from(row['subjects'] as Map);
                    return DropdownMenuItem(
                      value: item,
                      child: Text(_nestedName(item, 'name_fr', 'name_en')),
                    );
                  }).toList(),
                  onChanged: opening ? null : (value) async {
                    selectedSubject = value;
                    selectedCurriculum = null;
                    selectedChapter = null;
                    chapters = [];
                    curricula = value == null
                        ? []
                        : await _curriculaForClass(value['id'].toString(), selectedClass!);
                    selectedCurriculum = curricula.isEmpty ? null : curricula.first;
                    if (selectedCurriculum != null) {
                      chapters = List<Map<String, dynamic>>.from(
                        await _client
                            .from('course_chapters')
                            .select()
                            .eq('curriculum_id', selectedCurriculum!['id'])
                            .eq('is_active', true)
                            .order('position'),
                      );
                      selectedChapter = chapters.isEmpty ? null : chapters.first;
                    }
                    setDialog(() {});
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Map<String, dynamic>>(
                  initialValue: selectedCurriculum,
                  decoration: InputDecoration(
                    labelText: _fr ? 'Programme de cette salle *' : 'Class curriculum *',
                  ),
                  items: curricula.map((item) => DropdownMenuItem(
                    value: item,
                    child: Text(_nestedName(item, 'title_fr', 'title_en')),
                  )).toList(),
                  onChanged: opening ? null : (value) async {
                    selectedCurriculum = value;
                    selectedChapter = null;
                    chapters = value == null
                        ? []
                        : List<Map<String, dynamic>>.from(
                            await _client
                                .from('course_chapters')
                                .select()
                                .eq('curriculum_id', value['id'])
                                .eq('is_active', true)
                                .order('position'),
                          );
                    selectedChapter = chapters.isEmpty ? null : chapters.first;
                    setDialog(() {});
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Map<String, dynamic>>(
                  initialValue: selectedChapter,
                  decoration: InputDecoration(
                    labelText: _fr ? 'Chapitre *' : 'Chapter *',
                  ),
                  items: chapters.map((item) => DropdownMenuItem(
                    value: item,
                    child: Text(_nestedName(item, 'title_fr', 'title_en')),
                  )).toList(),
                  onChanged: opening ? null : (value) => setDialog(() => selectedChapter = value),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: published,
                  onChanged: opening ? null : (value) => setDialog(() => published = value),
                  title: Text(_fr ? 'Publier immédiatement' : 'Publish immediately'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: opening ||
                          selectedClass == null ||
                          selectedSubject == null ||
                          selectedCurriculum == null ||
                          selectedChapter == null
                      ? null
                      : () async {
                          setDialog(() => opening = true);
                          final courseContext = <String, dynamic>{
                            'class_ids': [selectedClass!['id'].toString()],
                            'subject_id': selectedSubject!['id'].toString(),
                            'teacher_id': _client.auth.currentUser?.id,
                            'curriculum_id': selectedCurriculum!['id'].toString(),
                            'chapter_id': selectedChapter!['id'].toString(),
                            'chapter_ids': [selectedChapter!['id'].toString()],
                            'publish': published,
                          };
                          final navigator = Navigator.of(sheetContext);
                          navigator.pop();
                          final saved = await navigator.push<bool>(
                            MaterialPageRoute(
                              builder: (_) => CourseNotebookEditorPage(
                                locale: widget.locale,
                                chapterId: selectedChapter!['id'].toString(),
                                courseContext: courseContext,
                              ),
                            ),
                          );
                          if (saved == true && mounted) await _load();
                        },
                  icon: const Icon(Icons.menu_book_rounded),
                  label: Text(_fr ? 'Ouvrir le cahier et rédiger' : 'Open notebook and write'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addResource(Map<String, dynamic> course) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.folder_open), title: Text(_fr ? 'Choisir un document' : 'Choose a document'), onTap: () => Navigator.pop(ctx, 'file')),
        ListTile(leading: const Icon(Icons.photo_camera), title: Text(_fr ? 'Prendre une photo' : 'Take a photo'), onTap: () => Navigator.pop(ctx, 'camera')),
        ListTile(leading: const Icon(Icons.photo_library), title: Text(_fr ? 'Choisir une photo' : 'Choose a photo'), onTap: () => Navigator.pop(ctx, 'gallery')),
      ])),
    );
    if (source == null) {
      return;
    }
    PlatformFile file;
    if (source == 'camera' || source == 'gallery') {
      final x = await _picker.pickImage(source: source == 'camera' ? ImageSource.camera : ImageSource.gallery, imageQuality: 90);
      if (x == null) {
        return;
      }
      final bytes = await x.readAsBytes();
      file = PlatformFile(name: x.name, size: bytes.length, bytes: bytes);
    } else {
      final result = await FilePicker.platform.pickFiles(withData: true, type: FileType.any);
      if (result == null || result.files.isEmpty) {
        return;
      }
      file = result.files.first;
    }
    if (file.bytes == null || file.bytes!.isEmpty) { _snack(_fr ? 'Impossible de lire ce fichier.' : 'Unable to read this file.'); return; }
    final ext = file.extension?.toLowerCase() ?? '';
    final type = switch (ext) { 'pdf' => 'pdf', 'jpg' || 'jpeg' || 'png' || 'webp' => 'image', 'mp4' || 'mov' => 'video', 'mp3' || 'wav' || 'm4a' => 'audio', 'doc' || 'docx' || 'txt' || 'ppt' || 'pptx' || 'xls' || 'xlsx' => 'document', _ => 'other' };
    try {
      final count = await _client.from('course_resources').select('id').eq('course_id', course['id']).count(CountOption.exact);
      final uploaded = await _resources.uploadResource(courseId: course['id'].toString(), file: file, resourceType: type, position: count.count, titleFr: file.name, titleEn: file.name);
      if (type == 'pdf') {
        _snack(_fr ? 'PDF envoyé. Analyse IA et organisation des chapitres en cours…' : 'PDF uploaded. AI chapter analysis and organization in progress…');
        try {
          final result = await _client.functions.invoke(
            'import-course-pdf',
            body: {'resource_id': uploaded.id},
          );
          final data = result.data;
          if (result.status >= 200 && result.status < 300 && data is Map && data['success'] == true) {
            final preparedPages = await _prepareImportedChapterPages(Map<String, dynamic>.from(data));
            final imported = data['imported'] ?? 0;
            final existing = data['already_exists'] ?? 0;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_fr
                    ? 'Extraction terminée : $imported chapitre(s) préparé(s), $existing déjà présent(s), $preparedPages page(s) A4 rendue(s). Les nouveaux cours sont en brouillon.'
                    : 'Extraction complete: $imported chapter(s) prepared, $existing already existed, $preparedPages A4 page(s) rendered. New lessons are drafts.'),
                duration: const Duration(seconds: 8),
                action: SnackBarAction(
                  label: _fr ? 'Ouvrir les cours écrits' : 'Open written lessons',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdminChapterContentPage(locale: widget.locale),
                      ),
                    );
                  },
                ),
              ),
            );
          } else {
            final message = data is Map ? (data['error']?.toString() ?? 'Erreur IA inconnue.') : 'Réponse IA invalide.';
            _snack(_fr ? 'PDF conservé, mais import IA échoué : $message' : 'PDF saved, but AI import failed: $message');
          }
        } catch (e) {
          _snack(_fr
              ? 'PDF conservé dans Supabase, mais l’analyse IA a échoué : $e'
              : 'PDF remains saved in Supabase, but AI analysis failed: $e');
        }
      } else {
        _snack(_fr ? 'Contenu ajouté à la salle et au cours.' : 'Content added to the classroom course.');
      }
    } catch (e) { _snack(_fr ? 'Échec de l’envoi : $e' : 'Upload failed: $e'); }
  }


  Future<void> _manageResources(Map<String, dynamic> course) async {
    var resources = await _resources.listForCourse(course['id'].toString());
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.78,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(children: [
                  Expanded(child: Text(_fr ? 'Documents du cours' : 'Course documents',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                  IconButton(
                    tooltip: _fr ? 'Actualiser' : 'Refresh',
                    onPressed: () async {
                      final latest = await _resources.listForCourse(course['id'].toString());
                      setSheetState(() => resources = latest);
                    },
                    icon: const Icon(Icons.refresh),
                  ),
                ]),
              ),
              Expanded(
                child: resources.isEmpty
                  ? Center(child: Text(_fr ? 'Aucun document dans ce cours.' : 'No documents in this course.'))
                  : ListView.separated(
                      itemCount: resources.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final resource = resources[index];
                        return ListTile(
                          leading: Icon(resource.resourceType == 'pdf' ? Icons.picture_as_pdf_rounded : Icons.insert_drive_file_rounded),
                          title: Text(resource.fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text('\${resource.resourceType.toUpperCase()} • \${resource.indexStatus}'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) async {
                              if (action == 'regenerate_pages') {
                                await _regenerateResourcePages(resource);
                              } else if (action == 'replace') {
                                await _replaceResource(resource);
                                if (!mounted || !sheetContext.mounted) return;
                                final latest = await _resources.listForCourse(course['id'].toString());
                                setSheetState(() => resources = latest);
                              } else if (action == 'delete') {
                                final confirmed = await showDialog<bool>(
                                  context: sheetContext,
                                  builder: (dialogContext) => AlertDialog(
                                    title: Text(_fr ? 'Supprimer ce document ?' : 'Delete this document?'),
                                    content: Text(_fr
                                      ? 'Le fichier « \${resource.fileName} » sera supprimé. Les leçons déjà créées resteront dans les chapitres.'
                                      : 'The file "\${resource.fileName}" will be deleted. Existing lessons will remain in their chapters.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_fr ? 'Annuler' : 'Cancel')),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(dialogContext, true),
                                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                        child: Text(_fr ? 'Supprimer' : 'Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true) return;
                                try {
                                  await _resources.deleteResource(resource);
                                  if (!sheetContext.mounted) return;
                                  final latest = await _resources.listForCourse(course['id'].toString());
                                  setSheetState(() => resources = latest);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(_fr ? 'Document supprimé.' : 'Document deleted.')),
                                  );
                                } catch (e) {
                                  _snack(_fr ? 'Suppression impossible : $e' : 'Unable to delete document: $e');
                                }
                              }
                            },
                            itemBuilder: (_) => [
                              if (resource.resourceType == 'pdf')
                                PopupMenuItem(
                                  value: 'regenerate_pages',
                                  child: Text(_fr ? 'Régénérer les pages du cours' : 'Regenerate course pages'),
                                ),
                              PopupMenuItem(value: 'replace', child: Text(_fr ? 'Remplacer par un autre document' : 'Replace with another document')),
                              PopupMenuItem(value: 'delete', child: Text(_fr ? 'Supprimer le document' : 'Delete document')),
                            ],
                          ),
                        );
                      },
                    ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _addResource(course);
                    },
                    icon: const Icon(Icons.add),
                    label: Text(_fr ? 'Ajouter un nouveau document' : 'Add a new document'),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _regenerateResourcePages(CourseResource resource) async {
    try {
      _snack(_fr ? 'Préparation des pages du cours…' : 'Preparing course pages…');
      final count = await CoursePdfPageService(_client).regenerate({
        'course_id': resource.courseId,
        'storage_path': resource.storagePath,
        'source_bucket': 'course-resources',
      });
      if (!mounted) return;
      _snack(_fr
          ? 'Conversion terminée : $count page(s) prêtes pour les élèves.'
          : 'Conversion complete: $count page(s) ready for students.');
    } catch (error) {
      if (!mounted) return;
      _snack(_fr
          ? 'Conversion impossible : $error'
          : 'Page conversion failed: $error');
    }
  }

  Future<int> _prepareImportedChapterPages(Map<String, dynamic> data) async {
    final reportRows = (data['report'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    final itemIds = reportRows
        .map((row) => row['content_item_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    var preparedPages = 0;
    if (itemIds.isNotEmpty) {
      final importedItems = await _client
          .from('chapter_content_items')
          .select('id,source_pdf_path,source_page_start,source_page_end')
          .inFilter('id', itemIds);
      for (final importedItem in importedItems) {
        final sourcePdfPath =
            (importedItem['source_pdf_path'] as String? ?? '').trim();
        if (sourcePdfPath.isEmpty) continue;
        preparedPages += await CoursePdfPageService(_client).regenerate({
          ...Map<String, dynamic>.from(importedItem),
          'storage_path': sourcePdfPath,
          'source_bucket': 'chapter-content',
        });
      }
    }
    return preparedPages;
  }

  Future<void> _convertResourceToA4(CourseResource resource) async {
    if (resource.resourceType != 'pdf') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_fr ? 'Convertir le PDF en cours A4 ?' : 'Convert PDF to A4 lessons?'),
        content: Text(_fr
            ? 'Le PDF sera relu. Les cours correspondants seront actualisés en conservant leur état publié/masqué. Les pages originales, formules et illustrations seront conservées.'
            : 'The PDF will be reprocessed. Matching lessons will be updated while keeping their published/hidden state. Original pages, formulas and illustrations will be preserved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_fr ? 'Annuler' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_fr ? 'Convertir' : 'Convert'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      _snack(_fr ? 'Analyse du PDF et préparation des pages A4…' : 'Analyzing PDF and preparing A4 pages…');
      final response = await _client.functions.invoke(
        'import-course-pdf',
        body: {'resource_id': resource.id, 'replace_existing': true},
      );
      final data = response.data;
      if (response.status < 200 ||
          response.status >= 300 ||
          data is! Map ||
          data['success'] != true) {
        final message = data is Map
            ? (data['error']?.toString() ?? 'Erreur inconnue.')
            : 'Réponse serveur invalide.';
        throw StateError(message);
      }
      final preparedPages =
          await _prepareImportedChapterPages(Map<String, dynamic>.from(data));
      final imported = data['imported'] ?? 0;
      final replaced = data['replaced'] ?? 0;
      _snack(_fr
          ? 'Conversion terminée : $imported nouveau(x) cours, $replaced actualisé(s), $preparedPages page(s) A4.'
          : 'Conversion complete: $imported new lesson(s), $replaced updated, $preparedPages A4 page(s).');
    } catch (error) {
      _snack(_fr ? 'Conversion PDF impossible : $error' : 'PDF conversion failed: $error');
    }
  }

  Future<void> _replaceResource(CourseResource resource) async {
    final result = await FilePicker.platform.pickFiles(withData: true, type: FileType.any);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null || file.bytes!.isEmpty) {
      _snack(_fr ? 'Impossible de lire le nouveau fichier.' : 'Unable to read the new file.');
      return;
    }
    final extension = file.extension?.toLowerCase() ?? '';
    final type = switch (extension) {
      'pdf' => 'pdf',
      'jpg' || 'jpeg' || 'png' || 'webp' => 'image',
      'mp4' || 'mov' => 'video',
      'mp3' || 'wav' || 'm4a' => 'audio',
      'doc' || 'docx' || 'txt' || 'ppt' || 'pptx' || 'xls' || 'xlsx' => 'document',
      _ => 'other',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_fr ? 'Confirmer le remplacement' : 'Confirm replacement'),
        content: Text(_fr
          ? '« \${resource.fileName} » sera remplacé par « \${file.name} ». Si le fichier est un PDF, ses contenus correspondants seront réimportés.'
          : '"\${resource.fileName}" will be replaced by "\${file.name}". If it is a PDF, matching lesson content will be re-imported.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_fr ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_fr ? 'Remplacer' : 'Replace')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _resources.replaceResourceFile(resource: resource, file: file, resourceType: type);
      if (type == 'pdf') {
        final response = await _client.functions.invoke(
          'import-course-pdf',
          body: {'resource_id': resource.id, 'replace_existing': true},
        );
        final data = response.data;
        if (response.status < 200 || response.status >= 300 || data is! Map || data['success'] != true) {
          final fallback = _fr ? 'erreur inconnue' : 'unknown error';
          final message = data is Map
              ? (data['error']?.toString() ?? fallback)
              : fallback;
          _snack(_fr
              ? 'Document remplacé, mais réimport échoué : $message'
              : 'Document replaced, but re-import failed: $message');
          return;
        }
        _snack(_fr ? 'PDF remplacé et contenus correspondants actualisés.' : 'PDF replaced and matching lesson content updated.');
      } else {
        _snack(_fr ? 'Document remplacé.' : 'Document replaced.');
      }
    } catch (e) {
      _snack(_fr ? 'Remplacement impossible : $e' : 'Unable to replace document: $e');
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'Cours et contenus' : 'Courses and content'),
        actions: [
          IconButton(
            tooltip: _fr ? 'Matières des salles' : 'Classroom subjects',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SchoolClassesPage(locale: widget.locale),
              ),
            ),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _createCourse, icon: const Icon(Icons.add), label: Text(_fr ? 'Créer un cours' : 'Create course')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Card(child: ListTile(leading: const Icon(Icons.menu_book_rounded, color: Color(0xFF166534)), title: Text(_fr ? 'Catalogue des salles' : 'Classroom catalogue', style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(_fr ? 'Appliquer le catalogue de base, puis ajuster chaque salle selon son programme et ses options.' : 'Apply the base catalogue, then adjust each classroom for its programme and options.'), trailing: _catalogLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : IconButton(onPressed: _applyCatalog, icon: const Icon(Icons.auto_fix_high))))),
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!))) : _items.isEmpty ? Center(child: Text(_fr ? 'Aucun cours.' : 'No courses.')) : RefreshIndicator(onRefresh: _load, child: ListView.separated(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), itemCount: _items.length, separatorBuilder: (_, _) => const SizedBox(height: 10), itemBuilder: (_, i) {
          final c = _items[i];
          final room = (c['school_classes'] is Map) ? Map<String, dynamic>.from(c['school_classes'] as Map) : <String, dynamic>{};
          final subject = (c['subjects'] is Map) ? Map<String, dynamic>.from(c['subjects'] as Map) : <String, dynamic>{};
          return Card(child: ListTile(isThreeLine: true, leading: const CircleAvatar(backgroundColor: Color(0xFF166534), child: Icon(Icons.menu_book, color: Colors.white)), title: Text(_name(c), style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${room['display_name'] ?? ''}\n${_nestedName(subject, 'name_fr', 'name_en')} • ${c['status'] ?? 'draft'}'), trailing: PopupMenuButton<String>(onSelected: (v) async {
            if (v == 'resource') {
              await _addResource(c);
            } else if (v == 'manage_resources') {
              await _manageResources(c);
            } else if (v == 'archive') {
              try {
                await _client.from('courses').update({'status': 'archived'}).eq('id', c['id']);
                _snack(_fr ? 'Cours archivé. Il reste dans la base et peut être réactivé.' : 'Course archived. It remains in the database and can be restored.');
                await _load();
              } catch (e) {
                _snack(_fr ? 'Impossible d’archiver ce cours : $e' : 'Unable to archive this course: $e');
              }
            }
          }, itemBuilder: (_) => [
            PopupMenuItem(value: 'resource', child: Text(_fr ? 'Ajouter photo/PDF/fichier' : 'Add photo/PDF/file')),
            PopupMenuItem(value: 'manage_resources', child: Text(_fr ? 'Gérer / remplacer / supprimer les documents' : 'Manage / replace / delete documents')),
            if (c['status'] != 'archived') PopupMenuItem(value: 'archive', child: Text(_fr ? 'Archiver le cours' : 'Archive course')),
          ])));
        })))
      ]),
    );
  }
}
