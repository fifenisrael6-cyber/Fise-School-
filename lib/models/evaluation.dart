// Modèles du système d'évaluation automatisée (épreuves PDF, remises en photos,
// correction IA proposée, validation par l'enseignant).

DateTime? _dt(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
double? _n(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
int _i(Object? v) => v is num ? v.toInt() : 0;
Map<String, dynamic> _m(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _ml(Object? v) => v is List
    ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList(growable: false)
    : const <Map<String, dynamic>>[];

class EvalSubmissionInfo {
  final String id;
  final String status; // draft | submitted
  final DateTime? submittedAt;
  final bool isLate;
  final int lateMinutes;
  final int photoCount;

  const EvalSubmissionInfo({
    required this.id,
    required this.status,
    this.submittedAt,
    this.isLate = false,
    this.lateMinutes = 0,
    this.photoCount = 0,
  });

  bool get isSubmitted => status == 'submitted';

  factory EvalSubmissionInfo.fromMap(Map<String, dynamic> m) => EvalSubmissionInfo(
        id: m['id'].toString(),
        status: (m['status'] ?? 'draft').toString(),
        submittedAt: _dt(m['submitted_at']),
        isLate: m['is_late'] == true,
        lateMinutes: _i(m['late_minutes']),
        photoCount: _i(m['photo_count']),
      );
}

class EvalQuestionResult {
  final String label;
  final double? points;
  final double maxPoints;
  final String? feedback;

  const EvalQuestionResult({
    required this.label,
    required this.points,
    required this.maxPoints,
    this.feedback,
  });

  factory EvalQuestionResult.fromMap(Map<String, dynamic> m) => EvalQuestionResult(
        label: (m['label'] ?? '').toString(),
        points: _n(m['points']),
        maxPoints: _n(m['max_points']) ?? 0,
        feedback: m['feedback']?.toString(),
      );
}

class EvalResult {
  final double? finalScore;
  final double maxScore;
  final double penaltyPercent;
  final String? comment;
  final List<EvalQuestionResult> questions;

  const EvalResult({
    required this.finalScore,
    required this.maxScore,
    required this.penaltyPercent,
    this.comment,
    this.questions = const [],
  });

  factory EvalResult.fromMap(Map<String, dynamic> m) => EvalResult(
        finalScore: _n(m['final_score']),
        maxScore: _n(m['max_score']) ?? 20,
        penaltyPercent: _n(m['penalty_percent']) ?? 0,
        comment: m['comment']?.toString(),
        questions: _ml(m['questions']).map(EvalQuestionResult.fromMap).toList(growable: false),
      );
}

class StudentEvaluation {
  final String id;
  final String title;
  final String? instructions;
  final String subjectFr;
  final String subjectEn;
  final DateTime startsAt;
  final DateTime dueAt;
  final int? durationMinutes;
  final String latePolicy; // reject | accept_flagged | accept_penalty
  final int lateGraceMinutes;
  final double latePenaltyPercent;
  final double maxScore;
  final String status;
  final String? pdfName;
  final String? pdfPath;
  final EvalSubmissionInfo? submission;
  final EvalResult? result;

  const StudentEvaluation({
    required this.id,
    required this.title,
    this.instructions,
    required this.subjectFr,
    required this.subjectEn,
    required this.startsAt,
    required this.dueAt,
    this.durationMinutes,
    required this.latePolicy,
    required this.lateGraceMinutes,
    required this.latePenaltyPercent,
    required this.maxScore,
    required this.status,
    this.pdfName,
    this.pdfPath,
    this.submission,
    this.result,
  });

  factory StudentEvaluation.fromMap(Map<String, dynamic> m) {
    final sub = m['submission'];
    final res = m['result'];
    return StudentEvaluation(
      id: m['id'].toString(),
      title: (m['title'] ?? '').toString(),
      instructions: m['instructions']?.toString(),
      subjectFr: (m['subject_name_fr'] ?? '').toString(),
      subjectEn: (m['subject_name_en'] ?? m['subject_name_fr'] ?? '').toString(),
      startsAt: _dt(m['starts_at']) ?? DateTime.now(),
      dueAt: _dt(m['due_at']) ?? DateTime.now(),
      durationMinutes: (m['duration_minutes'] as num?)?.toInt(),
      latePolicy: (m['late_policy'] ?? 'reject').toString(),
      lateGraceMinutes: _i(m['late_grace_minutes']),
      latePenaltyPercent: _n(m['late_penalty_percent']) ?? 0,
      maxScore: _n(m['max_score']) ?? 20,
      status: (m['status'] ?? 'published').toString(),
      pdfName: m['pdf_name']?.toString(),
      pdfPath: m['pdf_path']?.toString(),
      submission: sub is Map ? EvalSubmissionInfo.fromMap(Map<String, dynamic>.from(sub)) : null,
      result: res is Map ? EvalResult.fromMap(Map<String, dynamic>.from(res)) : null,
    );
  }

  String subjectFor(bool fr) => fr ? subjectFr : (subjectEn.isEmpty ? subjectFr : subjectEn);
  bool get submitted => submission?.isSubmitted == true;
}

class StudentEvaluationList {
  /// Écart entre l'horloge du serveur et celle de l'appareil : le compte à rebours
  /// et les fenêtres de remise se basent sur l'heure serveur.
  final Duration serverOffset;
  final List<StudentEvaluation> items;

  const StudentEvaluationList({required this.serverOffset, required this.items});

  factory StudentEvaluationList.fromMap(Map<String, dynamic> m) {
    final serverNow = _dt(m['server_now']);
    return StudentEvaluationList(
      serverOffset: serverNow == null ? Duration.zero : serverNow.difference(DateTime.now()),
      items: _ml(m['evaluations']).map(StudentEvaluation.fromMap).toList(growable: false),
    );
  }
}

class TeacherEvaluation {
  final String id;
  final String title;
  final String status;
  final String subjectFr;
  final DateTime startsAt;
  final DateTime dueAt;
  final double maxScore;
  final List<String> classes;
  final int submittedCount;
  final int toReviewCount;
  final int validatedCount;
  final int errorCount;

  const TeacherEvaluation({
    required this.id,
    required this.title,
    required this.status,
    required this.subjectFr,
    required this.startsAt,
    required this.dueAt,
    required this.maxScore,
    required this.classes,
    required this.submittedCount,
    required this.toReviewCount,
    required this.validatedCount,
    required this.errorCount,
  });

  factory TeacherEvaluation.fromMap(Map<String, dynamic> m) => TeacherEvaluation(
        id: m['id'].toString(),
        title: (m['title'] ?? '').toString(),
        status: (m['status'] ?? 'draft').toString(),
        subjectFr: (m['subject_name_fr'] ?? '').toString(),
        startsAt: _dt(m['starts_at']) ?? DateTime.now(),
        dueAt: _dt(m['due_at']) ?? DateTime.now(),
        maxScore: _n(m['max_score']) ?? 20,
        classes: (m['classes'] is List)
            ? (m['classes'] as List).map((e) => e.toString()).toList(growable: false)
            : const [],
        submittedCount: _i(m['submitted_count']),
        toReviewCount: _i(m['to_review_count']),
        validatedCount: _i(m['validated_count']),
        errorCount: _i(m['error_count']),
      );
}

class ReviewRow {
  final String studentId;
  final String firstName;
  final String lastName;
  final String className;
  final String? submissionId;
  final String submissionStatus; // submitted | not_submitted
  final DateTime? submittedAt;
  final bool isLate;
  final int lateMinutes;
  final int photoCount;
  final String? correctionStatus;
  final String? validationStatus;
  final double? provisionalScore;
  final double? finalScore;
  final double maxScore;
  final List<String> reviewReasons;
  final String? lastError;

  const ReviewRow({
    required this.studentId,
    required this.firstName,
    required this.lastName,
    required this.className,
    required this.submissionId,
    required this.submissionStatus,
    this.submittedAt,
    this.isLate = false,
    this.lateMinutes = 0,
    this.photoCount = 0,
    this.correctionStatus,
    this.validationStatus,
    this.provisionalScore,
    this.finalScore,
    required this.maxScore,
    this.reviewReasons = const [],
    this.lastError,
  });

  String get fullName => '$lastName $firstName'.trim();
  bool get submitted => submissionStatus == 'submitted';
  bool get validated => validationStatus == 'validated';

  factory ReviewRow.fromMap(Map<String, dynamic> m) => ReviewRow(
        studentId: m['student_id'].toString(),
        firstName: (m['first_name'] ?? '').toString(),
        lastName: (m['last_name'] ?? '').toString(),
        className: (m['class_name'] ?? '').toString(),
        submissionId: m['submission_id']?.toString(),
        submissionStatus: (m['submission_status'] ?? 'not_submitted').toString(),
        submittedAt: _dt(m['submitted_at']),
        isLate: m['is_late'] == true,
        lateMinutes: _i(m['late_minutes']),
        photoCount: _i(m['photo_count']),
        correctionStatus: m['correction_status']?.toString(),
        validationStatus: m['validation_status']?.toString(),
        provisionalScore: _n(m['provisional_score']),
        finalScore: _n(m['final_score']),
        maxScore: _n(m['max_score']) ?? 20,
        reviewReasons: (m['review_reasons'] is List)
            ? (m['review_reasons'] as List).map((e) => e.toString()).toList(growable: false)
            : const [],
        lastError: m['last_error']?.toString(),
      );
}

class ReviewPhoto {
  final String id;
  final String storagePath;
  final int position;
  const ReviewPhoto({required this.id, required this.storagePath, required this.position});
}

class ReviewQuestion {
  final String key;
  final String label;
  final String answer;
  final bool legible;
  final bool ambiguous;
  final double? confidence;
  final double? aiPoints;
  final double maxPoints;
  final double? finalPoints;
  final List<String> flags;
  final bool needsReview;
  final String? feedback;
  final String? teacherComment;

  const ReviewQuestion({
    required this.key,
    required this.label,
    required this.answer,
    required this.legible,
    required this.ambiguous,
    required this.confidence,
    required this.aiPoints,
    required this.maxPoints,
    required this.finalPoints,
    required this.flags,
    required this.needsReview,
    this.feedback,
    this.teacherComment,
  });

  factory ReviewQuestion.fromMap(Map<String, dynamic> m) => ReviewQuestion(
        key: m['question_key'].toString(),
        label: (m['question_label'] ?? 'Question ${m['question_key']}').toString(),
        answer: (m['student_answer'] ?? '').toString(),
        legible: m['legible'] != false,
        ambiguous: m['ambiguous'] == true,
        confidence: _n(m['confidence']),
        aiPoints: _n(m['ai_points']),
        maxPoints: _n(m['max_points']) ?? 0,
        finalPoints: _n(m['final_points']),
        flags: (m['flags'] is List)
            ? (m['flags'] as List).map((e) => e.toString()).toList(growable: false)
            : const [],
        needsReview: m['needs_review'] == true,
        feedback: m['feedback_fr']?.toString(),
        teacherComment: m['teacher_comment']?.toString(),
      );
}

class SubmissionDetail {
  final String submissionId;
  final String studentName;
  final String evaluationTitle;
  final double maxScore;
  final String latePolicy;
  final bool isLate;
  final int lateMinutes;
  final DateTime? submittedAt;
  final List<ReviewPhoto> photos;
  final List<ReviewQuestion> questions;
  final Map<String, dynamic> score;
  final Map<String, dynamic> correction;
  final List<Map<String, dynamic>> history;

  const SubmissionDetail({
    required this.submissionId,
    required this.studentName,
    required this.evaluationTitle,
    required this.maxScore,
    required this.latePolicy,
    required this.isLate,
    required this.lateMinutes,
    required this.submittedAt,
    required this.photos,
    required this.questions,
    required this.score,
    required this.correction,
    required this.history,
  });

  bool get validated => score['validation_status'] == 'validated';
  String get correctionStatus => (correction['status'] ?? score['correction_status'] ?? '').toString();

  factory SubmissionDetail.fromMap(Map<String, dynamic> m) {
    final sub = _m(m['submission']);
    final student = _m(m['student']);
    final ev = _m(m['evaluation']);
    return SubmissionDetail(
      submissionId: sub['id'].toString(),
      studentName: '${student['last_name'] ?? ''} ${student['first_name'] ?? ''}'.trim(),
      evaluationTitle: (ev['title'] ?? '').toString(),
      maxScore: _n(ev['max_score']) ?? 20,
      latePolicy: (ev['late_policy'] ?? 'reject').toString(),
      isLate: sub['is_late'] == true,
      lateMinutes: _i(sub['late_minutes']),
      submittedAt: _dt(sub['submitted_at']),
      photos: _ml(m['photos'])
          .map((p) => ReviewPhoto(
                id: p['id'].toString(),
                storagePath: p['storage_path'].toString(),
                position: _i(p['position']),
              ))
          .toList(growable: false),
      questions: _ml(m['questions']).map(ReviewQuestion.fromMap).toList(growable: false),
      score: _m(m['score']),
      correction: _m(m['correction']),
      history: _ml(m['history']),
    );
  }
}

class PublicationReport {
  final Map<String, dynamic> raw;
  const PublicationReport(this.raw);

  Map<String, dynamic> get period => _m(raw['period']);
  String get status => (period['publish_status'] ?? 'draft').toString();
  bool get isPublished => period['is_published'] == true;
  DateTime? get publishAt => _dt(period['publish_at']);
  String get policy => (period['unvalidated_policy'] ?? 'block').toString();
  String? get note => period['publish_note']?.toString();
  int get scoresTotal => _i(raw['scores_total']);
  int get validated => _i(raw['scores_validated']);
  int get needsReview => _i(raw['scores_needs_review']);
  int get errors => _i(raw['scores_error']);
  int get pending => _i(raw['scores_pending']);
  int get provisional => _i(raw['scores_provisional']);
  int get gradesCount => _i(raw['grades_count']);
  int get studentsWithGrades => _i(raw['students_with_grades']);
  int get manualConflicts => _i(raw['manual_conflicts']);
  int get syncErrors => _i(raw['sync_errors']);
  int get openScores => _i(raw['open_scores']);
  bool get blocking => raw['blocking'] == true;
  List<String> get classesWithoutGrades => (raw['classes_without_grades'] is List)
      ? (raw['classes_without_grades'] as List).map((e) => e.toString()).toList(growable: false)
      : const [];
}
