
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/course_offline_service.dart';
import '../../../core/offline/offline_resource_viewer.dart';
import '../../../core/offline/json_cache.dart';
import '../../../core/services/pedagogy_service.dart';
import 'school_classes_page.dart';

class AdminCoursesPage extends StatefulWidget {
  final Locale locale;
  const AdminCoursesPage({super.key, required this.locale});

  @override
  State<AdminCoursesPage> createState() => _AdminCoursesPageState();
}

class _AdminCoursesPageState extends State<AdminCoursesPage> {
  final SupabaseClient _client = Supabase.instance.client;
  final CourseService _courses = CourseService();
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
      final userId = _client.auth.currentUser?.id ?? 'anonymous';
      final rows = await JsonCache.instance.cachedRead<List<Map<String, dynamic>>>(
        key: 'admin_courses_$userId',
        fetch: () async => await _client
            .from('courses')
            .select('id,title_fr,title_en,description_fr,description_en,status,created_at,class_id,subject_id,teacher_id,school_classes(display_name,name),subjects(name_fr,name_en,code)')
            .order('created_at', ascending: false) as Object?,
        decode: (raw) => (raw as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(growable: false),
      );
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
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

  Future<void> _createCourse() async {
    final classes = List<Map<String, dynamic>>.from(
      await _client.from('school_classes').select('id,display_name,name,subsystem,sector,is_active,exam_level_id,series_id,specialty_id').eq('is_active', true).order('display_name'),
    );
    if (!mounted) {
      return;
    }
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

    final titleFr = TextEditingController();
    final titleEn = TextEditingController();
    final descFr = TextEditingController();
    final descEn = TextEditingController();
    final contentFr = TextEditingController();
    final contentEn = TextEditingController();
    bool published = true;
    bool saving = false;

    Future<void> loadCurricula(StateSetter setDialog) async {
      curricula = [];
      chapters = [];
      selectedCurriculum = null;
      selectedChapter = null;
      final classroom = selectedClass;
      final subject = selectedSubject;
      if (classroom == null || subject == null) {
        setDialog(() {});
        return;
      }

      dynamic query = _client
          .from('curricula')
          .select()
          .eq('subject_id', subject['id'])
          .eq('subsystem', classroom['subsystem'])
          .eq('sector', classroom['sector'])
          .eq('is_active', true);
      final levelId = classroom['exam_level_id'];
      query = levelId == null
          ? query.isFilter('exam_level_id', null)
          : query.eq('exam_level_id', levelId);
      final seriesId = classroom['series_id'];
      query = seriesId == null
          ? query.isFilter('series_id', null)
          : query.eq('series_id', seriesId);
      final specialtyId = classroom['specialty_id'];
      query = specialtyId == null
          ? query.isFilter('specialty_id', null)
          : query.eq('specialty_id', specialtyId);

      curricula = List<Map<String, dynamic>>.from(
        await query.order('title_fr'),
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
      setDialog(() {});
    }

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
      await loadCurricula(setDialog);
      setDialog(() {});
    }

    await loadSubjects((_) {});
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setDialog) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_fr ? 'Créer un contenu pédagogique' : 'Create educational content', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<Map<String, dynamic>>(
                      initialValue: selectedClass,
                      decoration: InputDecoration(labelText: _fr ? 'Salle de classe' : 'Classroom'),
                      items: classes.map((c) => DropdownMenuItem(value: c, child: Text(c['display_name']?.toString() ?? c['name']?.toString() ?? ''))).toList(),
                      onChanged: saving ? null : (value) async { selectedClass = value; await loadSubjects(setDialog); },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<Map<String, dynamic>>(
                      initialValue: selectedSubject,
                      decoration: InputDecoration(labelText: _fr ? 'Matière de cette salle' : 'Subject in this classroom'),
                      items: subjects.map((s) { final m = Map<String, dynamic>.from(s['subjects'] as Map); return DropdownMenuItem(value: m, child: Text(_nestedName(m, 'name_fr', 'name_en'))); }).toList(),
                      onChanged: saving ? null : (value) async {
                        selectedSubject = value;
                        await loadCurricula(setDialog);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<Map<String, dynamic>>(
                      initialValue: selectedCurriculum,
                      decoration: InputDecoration(labelText: _fr ? 'Programme' : 'Curriculum'),
                      items: curricula.map((c) => DropdownMenuItem(value: c, child: Text(_nestedName(c, 'title_fr', 'title_en')))).toList(),
                      onChanged: saving ? null : (value) async { selectedCurriculum = value; selectedChapter = null; chapters = value == null ? [] : List<Map<String, dynamic>>.from(await _client.from('course_chapters').select().eq('curriculum_id', value['id']).eq('is_active', true).order('position')); selectedChapter = chapters.isEmpty ? null : chapters.first; setDialog(() {}); },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<Map<String, dynamic>>(
                      initialValue: selectedChapter,
                      decoration: InputDecoration(labelText: _fr ? 'Chapitre' : 'Chapter'),
                      items: chapters.map((c) => DropdownMenuItem(value: c, child: Text(_nestedName(c, 'title_fr', 'title_en')))).toList(),
                      onChanged: saving ? null : (value) => setDialog(() => selectedChapter = value),
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: titleFr, decoration: InputDecoration(labelText: 'Titre français *')),
                    const SizedBox(height: 10),
                    TextField(controller: titleEn, decoration: InputDecoration(labelText: 'English title *')),
                    const SizedBox(height: 10),
                    TextField(controller: descFr, maxLines: 2, decoration: InputDecoration(labelText: _fr ? 'Description' : 'Description')),
                    const SizedBox(height: 10),
                    TextField(controller: contentFr, maxLines: 6, decoration: InputDecoration(labelText: _fr ? 'Contenu du cours (français)' : 'Course content (French)')),
                    const SizedBox(height: 10),
                    TextField(controller: contentEn, maxLines: 6, decoration: const InputDecoration(labelText: 'Course content (English)')),
                    SwitchListTile(value: published, onChanged: saving ? null : (v) => setDialog(() => published = v), title: Text(_fr ? 'Publier immédiatement' : 'Publish immediately'), contentPadding: EdgeInsets.zero),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: saving || selectedSubject == null || selectedCurriculum == null || selectedChapter == null || titleFr.text.trim().isEmpty || titleEn.text.trim().isEmpty ? null : () async {
                        setDialog(() => saving = true);
                        try {
                          await _courses.saveCourse(
                            curriculumId: selectedCurriculum!['id'].toString(),
                            chapterId: selectedChapter!['id'].toString(),
                            subjectId: selectedSubject!['id'].toString(),
                            teacherId: _client.auth.currentUser!.id,
                            classId: selectedClass!['id'].toString(),
                            titleFr: titleFr.text,
                            titleEn: titleEn.text,
                            descriptionFr: descFr.text,
                            descriptionEn: descEn.text,
                            contentFr: contentFr.text,
                            contentEn: contentEn.text,
                            status: published ? 'published' : 'draft',
                          );
                          if (published) {
                            // Generate the chapter's AI QCM in the background.
                            // Course publication remains successful if Gemini is temporarily unavailable.
                            unawaited(_courses.generateChapterQuiz(selectedChapter!['id'].toString()));
                          }
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                          await _load();
                        } catch (e) {
                          setDialog(() => saving = false);
                          if (sheetContext.mounted) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text(e.toString())));
                          }
                        }
                      },
                      icon: const Icon(Icons.publish_rounded),
                      label: Text(_fr ? 'Créer le cours' : 'Create course'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    titleFr.dispose(); titleEn.dispose(); descFr.dispose(); descEn.dispose(); contentFr.dispose(); contentEn.dispose();
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
      await _resources.uploadResource(courseId: course['id'].toString(), file: file, resourceType: type, position: count.count, titleFr: file.name, titleEn: file.name);
      _snack(_fr ? 'Contenu ajouté à la salle et au cours.' : 'Content added to the classroom course.');
    } catch (e) { _snack(_fr ? 'Échec de l’envoi : $e' : 'Upload failed: $e'); }
  }

  Future<void> _viewResources(Map<String, dynamic> course) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      _snack(_fr ? 'Connectez-vous pour ouvrir les fichiers.' : 'Sign in to open files.');
      return;
    }
    try {
      final resources = await _resources.listForCourse(course['id'].toString());
      if (!mounted) return;
      if (resources.isEmpty) {
        _snack(_fr ? 'Aucun fichier dans ce cours.' : 'No files in this course.');
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.72,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: resources.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final resource = resources[index];
                final icon = switch (resource.resourceType) {
                  'pdf' => Icons.picture_as_pdf_rounded,
                  'image' => Icons.image_rounded,
                  'video' => Icons.video_library_rounded,
                  'audio' => Icons.audiotrack_rounded,
                  _ => Icons.insert_drive_file_rounded,
                };
                return ListTile(
                  leading: Icon(icon, color: const Color(0xFF166534)),
                  title: Text(resource.fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_fr ? 'Téléchargé à la première ouverture' : 'Downloaded when first opened'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    try {
                      final localPath = await CourseOfflineService().openResource(
                        userId: userId,
                        resource: resource,
                      );
                      if (!mounted) return;
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
                    } catch (_) {
                      if (mounted) {
                        _snack(_fr
                            ? 'Ouvrez ce fichier une première fois avec Internet pour le garder hors ligne.'
                            : 'Open this file once while online to keep it available offline.');
                      }
                    }
                  },
                );
              },
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        _snack(_fr ? 'Impossible de charger les fichiers : $error' : 'Unable to load files: $error');
      }
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
          return Card(child: ListTile(isThreeLine: true, leading: const CircleAvatar(backgroundColor: Color(0xFF166534), child: Icon(Icons.menu_book, color: Colors.white)), title: Text(_name(c), style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${room['display_name'] ?? ''}\n${_nestedName(subject, 'name_fr', 'name_en')} • ${c['status'] ?? 'draft'}'), trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'resource') _addResource(c); if (v == 'open') _viewResources(Map<String, dynamic>.from(c)); }, itemBuilder: (_) => [PopupMenuItem(value: 'open', child: Text(_fr ? 'Ouvrir les fichiers' : 'Open files')), PopupMenuItem(value: 'resource', child: Text(_fr ? 'Ajouter photo/PDF/fichier' : 'Add photo/PDF/file'))])));
        })))
      ]),
    );
  }
}
