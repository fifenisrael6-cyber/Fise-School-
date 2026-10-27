import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/assignment.dart';
import '../offline/offline_repository.dart';
import '../offline/json_cache.dart';

class AssignmentService {
  final SupabaseClient _client;

  AssignmentService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<List<Assignment>> listStudentAssignments({
    required String studentId,
    String? courseId,
    String? lessonId,
    String? subjectId,
  }) async {
    final offline = OfflineRepository();
    final cachedAssignments = await offline.getAssignments(studentId);
    final cachedFiltered = cachedAssignments.where((assignment) =>
        (courseId == null || assignment.courseId == courseId) &&
        (lessonId == null || assignment.lessonId == lessonId) &&
        (subjectId == null || assignment.subjectId == subjectId)).toList(growable: false);
    if (cachedFiltered.isNotEmpty) {
      // Render saved QCM immediately; update the offline copy in the background.
      unawaited(_refreshStudentAssignments(
        studentId: studentId,
        courseId: courseId,
        lessonId: lessonId,
        subjectId: subjectId,
      ));
      return cachedFiltered;
    }
    try {
      // Row-level security restricts results to this student; a client-side
      // class_id filter hides assignments for compatible classroom targets.
      var request = _client
          .from('assignments')
          .select()
          .inFilter('status', ['published', 'closed'])
          .isFilter('exam_id', null);
      if (courseId != null) request = request.eq('course_id', courseId);
      if (lessonId != null) request = request.eq('lesson_id', lessonId);
      if (subjectId != null) request = request.eq('subject_id', subjectId);

      final rows = await request.order('due_at', ascending: true);
      final assignments = rows
          .map((row) => Assignment.fromMap(Map<String, dynamic>.from(row)))
          .toList(growable: false);
      final offline = OfflineRepository();
      for (final assignment in assignments) {
        await offline.saveAssignment(assignment, studentId);
        try {
          final questions = await listQuestions(
            assignment.id,
            studentId: studentId,
          );
          await offline.saveAssignmentQuestions(questions, studentId);
        } catch (_) {
          // Keep the published QCM visible if offline question caching fails.
        }
      }
      return assignments;
    } catch (_) {
      final cached = await OfflineRepository().getAssignments(studentId);
      return cached
          .where((assignment) =>
              (courseId == null || assignment.courseId == courseId) &&
              (lessonId == null || assignment.lessonId == lessonId) &&
              (subjectId == null || assignment.subjectId == subjectId))
          .toList(growable: false);
    }
  }

  Future<void> _refreshStudentAssignments({
    required String studentId,
    String? courseId,
    String? lessonId,
    String? subjectId,
  }) async {
    try {
      dynamic request = _client
          .from('assignments')
          .select()
          .inFilter('status', ['published', 'closed'])
          .isFilter('exam_id', null);
      if (courseId != null) request = request.eq('course_id', courseId);
      if (lessonId != null) request = request.eq('lesson_id', lessonId);
      if (subjectId != null) request = request.eq('subject_id', subjectId);
      final rows = await request.order('due_at', ascending: true)
          .timeout(JsonCache.networkTimeout);
      final offline = OfflineRepository();
      for (final row in rows) {
        final assignment = Assignment.fromMap(Map<String, dynamic>.from(row));
        await offline.saveAssignment(assignment, studentId);
        try {
          final questionRows = await _client
              .from('assignment_questions')
              .select()
              .eq('assignment_id', assignment.id)
              .order('position', ascending: true)
              .timeout(JsonCache.networkTimeout);
          final questions = questionRows
              .map((q) => AssignmentQuestion.fromMap(Map<String, dynamic>.from(q)))
              .toList(growable: false);
          await offline.saveAssignmentQuestions(questions, studentId);
        } catch (_) {
          // Keep the previous locally saved questions if refresh fails.
        }
      }
    } catch (_) {
      // Refresh is opportunistic; the cached QCM remains available.
    }
  }

  Future<Assignment> getAssignment(String id, {String? studentId}) async {
    try {
      final row = await _client.from('assignments').select().eq('id', id).single();
      final assignment = Assignment.fromMap(Map<String, dynamic>.from(row));
      if (studentId != null) {
        await OfflineRepository().saveAssignment(assignment, studentId);
      }
      return assignment;
    } catch (_) {
      final cached = await OfflineRepository().getAssignments(studentId ?? (_client.auth.currentUser?.id ?? ''), assignmentId: id);
      if (cached.isEmpty) {
        rethrow;
      }
      return cached.first;
    }
  }

  Future<List<AssignmentQuestion>> listQuestions(String assignmentId, {String? studentId}) async {
    try {
      final rows = await _client.from('assignment_questions').select().eq('assignment_id', assignmentId).order('position', ascending: true);
      final questions = rows.map((row) => AssignmentQuestion.fromMap(Map<String, dynamic>.from(row))).toList(growable: false);
      if (studentId != null) {
        await OfflineRepository().saveAssignmentQuestions(questions, studentId);
      }
      return questions;
    } catch (_) {
      final userId = studentId ?? _client.auth.currentUser?.id;
      if (userId == null) {
        rethrow;
      }
      return OfflineRepository().getAssignmentQuestions(userId, assignmentId);
    }
  }

  Future<AssignmentSubmission?> getStudentSubmission({
    required String assignmentId,
    required String studentId,
  }) async {
    final row = await _client
        .from('assignment_submissions')
        .select()
        .eq('assignment_id', assignmentId)
        .eq('student_id', studentId)
        .maybeSingle();

    if (row == null) {
      return null;
    }

    return AssignmentSubmission.fromMap(Map<String, dynamic>.from(row));
  }

  Future<AssignmentSubmission> createOrGetStudentSubmission({
    required String assignmentId,
    required String studentId,
  }) async {
    final existing = await getStudentSubmission(
      assignmentId: assignmentId,
      studentId: studentId,
    );

    if (existing != null) {
      return existing;
    }

    final row = await _client
        .from('assignment_submissions')
        .insert({
          'assignment_id': assignmentId,
          'student_id': studentId,
          'status': 'draft',
        })
        .select()
        .single();

    return AssignmentSubmission.fromMap(Map<String, dynamic>.from(row));
  }

  Future<List<AssignmentAnswer>> listAnswers(String submissionId) async {
    final rows = await _client
        .from('assignment_answers')
        .select()
        .eq('submission_id', submissionId)
        .order('created_at', ascending: true);

    return rows
        .map((row) => AssignmentAnswer.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<AssignmentAnswer?> getAnswer({
    required String submissionId,
    required String questionId,
  }) async {
    final row = await _client
        .from('assignment_answers')
        .select()
        .eq('submission_id', submissionId)
        .eq('question_id', questionId)
        .maybeSingle();

    if (row == null) {
      return null;
    }

    return AssignmentAnswer.fromMap(Map<String, dynamic>.from(row));
  }

  Future<AssignmentAnswer> saveAnswer({
    required String submissionId,
    required String questionId,
    String? answerText,
    String? selectedOption,
  }) async {
    final row = await _client
        .from('assignment_answers')
        .upsert({
          'submission_id': submissionId,
          'question_id': questionId,
          'answer_text': answerText,
          'selected_option': selectedOption,
        }, onConflict: 'submission_id,question_id')
        .select()
        .single();

    return AssignmentAnswer.fromMap(Map<String, dynamic>.from(row));
  }

  Future<AssignmentSubmission> submitAssignment({
    required String submissionId,
  }) async {
    final now = DateTime.now().toIso8601String();

    final row = await _client
        .from('assignment_submissions')
        .update({'status': 'submitted', 'submitted_at': now, 'updated_at': now})
        .eq('id', submissionId)
        .select()
        .single();

    return AssignmentSubmission.fromMap(Map<String, dynamic>.from(row));
  }

  Future<List<Assignment>> listTeacherAssignments({
    required String teacherId,
    String? courseId,
    String? classId,
    String? status,
  }) async {
    final cacheKey = 'teacher_assignments_' + teacherId +
        '_' + (courseId ?? 'all-courses') +
        '_' + (classId ?? 'all-classes') +
        '_' + (status ?? 'all-statuses');
    final assignments = await JsonCache.instance.cachedRead<List<Assignment>>(
      key: cacheKey,
      fetch: () async {
        dynamic request = _client.from('assignments').select().eq('teacher_id', teacherId);
        if (courseId != null) request = request.eq('course_id', courseId);
        if (classId != null) request = request.eq('class_id', classId);
        if (status != null) request = request.eq('status', status);
        return await request.order('updated_at', ascending: false) as Object?;
      },
      decode: (raw) => raw is List
          ? raw.whereType<Map>()
              .map((row) => Assignment.fromMap(Map<String, dynamic>.from(row)))
              .toList(growable: false)
          : <Assignment>[],
    );

    final prefs = await SharedPreferences.getInstance();
    final hidden = prefs.getStringList('hidden_teacher_assignments_$teacherId')?.toSet() ?? <String>{};
    return assignments.where((assignment) => !hidden.contains(assignment.id)).toList(growable: false);
  }

  Future<Assignment> saveAssignment({
    String? id,
    String? courseId,
    String? subjectId,
    String? lessonId,
    required String teacherId,
    required String classId,
    required String titleFr,
    required String titleEn,
    String? instructionsFr,
    String? instructionsEn,
    DateTime? dueAt,
    required String status,
    double maxScore = 20,
  }) async {
    final values = {
      'course_id': courseId,
      'subject_id': subjectId,
      'lesson_id': lessonId,
      'teacher_id': teacherId,
      'class_id': classId,
      'title_fr': titleFr.trim(),
      'title_en': titleEn.trim(),
      'instructions_fr': instructionsFr?.trim(),
      'instructions_en': instructionsEn?.trim(),
      'due_at': dueAt?.toIso8601String(),
      'status': status,
      'max_score': maxScore,
      'published_at': status == 'published'
          ? DateTime.now().toIso8601String()
          : null,
    };

    final row = id == null
        ? await _client.from('assignments').insert(values).select().single()
        : await _client
              .from('assignments')
              .update(values)
              .eq('id', id)
              .select()
              .single();

    return Assignment.fromMap(Map<String, dynamic>.from(row));
  }

  Future<AssignmentQuestion> saveQuestion({
    String? id,
    required String assignmentId,
    required int position,
    required String questionFr,
    required String questionEn,
    required String questionType,
    double points = 1,
    List<String> options = const [],
    String? correctAnswer,
  }) async {
    final values = {
      'assignment_id': assignmentId,
      'position': position,
      'question_fr': questionFr.trim(),
      'question_en': questionEn.trim(),
      'question_type': questionType,
      'points': points,
      'options': options,
      'correct_answer': correctAnswer,
    };

    final row = id == null
        ? await _client
              .from('assignment_questions')
              .insert(values)
              .select()
              .single()
        : await _client
              .from('assignment_questions')
              .update(values)
              .eq('id', id)
              .select()
              .single();

    return AssignmentQuestion.fromMap(Map<String, dynamic>.from(row));
  }

  Future<void> deleteQuestion(String questionId) async {
    await _client.from('assignment_questions').delete().eq('id', questionId);
  }

  Future<void> deleteAssignment(String assignmentId) async {
    await _client.from('assignments').delete().eq('id', assignmentId);
  }

  Future<void> deleteAssignmentForEveryone(String assignmentId, {required String teacherId}) async {
    await _client.from('assignments').delete().eq('id', assignmentId).eq('teacher_id', teacherId);
  }

  Future<void> hideAssignmentForMe(String assignmentId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('Session utilisateur absente.');
    final prefs = await SharedPreferences.getInstance();
    final key = 'hidden_teacher_assignments_$userId';
    final hidden = prefs.getStringList(key) ?? <String>[];
    if (!hidden.contains(assignmentId)) {
      hidden.add(assignmentId);
      await prefs.setStringList(key, hidden);
    }
  }

  Future<void> publishAssignment(String assignmentId) async {
    await _client
        .from('assignments')
        .update({
          'status': 'published',
          'published_at': DateTime.now().toIso8601String(),
        })
        .eq('id', assignmentId);
  }

  Future<void> closeAssignment(String assignmentId) async {
    await _client
        .from('assignments')
        .update({'status': 'closed'})
        .eq('id', assignmentId);
  }
}
