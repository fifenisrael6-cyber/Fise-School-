
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/pedagogy_service.dart';
import '../../../core/widgets/course_table_embed.dart';
import '../../../core/widgets/course_image_embed.dart';
import '../../../core/services/offline_pdf_course_importer.dart';
import '../../../core/widgets/pdf_import_preview_dialog.dart';
import 'school_classes_page.dart';
import 'admin_chapter_content_page.dart';
import '../../../models/pedagogy.dart';

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

  Future<void> _importPdfIntoEditor(
    BuildContext context,
    QuillController controller,
    StateSetter setDialog,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes ??
          (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null || bytes.isEmpty) {
        _snack(_fr ? 'Impossible de lire ce fichier PDF.' : 'Unable to read this PDF file.');
        return;
      }

      var completed = 0;
      var total = 1;
      StateSetter? updateProgress;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setProgress) {
            updateProgress = setProgress;
            return AlertDialog(
              title: Text(_fr ? 'Analyse du PDF' : 'Analyzing PDF'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(value: total == 0 ? null : completed / total),
                  const SizedBox(height: 12),
                  Text(_fr
                      ? 'Pages traitées : $completed / $total. Le traitement continue par lots de 10 pages.'
                      : 'Pages processed: $completed / $total. Processing continues in batches of 10 pages.'),
                ],
              ),
            );
          },
        ),
      );

      List<Map<String, dynamic>> blocks;
      try {
        blocks = await OfflinePdfCourseImporter().importFile(
          bytes,
          onProgress: (done, count) {
            completed = done;
            total = count;
            updateProgress?.call(() {});
          },
        );
      } finally {
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      }
      if (!context.mounted || blocks.isEmpty) {
        if (context.mounted) _snack(_fr ? 'Aucun texte exploitable trouvé dans ce PDF.' : 'No usable text was found in this PDF.');
        return;
      }

      final selected = await showDialog<List<Map<String, dynamic>>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PdfImportPreviewDialog(blocks: blocks),
      );
      if (selected == null || selected.isEmpty || !context.mounted) return;

      final selection = controller.selection;
      final start = selection.isValid ? selection.start : controller.document.length - 1;
      if (selection.isValid && selection.end > selection.start) {
        controller.replaceText(
          start,
          selection.end - selection.start,
          '',
          TextSelection.collapsed(offset: start),
        );
      }
      var offset = start;
      for (final block in selected) {
        final type = block['type']?.toString() ?? 'paragraph';
        if (type == 'table') {
          final cells = (block['cells'] as List? ?? const [])
              .map((row) => (row as List).map((cell) => cell.toString()).toList())
              .toList();
          if (cells.isNotEmpty) {
            controller.document.insert(
              offset,
              BlockEmbed.custom(CourseTableEmbed.fromCells(
                cells: cells,
                firstRowHeader: block['firstRowHeader'] == true,
              )),
            );
            offset += 1;
            controller.document.insert(offset, '\n');
            offset += 1;
          }
          continue;
        }
        if (type == 'image') {
          final data = block['data']?.toString() ?? '';
          if (data.startsWith('data:image/')) {
            controller.document.insert(offset, BlockEmbed.image(data));
            offset += 1;
            controller.document.insert(offset, '\n');
            offset += 1;
          }
          continue;
        }
        final text = block['text']?.toString().trim() ?? '';
        if (text.isEmpty) continue;
        controller.document.insert(offset, text);
        controller.document.insert(offset + text.length, '\n');
        final length = text.length + 1;
        if (type == 'heading') {
          final level = block['level'] as int? ?? 2;
          final attribute = level <= 1 ? Attribute.h1 : level == 2 ? Attribute.h2 : Attribute.h3;
          controller.formatText(offset, length, attribute);
        } else if (type == 'list') {
          controller.formatText(offset, length, block['ordered'] == true ? Attribute.ol : Attribute.ul);
        }
        offset += length;
      }
      controller.updateSelection(
        TextSelection.collapsed(offset: offset),
        ChangeSource.local,
      );
      setDialog(() {});
      _snack(_fr ? '${selected.length} bloc(s) PDF inséré(s) dans le cours.' : '${selected.length} PDF block(s) inserted into the course.');
    } on FormatException catch (e) {
      if (context.mounted) _snack(e.message);
    } catch (e) {
      if (context.mounted) {
        _snack(_fr ? 'Échec de l’import PDF : $e' : 'PDF import failed: $e');
      }
    }
  }

  Future<void> _insertImageIntoEditor(
    QuillController controller,
    StateSetter setDialog,
  ) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1800,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) {
      _snack(_fr ? 'Image vide ou illisible.' : 'The image is empty or unreadable.');
      return;
    }
    final extension = picked.name.split('.').last.toLowerCase();
    final mime = extension == 'png' ? 'image/png' : extension == 'webp' ? 'image/webp' : 'image/jpeg';
    final dataUri = 'data:' + mime + ';base64,' + base64Encode(bytes);
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : controller.document.length - 1;
    final length = selection.isValid ? selection.end - selection.start : 0;
    if (length > 0) {
      controller.replaceText(start, length, '', TextSelection.collapsed(offset: start));
    }
    controller.document.insert(start, BlockEmbed.image(dataUri));
    controller.document.insert(start + 1, '\n');
    controller.updateSelection(TextSelection.collapsed(offset: start + 2), ChangeSource.local);
    setDialog(() {});
  }

  Future<void> _createCourse() async {
    final classes = List<Map<String, dynamic>>.from(
      await _client.from('school_classes').select('id,display_name,name,subsystem,sector,exam_level_id,series_id,specialty_id,is_active').eq('is_active', true).order('display_name'),
    );
    if (!mounted) {
      return;
    }
    if (classes.isEmpty) {
      _snack(_fr ? 'Créez d’abord une salle active.' : 'Create an active classroom first.');
      return;
    }

    Map<String, dynamic>? selectedClass = classes.first;
    final selectedClassIds = <String>{classes.first['id'].toString()};
    List<Map<String, dynamic>> subjects = [];
    Map<String, dynamic>? selectedSubject;
    List<Map<String, dynamic>> curricula = [];
    Map<String, dynamic>? selectedCurriculum;
    List<Map<String, dynamic>> chapters = [];
    Map<String, dynamic>? selectedChapter;
    final selectedChapters = <Map<String, dynamic>>[];

    final titleFr = TextEditingController();
    final contentFr = QuillController.basic();
    final contentEn = TextEditingController();
    bool published = false;
    bool saving = false;

    Future<void> loadSubjects(StateSetter setDialog) async {
      final rows = await _client.from('class_subjects').select('subject_id,subjects(id,name_fr,name_en,code)').eq('class_id', selectedClass!['id']).eq('is_active', true).order('position');
      subjects = List<Map<String, dynamic>>.from(rows);
      selectedSubject = subjects.isEmpty ? null : subjects.first['subjects'] as Map<String, dynamic>;
      curricula = [];
      chapters = [];
      selectedCurriculum = null;
      selectedChapter = null;
      selectedChapters.clear();
      if (selectedSubject != null) {
        curricula = await _curriculaForClass(selectedSubject!['id'].toString(), selectedClass!);
        selectedCurriculum = curricula.isEmpty ? null : curricula.first;
        if (selectedCurriculum != null) {
          chapters = List<Map<String, dynamic>>.from(await _client.from('course_chapters').select().eq('curriculum_id', selectedCurriculum!['id']).eq('is_active', true).order('position'));
          selectedChapter = chapters.isEmpty ? null : chapters.first;
          if (selectedChapter != null) selectedChapters.add(selectedChapter!);
        }
      }
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
                      onChanged: saving ? null : (value) async {
                        if (value == null) return;
                        selectedClass = value;
                        selectedClassIds
                          ..clear()
                          ..add(value['id'].toString());
                        await loadSubjects(setDialog);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(_fr ? 'Autres salles compatibles' : 'Other compatible classrooms',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: classes.where((c) =>
                        c['id'] != selectedClass?['id'] &&
                        c['subsystem'] == selectedClass?['subsystem'] &&
                        c['sector'] == selectedClass?['sector'] &&
                        c['exam_level_id'] == selectedClass?['exam_level_id'] &&
                        c['specialty_id'] == selectedClass?['specialty_id']
                      ).map((c) {
                        final id = c['id'].toString();
                        return FilterChip(
                          label: Text(c['display_name']?.toString() ?? c['name']?.toString() ?? ''),
                          selected: selectedClassIds.contains(id),
                          onSelected: saving ? null : (checked) => setDialog(() {
                            if (checked) {
                              selectedClassIds.add(id);
                            } else {
                              selectedClassIds.remove(id);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<Map<String, dynamic>>(
                      isExpanded: true,
                      initialValue: selectedSubject,
                      decoration: InputDecoration(labelText: _fr ? 'Matière de cette salle' : 'Subject in this classroom'),
                      items: subjects.map((s) { final m = Map<String, dynamic>.from(s['subjects'] as Map); return DropdownMenuItem(value: m, child: Text(_nestedName(m, 'name_fr', 'name_en'), maxLines: 1, overflow: TextOverflow.ellipsis)); }).toList(),
                      onChanged: saving ? null : (value) async {
                        selectedSubject = value; selectedCurriculum = null; selectedChapter = null; chapters = [];
                        selectedChapters.clear();
                        if (value != null) {
                          curricula = await _curriculaForClass(value['id'].toString(), selectedClass!);
                          selectedCurriculum = curricula.isEmpty ? null : curricula.first;
                          if (selectedCurriculum != null) {
                            chapters = List<Map<String, dynamic>>.from(await _client.from('course_chapters').select().eq('curriculum_id', selectedCurriculum!['id']).eq('is_active', true).order('position'));
                            selectedChapter = chapters.isEmpty ? null : chapters.first;
                            if (selectedChapter != null) selectedChapters.add(selectedChapter!);
                          }
                        }
                        setDialog(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<Map<String, dynamic>>(
                      isExpanded: true,
                      initialValue: selectedCurriculum,
                      decoration: InputDecoration(labelText: _fr ? 'Programme de cette salle *' : 'Class curriculum *'),
                      items: curricula.map((c) => DropdownMenuItem(value: c, child: Text(_nestedName(c, 'title_fr', 'title_en'), maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: saving ? null : (value) async {
                        selectedCurriculum = value;
                        selectedChapter = null;
                        selectedChapters.clear();
                        chapters = value == null ? [] : List<Map<String, dynamic>>.from(await _client.from('course_chapters').select().eq('curriculum_id', value['id']).eq('is_active', true).order('position'));
                        selectedChapter = chapters.isEmpty ? null : chapters.first;
                        if (selectedChapter != null) selectedChapters.add(selectedChapter!);
                        setDialog(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(_fr ? 'Chapitres à alimenter' : 'Chapters to fill',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 4),
                    ...chapters.map((chapterOption) {
                      final id = chapterOption['id'].toString();
                      final checked = selectedChapters.any((item) => item['id'].toString() == id);
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: checked,
                        title: Text(_nestedName(chapterOption, 'title_fr', 'title_en')),
                        onChanged: saving ? null : (value) => setDialog(() {
                          selectedChapters.removeWhere((item) => item['id'].toString() == id);
                          if (value == true) selectedChapters.add(chapterOption);
                          selectedChapter = selectedChapters.isEmpty ? null : selectedChapters.first;
                        }),
                      );
                    }),
                    const SizedBox(height: 12),
                    TextField(controller: titleFr, decoration: InputDecoration(labelText: 'Titre français *')),
                    const SizedBox(height: 10),

                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(_fr ? 'Contenu du cours (français)' : 'Course content (French)',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: saving ? null : () => _importPdfIntoEditor(context, contentFr, setDialog),
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: Text(_fr ? 'Importer un PDF' : 'Import a PDF'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              QuillSimpleToolbar(
                                controller: contentFr,
                                config: const QuillSimpleToolbarConfig(
                                  multiRowsDisplay: false,
                                ),
                              ),
                              const SizedBox(width: 6),
                              OutlinedButton.icon(
                                onPressed: saving ? null : () => _insertImageIntoEditor(contentFr, setDialog),
                                icon: const Icon(Icons.add_photo_alternate_outlined),
                                label: const Text('Image'),
                              ),
                              OutlinedButton.icon(
                                onPressed: saving ? null : () async {
                                  final dimensions = await showDialog<List<int>>(
                                    context: context,
                                    builder: (dialogContext) {
                                      final rowsController = TextEditingController(text: '3');
                                      final columnsController = TextEditingController(text: '3');
                                      return AlertDialog(
                                        title: const Text('Insérer un tableau'),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            TextField(controller: rowsController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nombre de lignes')),
                                            TextField(controller: columnsController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nombre de colonnes')),
                                          ],
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
                                          FilledButton(
                                            onPressed: () {
                                              final rows = int.tryParse(rowsController.text) ?? 0;
                                              final columns = int.tryParse(columnsController.text) ?? 0;
                                              if (rows < 1 || columns < 1 || rows > 20 || columns > 12) return;
                                              Navigator.pop(dialogContext, [rows, columns]);
                                            },
                                            child: const Text('Créer'),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                  if (dimensions == null || !context.mounted) return;
                                  final cells = List.generate(
                                    dimensions[0],
                                    (_) => List<String>.filled(dimensions[1], ''),
                                  );
                                  final selection = contentFr.selection;
                                  final start = selection.isValid ? selection.start : contentFr.document.length - 1;
                                  final length = selection.isValid ? selection.end - selection.start : 0;
                                  contentFr.replaceText(
                                    start,
                                    length,
                                    BlockEmbed.custom(CourseTableEmbed.fromCells(
                                      cells: cells,
                                      firstRowHeader: false,
                                    )),
                                    TextSelection.collapsed(offset: start + 1),
                                  );
                                },
                                icon: const Icon(Icons.table_chart_outlined),
                                label: const Text('Tableau'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(minHeight: 300),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: QuillEditor.basic(
                            controller: contentFr,
                            config: QuillEditorConfig(
                              padding: const EdgeInsets.all(8),
                              expands: false,
                              embedBuilders: [CourseTableEmbedBuilder(), CourseImageEmbedBuilder()],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(value: published, onChanged: saving ? null : (v) => setDialog(() => published = v), title: Text(_fr ? 'Publier immédiatement' : 'Publish immediately'), contentPadding: EdgeInsets.zero),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: saving || selectedSubject == null || selectedCurriculum == null || selectedChapters.isEmpty || selectedClassIds.isEmpty || titleFr.text.trim().isEmpty ? null : () async {
                        setDialog(() => saving = true);
                        try {
                          final teacherId = _client.auth.currentUser!.id;
                          final encodedContent = jsonEncode(contentFr.document.toDelta().toJson());
                          var savedCount = 0;
                          final skippedTargets = <String>[];
                          for (final classId in selectedClassIds) {
                            final targetClass = classes.firstWhere((c) => c['id'].toString() == classId);
                            final subjectRows = await _client
                                .from('class_subjects')
                                .select('subject_id')
                                .eq('class_id', classId)
                                .eq('subject_id', selectedSubject!['id'])
                                .eq('is_active', true);
                            if ((subjectRows as List).isEmpty) {
                              skippedTargets.add(targetClass['display_name']?.toString() ?? classId);
                              continue;
                            }
                            final targetCurricula = await _curriculaForClass(
                              selectedSubject!['id'].toString(),
                              targetClass,
                            );
                            if (targetCurricula.isEmpty) {
                              skippedTargets.add(targetClass['display_name']?.toString() ?? classId);
                              continue;
                            }
                            final wantedCurriculumTitle = _nestedName(selectedCurriculum!, 'title_fr', 'title_en').trim().toLowerCase();
                            final targetCurriculum = targetCurricula.firstWhere(
                              (item) => _nestedName(item, 'title_fr', 'title_en').trim().toLowerCase() == wantedCurriculumTitle,
                              orElse: () => targetCurricula.first,
                            );
                            final targetChapters = List<Map<String, dynamic>>.from(
                              await _client.from('course_chapters')
                                  .select()
                                  .eq('curriculum_id', targetCurriculum['id'])
                                  .eq('is_active', true)
                                  .order('position'),
                            );
                            for (final sourceChapter in selectedChapters) {
                              final wantedFr = (sourceChapter['title_fr']?.toString() ?? '').trim().toLowerCase();
                              final wantedEn = (sourceChapter['title_en']?.toString() ?? '').trim().toLowerCase();
                              final matches = targetChapters.where((candidate) =>
                                (candidate['title_fr']?.toString() ?? '').trim().toLowerCase() == wantedFr ||
                                (candidate['title_en']?.toString() ?? '').trim().toLowerCase() == wantedEn
                              );
                              if (matches.isEmpty) continue;
                              final targetChapter = matches.first;
                              await _courses.saveCourse(
                                curriculumId: targetCurriculum['id'].toString(),
                                chapterId: targetChapter['id'].toString(),
                                subjectId: selectedSubject!['id'].toString(),
                                teacherId: teacherId,
                                classId: classId,
                                titleFr: titleFr.text,
                                titleEn: titleFr.text.trim(),
                                descriptionFr: '',
                                descriptionEn: null,
                                contentFr: encodedContent,
                                contentEn: null,
                                status: published ? 'published' : 'draft',
                              );
                              savedCount++;
                            }
                            if (!targetChapters.any((candidate) => selectedChapters.any((sourceChapter) =>
                              (candidate['title_fr']?.toString() ?? '').trim().toLowerCase() == (sourceChapter['title_fr']?.toString() ?? '').trim().toLowerCase() ||
                              (candidate['title_en']?.toString() ?? '').trim().toLowerCase() == (sourceChapter['title_en']?.toString() ?? '').trim().toLowerCase()
                            ))) {
                              skippedTargets.add(targetClass['display_name']?.toString() ?? classId);
                            }
                          }
                          if (savedCount == 0) {
                            throw StateError(_fr
                              ? 'Aucun chapitre correspondant trouvé dans les salles sélectionnées.'
                              : 'No matching chapter was found in the selected classrooms.');
                          }
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                            final skipped = skippedTargets.isEmpty ? '' : (_fr
                              ? ' Salles ignorées : ${skippedTargets.join(', ')}.'
                              : ' Skipped classrooms: ${skippedTargets.join(', ')}.');
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(_fr
                                ? '${savedCount} cours enregistrés dans les chapitres sélectionnés.$skipped'
                                : '${savedCount} courses saved in selected chapters.$skipped'),
                            ));
                          }
                          await _load();
                        } on PostgrestException catch (e) {
                          setDialog(() => saving = false);
                          if (!sheetContext.mounted) {
                            return;
                          }
                          final message = e.code == 'P0001' &&
                                  e.message.toLowerCase().contains('curriculum is not active')
                              ? (_fr
                                  ? 'Le programme sélectionné est inactif. Choisissez un programme actif ou créez le cours sans programme.'
                                  : 'The selected curriculum is inactive. Choose an active curriculum or create the course without a curriculum.')
                              : (_fr
                                  ? 'Impossible de créer le cours : ' + e.message
                                  : 'Unable to create the course: ' + e.message);
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(content: Text(message)),
                          );
                        } catch (e) {
                          setDialog(() => saving = false);
                          if (sheetContext.mounted) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _fr
                                      ? 'Impossible de créer le cours.'
                                      : 'Unable to create the course.',
                                ),
                              ),
                            );
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
    titleFr.dispose(); contentFr.dispose(); contentEn.dispose();
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
            final imported = data['imported'] ?? 0;
            final existing = data['already_exists'] ?? 0;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_fr
                    ? 'Extraction terminée : $imported chapitre(s) préparé(s), $existing déjà présent(s). Les nouveaux cours sont en brouillon.'
                    : 'Extraction complete: $imported chapter(s) prepared, $existing already existed. New lessons are drafts.'),
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
                              if (action == 'replace') {
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
          final message = data is Map ? data['error']?.toString() : null;
          _snack(_fr
            ? 'Document remplacé, mais réimport échoué : ${message ?? 'erreur inconnue'}'
            : 'Document replaced, but re-import failed: ${message ?? 'unknown error'}');
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
          IconButton(
            tooltip: _fr ? 'Gérer les cours par salle et chapitre' : 'Manage courses by class and chapter',
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AdminChapterContentPage(locale: widget.locale)),
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
