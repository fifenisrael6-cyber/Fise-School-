import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/pedagogy_service.dart';
import '../../../core/services/photo_service.dart';
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
  final List<PickedAttachment> initialSharedAttachments;

  const CreateCoursePage({
    super.key,
    required this.locale,
    required this.profile,
    this.initialSharedAttachments = const [],
  });

  @override
  State<CreateCoursePage> createState() => _CreateCoursePageState();
}

class _CreateCoursePageState extends State<CreateCoursePage> {
  final CourseService _service = CourseService();
  final ResourceService _resources = ResourceService();
  final PhotoService _photos = PhotoService();
  final ImagePicker _imagePicker = ImagePicker();

  final _title = TextEditingController();

  List<SchoolClass> _classes = const [];
  Subject? _subject;
  final List<_CourseAttachment> _attachments = [];
  bool _saving = false;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    for (final attachment in widget.initialSharedAttachments) {
      final mime = attachment.mimeType.toLowerCase();
      final type = mime.startsWith('image/')
          ? 'image'
          : mime.startsWith('video/')
              ? 'video'
              : mime.startsWith('audio/')
                  ? 'audio'
                  : mime == 'application/pdf' || attachment.name.toLowerCase().endsWith('.pdf')
                      ? 'pdf'
                      : null;
      if (type != null) {
        _attachments.add(_CourseAttachment(
          name: attachment.name,
          bytes: attachment.bytes,
          resourceType: type,
        ));
      }
    }
  }

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

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = await _readPickedBytes(file);
    if (bytes == null || bytes.isEmpty) {
      _snack(_fr ? 'Impossible de lire le PDF sélectionné.' : 'Unable to read the selected PDF.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _attachments.add(_CourseAttachment(
        name: file.name,
        bytes: bytes,
        resourceType: 'pdf',
      ));
    });
  }

  Future<Uint8List?> _readPickedBytes(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes != null && bytes.isNotEmpty) return bytes;
    final path = file.path;
    if (path == null || path.isEmpty) return null;
    try { return await File(path).readAsBytes(); } catch (_) { return null; }
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'opus', 'flac'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = await _readPickedBytes(file);
    if (bytes == null || bytes.isEmpty) {
      _snack(_fr ? 'Impossible de lire le fichier audio.' : 'Unable to read the audio file.');
      return;
    }
    if (!mounted) return;
    setState(() => _attachments.add(_CourseAttachment(name: file.name, bytes: bytes, resourceType: 'audio')));
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
    final bytes = await _readPickedBytes(file);
    if (bytes == null || bytes.isEmpty) {
      _snack(_fr ? 'Impossible de lire la vidéo sélectionnée.' : 'Unable to read the selected video.');
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
          ? 'Ajoutez au moins une photo, vidéo, PDF ou fichier audio.'
          : 'Add at least one photo, video, PDF or audio file.');
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
          // Keep the course hidden from students while attachments are pending.
          status: 'draft',
        );

        for (var i = 0; i < _attachments.length; i++) {
          final attachment = _attachments[i];
          await _resources.uploadResource(
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
        }

        if (status == 'published') {
          await _service.saveCourse(
            id: course.id,
            subjectId: _subject!.id,
            teacherId: widget.profile.id,
            classId: schoolClass.id,
            titleFr: title,
            titleEn: title,
            contentFr: null,
            contentEn: null,
            smartLessonEnabled: false,
            status: 'published',
          );
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
                ? 'Partagez des photos, vidéos, PDF et fichiers audio dans la salle choisie.'
                : 'Share photos, videos, PDFs and audio files with the selected classroom.'),
          ),
          const SizedBox(height: 16),
          Text(
            _fr ? 'Photos, vidéos, PDF et audio' : 'Photos, videos, PDFs and audio',
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
              ActionChip(
                avatar: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: Text(_fr ? 'Choisir un PDF' : 'Choose a PDF'),
                onPressed: _saving ? null : _pickPdf,
              ),
              ActionChip(
                avatar: const Icon(Icons.audiotrack_rounded, size: 18),
                label: Text(_fr ? 'Choisir un audio' : 'Choose audio'),
                onPressed: _saving ? null : _pickAudio,
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
