import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/assignment.dart';
import '../offline/offline_repository.dart';

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
    // Publish grades whose administrator-configured release time has arrived.
    // The RPC is time-gated in Postgres and never exposes unreleased private grades.
    try {
      await _client.rpc('publish_due_assignment_results');
    } catch (_) {
      // Listing upcoming evaluations must still work if publication has no work to do.
    }

    final hiddenIds = await _hiddenAssignmentIds(studentId);
    List<Assignment> assignments;
    try {
      // Let Supabase RLS determine which published assignments belong to this
      // student. This uses the same is_student_in_class policy as the database
      // instead of a second, potentially inconsistent class_students lookup.
      var request = _client
          .from('assignments')
          .select()
          .inFilter('status', ['published', 'closed']);
      if (courseId != null) {
        request = request.eq('course_id', courseId);
      }
      if (lessonId != null) {
        request = request.eq('lesson_id', lessonId);
      }
      if (subjectId != null) {
        request = request.eq('subject_id', subjectId);
      }
      final rows = await request.order('due_at', ascending: true);
      assignments = rows
          .map((row) => Assignment.fromMap(Map<String, dynamic>.from(row)))
          .where((assignment) => !hiddenIds.contains(assignment.id))
          .toList(growable: false);
    } catch (_) {
      // Fall back only when the remote query failed, not when offline caching
      // fails after a successful response.
      final cached = await OfflineRepository().getAssignments(studentId);
      return cached
          .where((assignment) =>
              !hiddenIds.contains(assignment.id) &&
              (courseId == null || assignment.courseId == courseId) &&
              (lessonId == null || assignment.lessonId == lessonId) &&
              (subjectId == null || assignment.subjectId == subjectId) &&
              ['published', 'closed'].contains(assignment.status))
          .toList(growable: false);
    }

    final offline = OfflineRepository();
    for (final assignment in assignments) {
      try {
        await offline.saveAssignment(assignment, studentId);
      } catch (_) {
        // Keep using the live QCM even if local storage is unavailable.
      }
      try {
        // listQuestions also treats saving to the offline cache as best-effort.
        await listQuestions(assignment.id, studentId: studentId);
      } catch (_) {
        // An unavailable question cache must not hide the QCM itself.
      }
    }
    return assignments;
  }

  Future<Assignment> getAssignment(String id, {String? studentId}) async {
    Assignment assignment;
    try {
      final row = await _client.from('assignments').select().eq('id', id).single();
      assignment = Assignment.fromMap(Map<String, dynamic>.from(row));
    } catch (_) {
      final cached = await OfflineRepository().getAssignments(
        studentId ?? (_client.auth.currentUser?.id ?? ''),
        assignmentId: id,
      );
      if (cached.isEmpty) {
        rethrow;
      }
      return cached.first;
    }

    if (studentId != null) {
      try {
        await OfflineRepository().saveAssignment(assignment, studentId);
      } catch (_) {
        // Use the remote assignment even if offline persistence fails.
      }
    }
    return assignment;
  }

  Future<List<AssignmentQuestion>> listQuestions(String assignmentId, {String? studentId}) async {
    List<AssignmentQuestion> questions;
    try {
      final rows = await _client
          .from('assignment_questions')
          .select(
            studentId == null
                ? '*'
                : 'id,assignment_id,position,question_fr,question_en,question_type,points,options,created_at',
          )
          .eq('assignment_id', assignmentId)
          .order('position', ascending: true);
      questions = rows
          .map((row) => AssignmentQuestion.fromMap(Map<String, dynamic>.from(row)))
          .toList(growable: false);
    } catch (_) {
      final userId = studentId ?? _client.auth.currentUser?.id;
      if (userId == null) {
        rethrow;
      }
      return OfflineRepository().getAssignmentQuestions(userId, assignmentId);
    }

    if (studentId != null) {
      try {
        await OfflineRepository().saveAssignmentQuestions(questions, studentId);
      } catch (_) {
        // A valid remote question list must not be replaced by an empty cache.
      }
    }
    return questions;
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

  Future<Map<String, dynamic>> checkQcmAnswer({
    required String questionId,
    required String selectedOption,
  }) async {
    final result = await _client.rpc(
      'check_assignment_qcm_answer',
      params: {
        'p_question_id': questionId,
        'p_selected_option': selectedOption,
      },
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    if (result is List && result.isNotEmpty && result.first is Map) {
      return Map<String, dynamic>.from(result.first as Map);
    }
    throw StateError('La correction n’a retourné aucun résultat.');
  }

  Future<void> _ensureAssignmentAcceptsAnswers(String submissionId) async {
    final row = await _client
        .from('assignment_submissions')
        .select('assignment_id')
        .eq('id', submissionId)
        .single();
    final assignment = await _client
        .from('assignments')
        .select('status,starts_at,due_at')
        .eq('id', row['assignment_id'] as String)
        .single();
    final status = assignment['status'] as String? ?? 'draft';
    final now = DateTime.now().toUtc();
    final startValue = assignment['starts_at'];
    final startsAt = startValue is String ? DateTime.tryParse(startValue) : null;
    final dueValue = assignment['due_at'];
    final dueAt = dueValue is String ? DateTime.tryParse(dueValue) : null;
    if (status != 'published' ||
        (startsAt != null && now.isBefore(startsAt.toUtc())) ||
        (dueAt != null && !now.isBefore(dueAt.toUtc()))) {
      throw StateError('Cette évaluation est terminée ou n’accepte plus de réponses.');
    }
  }

  Future<AssignmentAnswer> saveAnswer({
    required String submissionId,
    required String questionId,
    String? answerText,
    String? selectedOption,
  }) async {
    await _ensureAssignmentAcceptsAnswers(submissionId);
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
    await _ensureAssignmentAcceptsAnswers(submissionId);
    final now = DateTime.now().toUtc().toIso8601String();

    final row = await _client
        .from('assignment_submissions')
        .update({'status': 'submitted', 'submitted_at': now, 'updated_at': now})
        .eq('id', submissionId)
        .select()
        .single();

    // Submission is already safely saved. AI grading runs asynchronously and
    // stores marks in the private table until the configured release time.
    unawaited(requestAiCorrection(submissionId));
    return AssignmentSubmission.fromMap(Map<String, dynamic>.from(row));
  }

  Future<void> requestAiCorrection(String submissionId) async {
    try {
      await _client.functions.invoke(
        'grade-assignment',
        body: {'submission_id': submissionId},
      );
    } catch (_) {
      // Never turn a successful submission into a reported send failure.
      // The saved submission remains available for a grading retry.
    }
  }

  Future<List<Assignment>> listTeacherAssignments({
    required String teacherId,
    String? courseId,
    String? classId,
    String? status,
  }) async {
    final hiddenIds = await _hiddenAssignmentIds(teacherId);
    var request = _client
        .from('assignments')
        .select()
        .eq('teacher_id', teacherId);

    if (courseId != null) {
      request = request.eq('course_id', courseId);
    }

    if (classId != null) {
      request = request.eq('class_id', classId);
    }

    if (status != null) {
      request = request.eq('status', status);
    }

    final rows = await request.order('updated_at', ascending: false);

    return rows
        .map((row) => Assignment.fromMap(Map<String, dynamic>.from(row)))
        .where((assignment) => !hiddenIds.contains(assignment.id))
        .toList(growable: false);
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
    DateTime? startsAt,
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
      'starts_at': startsAt?.toIso8601String(),
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

  Future<Set<String>> _hiddenAssignmentIds(String userId) async {
    try {
      final rows = await _client
          .from('assignment_user_hides')
          .select('assignment_id')
          .eq('user_id', userId);
      return rows
          .map((row) => row['assignment_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      // Preserve the current QCM experience until the matching migration is applied.
      return <String>{};
    }
  }

  /// Hide an assignment only for the currently authenticated user.
  Future<void> hideAssignmentForMe(String assignmentId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Vous devez être connecté pour masquer ce QCM.');
    }
    await _client.from('assignment_user_hides').upsert(
      {
        'assignment_id': assignmentId,
        'user_id': userId,
      },
      onConflict: 'assignment_id,user_id',
    );
  }

  /// Permanently remove a teacher-owned QCM for everyone, including its
  /// dependent questions/submissions as governed by the database foreign keys.
  Future<void> deleteAssignmentForEveryone(
    String assignmentId, {
    required String teacherId,
  }) async {
    final deleted = await _client
        .from('assignments')
        .delete()
        .eq('id', assignmentId)
        .eq('teacher_id', teacherId)
        .select('id')
        .maybeSingle();
    if (deleted == null) {
      throw StateError(
        'Suppression refusée : le QCM est introuvable ou vous ne pouvez pas le supprimer.',
      );
    }
  }

  /// Remove a partially created QCM only after a fresh server read confirms
  /// that it is still a draft. If the server state cannot be read, preserve it.
  Future<void> deleteDraftAssignmentIfUnpublished(
    String assignmentId, {
    required String teacherId,
  }) async {
    final row = await _client
        .from('assignments')
        .select('status')
        .eq('id', assignmentId)
        .eq('teacher_id', teacherId)
        .maybeSingle();
    if (row != null && row['status'] == 'draft') {
      await deleteAssignmentForEveryone(assignmentId, teacherId: teacherId);
    }
  }

  /// Backwards-compatible alias: permanent deletion remains owner-scoped.
  Future<void> deleteAssignment(String assignmentId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Vous devez être connecté pour supprimer ce QCM.');
    }
    await deleteAssignmentForEveryone(assignmentId, teacherId: userId);
  }

  Future<Assignment> publishAssignment(String assignmentId) async {
    // Return the row produced by the UPDATE itself. Do not verify publication
    // through getAssignment(), which may return a stale offline draft after a
    // transient read error even though the server accepted the publication.
    final row = await _client
        .from('assignments')
        .update({
          'status': 'published',
          'published_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', assignmentId)
        .select()
        .single();
    final published = Assignment.fromMap(Map<String, dynamic>.from(row));
    if (published.status != 'published') {
      throw StateError('Supabase n’a pas confirmé la publication du QCM.');
    }
    return published;
  }

  Future<void> closeAssignment(String assignmentId) async {
    await _client
        .from('assignments')
        .update({'status': 'closed'})
        .eq('id', assignmentId);
  }
}
