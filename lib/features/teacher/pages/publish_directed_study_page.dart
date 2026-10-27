import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/pedagogy_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/school_class.dart';
import '../../../models/user_profile.dart';

class PublishDirectedStudyPage extends StatefulWidget {
  final Locale locale;
  final UserProfile? profile;
  final bool adminMode;

  const PublishDirectedStudyPage({
    super.key,
    required this.locale,
    this.profile,
    this.adminMode = false,
  });

  @override
  State<PublishDirectedStudyPage> createState() => _PublishDirectedStudyPageState();
}

class _PublishDirectedStudyPageState extends State<PublishDirectedStudyPage> {
  final _db = Supabase.instance.client;
  final _coursesService = CourseService();
  final _title = TextEditingController();
  final _description = TextEditingController();
  late Future<List<Course>> _coursesFuture;
  late Future<List<SchoolClass>> _classesFuture;
  Course? _course;
  PlatformFile? _file;
  final Set<String> _selectedClassIds = {};
  bool _saving = false;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _coursesFuture = _loadCourses();
    _classesFuture = _loadClasses();
  }

  Future<List<Course>> _loadCourses() async {
    if (!widget.adminMode) {
      final profile = widget.profile;
      if (profile == null) {
        throw StateError('Teacher profile is required.');
      }
      return _coursesService.listTeacherCourses(profile.id);
    }

    final rows = await _db
        .from('courses')
        .select()
        .order('created_at', ascending: false);
    return rows
        .whereType<Map>()
        .map((row) => Course.fromMap(Map<String, dynamic>.from(row)))
        .where((course) => course.status != 'archived' && course.classId != null)
        .toList(growable: false);
  }

  Future<List<SchoolClass>> _loadClasses() async {
    if (widget.adminMode) return const <SchoolClass>[];
    final profile = widget.profile;
    if (profile == null) {
      throw StateError('Teacher profile is required.');
    }
    return _coursesService.listTeacherClasses(profile.id);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _file = result.files.single);
  }

  Future<void> _publish() async {
    final course = _course;
    final file = _file;
    if (course == null || course.classId == null) {
      _message(_fr ? 'Choisissez un cours associé à une salle.' : 'Choose a course linked to a classroom.');
      return;
    }
    if (_title.text.trim().isEmpty || file == null) {
      _message(_fr ? 'Ajoutez le titre et le fichier PDF du TD.' : 'Enter a title and choose the TD PDF.');
      return;
    }
    if (_selectedClassIds.isEmpty) {
      _message(_fr
          ? 'Choisissez le cours et sa salle avant de publier.'
          : 'Choose the course and its classroom before publishing.');
      return;
    }

    setState(() => _saving = true);
    String? uploadedPath;
    try {
      if (!widget.adminMode) {
        final compatibleSelections = await _db
            .from('class_subjects')
            .select('class_id')
            .eq('subject_id', course.subjectId)
            .eq('is_active', true)
            .inFilter('class_id', _selectedClassIds.toList(growable: false));
        final validIds = compatibleSelections
            .map((row) => row['class_id'].toString())
            .toSet();
        if (!validIds.containsAll(_selectedClassIds)) {
          throw StateError(_fr
              ? 'Chaque salle choisie doit proposer la matière de ce cours.'
              : 'Every selected classroom must offer this course subject.');
        }
      }
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError(_fr ? 'Le fichier PDF est vide ou illisible.' : 'The PDF is empty or unreadable.');
      }
      final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final uploaderId = _db.auth.currentUser?.id;
      if (uploaderId == null) {
        throw StateError('Session introuvable.');
      }
      uploadedPath = '${uploaderId}/${DateTime.now().microsecondsSinceEpoch}-$safeName';
      await _db.storage.from('directed-study-files').uploadBinary(
        uploadedPath,
        bytes,
        fileOptions: const FileOptions(contentType: 'application/pdf', upsert: false),
      );
      await _db.from('directed_studies').insert({
        'course_id': course.id,
        'source_class_id': course.classId,
        'subject_id': course.subjectId,
        'teacher_id': course.teacherId,
        'title': _title.text.trim(),
        'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
        'storage_path': uploadedPath,
        'file_name': file.name,
        'requested_class_ids': _selectedClassIds.toList(growable: false),
        'status': 'published',
        'published_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (!mounted) return;
      _message(_fr
          ? 'TD publié. Les salles compatibles sont ajoutées automatiquement.'
          : 'TD published. Compatible classrooms are added automatically.');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (uploadedPath != null) {
        try { await _db.storage.from('directed-study-files').remove([uploadedPath]); } catch (_) {}
      }
      if (mounted) _message('${_fr ? 'Publication impossible' : 'Could not publish'}: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _fr
              ? (widget.adminMode
                  ? 'Publier un TD — administration'
                  : 'Publier un travail dirigé')
              : (widget.adminMode
                  ? 'Publish TD — administration'
                  : 'Publish a directed study'),
        ),
      ),
      body: FutureBuilder<List<Course>>(
        future: _coursesFuture,
        builder: (context, courseSnapshot) {
          if (courseSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final courses = (courseSnapshot.data ?? const <Course>[])
              .where((course) => course.status != 'archived' && course.classId != null)
              .toList(growable: false);
          return FutureBuilder<List<SchoolClass>>(
            future: _classesFuture,
            builder: (context, classSnapshot) {
              if (classSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final rooms = classSnapshot.data ?? const <SchoolClass>[];
              final eligibleRooms = _course == null
                  ? <SchoolClass>[]
                  : rooms.where((room) =>
                      room.subsystem == rooms.where((r) => r.id == _course!.classId).firstOrNull?.subsystem &&
                      room.sector == rooms.where((r) => r.id == _course!.classId).firstOrNull?.sector &&
                      room.id != _course!.classId &&
                      _course!.subjectId.isNotEmpty).toList(growable: false);
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(_fr
                      ? 'Le TD est attaché au cours, pas à un chapitre. Après publication, Fise School recherche les salles compatibles pour la même matière.'
                      : 'The TD belongs to the course, not a chapter. After publishing, Fise School finds compatible classrooms for the same subject.',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<Course>(
                    value: _course,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: _fr ? 'Cours concerné' : 'Course'),
                    items: courses.map((course) => DropdownMenuItem(
                      value: course,
                      child: Text(course.labelFor(widget.locale.languageCode), overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (value) => setState(() {
                      _course = value;
                      _selectedClassIds.clear();
                      if (value?.classId != null) _selectedClassIds.add(value!.classId!);
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _title,
                    decoration: InputDecoration(labelText: _fr ? 'Titre du TD' : 'Directed study title'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _description,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(labelText: _fr ? 'Consignes (facultatif)' : 'Instructions (optional)'),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _pickPdf,
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: Text(_file?.name ?? (_fr ? 'Choisir le PDF du TD' : 'Choose TD PDF')),
                  ),
                  const SizedBox(height: 20),
                  if (widget.adminMode)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE4F2E9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _fr
                            ? 'Le TD sera publié au nom de l’enseignant du cours sélectionné et diffusé automatiquement aux salles compatibles.'
                            : 'The TD will be published under the selected course teacher and automatically shared with compatible classrooms.',
                      ),
                    )
                  else ...[
                    Text(
                      _fr ? 'Salles que vous suivez' : 'Classrooms you teach',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _fr
                          ? 'Choisissez une ou plusieurs salles. Les salles compatibles seront ajoutées automatiquement après publication.'
                          : 'Choose one or more classrooms. Compatible classrooms will be added automatically after publishing.',
                    ),
                    ...rooms.where((room) => _course == null
                        ? true
                        : room.id == _course!.classId || eligibleRooms.any((candidate) => candidate.id == room.id))
                      .map((room) => CheckboxListTile(
                        value: _selectedClassIds.contains(room.id),
                        title: Text(room.displayName),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (checked) => setState(() {
                          if (checked == true) {
                            _selectedClassIds.add(room.id);
                          } else {
                            _selectedClassIds.remove(room.id);
                          }
                        }),
                      )),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _saving ? null : _publish,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.publish_rounded),
                    label: Text(_saving ? (_fr ? 'Publication...' : 'Publishing...') : (_fr ? 'Publier le TD' : 'Publish TD')),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
