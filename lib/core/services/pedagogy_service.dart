import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/pedagogy.dart';
import '../../models/school_class.dart';
import '../../models/user_profile.dart';
import '../offline/json_cache.dart';
import '../offline/offline_repository.dart';

class SubjectService {
  final SupabaseClient _client;

  SubjectService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<List<Subject>> listForProfile(UserProfile profile) async {
    // Students must see only subjects assigned to their active classroom(s).
    // Never return every subject in the same subsystem/sector as a fallback.
    return CourseService(client: _client).listSubjects(profile);
  }
}

class CourseService {
  final SupabaseClient _client;

  CourseService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<List<ClassSubjectEntry>> listClassSubjects(UserProfile profile) async {
    // The active class membership is the source of truth. Do not require
    // profile.subsystem/sector to discover the student's class: older
    // accounts can have those profile fields incomplete even when their
    // class membership is valid.
    return JsonCache.instance.cachedRead<List<ClassSubjectEntry>>(
      key: 'class_subjects_${profile.id}',
      fetch: () async {
        final memberships = await _client
            .from('class_students')
            .select('class_id')
            .eq('student_id', profile.id)
            .eq('is_active', true);

        final classIds = memberships
            .map((row) => row['class_id']?.toString())
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList(growable: false);

        if (classIds.isEmpty) {
          return <Object?>[];
        }

        final rows = await _client
            .from('class_subjects')
            .select('subject_id, is_compulsory, option_group, position, subjects(*)')
            .inFilter('class_id', classIds)
            .eq('is_active', true)
            .order('position');

        return rows.map((row) => Map<String, dynamic>.from(row)).toList();
      },
      decode: (raw) {
        final seen = <String>{};
        final result = <ClassSubjectEntry>[];
        if (raw is! List) return result;

        for (final row in raw) {
          if (row is! Map) continue;
          try {
            final entry = ClassSubjectEntry.fromMap(
              Map<String, dynamic>.from(row),
            );

            // Keep the school-system boundary when the profile has it.
            // If an older account has missing profile values, the class
            // membership remains authoritative instead of hiding everything.
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
          } catch (_) {
            // A malformed catalogue row must not hide all other subjects.
          }
        }
        return result;
      },
    );
  }

  Future<List<Subject>> listSubjects(UserProfile profile) async {
    // Never fall back to every subject in the subsystem/sector: only the
    // curriculum explicitly assigned to the student's classroom is allowed.
    final entries = await listClassSubjects(profile);
    return entries.map((e) => e.subject).toList(growable: false);
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
      final memberships = await _client
          .from('class_students')
          .select('class_id')
          .eq('student_id', studentId)
          .eq('is_active', true);

      final classIds = memberships
          .map((row) => row['class_id'] as String)
          .toList(growable: false);

      if (classIds.isEmpty) {
        return const [];
      }

      dynamic request = _client
          .from('courses')
          .select()
          .eq('status', 'published')
          .inFilter('class_id', classIds);

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
      if (subjectId == null) {
        return cached;
      }
      return cached.where((course) => course.subjectId == subjectId).toList(growable: false);
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

    final extension = file.extension?.toLowerCase() ?? '';
    final safeFileName = file.name.isEmpty ? 'resource' : file.name;

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
          fileOptions: const FileOptions(upsert: false),
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
      'mime_type': _mimeTypeFor(file.extension),
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
      case 'webp': return 'image/webp';
      case 'mp3': return 'audio/mpeg';
      case 'm4a': return 'audio/mp4';
      case 'aac': return 'audio/aac';
      case 'mp4': return 'video/mp4';
      case 'mov': return 'video/quicktime';
      case 'txt': return 'text/plain';
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
