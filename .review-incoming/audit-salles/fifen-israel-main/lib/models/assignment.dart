import 'dart:ui';

class Assignment {
  final String id;
  final String? courseId;
  final String? subjectId;
  final String? lessonId;
  final String teacherId;
  final String classId;
  final String titleFr;
  final String titleEn;
  final String? instructionsFr;
  final String? instructionsEn;
  final DateTime? dueAt;
  final String status;
  final double maxScore;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? publishedAt;

  const Assignment({
    required this.id,
    this.courseId,
    this.subjectId,
    this.lessonId,
    required this.teacherId,
    required this.classId,
    required this.titleFr,
    required this.titleEn,
    this.instructionsFr,
    this.instructionsEn,
    this.dueAt,
    required this.status,
    required this.maxScore,
    this.createdAt,
    this.updatedAt,
    this.publishedAt,
  });

  factory Assignment.fromMap(Map<String, dynamic> map) {
    return Assignment(
      id: map['id'] as String,
      courseId: map['course_id'] as String?,
      subjectId: map['subject_id'] as String?,
      lessonId: map['lesson_id'] as String?,
      teacherId: map['teacher_id'] as String,
      classId: map['class_id'] as String,
      titleFr: map['title_fr'] as String? ?? '',
      titleEn: map['title_en'] as String? ?? '',
      instructionsFr: map['instructions_fr'] as String?,
      instructionsEn: map['instructions_en'] as String?,
      dueAt: _parseDate(map['due_at']),
      status: map['status'] as String? ?? 'draft',
      maxScore: _parseDouble(map['max_score'], fallback: 20),
      createdAt: _parseDate(map['created_at']),
      updatedAt: _parseDate(map['updated_at']),
      publishedAt: _parseDate(map['published_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'course_id': courseId,
      'subject_id': subjectId,
      'lesson_id': lessonId,
      'teacher_id': teacherId,
      'class_id': classId,
      'title_fr': titleFr,
      'title_en': titleEn,
      'instructions_fr': instructionsFr,
      'instructions_en': instructionsEn,
      'due_at': dueAt?.toIso8601String(),
      'status': status,
      'max_score': maxScore,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'published_at': publishedAt?.toIso8601String(),
    };
  }

  String titleFor(Locale locale) {
    return locale.languageCode == 'en' ? titleEn : titleFr;
  }

  String? instructionsFor(Locale locale) {
    return locale.languageCode == 'en' ? instructionsEn : instructionsFr;
  }

  Assignment copyWith({
    String? id,
    String? courseId,
    String? subjectId,
    String? lessonId,
    String? teacherId,
    String? classId,
    String? titleFr,
    String? titleEn,
    String? instructionsFr,
    String? instructionsEn,
    DateTime? dueAt,
    String? status,
    double? maxScore,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? publishedAt,
  }) {
    return Assignment(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      subjectId: subjectId ?? this.subjectId,
      lessonId: lessonId ?? this.lessonId,
      teacherId: teacherId ?? this.teacherId,
      classId: classId ?? this.classId,
      titleFr: titleFr ?? this.titleFr,
      titleEn: titleEn ?? this.titleEn,
      instructionsFr: instructionsFr ?? this.instructionsFr,
      instructionsEn: instructionsEn ?? this.instructionsEn,
      dueAt: dueAt ?? this.dueAt,
      status: status ?? this.status,
      maxScore: maxScore ?? this.maxScore,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      publishedAt: publishedAt ?? this.publishedAt,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }

    return null;
  }

  static double _parseDouble(dynamic value, {required double fallback}) {
    if (value == null) {
      return fallback;
    }

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value) ?? fallback;
    }

    return fallback;
  }
}

class AssignmentQuestion {
  final String id;
  final String assignmentId;
  final int position;
  final String questionFr;
  final String questionEn;
  final String questionType;
  final double points;
  final List<String> options;
  final String? correctAnswer;
  final DateTime? createdAt;

  const AssignmentQuestion({
    required this.id,
    required this.assignmentId,
    required this.position,
    required this.questionFr,
    required this.questionEn,
    required this.questionType,
    required this.points,
    this.options = const [],
    this.correctAnswer,
    this.createdAt,
  });

  factory AssignmentQuestion.fromMap(Map<String, dynamic> map) {
    return AssignmentQuestion(
      id: map['id'] as String,
      assignmentId: map['assignment_id'] as String,
      position: _parseInt(map['position'], fallback: 1),
      questionFr: map['question_fr'] as String? ?? '',
      questionEn: map['question_en'] as String? ?? '',
      questionType: map['question_type'] as String? ?? 'text',
      points: _parseDouble(map['points'], fallback: 1),
      options: _parseOptions(map['options']),
      correctAnswer: map['correct_answer'] as String?,
      createdAt: _parseDate(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'assignment_id': assignmentId,
      'position': position,
      'question_fr': questionFr,
      'question_en': questionEn,
      'question_type': questionType,
      'points': points,
      'options': options,
      'correct_answer': correctAnswer,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  String questionFor(Locale locale) {
    return locale.languageCode == 'en' ? questionEn : questionFr;
  }

  bool get isQcm => questionType == 'qcm';

  bool get isTrueFalse => questionType == 'true_false';

  bool get isText => questionType == 'text';

  bool get isShortAnswer => questionType == 'short_answer';

  AssignmentQuestion copyWith({
    String? id,
    String? assignmentId,
    int? position,
    String? questionFr,
    String? questionEn,
    String? questionType,
    double? points,
    List<String>? options,
    String? correctAnswer,
    DateTime? createdAt,
  }) {
    return AssignmentQuestion(
      id: id ?? this.id,
      assignmentId: assignmentId ?? this.assignmentId,
      position: position ?? this.position,
      questionFr: questionFr ?? this.questionFr,
      questionEn: questionEn ?? this.questionEn,
      questionType: questionType ?? this.questionType,
      points: points ?? this.points,
      options: options ?? this.options,
      correctAnswer: correctAnswer ?? this.correctAnswer,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static List<String> _parseOptions(dynamic value) {
    if (value == null) {
      return const [];
    }

    if (value is List) {
      return value
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false);
    }

    return const [];
  }

  static int _parseInt(dynamic value, {required int fallback}) {
    if (value == null) {
      return fallback;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }

    return fallback;
  }

  static double _parseDouble(dynamic value, {required double fallback}) {
    if (value == null) {
      return fallback;
    }

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value) ?? fallback;
    }

    return fallback;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }

    return null;
  }
}

class AssignmentSubmission {
  final String id;
  final String assignmentId;
  final String studentId;
  final String status;
  final double? score;
  final DateTime? submittedAt;
  final DateTime? correctedAt;
  final String? teacherFeedbackFr;
  final String? teacherFeedbackEn;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AssignmentSubmission({
    required this.id,
    required this.assignmentId,
    required this.studentId,
    required this.status,
    this.score,
    this.submittedAt,
    this.correctedAt,
    this.teacherFeedbackFr,
    this.teacherFeedbackEn,
    this.createdAt,
    this.updatedAt,
  });

  factory AssignmentSubmission.fromMap(Map<String, dynamic> map) {
    return AssignmentSubmission(
      id: map['id'] as String,
      assignmentId: map['assignment_id'] as String,
      studentId: map['student_id'] as String,
      status: map['status'] as String? ?? 'draft',
      score: _parseNullableDouble(map['score']),
      submittedAt: _parseDate(map['submitted_at']),
      correctedAt: _parseDate(map['corrected_at']),
      teacherFeedbackFr: map['teacher_feedback_fr'] as String?,
      teacherFeedbackEn: map['teacher_feedback_en'] as String?,
      createdAt: _parseDate(map['created_at']),
      updatedAt: _parseDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'assignment_id': assignmentId,
      'student_id': studentId,
      'status': status,
      'score': score,
      'submitted_at': submittedAt?.toIso8601String(),
      'corrected_at': correctedAt?.toIso8601String(),
      'teacher_feedback_fr': teacherFeedbackFr,
      'teacher_feedback_en': teacherFeedbackEn,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  String? feedbackFor(Locale locale) {
    return locale.languageCode == 'en' ? teacherFeedbackEn : teacherFeedbackFr;
  }

  bool get isDraft => status == 'draft';

  bool get isSubmitted => status == 'submitted';

  bool get isCorrected => status == 'corrected';

  AssignmentSubmission copyWith({
    String? id,
    String? assignmentId,
    String? studentId,
    String? status,
    double? score,
    DateTime? submittedAt,
    DateTime? correctedAt,
    String? teacherFeedbackFr,
    String? teacherFeedbackEn,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AssignmentSubmission(
      id: id ?? this.id,
      assignmentId: assignmentId ?? this.assignmentId,
      studentId: studentId ?? this.studentId,
      status: status ?? this.status,
      score: score ?? this.score,
      submittedAt: submittedAt ?? this.submittedAt,
      correctedAt: correctedAt ?? this.correctedAt,
      teacherFeedbackFr: teacherFeedbackFr ?? this.teacherFeedbackFr,
      teacherFeedbackEn: teacherFeedbackEn ?? this.teacherFeedbackEn,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static double? _parseNullableDouble(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value);
    }

    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }

    return null;
  }
}

class AssignmentAnswer {
  final String id;
  final String submissionId;
  final String questionId;
  final String? answerText;
  final String? selectedOption;
  final bool? isCorrect;
  final double? pointsAwarded;
  final String? teacherFeedbackFr;
  final String? teacherFeedbackEn;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AssignmentAnswer({
    required this.id,
    required this.submissionId,
    required this.questionId,
    this.answerText,
    this.selectedOption,
    this.isCorrect,
    this.pointsAwarded,
    this.teacherFeedbackFr,
    this.teacherFeedbackEn,
    this.createdAt,
    this.updatedAt,
  });

  factory AssignmentAnswer.fromMap(Map<String, dynamic> map) {
    return AssignmentAnswer(
      id: map['id'] as String,
      submissionId: map['submission_id'] as String,
      questionId: map['question_id'] as String,
      answerText: map['answer_text'] as String?,
      selectedOption: map['selected_option'] as String?,
      isCorrect: map['is_correct'] as bool?,
      pointsAwarded: _parseNullableDouble(map['points_awarded']),
      teacherFeedbackFr: map['teacher_feedback_fr'] as String?,
      teacherFeedbackEn: map['teacher_feedback_en'] as String?,
      createdAt: _parseDate(map['created_at']),
      updatedAt: _parseDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'submission_id': submissionId,
      'question_id': questionId,
      'answer_text': answerText,
      'selected_option': selectedOption,
      'is_correct': isCorrect,
      'points_awarded': pointsAwarded,
      'teacher_feedback_fr': teacherFeedbackFr,
      'teacher_feedback_en': teacherFeedbackEn,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  String? feedbackFor(Locale locale) {
    return locale.languageCode == 'en' ? teacherFeedbackEn : teacherFeedbackFr;
  }

  AssignmentAnswer copyWith({
    String? id,
    String? submissionId,
    String? questionId,
    String? answerText,
    String? selectedOption,
    bool? isCorrect,
    double? pointsAwarded,
    String? teacherFeedbackFr,
    String? teacherFeedbackEn,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AssignmentAnswer(
      id: id ?? this.id,
      submissionId: submissionId ?? this.submissionId,
      questionId: questionId ?? this.questionId,
      answerText: answerText ?? this.answerText,
      selectedOption: selectedOption ?? this.selectedOption,
      isCorrect: isCorrect ?? this.isCorrect,
      pointsAwarded: pointsAwarded ?? this.pointsAwarded,
      teacherFeedbackFr: teacherFeedbackFr ?? this.teacherFeedbackFr,
      teacherFeedbackEn: teacherFeedbackEn ?? this.teacherFeedbackEn,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static double? _parseNullableDouble(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value);
    }

    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }

    return null;
  }
}
