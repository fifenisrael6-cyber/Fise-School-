import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/pedagogy_service.dart';
import '../../core/services/assignment_service.dart';
import '../../core/services/chapter_learning_service.dart';
import '../../models/pedagogy.dart';
import '../../models/chapter_learning_content.dart';
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

    // Dès la synchronisation des cours, lancer le préchargement local des
    // ressources de tous les cours publiés. L'interface n'attend pas les fichiers.
    unawaited(CourseOfflineService.shared.enqueueSubject(
      userId: studentId,
      courses: courses,
    ));
    unawaited(_prefetchChapterLearning(studentId, courses));

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

  /// Reprend les téléchargements de médias de chapitres manquants sans
  /// refaire toute la synchronisation des cours.
  Future<void> retryChapterMediaPrefetch(String studentId) async {
    final cachedCourses = await _offline.getCoursesForStudent(studentId);
    await _prefetchChapterLearning(studentId, cachedCourses);
  }

  Future<void> _prefetchChapterLearning(String studentId, List<Course> courses) async {
    final chapterIds = courses
        .map((course) => course.chapterId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final subjectIds = courses.map((course) => course.subjectId).where((id) => id.isNotEmpty).toSet();
    try {
      final memberships = await _client
          .from('class_students')
          .select('class_id, joined_at')
          .eq('student_id', studentId)
          .eq('is_active', true)
          .order('joined_at', ascending: false)
          .limit(1);
      final classIds = memberships
          .map((row) => row['class_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
      if (classIds.isNotEmpty) {
        final assigned = await _client
            .from('class_subjects')
            .select('subject_id')
            .eq('is_active', true)
            .inFilter('class_id', classIds.toList(growable: false));
        subjectIds.addAll(assigned
            .map((row) => row['subject_id']?.toString())
            .whereType<String>()
            .where((id) => id.isNotEmpty));
      }
    } catch (_) {
      // Retain subjects discovered through published courses if membership
      // metadata is unavailable.
    }
    final catalog = CourseService(client: _client);
    for (final subjectId in subjectIds) {
      try {
        final catalogChapters = await catalog.listStudentCatalogChapters(
          studentId,
          subjectId: subjectId,
        );
        chapterIds.addAll(catalogChapters.map((chapter) => chapter.id).where((id) => id.isNotEmpty));
      } catch (_) {
        // Keep chapter IDs from published courses if the catalog is unavailable.
      }
    }
    if (chapterIds.isEmpty) return;
    final chapters = ChapterLearningService(client: _client);
    for (final chapterId in chapterIds) {
      try {
        final results = await Future.wait<dynamic>([
          chapters.listContent(chapterId),
          chapters.listExercises(chapterId),
          chapters.listQuizzes(chapterId),
          chapters.getCounts(chapterId),
        ]);
        final quizzes = results[2] as List<ChapterLearningQuiz>;
        await Future.wait<void>(quizzes.map((quiz) async {
          try {
            await chapters.listQuizQuestions(quiz.id);
          } catch (_) {
            // Keep the chapter available even if one quiz question set fails.
          }
        }));
        await chapters.prefetchChapterMedia(chapterId);
      } catch (_) {
        // Keep each successfully cached chapter available if another fails.
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
