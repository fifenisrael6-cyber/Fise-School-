import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/pedagogy.dart';
import '../../../models/school_class.dart';
import '../../../models/user_profile.dart';
import '../widgets/class_subject_picker.dart';

/// Les enseignants peuvent joindre des médias à un chapitre existant.
/// La rédaction des cours et la création des QCM restent réservées à l'admin.
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
  final SupabaseClient _db = Supabase.instance.client;
  final ImagePicker _images = ImagePicker();

  List<Map<String, dynamic>> _curricula = [];
  Map<String, dynamic>? _curriculum;
  List<Map<String, dynamic>> _chapters = [];
  Map<String, dynamic>? _chapter;
  bool _loadingProgrammes = false;
  bool _uploading = false;

  bool get _fr => widget.locale.languageCode == 'fr';

  String _label(Map<String, dynamic> row, String fr, String en) {
    final a = row[fr]?.toString() ?? '';
    final b = row[en]?.toString() ?? '';
    return _fr ? (a.isNotEmpty ? a : b) : (b.isNotEmpty ? b : a);
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  String _chapterLabel(Map<String, dynamic> row) {
    final title = _label(row, 'title_fr', 'title_en');
    final status = (row['verification_status'] ?? '').toString().toLowerCase();
    final source = (row['source_title'] ?? '').toString().toLowerCase();
    final needsVerification = status == 'pending_official_confirmation' ||
        status == 'pending_confirmation' ||
        status == 'needs_review' ||
        source.contains('à confirmer') ||
        source.contains('pending confirmation') ||
        source.contains('provisional');
    if (!needsVerification) return title;
    return '$title • ${_fr ? 'titre à confirmer' : 'title to verify'}';
  }

  Future<void> _selectionChanged(
    List<SchoolClass> classes,
    Subject? subject,
  ) async {
    setState(() {
      _curricula = [];
      _curriculum = null;
      _chapters = [];
      _chapter = null;
      _loadingProgrammes = classes.isNotEmpty && subject != null;
    });
    if (classes.isEmpty || subject == null) {
      if (mounted) setState(() => _loadingProgrammes = false);
      return;
    }
    try {
      final classIds = classes.map((e) => e.id).toList();
      final classRows = await _db
          .from('school_classes')
          .select('id,subsystem,sector,exam_level_id,series_id,specialty_id,is_active')
          .inFilter('id', classIds)
          .eq('is_active', true);
      final programmes = await _db
          .from('curricula')
          .select('id,title_fr,title_en,subsystem,sector,exam_level_id,series_id,specialty_id,is_catalog_container,is_active')
          .eq('subject_id', subject.id)
          .eq('is_active', true)
          .order('title_fr');

      bool matchesEverySelectedClass(Map<String, dynamic> programme) {
        return classRows.length == classes.length && classRows.every((rawClass) {
          final c = Map<String, dynamic>.from(rawClass);
          return programme['subsystem'] == c['subsystem'] &&
              programme['sector'] == c['sector'] &&
              (programme['exam_level_id'] == null ||
                  programme['exam_level_id'] == c['exam_level_id']) &&
              (programme['series_id'] == null ||
                  programme['series_id'] == c['series_id']) &&
              (programme['specialty_id'] == null ||
                  programme['specialty_id'] == c['specialty_id']);
        });
      }

      final matching = List<Map<String, dynamic>>.from(programmes)
          .where(matchesEverySelectedClass)
          .toList(growable: false);
      final containers = matching
          .where((row) => row['is_catalog_container'] == true)
          .toList(growable: false);

      // Never select an empty catalogue container: doing so hides the older
      // active programme and leaves teachers with no chapters to publish into.
      var populatedContainerIds = <String>{};
      if (containers.isNotEmpty) {
        final containerIds = containers
            .map((row) => row['id'])
            .whereType<String>()
            .toList(growable: false);
        if (containerIds.isNotEmpty) {
          final populatedRows = await _db
              .from('course_chapters')
              .select('curriculum_id')
              .inFilter('curriculum_id', containerIds)
              .eq('is_active', true);
          populatedContainerIds = populatedRows
              .map((row) => row['curriculum_id'])
              .whereType<String>()
              .toSet();
        }
      }
      final populatedContainers = containers
          .where((row) => populatedContainerIds.contains(row['id']))
          .toList(growable: false);
      final filtered = populatedContainers.isNotEmpty
          ? populatedContainers
          : matching
              .where((row) => row['is_catalog_container'] != true)
              .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _curricula = filtered;
        _curriculum = filtered.isEmpty ? null : filtered.first;
        _loadingProgrammes = false;
      });
      if (_curriculum != null) await _loadChapters(_curriculum!['id'].toString());
    } catch (e) {
      if (mounted) setState(() => _loadingProgrammes = false);
      _message((_fr ? 'Programmes indisponibles : ' : 'Unable to load programmes: ') + e.toString());
    }
  }

  Future<void> _loadChapters(String curriculumId) async {
    final rows = await _db
        .from('course_chapters')
        .select('id,title_fr,title_en,position,is_active,source_title,verification_status')
        .eq('curriculum_id', curriculumId)
        .eq('is_active', true)
        .order('position');
    if (!mounted) return;
    final chapters = List<Map<String, dynamic>>.from(rows);
    setState(() {
      _chapters = chapters;
      _chapter = chapters.isEmpty ? null : chapters.first;
    });
  }

  String? _typeFor(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'pdf';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
        return 'image';
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
      case 'webm':
        return 'video';
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'aac':
      case 'ogg':
        return 'audio';
      default:
        return null;
    }
  }

  String _mimeFor(String type, String extension) {
    // Use canonical IANA media types so Android, Supabase Storage and viewers
    // agree on the content type even when the phone file extension is unusual.
    switch (type) {
      case 'pdf':
        return 'application/pdf';
      case 'image':
        switch (extension.toLowerCase()) {
          case 'jpg':
          case 'jpeg':
            return 'image/jpeg';
          case 'png':
            return 'image/png';
          case 'gif':
            return 'image/gif';
          case 'webp':
            return 'image/webp';
          case 'bmp':
            return 'image/bmp';
          default:
            return 'application/octet-stream';
        }
      case 'video':
        switch (extension.toLowerCase()) {
          case 'mp4':
            return 'video/mp4';
          case 'mov':
            return 'video/quicktime';
          case 'avi':
            return 'video/x-msvideo';
          case 'mkv':
            return 'video/x-matroska';
          case 'webm':
            return 'video/webm';
          default:
            return 'application/octet-stream';
        }
      case 'audio':
        switch (extension.toLowerCase()) {
          case 'mp3':
            return 'audio/mpeg';
          case 'wav':
            return 'audio/wav';
          case 'm4a':
            return 'audio/mp4';
          case 'aac':
            return 'audio/aac';
          case 'ogg':
            return 'audio/ogg';
          default:
            return 'application/octet-stream';
        }
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _pickAndUpload({ImageSource? imageSource}) async {
    // Never start a Storage/database write without the live Supabase session.
    final authUser = _db.auth.currentUser;
    if (authUser == null) {
      _message(_fr
          ? 'Votre session a expiré. Reconnectez-vous puis réessayez.'
          : 'Your session has expired. Sign in again and retry.');
      return;
    }
    if (authUser.id != widget.profile.id) {
      _message(_fr
          ? 'Le compte connecté ne correspond pas au profil enseignant. Reconnectez-vous.'
          : 'The signed-in account does not match the teacher profile. Sign in again.');
      return;
    }
    if (_chapter == null) {
      _message(_fr ? 'Choisissez d’abord une salle, une matière et un chapitre.' : 'Choose a classroom, subject and chapter first.');
      return;
    }
    PlatformFile file;
    try {
      if (imageSource != null) {
        final picked = await _images.pickImage(source: imageSource, imageQuality: 88);
        if (picked == null) return;
        final bytes = await picked.readAsBytes();
        file = PlatformFile(name: picked.name, size: bytes.length, bytes: bytes);
      } else {
        final result = await FilePicker.platform.pickFiles(
          withData: true,
          type: FileType.custom,
          allowedExtensions: const [
            'pdf','jpg','jpeg','png','gif','webp','bmp',
            'mp4','mov','avi','mkv','webm','mp3','wav','m4a','aac','ogg',
          ],
        );
        if (result == null || result.files.isEmpty) return;
        file = result.files.single;
      }
      if (file.bytes == null || file.bytes!.isEmpty) {
        _message(_fr ? 'Impossible de lire ce fichier.' : 'Could not read this file.');
        return;
      }
      final extension = (file.extension ?? '').toLowerCase();
      final type = _typeFor(extension);
      if (type == null) {
        _message(_fr ? 'Format non pris en charge.' : 'Unsupported file type.');
        return;
      }

      setState(() => _uploading = true);
      final chapterId = _chapter!['id'].toString();
      String? storagePath;
      try {
        final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        storagePath = '$chapterId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
        await _db.storage.from('chapter-content').uploadBinary(
          storagePath,
          file.bytes!,
          fileOptions: FileOptions(contentType: _mimeFor(type, extension), upsert: false),
        );
        final existing = await _db
            .from('chapter_content_items')
            .select('position')
            .eq('chapter_id', chapterId)
            .order('position');
        var position = 0;
        for (final row in existing) {
          final current = row['position'];
          if (current is int && current >= position) position = current + 1;
        }
        await _db.from('chapter_content_items').insert({
          'chapter_id': chapterId,
          'content_type': type,
          'folder_key': switch (type) {
            'image' => 'images',
            'pdf' => 'pdf',
            'audio' => 'audio',
            'video' => 'video',
            _ => 'course',
          },
          'title_fr': file.name,
          'title_en': file.name,
          'storage_path': storagePath,
          'position': position,
          'is_published': true,
          'created_by': authUser.id,
        });
        _message(_fr ? 'Média publié dans le chapitre.' : 'Media published in the chapter.');
      } catch (e) {
        if (storagePath != null) {
          try { await _db.storage.from('chapter-content').remove([storagePath]); } catch (_) {}
        }
        rethrow;
      }
    } catch (e) {
      _message((_fr ? 'Échec de la publication : ' : 'Publishing failed: ') + e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_fr ? 'Partager des médias' : 'Share media')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline, color: Color(0xFF166534)),
                const SizedBox(width: 12),
                Expanded(child: Text(_fr
                    ? 'Les cours écrits et les QCM sont préparés par l’administration. Ici, vous pouvez uniquement joindre des photos, PDF, vidéos et fichiers audio à un chapitre du programme.'
                    : 'Written lessons and quizzes are prepared by administrators. Here you can only attach photos, PDFs, videos and audio files to a curriculum chapter.')),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          ClassSubjectPicker(
            locale: widget.locale,
            teacherId: widget.profile.id,
            onChanged: _selectionChanged,
          ),
          const SizedBox(height: 18),
          if (_loadingProgrammes) const LinearProgressIndicator(),
          DropdownButtonFormField<Map<String, dynamic>>(
            initialValue: _curriculum,
            isExpanded: true,
            decoration: InputDecoration(labelText: _fr ? 'Programme de la matière' : 'Subject curriculum'),
            items: _curricula.map((row) => DropdownMenuItem(
              value: row,
              child: Text(_label(row, 'title_fr', 'title_en'), overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: _uploading ? null : (value) async {
              setState(() { _curriculum = value; _chapter = null; _chapters = []; });
              if (value != null) await _loadChapters(value['id'].toString());
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Map<String, dynamic>>(
            initialValue: _chapter,
            isExpanded: true,
            decoration: InputDecoration(labelText: _fr ? 'Chapitre' : 'Chapter'),
            items: _chapters.map((row) => DropdownMenuItem(
              value: row,
              child: Text(_chapterLabel(row), overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: _uploading ? null : (value) => setState(() => _chapter = value),
          ),
          const SizedBox(height: 22),
          Text(_fr ? 'Ajouter un média à ce chapitre' : 'Add media to this chapter',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ActionChip(
              avatar: const Icon(Icons.camera_alt_outlined),
              label: Text(_fr ? 'Prendre une photo' : 'Take photo'),
              onPressed: _uploading ? null : () => _pickAndUpload(imageSource: ImageSource.camera),
            ),
            ActionChip(
              avatar: const Icon(Icons.photo_library_outlined),
              label: Text(_fr ? 'Choisir une photo' : 'Choose photo'),
              onPressed: _uploading ? null : () => _pickAndUpload(imageSource: ImageSource.gallery),
            ),
            ActionChip(
              avatar: const Icon(Icons.attach_file),
              label: Text(_fr ? 'PDF, vidéo ou audio' : 'PDF, video or audio'),
              onPressed: _uploading ? null : () => _pickAndUpload(),
            ),
          ]),
          if (_uploading) ...[
            const SizedBox(height: 18),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(_fr ? 'Publication en cours…' : 'Publishing…', textAlign: TextAlign.center),
          ],
          const SizedBox(height: 18),
          Text(_fr
              ? 'Le média apparaît dans le chapitre dès sa publication. Les élèves autorisés par leur programme peuvent le consulter et le télécharger pour le mode hors ligne si la fonction le prend en charge.'
              : 'The media appears in the chapter after publishing. Students whose curriculum grants access can view it and download it for offline use when supported.',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
