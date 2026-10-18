import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/pedagogy.dart';
import '../../models/assignment.dart';
import 'app_database.dart';

class OfflineRepository {
  OfflineRepository({AppDatabase? database})
      : _database = database ?? AppDatabase();

  final AppDatabase _database;

  // ============================================================
  // COURSES
  // ============================================================

  Future<void> saveCourse(Course course) async {
    await _database.saveCourse(
      CachedCoursesCompanion(
        id: Value(course.id),
        title: Value(course.titleFr),
        description: Value(course.descriptionFr),
        subjectId: Value(course.subjectId),
        classId: Value(course.classId),
        dataJson: Value(jsonEncode(_courseToJson(course))),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> saveCourses(List<Course> courses) async {
    for (final course in courses) {
      await saveCourse(course);
    }
  }

  Future<List<Course>> getCourses() async {
    final rows = await _database.getAllCourses();

    return rows.map((row) {
      final json =
          jsonDecode(row.dataJson) as Map<String, dynamic>;

      return Course.fromMap(json);
    }).toList(growable: false);
  }

  Future<List<Course>> getCoursesForStudent(String studentId) async {
    final courses = await getCourses();
    return courses.where((course) => course.status == 'published').toList(growable: false);
  }

  Future<Course?> getCourse(String id) async {
    final rows = await _database.getAllCourses();

    for (final row in rows) {
      if (row.id == id) {
        final json =
            jsonDecode(row.dataJson) as Map<String, dynamic>;

        return Course.fromMap(json);
      }
    }

    return null;
  }

  // ============================================================
  // LESSONS
  // ============================================================

  Future<void> saveLesson(Lesson lesson) async {
    await _database.saveLesson(
      CachedLessonsCompanion(
        id: Value(lesson.id),
        courseId: Value(lesson.courseId),
        title: Value(lesson.titleFr),
        content: Value(lesson.contentFr ?? ''),
        durationMinutes: Value(lesson.estimatedMinutes),
        dataJson: Value(jsonEncode(_lessonToJson(lesson))),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> saveLessons(List<Lesson> lessons) async {
    for (final lesson in lessons) {
      await saveLesson(lesson);
    }
  }

  Future<List<Lesson>> getLessons() async {
    final rows = await _database.getAllLessons();

    return rows.map((row) {
      final json =
          jsonDecode(row.dataJson) as Map<String, dynamic>;

      return Lesson.fromMap(json);
    }).toList(growable: false);
  }

  Future<List<Lesson>> getLessonsForCourse(String courseId) async {
    final rows = await _database.getAllLessons();

    return rows
        .where((row) => row.courseId == courseId)
        .map((row) {
          final json =
              jsonDecode(row.dataJson) as Map<String, dynamic>;

          return Lesson.fromMap(json);
        })
        .toList(growable: false);
  }

  Future<Lesson?> getLesson(String id) async {
    final rows = await _database.getAllLessons();

    for (final row in rows) {
      if (row.id == id) {
        final json =
            jsonDecode(row.dataJson) as Map<String, dynamic>;

        return Lesson.fromMap(json);
      }
    }

    return null;
  }

  // ============================================================
  // PROGRESSION LOCALE
  // ============================================================

  Future<void> saveProgress({
    required LessonProgress progress,
  }) async {
    await _database.saveProgress(
      LocalProgressCompanion(
        // Local progress has a stable key even before Supabase creates a row.
        id: Value('${progress.studentId}:${progress.lessonId}'),
        userId: Value(progress.studentId),
        courseId: const Value(null),
        lessonId: Value(progress.lessonId),
        progressPercent: Value(progress.progressPercent),
        completed: Value(progress.status == 'completed'),
        updatedAt: Value(
          progress.updatedAt ?? DateTime.now(),
        ),
      ),
    );
  }

  Future<List<LocalProgressData>> getProgress() {
    return _database.getAllProgress();
  }

  Future<LocalProgressData?> getLocalProgress(String id) async {
    final rows = await _database.getAllProgress();

    for (final row in rows) {
      if (row.id == id) {
        return row;
      }
    }

    return null;
  }

  // ============================================================
  // QCM / DEVOIRS HORS LIGNE
  // ============================================================

  Future<void> saveAssignment(Assignment assignment, String userId) => _database.saveOfflineQcm(
    id: assignment.id, userId: userId, kind: 'assignment', dataJson: jsonEncode(assignment.toMap()),
  );

  Future<void> saveAssignmentQuestions(List<AssignmentQuestion> questions, String userId) async {
    for (final question in questions) {
      await _database.saveOfflineQcm(
        id: question.id, userId: userId, kind: 'question', assignmentId: question.assignmentId,
        dataJson: jsonEncode(question.toMap()),
      );
    }
  }

  Future<List<Assignment>> getAssignments(String userId, {String? assignmentId}) async {
    final rows = await _database.getOfflineQcm(userId, 'assignment', assignmentId: assignmentId);
    return rows.map((row) => Assignment.fromMap(jsonDecode(row.read<String>('data_json')) as Map<String, dynamic>)).toList(growable: false);
  }

  Future<List<AssignmentQuestion>> getAssignmentQuestions(String userId, String assignmentId) async {
    final rows = await _database.getOfflineQcm(userId, 'question', assignmentId: assignmentId);
    return rows.map((row) => AssignmentQuestion.fromMap(jsonDecode(row.read<String>('data_json')) as Map<String, dynamic>)).toList(growable: false);
  }

  Future<void> savePendingAssignment({required String userId, required String submissionId, required String assignmentId, required Map<String, dynamic> payload}) => _database.saveOfflineQcmQueue(
    id: '$submissionId:${DateTime.now().microsecondsSinceEpoch}', userId: userId, submissionId: submissionId, assignmentId: assignmentId, dataJson: jsonEncode(payload),
  );

  Future<List<Map<String, dynamic>>> getPendingAssignments(String userId) async {
    final rows = await _database.getOfflineQcmQueue(userId);
    return rows.map((row) => {
      'id': row.read<String>('id'), 'submission_id': row.read<String>('submission_id'),
      'assignment_id': row.read<String>('assignment_id'), 'data': jsonDecode(row.read<String>('data_json')),
    }).toList(growable: false);
  }

  Future<void> removePendingAssignment(String id, String userId) => _database.deleteOfflineQcmQueue(id, userId);

  Future<void> saveSubmission(AssignmentSubmission submission, String userId) => _database.saveOfflineQcm(
    id: submission.id, userId: userId, kind: 'submission', assignmentId: submission.assignmentId, dataJson: jsonEncode(submission.toMap()),
  );

  Future<AssignmentSubmission?> getSubmission(String userId, String assignmentId) async {
    final rows = await _database.getOfflineQcm(userId, 'submission', assignmentId: assignmentId);
    if (rows.isEmpty) {
      return null;
    }
    return AssignmentSubmission.fromMap(jsonDecode(rows.last.read<String>('data_json')) as Map<String, dynamic>);
  }

  Future<void> saveAnswer(AssignmentAnswer answer, String userId) => _database.saveOfflineQcm(
    id: '${answer.submissionId}:${answer.questionId}', userId: userId, kind: 'answer', assignmentId: answer.submissionId, dataJson: jsonEncode(answer.toMap()),
  );

  Future<List<AssignmentAnswer>> getAnswers(String userId, String submissionId) async {
    final rows = await _database.getOfflineQcm(userId, 'answer', assignmentId: submissionId);
    return rows.map((row) => AssignmentAnswer.fromMap(jsonDecode(row.read<String>('data_json')) as Map<String, dynamic>)).toList(growable: false);
  }

  // ============================================================
  // NETTOYAGE DU CACHE
  // ============================================================

  Future<void> clearCourses() async {
    await _database.deleteAllCourses();
  }

  Future<void> clearLessons() async {
    await _database.deleteAllLessons();
  }

  Future<void> clearProgress() async {
    await _database.deleteAllProgress();
  }

  // ============================================================
  // FERMETURE
  // ============================================================

  Future<void> close() async {
    await _database.closeDatabase();
  }

  // ============================================================
  // CONVERSION COURSE -> JSON
  // ============================================================

  Map<String, dynamic> _courseToJson(Course course) {
    return {
      'id': course.id,
      'curriculum_id': course.curriculumId,
      'chapter_id': course.chapterId,
      'subject_id': course.subjectId,
      'teacher_id': course.teacherId,
      'class_id': course.classId,
      'title_fr': course.titleFr,
      'title_en': course.titleEn,
      'description_fr': course.descriptionFr,
      'description_en': course.descriptionEn,
      'content_fr': course.contentFr,
      'content_en': course.contentEn,
      'status': course.status,
      'smart_lesson_enabled': course.smartLessonEnabled,
      'minimum_exercise_score': course.minimumExerciseScore,
      'published_at':
          course.publishedAt?.toIso8601String(),
    };
  }

  // ============================================================
  // CONVERSION LESSON -> JSON
  // ============================================================

  Map<String, dynamic> _lessonToJson(Lesson lesson) {
    return {
      'id': lesson.id,
      'course_id': lesson.courseId,
      'title_fr': lesson.titleFr,
      'title_en': lesson.titleEn,
      'content_fr': lesson.contentFr,
      'content_en': lesson.contentEn,
      'objectives_fr': lesson.objectivesFr,
      'objectives_en': lesson.objectivesEn,
      'examples_fr': lesson.examplesFr,
      'examples_en': lesson.examplesEn,
      'summary_fr': lesson.summaryFr,
      'summary_en': lesson.summaryEn,
      'position': lesson.position,
      'estimated_minutes': lesson.estimatedMinutes,
      'is_published': lesson.isPublished,
    };
  }
}