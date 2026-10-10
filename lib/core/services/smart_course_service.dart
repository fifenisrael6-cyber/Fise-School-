import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/smart_learning.dart';
import '../offline/app_database.dart';

class SmartCourseService {
  SmartCourseService({SupabaseClient? client, AppDatabase? database})
      : _client = client ?? Supabase.instance.client,
        _db = database ?? AppDatabase();

  final SupabaseClient _client;
  final AppDatabase _db;

  Future<bool> _isOnline() async {
    final values = await Connectivity().checkConnectivity();
    return values.any((value) => value != ConnectivityResult.none);
  }

  Future<SmartLesson?> loadDailyLesson({String? subjectId}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return null;
    }

    if (await _isOnline()) {
      try {
        final response = await _client.functions.invoke(
          'daily-lesson',
          body: {'subject_id': ?subjectId},
        );
        final data = Map<String, dynamic>.from(
          (response.data as Map?)?.cast<String, dynamic>() ?? const {},
        );
        if (data['error'] != null) {
          throw Exception(data['error']);
        }
        if (data['status'] != 'ready') {
          return null;
        }
        final lesson = SmartLesson.fromEdge(data);
        if (lesson.id.isNotEmpty) {
          await _db.saveSmartLesson(
            userId: userId,
            id: lesson.id,
            dataJson: jsonEncode(lesson.toJson()),
          );
        }
        return lesson;
      } catch (_) {
        // Offline cache is the fallback even if the network exists but the server is temporary unavailable.
      }
    }

    final cachedRows = await _db.getSmartLessons(userId);
    for (final cached in cachedRows) {
      final data = jsonDecode(cached.read<String>('data_json'));
      final lesson = SmartLesson.fromJson(Map<String, dynamic>.from(data as Map));
      if (subjectId == null || lesson.subjectId == subjectId) {
        return lesson;
      }
    }
    return null;
  }

  Future<SmartExerciseResult?> submitAnswers({
    required SmartLesson lesson,
    required Map<String, int> answers,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return null;
    }

    if (await _isOnline()) {
      final response = await _client.rpc(
        'submit_exercise_answers',
        params: {
          'p_lesson_id': lesson.id,
          'p_answers': answers.map((key, value) => MapEntry(key, value.toString())),
        },
      );
      final result = SmartExerciseResult.fromMap(
        Map<String, dynamic>.from(response as Map),
      );
      await _db.saveSmartExerciseResult(
        id: '${lesson.id}-${result.attempt}',
        userId: userId,
        lessonId: lesson.id,
        dataJson: jsonEncode(response),
      );
      return result;
    }

    await _db.queueSmartExercise(
      id: '$userId-${lesson.id}-${DateTime.now().microsecondsSinceEpoch}',
      userId: userId,
      lessonId: lesson.id,
      answersJson: jsonEncode(answers.map((key, value) => MapEntry(key, value.toString()))),
    );
    return null;
  }

  Future<SmartExerciseResult?> loadCachedResult(String lessonId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return null;
    }
    final row = await _db.getSmartExerciseResult(userId, lessonId);
    if (row == null) {
      return null;
    }
    final data = jsonDecode(row.read<String>('data_json'));
    return SmartExerciseResult.fromMap(Map<String, dynamic>.from(data as Map));
  }

  Future<void> reportError(String lessonId, String reason) async {
    await _client.rpc(
      'report_smart_lesson_error',
      params: {'p_lesson_id': lessonId, 'p_reason': reason},
    );
  }

  Future<ClassProgressSummary?> getClassProgressSummary(String classId) async {
    final response = await _client.rpc(
      'get_class_progress_summary',
      params: {'p_class_id': classId},
    );
    if (response is! Map) {
      return null;
    }
    return ClassProgressSummary.fromMap(Map<String, dynamic>.from(response));
  }

  Future<List<Map<String, dynamic>>> getWeeklyProgress(String classId) async {
    final rows = await _client.rpc(
      'get_student_weekly_progress',
      params: {'p_class_id': classId, 'p_weeks': 8},
    );
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getTeacherClassDetail(String classId) async {
    final rows = await _client.rpc(
      'get_teacher_class_progress_detail',
      params: {'p_class_id': classId},
    );
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getTeacherSubjectDetail(String classId) async {
    final rows = await _client.rpc(
      'get_teacher_class_subject_summary',
      params: {'p_class_id': classId},
    );
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<void> approveIndex(String resourceId, {bool approved = true}) async {
    await _client.rpc(
      'approve_course_resource_index',
      params: {'p_resource_id': resourceId, 'p_approved': approved},
    );
  }

  Future<void> reindexResource(String resourceId) async {
    final response = await _client.functions.invoke(
      'index-course-file',
      body: {'resource_id': resourceId},
    );
    final data = Map<String, dynamic>.from(
      (response.data as Map?)?.cast<String, dynamic>() ?? const {},
    );
    if (data['error'] != null) {
      throw Exception(data['error']);
    }
  }
}
