import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/pedagogy.dart';
import '../../models/school_class.dart';
import '../../models/user_profile.dart';
import '../offline/offline_repository.dart';

class SubjectService {
  final SupabaseClient _client;

  SubjectService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<List<Subject>> listForProfile(UserProfile profile) async {
    if (profile.subsystem == null || profile.sector == null) {
      return const [];
    }

    final rows = await _client
        .from('subjects')
        .select()
        .eq('subsystem', profile.subsystem!)
        .eq('sector', profile.sector!)
        .eq('is_active', true)
        .order('name_fr');

    return rows
        .map((row) => Subject.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }
}

class CourseService {
  final SupabaseClient _client;

  CourseService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  /// Active classrooms for a student, returned separately so the course catalogue
  /// never silently mixes programmes from several rooms.
  Future<List<SchoolClass>> listStudentClasses(String studentId) async {
    final rows = await _client
        .from('class_students')
        .select('school_classes!inner(*)')
        .eq('student_id', studentId)
        .eq('is_active', true);

    final seen = <String>{};
    final classes = <SchoolClass>[];
    for (final row in rows) {
      final nested = row['school_classes'];
      if (nested is! Map) continue;
      final schoolClass = SchoolClass.fromMap(
        Map<String, dynamic>.from(nested),
      );
      if (schoolClass.isActive && seen.add(schoolClass.id)) {
        classes.add(schoolClass);
      }
    }
    classes.sort((a, b) => a.displayName.compareTo(b.displayName));
    return classes;
  }

  /// Only the subjects assigned to this exact classroom.
  Future<List<ClassSubjectEntry>> listClassSubjectEntries(
    String classId,
  ) async {
    final rows = await _client
        .from('class_subjects')
        .select('subject_id, is_compulsory, option_group, position, subjects(*)')
        .eq('class_id', classId)
        .eq('is_active', true)
        .order('position');

    return rows
        .map((row) => ClassSubjectEntry.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<ClassSubjectEntry>> listClassSubjects(UserProfile profile) async {
    // La classe active de l'élève est la source de vérité.
    // Les champs subsystem/sector du profil peuvent être absents sur les
    // anciens comptes : dans ce cas, ils ne doivent surtout pas masquer
    // toutes les matières de la classe.
    final memberships = await _client
        .from('class_students')
        .select('class_id')
        .eq('student_id', profile.id)
        .eq('is_active', true);

    final classIds = memberships
        .map((row) => row['class_id'])
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (classIds.isEmpty) {
      return const [];
    }

    final rows = await _client
        .from('class_subjects')
        .select('subject_id, is_compulsory, option_group, position, subjects(*)')
        .inFilter('class_id', classIds)
        .eq('is_active', true)
        .order('position');

    final seen = <String>{};
    final result = <ClassSubjectEntry>[];

    for (final row in rows) {
      final entry = ClassSubjectEntry.fromMap(Map<String, dynamic>.from(row));

      // Ne filtrer par subsystem/sector que lorsque ces informations sont
      // réellement présentes dans le profil. Sinon, la matière assignée à
      // la classe reste visible.
      if (profile.subsystem != null &&
          entry.subject.subsystem.name != profile.subsystem) {
        continue;
      }
      if (profile.sector != null &&
          entry.subject.sector.name != profile.sector) {
        continue;
      }

      if (seen.add(entry.subject.id)) {
        result.add(entry);
      }
    }

    return result;
  }

  Future<List<Subject>> listSubjects(UserProfile profile) async {
    final entries = await listClassSubjects(profile);
    if (entries.isNotEmpty) {
      return entries.map((e) => e.subject).toList(growable: false);
    }
    return SubjectService(client: _client).listForProfile(profile);
  }

  /// Subjects explicitly assigned to one classroom. Teachers use this when
  /// creating content so a subject can never silently come from another room.
  Future<List<Subject>> listSubjectsForClass(String classId) async {
    final rows = await _client
        .from('class_subjects')
        .select('subject_id, is_compulsory, option_group, position, subjects(*)')
        .eq('class_id', classId)
        .eq('is_active', true)
        .order('position');

    return rows
        .map((row) => ClassSubjectEntry.fromMap(Map<String, dynamic>.from(row)).subject)
        .toList(growable: false);
  }

  /// Matières que l'enseignant peut encore ajouter à une salle.
  Future<List<Subject>> listAddableSubjects(String classId) async {
    final rows = await _client.rpc(
      'list_class_addable_subjects',
      params: {'p_class_id': classId},
    );
    return (rows as List)
        .map((row) => Subject.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
  }

  Future<void> addSubjectToClass(String classId, String subjectId) async {
    await _client.rpc(
      'teacher_add_class_subject',
      params: {'p_class_id': classId, 'p_subject_id': subjectId},
    );
  }

  Future<List<Curriculum>> listCurricula(String subjectId) async {
    final rows = await _client
        .from('curricula')
        .select()
        .eq('subject_id', subjectId)
        .eq('is_active', true)
        .order('title_fr');

    return rows
        .map((row) => Curriculum.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<CourseChapter>> listChapters(String curriculumId) async {
    final rows = await _client
        .from('course_chapters')
        .select()
        .eq('curriculum_id', curriculumId)
        .eq('is_active', true)
        .order('position');

    return rows
        .map((row) => CourseChapter.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<Course>> listStudentCourses(
    String studentId, {
    String? subjectId,
  }) async {
    try {
      // Let Supabase RLS decide which published courses this student can access.
      // A client-side class_id filter hid content available to compatible classes.
      dynamic request = _client
          .from('courses')
          .select()
          .eq('status', 'published');
      if (subjectId != null) {
        request = request.eq('subject_id', subjectId);
      }
      final rows = await request.order('updated_at', ascending: false);
      final courses = rows
          .map((row) => Course.fromMap(Map<String, dynamic>.from(row)))
          .toList(growable: false);
      await OfflineRepository().saveCourses(courses);
      return courses;
    } catch (_) {
      final cached = await OfflineRepository().getCoursesForStudent(studentId);
      if (subjectId == null) return cached;
      return cached
          .where((course) => course.subjectId == subjectId)
          .toList(growable: false);
    }
  }

  Future<Course> getCourse(String id) async {
    try {
      final row = await _client.from('courses').select().eq('id', id).single();
      final course = Course.fromMap(Map<String, dynamic>.from(row));
      await OfflineRepository().saveCourse(course);
      return course;
    } catch (_) {
      final cached = await OfflineRepository().getCourse(id);
      if (cached == null) {
        rethrow;
      }
      return cached;
    }
  }

  Future<List<Lesson>> listLessons(String courseId) async {
    try {
      final rows = await _client
          .from('lessons')
          .select()
          .eq('course_id', courseId)
          .eq('is_published', true)
          .order('position');
      final lessons = rows
          .map((row) => Lesson.fromMap(Map<String, dynamic>.from(row)))
          .toList(growable: false);
      await OfflineRepository().saveLessons(lessons);
      return lessons;
    } catch (_) {
      return OfflineRepository().getLessonsForCourse(courseId);
    }
  }

  Future<List<Course>> listTeacherCourses(
    String teacherId, {
    String? status,
  }) async {
    dynamic request = _client
        .from('courses')
        .select()
        .eq('teacher_id', teacherId);

    if (status != null) {
      request = request.eq('status', status);
    }

    final rows = await request.order('updated_at', ascending: false);

    return rows
        .map((row) => Course.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<SchoolClass>> listTeacherClasses(String teacherId) async {
    final rows = await _client
        .from('class_teachers')
        .select('school_classes!inner(*)')
        .eq('teacher_id', teacherId)
        .eq('is_active', true);

    return rows
        .map(
          (row) => SchoolClass.fromMap(
            Map<String, dynamic>.from(row['school_classes'] as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<Course> saveCourse({
    String? id,
    String? curriculumId,
    String? chapterId,
    required String subjectId,
    required String teacherId,
    required String classId,
    required String titleFr,
    required String titleEn,
    String? descriptionFr,
    String? descriptionEn,
    String? contentFr,
    String? contentEn,
    bool smartLessonEnabled = true,
    int minimumExerciseScore = 50,
    required String status,
  }) async {
    final values = <String, dynamic>{
      'curriculum_id': curriculumId,
      'chapter_id': chapterId,
      'subject_id': subjectId,
      'teacher_id': teacherId,
      'class_id': classId,
      'title_fr': titleFr.trim(),
      'title_en': titleEn.trim(),
      'description_fr': descriptionFr?.trim(),
      'description_en': descriptionEn?.trim(),
      'content_fr': contentFr?.trim(),
      'content_en': contentEn?.trim(),
      'smart_lesson_enabled': smartLessonEnabled,
      'minimum_exercise_score': minimumExerciseScore.clamp(0, 100),
      'status': status,
      'published_at': status == 'published'
          ? DateTime.now().toIso8601String()
          : null,
    };

    final row = id == null
        ? await _client.from('courses').insert(values).select().single()
        : await _client
              .from('courses')
              .update(values)
              .eq('id', id)
              .select()
              .single();

    return Course.fromMap(Map<String, dynamic>.from(row));
  }

  Future<void> archiveCourse(String id) async {
    await _client.from('courses').update({'status': 'archived'}).eq('id', id);
  }
}

class LessonService {
  final SupabaseClient _client;

  LessonService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<Lesson> getLesson(String id) async {
    try {
      final row = await _client.from('lessons').select().eq('id', id).single();
      final lesson = Lesson.fromMap(Map<String, dynamic>.from(row));
      await OfflineRepository().saveLesson(lesson);
      return lesson;
    } catch (_) {
      final cached = await OfflineRepository().getLesson(id);
      if (cached == null) {
        rethrow;
      }
      return cached;
    }
  }

  Future<List<Lesson>> listLessons(String courseId) async {
    try {
      final rows = await _client
          .from('lessons')
          .select()
          .eq('course_id', courseId)
          .eq('is_published', true)
          .order('position');
      final lessons = rows
          .map((row) => Lesson.fromMap(Map<String, dynamic>.from(row)))
          .toList(growable: false);
      await OfflineRepository().saveLessons(lessons);
      return lessons;
    } catch (_) {
      return OfflineRepository().getLessonsForCourse(courseId);
    }
  }

  Future<List<Lesson>> listCourseLessons(String courseId) {
    return listLessons(courseId);
  }

  Future<List<Lesson>> listAllLessons(String courseId) async {
    final rows = await _client
        .from('lessons')
        .select()
        .eq('course_id', courseId)
        .order('position');

    return rows
        .map((row) => Lesson.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<Lesson> saveLesson({
    String? id,
    required String courseId,
    required String titleFr,
    required String titleEn,
    String? contentFr,
    String? contentEn,
    required int position,
    required int durationMinutes,
    String? objectivesFr,
    String? objectivesEn,
    String? examplesFr,
    String? examplesEn,
    String? summaryFr,
    String? summaryEn,
    int? estimatedMinutes,
    required bool isPublished,
  }) async {
    final values = <String, dynamic>{
      'course_id': courseId,
      'title_fr': titleFr.trim(),
      'title_en': titleEn.trim(),
      'content_fr': contentFr?.trim(),
      'content_en': contentEn?.trim(),
      'position': position,
      'duration_minutes': durationMinutes,
      'objectives_fr': objectivesFr?.trim(),
      'objectives_en': objectivesEn?.trim(),
      'examples_fr': examplesFr?.trim(),
      'examples_en': examplesEn?.trim(),
      'summary_fr': summaryFr?.trim(),
      'summary_en': summaryEn?.trim(),
      'estimated_minutes': estimatedMinutes,
      'is_published': isPublished,
    };

    final row = id == null
        ? await _client.from('lessons').insert(values).select().single()
        : await _client
              .from('lessons')
              .update(values)
              .eq('id', id)
              .select()
              .single();

    return Lesson.fromMap(Map<String, dynamic>.from(row));
  }

  Future<void> deleteLesson(String id) async {
    await _client.from('lessons').delete().eq('id', id);
  }
}

class ProgressService {
  final SupabaseClient _client;

  ProgressService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<LessonProgress?> get(String studentId, String lessonId) async {
    final row = await _client
        .from('lesson_progress')
        .select()
        .eq('student_id', studentId)
        .eq('lesson_id', lessonId)
        .maybeSingle();

    if (row == null) {
      return null;
    }

    return LessonProgress.fromMap(Map<String, dynamic>.from(row));
  }

  Future<LessonProgress> open({
    required String studentId,
    required String lessonId,
  }) async {
    final existing = await get(studentId, lessonId);
    final now = DateTime.now().toIso8601String();

    final values = <String, dynamic>{
      'student_id': studentId,
      'lesson_id': lessonId,
      'status': existing?.status == 'completed' ? 'completed' : 'in_progress',
      'progress_percent': existing?.progressPercent ?? 0,
      'started_at': existing?.startedAt?.toIso8601String() ?? now,
      'last_opened_at': now,
      'completed_at': existing?.completedAt?.toIso8601String(),
    };

    final row = await _client
        .from('lesson_progress')
        .upsert(values, onConflict: 'student_id,lesson_id')
        .select()
        .single();

    return LessonProgress.fromMap(Map<String, dynamic>.from(row));
  }

  Future<LessonProgress> complete({
    required String studentId,
    required String lessonId,
  }) async {
    final existing = await get(studentId, lessonId);
    final now = DateTime.now().toIso8601String();

    final values = <String, dynamic>{
      'student_id': studentId,
      'lesson_id': lessonId,
      'status': 'completed',
      'progress_percent': 100,
      'started_at': existing?.startedAt?.toIso8601String() ?? now,
      'last_opened_at': now,
      'completed_at': now,
    };

    final row = await _client
        .from('lesson_progress')
        .upsert(values, onConflict: 'student_id,lesson_id')
        .select()
        .single();

    return LessonProgress.fromMap(Map<String, dynamic>.from(row));
  }
}

class ResourceService {
  final SupabaseClient _client;

  ResourceService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static const String bucket = 'course-resources';

  Future<List<CourseResource>> listForCourse(String courseId) async {
    final rows = await _client
        .from('course_resources')
        .select()
        .eq('course_id', courseId)
        .order('position');

    return rows
        .map((row) => CourseResource.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<CourseResource>> listForLesson(String lessonId) async {
    final rows = await _client
        .from('course_resources')
        .select()
        .eq('lesson_id', lessonId)
        .order('position');

    return rows
        .map((row) => CourseResource.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<String> createSignedUrl(String storagePath, {int expiresIn = 3600}) {
    return _client.storage.from(bucket).createSignedUrl(storagePath, expiresIn);
  }

  Future<CourseResource> uploadResource({
    required String courseId,
    String? lessonId,
    required PlatformFile file,
    required String resourceType,
    required int position,
    String? titleFr,
    String? titleEn,
  }) async {
    Uint8List? bytes = file.bytes;

    if (bytes == null) {
      throw Exception('Le fichier sélectionné ne contient aucune donnée.');
    }

    final safeFileName = file.name.isEmpty ? 'resource' : file.name;
    // Some in-app photo/PDF/video pickers construct PlatformFile from bytes
    // and do not set PlatformFile.extension, so infer it from the filename.
    final suppliedExtension = file.extension?.trim();
    final extension = suppliedExtension != null && suppliedExtension.isNotEmpty
        ? suppliedExtension.toLowerCase()
        : (safeFileName.contains('.')
              ? safeFileName.split('.').last.toLowerCase()
              : '');

    final fileId = DateTime.now().microsecondsSinceEpoch;

    final storagePath = [
      courseId,
      if (lessonId != null && lessonId.isNotEmpty) lessonId,
      '$fileId-$safeFileName',
    ].join('/');

    await _client.storage
        .from(bucket)
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            upsert: false,
            contentType: _mimeTypeFor(extension),
          ),
        );

    final values = <String, dynamic>{
      'course_id': courseId,
      'lesson_id': lessonId,
      'storage_path': storagePath,
      'file_name': safeFileName,
      'resource_type': resourceType,
      'position': position,
      'title_fr': (titleFr == null || titleFr.trim().isEmpty) ? safeFileName : titleFr.trim(),
      'title_en': (titleEn == null || titleEn.trim().isEmpty) ? safeFileName : titleEn.trim(),
      'mime_type': _mimeTypeFor(extension),
      'file_size': bytes.length,
      if (extension.isNotEmpty) 'file_extension': extension,
    };

    try {
      final row = await _client
          .from('course_resources')
          .insert(values)
          .select()
          .single();

      return CourseResource.fromMap(Map<String, dynamic>.from(row));
    } catch (error) {
      try {
        await _client.storage.from(bucket).remove([storagePath]);
      } catch (_) {
        // On ignore l'erreur de nettoyage.
      }

      rethrow;
    }
  }

  String? _mimeTypeFor(String? extension) {
    switch ((extension ?? '').toLowerCase()) {
      case 'pdf': return 'application/pdf';
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'bmp': return 'image/bmp';
      case 'webp': return 'image/webp';
      case 'mp3': return 'audio/mpeg';
      case 'wav': return 'audio/wav';
      case 'm4a': return 'audio/mp4';
      case 'aac': return 'audio/aac';
      case 'ogg': return 'audio/ogg';
      case 'mp4': return 'video/mp4';
      case 'mov': return 'video/quicktime';
      case 'avi': return 'video/x-msvideo';
      case 'mkv': return 'video/x-matroska';
      case 'webm': return 'video/webm';
      case 'txt': return 'text/plain';
      case 'doc': return 'application/msword';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'ppt': return 'application/vnd.ms-powerpoint';
      case 'pptx': return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'xls': return 'application/vnd.ms-excel';
      case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      default: return null;
    }
  }

  Future<void> deleteResource(CourseResource resource) async {
    try {
      await _client.storage.from(bucket).remove([resource.storagePath]);
    } finally {
      await _client.from('course_resources').delete().eq('id', resource.id);
    }
  }
}
