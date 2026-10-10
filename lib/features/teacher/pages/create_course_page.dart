import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/pedagogy_service.dart';
import '../../../core/services/photo_service.dart';
import '../../../core/services/smart_course_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/school_class.dart';
import '../../../models/user_profile.dart';
import '../widgets/class_subject_picker.dart';

class _CourseAttachment {
  final String name;
  final Uint8List bytes;
  final String resourceType;

  const _CourseAttachment({
    required this.name,
    required this.bytes,
    required this.resourceType,
  });
}

/// Création d'un cours : l'enseignant choisit la ou les classes, la matière,
/// écrit son cours et joint un PDF, une photo ou des images.
class CreateCoursePage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const CreateCoursePage({
    super.key,
    required this.locale,
    required this.profile,
  });

  @override
  State<CreateCoursePage> createState() => _CreateCoursePageState();
}

class _CreateCoursePageState extends State<CreateCoursePage> {
  final CourseService _service = CourseService();
  final ResourceService _resources = ResourceService();
  final PhotoService _photos = PhotoService();
  final SmartCourseService _smart = SmartCourseService();
  final ImagePicker _imagePicker = ImagePicker();

  final _title = TextEditingController();

  List<SchoolClass> _classes = const [];
  Subject? _subject;
  final List<_CourseAttachment> _attachments = [];
  bool _saving = false;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _takePhoto() async {
    final file = await _photos.takePhoto();
    if (file == null) {
      return;
    }
    final bytes = await file.readAsBytes();
    if (!mounted) {
      return;
    }
    setState(() {
      _attachments.add(
        _CourseAttachment(
          name: 'photo-${DateTime.now().millisecondsSinceEpoch}.jpg',
          bytes: bytes,
          resourceType: 'image',
        ),
      );
    });
  }

  Future<void> _pickImages() async {
    final files = await _imagePicker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty) {
      return;
    }
    final added = <_CourseAttachment>[];
    for (final file in files) {
      final bytes = await file.readAsBytes();
      final name = file.name.isEmpty
          ? 'image-${DateTime.now().millisecondsSinceEpoch}.jpg'
          : file.name;
      added.add(
        _CourseAttachment(name: name, bytes: bytes, resourceType: 'image'),
      );
    }
    if (!mounted) {
      return;
    }
    setState(() => _attachments.addAll(added));
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mov', 'm4v', 'webm', 'mkv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _attachments.add(
        _CourseAttachment(
          name: file.name,
          bytes: bytes,
          resourceType: 'video',
        ),
      );
    });
  }

  Future<void> _save(String status) async {
    final title = _title.text.trim();

    if (_classes.isEmpty) {
      _snack(_fr ? 'Choisissez au moins une classe.' : 'Choose at least one class.');
      return;
    }
    if (_subject == null) {
      _snack(_fr ? 'Choisissez la matière.' : 'Choose the subject.');
      return;
    }
    if (title.isEmpty) {
      _snack(_fr ? 'Donnez un titre au cours.' : 'Give the course a title.');
      return;
    }
    if (_attachments.isEmpty) {
      _snack(_fr
          ? 'Ajoutez au moins une photo ou une vidéo.'
          : 'Add at least one photo or video.');
      return;
    }

    setState(() => _saving = true);

    try {
      await _service.authorizeTeacherClasses(
        _classes.map((schoolClass) => schoolClass.id).toList(growable: false),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('${_fr ? 'Accès aux salles refusé' : 'Classroom access denied'}: $error');
      }
      return;
    }

    var published = 0;
    final errors = <String>[];
    final indexingFailures = <String>[];

    for (final schoolClass in _classes) {
      try {
        final course = await _service.saveCourse(
          subjectId: _subject!.id,
          teacherId: widget.profile.id,
          classId: schoolClass.id,
          titleFr: title,
          titleEn: title,
          contentFr: null,
          contentEn: null,
          smartLessonEnabled: false,
          status: status,
        );

        for (var i = 0; i < _attachments.length; i++) {
          final attachment = _attachments[i];
          final resource = await _resources.uploadResource(
            courseId: course.id,
            file: PlatformFile(
              name: attachment.name,
              size: attachment.bytes.length,
              bytes: attachment.bytes,
            ),
            resourceType: attachment.resourceType,
            position: i,
            titleFr: attachment.name,
            titleEn: attachment.name,
          );
          // Photos attached while creating a course must enter the same
          // indexing flow as photos added later from the resource library.
          // Approval remains explicit in the resource details before AI use.
          if (attachment.resourceType == 'image') {
            try {
              await _smart.reindexResource(resource.id);
            } catch (_) {
              indexingFailures.add('${schoolClass.displayName}: ${attachment.name}');
            }
          }
        }
        published++;
      } catch (error) {
        errors.add('${schoolClass.displayName}: $error');
      }
    }

    if (!mounted) {
      return;
    }
    setState(() => _saving = false);

    if (errors.isNotEmpty) {
      _snack(
        '${_fr ? 'Erreur' : 'Error'} (${errors.length}/${_classes.length})\n${errors.first}',
      );
      if (published == 0) {
        return;
      }
    } else if (indexingFailures.isNotEmpty && status == 'published') {
      _snack(_fr
          ? 'Cours publié dans $published classe(s), mais l’indexation de ${indexingFailures.length} photo(s) a échoué. Réessayez depuis les ressources du cours.'
          : 'Course published to $published classroom(s), but ${indexingFailures.length} photo(s) could not be indexed. Retry from course resources.');
    } else {
      _snack(status == 'published'
          ? (_fr ? 'Cours publié dans $published classe(s).' : 'Course published in $published class(es).')
          : (_fr ? 'Brouillon enregistré.' : 'Draft saved.'));
    }

    Navigator.pop(context, true);
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'image':
        return Icons.image_rounded;
      case 'video':
        return Icons.videocam_rounded;
      case 'audio':
        return Icons.audiotrack_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_fr ? 'Partager des médias' : 'Share media')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ClassSubjectPicker(
            locale: widget.locale,
            teacherId: widget.profile.id,
            includeCompatibleClasses: true,
            onChanged: (classes, subject) {
              setState(() {
                _classes = classes;
                _subject = subject;
              });
            },
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: _fr ? 'Titre ou légende du média' : 'Media title or caption',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFE8F5EC), borderRadius: BorderRadius.circular(14)),
            child: Text(_fr
                ? 'Les enseignants partagent ici uniquement des photos et des vidéos. Les cours écrits et les PDF sont publiés par l’administration.'
                : 'Teachers can share photos and videos here. Written lessons and PDFs are published by the administration.'),
          ),
          const SizedBox(height: 16),
          Text(
            _fr ? 'Photos et vidéos' : 'Photos and videos',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.camera_alt_rounded, size: 18),
                label: Text(_fr ? 'Prendre une photo' : 'Take a photo'),
                onPressed: _saving ? null : _takePhoto,
              ),
              ActionChip(
                avatar: const Icon(Icons.image_rounded, size: 18),
                label: Text(_fr ? 'Images' : 'Images'),
                onPressed: _saving ? null : _pickImages,
              ),
              ActionChip(
                avatar: const Icon(Icons.videocam_rounded, size: 18),
                label: Text(_fr ? 'Choisir une vidéo' : 'Choose a video'),
                onPressed: _saving ? null : _pickVideo,
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _attachments.length; i++)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                leading: _attachments[i].resourceType == 'image'
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(
                          _attachments[i].bytes,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Icon(_iconFor(_attachments[i].resourceType)),
                title: Text(_attachments[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _saving ? null : () => setState(() => _attachments.removeAt(i)),
                ),
              ),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _save('draft'),
                  child: Text(_fr ? 'Enregistrer' : 'Save'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : () => _save('published'),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_fr ? 'Publier les médias' : 'Publish media'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
