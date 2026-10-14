import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:io';
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

            // The active classroom membership is authoritative. Older profiles
            // can contain stale subsystem/sector labels (especially bilingual
            // and legacy accounts); filtering subjects a second time by those
            // labels silently made the Cours page appear empty.
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

  /// Subjects explicitly assigned to one classroom. The table's SELECT RLS
  /// intentionally limits direct reads to class members/assigned teachers.
  /// Use the scoped teacher RPC so an authorized teacher can read the selected
  /// curriculum without weakening table policies or bypassing class scope.
  Future<List<Subject>> listSubjectsForClass(String classId) async {
    final rows = await _client.rpc(
      'list_teacher_class_subjects',
      params: {'p_class_id': classId},
    );

    return (rows as List)
        .map((row) => ClassSubjectEntry.fromMap(
              Map<String, dynamic>.from(row as Map),
            ).subject)
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

  /// Chapter-title pages available to a student for the subject in their active classroom.
  /// Only the canonical catalogue containers for the student's exact class context
  /// are considered. This reads titles only; it does not create courses or media.
  Future<List<CourseChapter>> listStudentCatalogChapters(
    String studentId, {
    required String subjectId,
  }) async {
    final memberships = await _client
        .from('class_students')
        .select('class_id')
        .eq('student_id', studentId)
        .eq('is_active', true);
    final classIds = memberships
        .map((row) => row['class_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (classIds.isEmpty) return const <CourseChapter>[];

    final classRows = await _client
        .from('school_classes')
        .select('id, subsystem, sector, exam_level_id, series_id, specialty_id')
        .inFilter('id', classIds)
        .eq('is_active', true);
    if (classRows.isEmpty) return const <CourseChapter>[];

    final curriculumRows = await _client
        .from('curricula')
        .select('id, subsystem, sector, exam_level_id, series_id, specialty_id')
        .eq('subject_id', subjectId)
        .eq('is_catalog_container', true)
        .eq('is_active', true);

    bool sameContextValue(Object? left, Object? right) =>
        left?.toString() == right?.toString();

    final matchingCurriculumIds = <String>{};
    for (final rawCurriculum in curriculumRows) {
      final curriculum = Map<String, dynamic>.from(rawCurriculum);
      final matchesClass = classRows.any((rawClass) {
        final schoolClass = Map<String, dynamic>.from(rawClass);
        return curriculum['subsystem'] == schoolClass['subsystem'] &&
            curriculum['sector'] == schoolClass['sector'] &&
            sameContextValue(curriculum['exam_level_id'], schoolClass['exam_level_id']) &&
            sameContextValue(curriculum['series_id'], schoolClass['series_id']) &&
            sameContextValue(curriculum['specialty_id'], schoolClass['specialty_id']);
      });
      final id = curriculum['id']?.toString();
      if (matchesClass && id != null && id.isNotEmpty) {
        matchingCurriculumIds.add(id);
      }
    }
    if (matchingCurriculumIds.isEmpty) return const <CourseChapter>[];

    final chapterRows = await _client
        .from('course_chapters')
        .select()
        .inFilter('curriculum_id', matchingCurriculumIds.toList(growable: false))
        .eq('is_active', true)
        .order('position');

    final seenTitles = <String>{};
    final chapters = <CourseChapter>[];
    for (final raw in chapterRows) {
      try {
        final chapter = CourseChapter.fromMap(Map<String, dynamic>.from(raw));
        final normalizedTitle = chapter.titleFr.trim().toLowerCase();
        if (normalizedTitle.isNotEmpty && seenTitles.add(normalizedTitle)) {
          chapters.add(chapter);
        }
      } catch (_) {
        // One invalid title must not hide all the other chapter pages.
      }
    }
    chapters.sort((a, b) {
      final byPosition = a.position.compareTo(b.position);
      return byPosition != 0
          ? byPosition
          : a.titleFr.toLowerCase().compareTo(b.titleFr.toLowerCase());
    });
    return chapters.toList(growable: false);
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

  /// Official curriculum content stored in chapter_content_items is separate
  /// from teacher-created courses. Load only curricula matching the student's
  /// enrolled class and the currently opened subject; database RLS applies the
  /// same student_can_access_chapter check to every returned item.
  Future<List<Map<String, dynamic>>> listStudentChapterContent(
    String studentId, {
    required String subjectId,
  }) async {
    try {
      final memberships = await _client
          .from('class_students')
          .select('class_id')
          .eq('student_id', studentId)
          .eq('is_active', true);
      final classIds = memberships
          .map((row) => row['class_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (classIds.isEmpty) return const <Map<String, dynamic>>[];

      final classRows = await _client
          .from('school_classes')
          .select('id, subsystem, sector, exam_level_id, series_id, specialty_id')
          .inFilter('id', classIds)
          .eq('is_active', true);
      final classes = classRows.map((row) => Map<String, dynamic>.from(row)).toList();

      final curriculumRows = await _client
          .from('curricula')
          .select('id, subsystem, sector, exam_level_id, series_id, specialty_id')
          .eq('subject_id', subjectId)
          .eq('is_active', true);
      final curriculumIds = <String>{};
      for (final raw in curriculumRows) {
        final curriculum = Map<String, dynamic>.from(raw);
        final matches = classes.any((schoolClass) {
          if (curriculum['subsystem'] != null &&
              curriculum['subsystem'] != schoolClass['subsystem']) return false;
          if (curriculum['sector'] != null &&
              curriculum['sector'] != schoolClass['sector']) return false;
          if (curriculum['exam_level_id'] != null &&
              curriculum['exam_level_id'] != schoolClass['exam_level_id']) return false;
          if (curriculum['series_id'] != null &&
              curriculum['series_id'] != schoolClass['series_id']) return false;
          if (curriculum['specialty_id'] != null &&
              curriculum['specialty_id'] != schoolClass['specialty_id']) return false;
          return true;
        });
        final id = curriculum['id']?.toString();
        if (matches && id != null && id.isNotEmpty) curriculumIds.add(id);
      }
      if (curriculumIds.isEmpty) return const <Map<String, dynamic>>[];

      final chapterRows = await _client
          .from('course_chapters')
          .select('id, curriculum_id, title_fr, title_en, position')
          .inFilter('curriculum_id', curriculumIds.toList(growable: false))
          .eq('is_active', true)
          .order('position');
      final chapterById = <String, Map<String, dynamic>>{};
      for (final raw in chapterRows) {
        final chapter = Map<String, dynamic>.from(raw);
        final id = chapter['id']?.toString();
        if (id != null) chapterById[id] = chapter;
      }
      if (chapterById.isEmpty) return const <Map<String, dynamic>>[];

      final itemRows = await _client
          .from('chapter_content_items')
          .select('id, chapter_id, content_type, title_fr, title_en, body_text_fr, body_text_en, position, created_at')
          .inFilter('chapter_id', chapterById.keys.toList(growable: false))
          .inFilter('content_type', ['course', 'lesson', 'text'])
          .eq('is_published', true)
          .order('position');
      return itemRows.map((raw) {
        final item = Map<String, dynamic>.from(raw);
        final chapter = chapterById[item['chapter_id']?.toString()];
        item['chapter_title_fr'] = chapter?['title_fr'];
        item['chapter_title_en'] = chapter?['title_en'];
        return item;
      }).toList(growable: false);
    } catch (_) {
      // Keep teacher courses, media and QCM available if official content
      // is temporarily unavailable or the student is offline.
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Course>> listStudentCourses(
    String studentId, {
    String? subjectId,
  }) async {
    List<Course> courses;
    try {
      // Let the database's student-safe RLS policy decide classroom visibility.
      // Rebuilding an allow-list from school_classes silently excluded
      // compatible generic/level-wide rooms that the student cannot SELECT
      // directly. is_course_student(id) enforces active membership and matching
      // subsystem/sector before a course can be returned.
      dynamic request = _client
          .from('courses')
          .select();
      // Do not filter to published on the client: RLS also exposes draft
      // teacher-media posts with resources to students enrolled in that class.
      // Official course publication remains restricted by database policy.

      if (subjectId != null) {
        request = request.eq('subject_id', subjectId);
      }

      final response = await request.order('updated_at', ascending: false);
      // A dynamic Supabase query can expose its decoded result as List<dynamic>.
      // Normalize it to a list and explicitly type every mapped Course.
      final rows = response is List ? response : const <dynamic>[];
      courses = rows
          .whereType<Map>()
          .map<Course>((row) => Course.fromMap(Map<String, dynamic>.from(row)))
          .toList(growable: false);
    } catch (_) {
      // Use offline data only when the remote read itself failed. A local
      // cache write must never replace a successful response with stale data.
      final cached = await OfflineRepository().getCoursesForStudent(studentId);
      if (subjectId == null) {
        return cached;
      }
      return cached
          .where((course) => course.subjectId == subjectId)
          .toList(growable: false);
    }

    try {
      await OfflineRepository().saveCourses(courses);
    } catch (_) {
      // Offline caching is best-effort; the live courses still belong on screen.
    }
    return courses;
  }

  Future<Course> getCourse(String id) async {
    Course course;
    try {
      final row = await _client.from('courses').select().eq('id', id).single();
      course = Course.fromMap(Map<String, dynamic>.from(row));
    } catch (_) {
      final cached = await OfflineRepository().getCourse(id);
      if (cached == null) {
        rethrow;
      }
      return cached;
    }

    try {
      await OfflineRepository().saveCourse(course);
    } catch (_) {
      // Do not discard a course fetched successfully from Supabase.
    }
    return course;
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

    final response = await request.order('updated_at', ascending: false);
    // Keep the result typed even though the query builder above is dynamic.
    // A null, empty, or unexpected non-list response becomes an empty list.
    final rows = response is List ? response : const <dynamic>[];

    return rows
        .whereType<Map>()
        .map<Course>((row) => Course.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  /// Toutes les salles actives compatibles avec le sous-système et le secteur
  /// du profil enseignant. Le filtrage est aussi appliqué côté base de données.
  Future<List<SchoolClass>> listTeacherCompatibleClasses() async {
    final result = await _client.rpc('list_compatible_teacher_classes');
    final ids = (result as List)
        .map((row) => (row as Map)['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return const <SchoolClass>[];
    final rows = await _client
        .from('school_classes')
        .select()
        .inFilter('id', ids)
        .eq('is_active', true)
        .order('display_name');
    return rows
        .map((row) => SchoolClass.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  /// IDs des salles que l'enseignant a choisi de suivre.
  Future<Set<String>> listTeacherFollowedClassIds() async {
    final result = await _client.rpc('list_teacher_followed_class_ids');
    return (result as List)
        .map((row) => (row as Map)['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  /// Enregistre la sélection persistante des salles suivies.
  Future<void> saveTeacherFollowedClasses(List<String> classIds) async {
    if (classIds.isEmpty) {
      throw StateError('Choose at least one classroom.');
    }
    await _client.rpc(
      'save_teacher_followed_classes',
      params: {'p_class_ids': classIds.toSet().toList(growable: false)},
    );
    // Ensure each selected classroom is active in the existing teacher scope.
    await authorizeTeacherClasses(classIds);
  }

  /// Salles suivies par l'enseignant. Lors de la première utilisation, avant
  /// toute sélection enregistrée, affiche toutes les salles compatibles.
  Future<List<SchoolClass>> listTeacherSelectedClasses() async {
    final all = await listTeacherCompatibleClasses();
    final selectedIds = await listTeacherFollowedClassIds();
    if (selectedIds.isEmpty) return all;
    final selected = all
        .where((schoolClass) => selectedIds.contains(schoolClass.id))
        .toList(growable: false);
    // Older saved preferences may contain only empty generic level buckets.
    // If filtering removes all of them, keep the picker usable and show the
    // current real classrooms instead of presenting an empty list.
    return selected.isEmpty ? all : selected;
  }

  /// Active les affectations nécessaires pour les salles compatibles choisies.
  /// La fonction serveur refuse tout identifiant hors du sous-système/secteur.
  Future<void> authorizeTeacherClasses(List<String> classIds) async {
    if (classIds.isEmpty) {
      throw StateError('Select at least one classroom.');
    }
    await _client.rpc(
      'teacher_authorize_compatible_classes',
      params: {'p_class_ids': classIds},
    );
  }

  /// Les formulaires courants affichent seulement les salles suivies.
  Future<List<SchoolClass>> listTeacherClasses(String teacherId) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId != teacherId) {
      throw StateError('A teacher can only list their own compatible classrooms.');
    }
    return listTeacherSelectedClasses();
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

  /// Publish only after the media rows have been uploaded and verified.
  /// This avoids notifying students about a course that their media-feed RLS
  /// cannot expose yet because it has no course_resources rows.
  Future<Course> publishCourse(String id) async {
    final row = await _client
        .from('courses')
        .update({
          'status': 'published',
          'published_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .select()
        .single();
    final publishedCourse = Course.fromMap(Map<String, dynamic>.from(row));
    final chapterId = row['chapter_id']?.toString().trim() ?? '';
    if (chapterId.isNotEmpty) {
      // Keep course publication fast; generate/update the AI QCM once in the
      // background. A temporary Gemini failure must not undo publication.
      unawaited(_generateChapterQuizInBackground(chapterId));
    }
    return publishedCourse;
  }

  Future<void> _generateChapterQuizInBackground(String chapterId) async {
    // Automatic QCM generation is intentionally disabled. Teachers now create
    // and publish their own questions from the teacher QCM workspace.
    return;
  }

  Future<void> archiveCourse(String id) async {
    await _client.from('courses').update({'status': 'archived'}).eq('id', id);
  }

  Future<void> updateCourseTitle({
    required String id,
    required String titleFr,
    required String titleEn,
  }) async {
    final fr = titleFr.trim();
    final en = titleEn.trim();
    if (fr.isEmpty || en.isEmpty) {
      throw ArgumentError('Course titles cannot be empty.');
    }
    await _client.from('courses').update({
      'title_fr': fr,
      'title_en': en,
    }).eq('id', id);
  }

  Future<void> deleteCourse(String id) async {
    await _client.from('courses').delete().eq('id', id);
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
    String? folderKey,
    String? titleFr,
    String? titleEn,
  }) async {
    Uint8List? bytes = file.bytes;
    if ((bytes == null || bytes.isEmpty) && file.path != null) {
      try { bytes = await File(file.path!).readAsBytes(); } catch (_) {}
    }
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Impossible de lire le fichier sélectionné. Réessayez depuis le stockage du téléphone.');
    }

    final extension = (file.extension ??
            (file.name.contains('.') ? file.name.split('.').last : ''))
        .toLowerCase();
    final safeFileName = file.name.isEmpty ? 'resource' : file.name;
    final storageFileName = safeFileName.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final mimeType = _mimeTypeFor(extension) ??
        (resourceType == 'pdf' ? 'application/pdf' : null);
    final fileId = DateTime.now().microsecondsSinceEpoch;

    final storagePath = [
      courseId,
      if (lessonId != null && lessonId.isNotEmpty) lessonId,
      '$fileId-$storageFileName',
    ].join('/');

    await _client.storage
        .from(bucket)
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            upsert: false,
            contentType: mimeType ?? 'application/octet-stream',
          ),
        );

    final values = <String, dynamic>{
      'course_id': courseId,
      'lesson_id': lessonId,
      'storage_path': storagePath,
      'file_name': safeFileName,
      'resource_type': resourceType,
      'folder_key': folderKey ?? _folderForResourceType(resourceType),
      'position': position,
      'title_fr': (titleFr == null || titleFr.trim().isEmpty) ? safeFileName : titleFr.trim(),
      'title_en': (titleEn == null || titleEn.trim().isEmpty) ? safeFileName : titleEn.trim(),
      'mime_type': mimeType,
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

  String _folderForResourceType(String type) {
    switch (type.toLowerCase()) {
      case 'video': return 'videos';
      case 'audio': return 'audios';
      case 'exercise': case 'worksheet': case 'work': case 'assignment': return 'exercises';
      case 'text': case 'lesson': return 'lessons';
      default: return 'documents';
    }
  }

  String? _mimeTypeFor(String? extension) {
    switch ((extension ?? '').toLowerCase()) {
      case 'pdf': return 'application/pdf';
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'webp': return 'image/webp';
      case 'mp3': return 'audio/mpeg';
      case 'oga': return 'audio/ogg';
      case 'amr': return 'audio/amr';
      case '3gp': return 'video/3gpp';
      case 'wma': return 'audio/x-ms-wma';
      case 'gif': return 'image/gif';
      case 'bmp': return 'image/bmp';
      case 'wav': return 'audio/wav';
      case 'm4a': return 'audio/mp4';
      case 'aac': return 'audio/aac';
      case 'ogg': return 'audio/ogg';
      case 'opus': return 'audio/opus';
      case 'flac': return 'audio/flac';
      case 'webm': return 'video/webm';
      case 'mkv': return 'video/x-matroska';
      case 'avi': return 'video/x-msvideo';
      case 'mp4': return 'video/mp4';
      case 'mov': return 'video/quicktime';
      case 'txt': return 'text/plain';
      default: return null;
    }
  }

  Future<void> replaceResourceFile({
    required CourseResource resource,
    required PlatformFile file,
    required String resourceType,
  }) async {
    Uint8List? bytes = file.bytes;
    if ((bytes == null || bytes.isEmpty) && file.path != null) {
      try { bytes = await File(file.path!).readAsBytes(); } catch (_) {}
    }
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Impossible de lire le fichier sélectionné. Réessayez depuis le stockage du téléphone.');
    }
    final extension = (file.extension ??
            (file.name.contains('.') ? file.name.split('.').last : ''))
        .toLowerCase();
    final safeName = file.name.isEmpty ? 'resource' : file.name;
    final storageName = safeName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final mimeType = _mimeTypeFor(extension) ??
        (resourceType == 'pdf' ? 'application/pdf' : null);
    final newPath = [
      resource.courseId,
      if (resource.lessonId != null && resource.lessonId!.isNotEmpty) resource.lessonId!,
      '${DateTime.now().microsecondsSinceEpoch}-$storageName',
    ].join('/');
    await _client.storage.from(bucket).uploadBinary(
      newPath,
      bytes,
      fileOptions: FileOptions(
        upsert: false,
        contentType: mimeType ?? 'application/octet-stream',
      ),
    );
    try {
      await _client.from('course_resources').update({
        'storage_path': newPath,
        'file_name': safeName,
        'resource_type': resourceType,
        'mime_type': mimeType,
        'file_size': bytes.length,
        if (extension.isNotEmpty) 'file_extension': extension,
      }).eq('id', resource.id);
    } catch (_) {
      try {
        await _client.storage.from(bucket).remove([newPath]);
      } catch (_) {}
      rethrow;
    }
    try {
      await _client.storage.from(bucket).remove([resource.storagePath]);
    } catch (_) {
      // The new file and database reference are already saved.
    }
  }

  Future<void> updateResourceTitle({
    required String resourceId,
    required String title,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw ArgumentError('Le titre ne peut pas être vide.');
    }
    await _client
        .from('course_resources')
        .update({'title_fr': cleanTitle, 'title_en': cleanTitle})
        .eq('id', resourceId);
  }

  Future<void> deleteResource(CourseResource resource) async {
    try {
      await _client.storage.from(bucket).remove([resource.storagePath]);
    } finally {
      await _client.from('course_resources').delete().eq('id', resource.id);
    }
  }
}
