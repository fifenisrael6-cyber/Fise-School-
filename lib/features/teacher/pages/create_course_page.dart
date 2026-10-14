import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final String folderKey;

  const _CourseAttachment({
    required this.name,
    required this.bytes,
    required this.resourceType,
    required this.folderKey,
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
  final SmartCourseService _smart = SmartCourseService();
  final ImagePicker _imagePicker = ImagePicker();

  final _title = TextEditingController();

  List<SchoolClass> _classes = const [];
  Subject? _subject;
  final Map<String, Curriculum?> _curriculumByClass = <String, Curriculum?>{};
  final Map<String, List<CourseChapter>> _chaptersByClass = <String, List<CourseChapter>>{};
  final Map<String, String> _selectedChapterByClass = <String, String>{};
  bool _loadingChapters = false;
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
          folderKey: _folderKeyForType(type),
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
          folderKey: _folderKeyForType('image'),
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
        _CourseAttachment(name: name, bytes: bytes, resourceType: 'image', folderKey: _folderKeyForType('image')),
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
        folderKey: _folderKeyForType('pdf'),
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
    setState(() => _attachments.add(_CourseAttachment(name: file.name, bytes: bytes, resourceType: 'audio', folderKey: _folderKeyForType('audio'))));
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
          folderKey: _folderKeyForType('video'),
        ),
      );
    });
  }

  /// Charge les chapitres correspondant à chaque classe sélectionnée.
  /// Les filières peuvent avoir des programmes différents : le choix du chapitre
  /// est donc conservé séparément pour chaque classe, sans mélanger les catalogues.
  Future<void> _loadChapterOptions(
    List<SchoolClass> classes,
    Subject? subject,
  ) async {
    _curriculumByClass.clear();
    _chaptersByClass.clear();
    _selectedChapterByClass.clear();
    if (classes.isEmpty || subject == null) {
      if (mounted) setState(() => _loadingChapters = false);
      return;
    }

    setState(() => _loadingChapters = true);
    try {
      final curricula = await _service.listCurricula(subject.id);
      for (final schoolClass in classes) {
        final matches = curricula.where((curriculum) =>
          curriculum.subsystem == schoolClass.subsystem &&
          curriculum.sector == schoolClass.sector &&
          (curriculum.examLevelId == null || curriculum.examLevelId == schoolClass.examLevelId) &&
          (curriculum.seriesId == null || curriculum.seriesId == schoolClass.seriesId) &&
          (curriculum.specialtyId == null || curriculum.specialtyId == schoolClass.specialtyId)
        ).toList()
          ..sort((a, b) {
            int specificity(Curriculum value) =>
                (value.examLevelId == null ? 0 : 1) +
                (value.seriesId == null ? 0 : 1) +
                (value.specialtyId == null ? 0 : 1);
            return specificity(b).compareTo(specificity(a));
          });

        final curriculum = matches.isEmpty ? null : matches.first;
        _curriculumByClass[schoolClass.id] = curriculum;
        if (curriculum != null) {
          _chaptersByClass[schoolClass.id] =
              await _service.listChapters(curriculum.id);
        } else {
          _chaptersByClass[schoolClass.id] = const <CourseChapter>[];
        }
      }
    } catch (error) {
      if (mounted) {
        _snack('${_fr ? 'Impossible de charger les chapitres' : 'Unable to load chapters'}: $error');
      }
    } finally {
      if (mounted) setState(() => _loadingChapters = false);
    }
  }

  Future<void> _save() async {
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

    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser == null || authUser.id != widget.profile.id) {
      _snack(_fr
          ? 'Session enseignant incohérente. Déconnectez-vous puis reconnectez-vous avant de partager.'
          : 'Teacher session mismatch. Sign out and sign in again before sharing.');
      return;
    }

    setState(() => _saving = true);

    List<SchoolClass> targets;
    try {
      // Expand the chosen level to the compatible rooms in the same academic
      // year. A room receives the media only when the selected subject exists
      // in its own class_subjects catalogue.
      final compatible = await _service.listTeacherCompatibleClasses();
      final byId = <String, SchoolClass>{for (final room in _classes) room.id: room};
      for (final chosen in _classes) {
        if (chosen.examLevelId == null) continue;
        for (final candidate in compatible) {
          if (candidate.academicYearId == chosen.academicYearId &&
              candidate.subsystem == chosen.subsystem &&
              candidate.sector == chosen.sector &&
              candidate.examLevelId == chosen.examLevelId) {
            byId[candidate.id] = candidate;
          }
        }
      }

      final candidates = byId.values.toList(growable: false);
      targets = <SchoolClass>[];
      for (final candidate in candidates) {
        final subjects = await _service.listSubjectsForClass(candidate.id);
        if (subjects.any((subject) => subject.id == _subject!.id)) {
          targets.add(candidate);
        }
      }
      if (targets.isEmpty) {
        throw StateError(_fr
            ? 'Aucune salle ne possède cette matière dans son programme.'
            : 'No classroom has this subject in its curriculum.');
      }

      await _service.authorizeTeacherClasses(
        targets.map((room) => room.id).toList(growable: false),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('${_fr ? 'Accès ou diffusion des salles refusé' : 'Classroom access or distribution denied'}: $error');
      }
      return;
    }

    CourseChapter? referenceChapter;
    for (final chosen in _classes) {
      final chosenId = _selectedChapterByClass[chosen.id];
      if (chosenId == null) continue;
      for (final chapter in _chaptersByClass[chosen.id] ?? const <CourseChapter>[]) {
        if (chapter.id == chosenId) {
          referenceChapter = chapter;
          break;
        }
      }
      if (referenceChapter != null) break;
    }

    var saved = 0;
    final errors = <String>[];

    for (final schoolClass in targets) {
      try {
        Curriculum? curriculum = _curriculumByClass[schoolClass.id];
        List<CourseChapter> chapters =
            _chaptersByClass[schoolClass.id] ?? const <CourseChapter>[];
        String? selectedChapterId = _selectedChapterByClass[schoolClass.id];

        if (!_curriculumByClass.containsKey(schoolClass.id)) {
          final curricula = await _service.listCurricula(_subject!.id);
          final matches = curricula.where((item) =>
              item.subsystem == schoolClass.subsystem &&
              item.sector == schoolClass.sector &&
              (item.examLevelId == null || item.examLevelId == schoolClass.examLevelId) &&
              (item.seriesId == null || item.seriesId == schoolClass.seriesId) &&
              (item.specialtyId == null || item.specialtyId == schoolClass.specialtyId)).toList()
            ..sort((a, b) {
              int specificity(Curriculum value) =>
                  (value.examLevelId == null ? 0 : 1) +
                  (value.seriesId == null ? 0 : 1) +
                  (value.specialtyId == null ? 0 : 1);
              return specificity(b).compareTo(specificity(a));
            });
          curriculum = matches.isEmpty ? null : matches.first;
          chapters = curriculum == null
              ? const <CourseChapter>[]
              : await _service.listChapters(curriculum.id);
          if (referenceChapter != null) {
            final wantedFr = referenceChapter.titleFr.trim().toLowerCase();
            final wantedEn = referenceChapter.titleEn.trim().toLowerCase();
            final matching = chapters.where((chapter) =>
                chapter.titleFr.trim().toLowerCase() == wantedFr ||
                chapter.titleEn.trim().toLowerCase() == wantedEn).toList();
            if (matching.isEmpty) {
              throw StateError(_fr
                  ? 'Le chapitre commun « ${referenceChapter.titleFr} » n’existe pas dans cette salle.'
                  : 'The shared chapter “${referenceChapter.titleEn}” is unavailable in this classroom.');
            }
            selectedChapterId = matching.first.id;
          }
        }

        if (curriculum == null) {
          throw StateError(_fr
              ? 'Aucun programme officiel n’est associé à ${schoolClass.displayName} pour cette matière. Demandez à l’administrateur de compléter les chapitres avant de publier.'
              : 'No official curriculum is linked to ${schoolClass.displayName} for this subject. Ask the administrator to complete the chapter catalogue before publishing.');
        }
        if (chapters.isEmpty) {
          throw StateError(_fr
              ? 'Aucun chapitre disponible pour ${schoolClass.displayName}. Demandez à l’administrateur de compléter le catalogue.'
              : 'No chapter is available for ${schoolClass.displayName}. Ask the administrator to complete the catalogue.');
        }
        if (selectedChapterId == null) {
          throw StateError(_fr
              ? 'Choisissez un chapitre pour ${schoolClass.displayName}.'
              : 'Choose a chapter for ${schoolClass.displayName}.');
        }

        final course = await _service.saveCourse(
          curriculumId: curriculum.id,
          chapterId: selectedChapterId,
          subjectId: _subject!.id,
          teacherId: widget.profile.id,
          classId: schoolClass.id,
          titleFr: title,
          titleEn: title,
          contentFr: null,
          contentEn: null,
          smartLessonEnabled: false,
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
            folderKey: attachment.folderKey,
            position: i,
            titleFr: attachment.name,
            titleEn: attachment.name,
          );
        }

        final persistedResources = await _resources.listForCourse(course.id);
        if (persistedResources.length < _attachments.length) {
          throw StateError(_fr
              ? 'Publication incomplète : ${persistedResources.length}/${_attachments.length} média(s) enregistrés côté serveur.'
              : 'Incomplete publication: ${persistedResources.length}/${_attachments.length} media record(s) persisted on the server.');
        }

        for (final resource in persistedResources) {
          if (resource.resourceType != 'pdf' && resource.resourceType != 'image') continue;
          try {
            if (resource.resourceType == 'pdf') {
              await _smart.reindexPdf(resource.id);
            } else {
              await _smart.reindexResource(resource.id);
            }
          } catch (indexError) {
            debugPrint('Optional AI source indexing failed for ${resource.id}: $indexError');
          }
        }

        await _service.publishCourse(course.id);
        saved++;
      } catch (error) {
        errors.add('${schoolClass.displayName}: $error');
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (errors.isNotEmpty) {
      _snack(
        '${_fr ? 'Erreur' : 'Error'} (${errors.length}/${targets.length})\n${errors.first}',
      );
      if (saved == 0) return;
    } else {
      _snack(_fr
          ? 'Médias publiés automatiquement dans $saved salle(s) partageant cette matière.'
          : 'Media automatically published to $saved classrooms sharing this subject.');
    }

    Navigator.pop(context, true);
  }

  String _folderKeyForType(String type) {
    switch (type.toLowerCase()) {
      case 'video': return 'videos';
      case 'audio': return 'audios';
      case 'exercise':
      case 'worksheet':
      case 'work':
      case 'assignment': return 'exercises';
      case 'text':
      case 'lesson': return 'lessons';
      default: return 'documents';
    }
  }

  String _folderForType(String type) {
    switch (type) {
      case 'lessons': return _fr ? 'Cours' : 'Lessons';
      case 'videos': return _fr ? 'Vidéos' : 'Videos';
      case 'audios': return _fr ? 'Audios' : 'Audio';
      case 'exercises': return _fr ? 'Exercices' : 'Exercises';
      default: return 'Documents';
    }
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
                _curriculumByClass.clear();
                _chaptersByClass.clear();
                _selectedChapterByClass.clear();
              });
              _loadChapterOptions(classes, subject);
            },
          ),
          const SizedBox(height: 14),
          Text(
            _fr ? 'Chapitre de destination (pour chaque classe)' : 'Destination chapter (for each classroom)',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (_loadingChapters)
            const LinearProgressIndicator()
          else if (_classes.isEmpty || _subject == null)
            Text(_fr ? 'Choisissez d’abord les classes et la matière.' : 'Choose classrooms and a subject first.')
          else
            ..._classes.map((schoolClass) {
              final curriculum = _curriculumByClass[schoolClass.id];
              final chapters = _chaptersByClass[schoolClass.id] ?? const <CourseChapter>[];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(schoolClass.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (curriculum == null)
                      Text(_fr ? 'Aucun programme correspondant trouvé pour cette classe.' : 'No matching curriculum found for this classroom.')
                    else if (chapters.isEmpty)
                      Text(_fr ? 'Aucun chapitre actif dans ce programme.' : 'No active chapters in this curriculum.')
                    else
                      DropdownButtonFormField<String>(
                        key: ValueKey('chapter-${schoolClass.id}-${curriculum.id}-${chapters.length}'),
                        initialValue: _selectedChapterByClass[schoolClass.id],
                        isExpanded: true,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: _fr ? 'Choisir un chapitre' : 'Choose a chapter',
                        ),
                        items: chapters.map((chapter) => DropdownMenuItem<String>(
                          value: chapter.id,
                          child: Text(chapter.labelFor(widget.locale.languageCode), overflow: TextOverflow.ellipsis),
                        )).toList(growable: false),
                        onChanged: (chapterId) {
                          setState(() {
                            if (chapterId == null) {
                              _selectedChapterByClass.remove(schoolClass.id);
                            } else {
                              _selectedChapterByClass[schoolClass.id] = chapterId;
                            }
                          });
                        },
                      ),
                  ],
                ),
              );
            }),
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
                ? 'Chaque fichier est classé par défaut selon son type, mais vous pouvez choisir son dossier de destination (Cours, Vidéos, Audios, Documents ou Exercices) avant l’envoi. Choisissez aussi le chapitre de destination.'
                : 'Each file is classified by type by default, but you can choose its destination folder (Lessons, Videos, Audio, Documents or Exercises) before sending. Choose the destination chapter too.'),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
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
                subtitle: Text(
                  _fr
                      ? 'Dossier : ${_folderForType(_attachments[i].folderKey)}'
                      : 'Folder: ${_folderForType(_attachments[i].folderKey)}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF166534)),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _saving ? null : () => setState(() => _attachments.removeAt(i)),
                ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('folder-${_attachments[i].name}-${i}'),
                      initialValue: _attachments[i].folderKey,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: _fr ? 'Dossier de destination' : 'Destination folder',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem(value: 'lessons', child: Text(_fr ? 'Cours' : 'Lessons')),
                        DropdownMenuItem(value: 'videos', child: Text(_fr ? 'Vidéos' : 'Videos')),
                        DropdownMenuItem(value: 'audios', child: Text(_fr ? 'Audios' : 'Audio')),
                        DropdownMenuItem(value: 'documents', child: Text(_fr ? 'Documents (PDF, images)' : 'Documents (PDF, images)')),
                        DropdownMenuItem(value: 'exercises', child: Text(_fr ? 'Exercices' : 'Exercises')),
                      ],
                      onChanged: _saving ? null : (value) {
                        if (value == null) return;
                        setState(() {
                          final previous = _attachments[i];
                          _attachments[i] = _CourseAttachment(
                            name: previous.name,
                            bytes: previous.bytes,
                            resourceType: previous.resourceType,
                            folderKey: value,
                          );
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_fr ? 'Enregistrer' : 'Save'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_fr ? 'Envoyer les médias' : 'Send media'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
