import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/pedagogy_service.dart';
import '../../core/services/assignment_service.dart';
import '../../models/pedagogy.dart';
import 'offline_repository.dart';
import 'app_database.dart';
import 'course_offline_service.dart';

class SyncService {
  SyncService({SupabaseClient? client, OfflineRepository? offlineRepository})
    : _client = client ?? Supabase.instance.client,
      _offline = offlineRepository ?? OfflineRepository();

  final SupabaseClient _client;
  final OfflineRepository _offline;

  // ============================================================
  // SYNCHRONISATION DES COURS D'UN ÉLÈVE
  // ============================================================

  Future<void> syncStudentCourses(String studentId) async {
    final courseService = CourseService(client: _client);

    final List<Course> courses = await courseService.listStudentCourses(studentId);
    final cachedCourses = await _offline.getCoursesForStudent(studentId);
    final visibleIds = courses.map((course) => course.id).toSet();
    final fileCleaner = CourseOfflineService(client: _client);
    for (final cached in cachedCourses) {
      if (!visibleIds.contains(cached.id)) {
        await fileCleaner.deleteCourseFiles(studentId, cached.id);
      }
    }
    await _offline.saveCourses(courses);

    await syncPendingAssignments(studentId);
    await syncPendingSmartExercises(studentId);

    for (final Course course in courses) {
      try {
        final List<Lesson> lessons = await courseService.listLessons(course.id);
        await _offline.saveLessons(lessons);
      } catch (_) {
        // Keep the rest of the offline cache usable if one course fails.
      }
    }
  }

  // ============================================================
  // SYNCHRONISATION D'UN COURS
  // ============================================================

  Future<void> syncCourse(String courseId) async {
    final courseService = CourseService(client: _client);

    final Course course = await courseService.getCourse(courseId);

    await _offline.saveCourse(course);

    final List<Lesson> lessons = await courseService.listLessons(courseId);

    await _offline.saveLessons(lessons);
  }

  // ============================================================
  // SYNCHRONISATION D'UNE LEÇON
  // ============================================================

  Future<void> syncLesson(String lessonId) async {
    final lessonService = LessonService(client: _client);

    final Lesson lesson = await lessonService.getLesson(lessonId);

    await _offline.saveLesson(lesson);
  }

  Future<void> syncPendingSmartExercises(String studentId) async {
    final database = AppDatabase();
    final pending = await database.getSmartExerciseQueue(studentId);
    for (final item in pending) {
      try {
        final answers = jsonDecode(item.read<String>('answers_json'));
        final response = await _client.rpc(
          'submit_exercise_answers',
          params: {
            'p_lesson_id': item.read<String>('lesson_id'),
            'p_answers': answers,
          },
        );
        await database.saveSmartExerciseResult(
          id: '${item.read<String>('lesson_id')}-${DateTime.now().microsecondsSinceEpoch}',
          userId: studentId,
          lessonId: item.read<String>('lesson_id'),
          dataJson: jsonEncode(response),
        );
        await database.deleteSmartExerciseQueue(item.read<String>('id'), studentId);
      } catch (_) {
        // Keep the answer queued for a later online synchronization.
      }
    }
  }

  Future<void> syncPendingAssignments(String studentId) async {
    final pending = await _offline.getPendingAssignments(studentId);
    final assignmentService = AssignmentService(client: _client);
    for (final item in pending) {
      try {
        final serverSubmission = await assignmentService.createOrGetStudentSubmission(
          assignmentId: item['assignment_id'] as String, studentId: studentId,
        );
        final data = Map<String, dynamic>.from(item['data'] as Map);
        final answers = (data['answers'] as List? ?? const []).whereType<Map>().toList();
        for (final answer in answers) {
          await assignmentService.saveAnswer(
            submissionId: serverSubmission.id,
            questionId: answer['question_id'] as String,
            answerText: answer['answer_text'] as String?,
            selectedOption: answer['selected_option'] as String?,
          );
        }
        await assignmentService.submitAssignment(submissionId: serverSubmission.id);
        await _offline.removePendingAssignment(item['id'] as String, studentId);
      } catch (_) {
        // Keep it queued until a later online synchronization succeeds.
      }
    }
  }

}
