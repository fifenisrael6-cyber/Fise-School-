class SmartQuestion {
  final String id;
  final String question;
  final List<String> choices;

  const SmartQuestion({
    required this.id,
    required this.question,
    required this.choices,
  });

  factory SmartQuestion.fromMap(Map<String, dynamic> map) => SmartQuestion(
        id: map['id']?.toString() ?? '',
        question: map['question']?.toString() ?? '',
        choices: (map['choices'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(growable: false),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'question': question,
        'choices': choices,
      };
}

class SmartLesson {
  final String id;
  final String chunkId;
  final String language;
  final String text;
  final DateTime? generatedAt;
  final List<SmartQuestion> questions;
  final String? subjectId;
  final String? courseId;
  final bool cached;

  const SmartLesson({
    required this.id,
    required this.chunkId,
    required this.language,
    required this.text,
    required this.questions,
    this.generatedAt,
    this.subjectId,
    this.courseId,
    this.cached = false,
  });

  factory SmartLesson.fromEdge(Map<String, dynamic> map) {
    final lesson = Map<String, dynamic>.from(
      (map['lesson'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    final rawQuestions = (map['questions'] as List?) ?? const [];
    return SmartLesson(
      id: lesson['id']?.toString() ?? '',
      chunkId: lesson['chunk_id']?.toString() ?? map['chunk_id']?.toString() ?? '',
      language: lesson['language']?.toString() ?? 'fr',
      text: lesson['text']?.toString() ?? '',
      generatedAt: lesson['generated_at'] is String
          ? DateTime.tryParse(lesson['generated_at'] as String)
          : null,
      questions: rawQuestions
          .map((item) => SmartQuestion.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList(growable: false),
      subjectId: map['subject_id']?.toString(),
      courseId: map['course_id']?.toString(),
      cached: map['cached'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'lesson': {
          'id': id,
          'chunk_id': chunkId,
          'language': language,
          'text': text,
          'generated_at': generatedAt?.toIso8601String(),
        },
        'questions': questions.map((q) => q.toMap()).toList(growable: false),
        'subject_id': subjectId,
        'course_id': courseId,
        'chunk_id': chunkId,
        'cached': cached,
      };

  factory SmartLesson.fromJson(Map<String, dynamic> json) =>
      SmartLesson.fromEdge(json);
}

class SmartExerciseResult {
  final int score;
  final bool passed;
  final int attempt;
  final List<Map<String, dynamic>> correction;
  final String? nextChunkId;
  final int minimumScore;

  const SmartExerciseResult({
    required this.score,
    required this.passed,
    required this.attempt,
    required this.correction,
    required this.nextChunkId,
    required this.minimumScore,
  });

  factory SmartExerciseResult.fromMap(Map<String, dynamic> map) =>
      SmartExerciseResult(
        score: (map['score'] as num?)?.toInt() ?? 0,
        passed: map['passed'] == true,
        attempt: (map['attempt'] as num?)?.toInt() ?? 1,
        correction: ((map['correction'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        nextChunkId: map['next_chunk_id']?.toString(),
        minimumScore: (map['minimum_score'] as num?)?.toInt() ?? 50,
      );
}

class ClassProgressSummary {
  final int classSize;
  final bool comparisonAvailable;
  final double ownAverageScore;
  final double classAverageScore;
  final int? topPercent;
  final List<Map<String, dynamic>> subjects;

  const ClassProgressSummary({
    required this.classSize,
    required this.comparisonAvailable,
    required this.ownAverageScore,
    required this.classAverageScore,
    required this.topPercent,
    required this.subjects,
  });

  factory ClassProgressSummary.fromMap(Map<String, dynamic> map) =>
      ClassProgressSummary(
        classSize: (map['class_size'] as num?)?.toInt() ?? 0,
        comparisonAvailable: map['comparison_available'] == true,
        ownAverageScore: (map['own_average_score'] as num?)?.toDouble() ?? 0,
        classAverageScore:
            (map['class_average_score'] as num?)?.toDouble() ?? 0,
        topPercent: (map['top_percent'] as num?)?.toInt(),
        subjects: ((map['subjects'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
      );
}
