/// Modèles des contenus de chapitre Fise School.
///
/// Ces modèles complètent lib/models/pedagogy.dart :
/// Subject, Curriculum, CourseChapter, Course, Lesson et CourseResource
/// restent les modèles de référence du projet existant.
///
/// Les réponses correctes des quiz ne sont volontairement pas modélisées ici,
/// car elles sont conservées dans une table Supabase réservée aux admins.

enum ChapterLearningContentType { course, video, pdf, image, audio }

enum ChapterExerciseDifficulty { easy, medium, hard }

class ChapterLearningContentItem {
  const ChapterLearningContentItem({
    required this.id,
    required this.chapterId,
    required this.type,
    required this.titleFr,
    required this.titleEn,
    required this.position,
    required this.isPublished,
    this.bodyTextFr,
    this.bodyTextEn,
    this.externalUrl,
    this.storagePath,
  });

  final String id;
  final String chapterId;
  final ChapterLearningContentType type;
  final String titleFr;
  final String titleEn;
  final int position;
  final bool isPublished;
  final String? bodyTextFr;
  final String? bodyTextEn;
  final String? externalUrl;
  final String? storagePath;

  String titleFor(String languageCode) =>
      languageCode == 'en' ? titleEn : titleFr;

  String? bodyFor(String languageCode) =>
      languageCode == 'en' ? bodyTextEn : bodyTextFr;

  factory ChapterLearningContentItem.fromMap(
    Map<String, dynamic> map,
  ) {
    final rawType = map['content_type'] as String? ?? 'course';
    final type = switch (rawType) {
      'video' => ChapterLearningContentType.video,
      'pdf' => ChapterLearningContentType.pdf,
      'image' => ChapterLearningContentType.image,
      'audio' => ChapterLearningContentType.audio,
      _ => ChapterLearningContentType.course,
    };

    return ChapterLearningContentItem(
      id: map['id'] as String,
      chapterId: map['chapter_id'] as String,
      type: type,
      titleFr: map['title_fr'] as String? ?? '',
      titleEn: map['title_en'] as String? ?? '',
      position: _asInt(map['position']),
      isPublished: map['is_published'] as bool? ?? false,
      bodyTextFr: map['body_text_fr'] as String?,
      bodyTextEn: map['body_text_en'] as String?,
      externalUrl: map['external_url'] as String?,
      storagePath: map['storage_path'] as String?,
    );
  }
}

class ChapterLearningExercise {
  const ChapterLearningExercise({
    required this.id,
    required this.chapterId,
    required this.statementFr,
    required this.statementEn,
    required this.difficulty,
    required this.position,
    required this.isPublished,
  });

  final String id;
  final String chapterId;
  final String statementFr;
  final String statementEn;
  final ChapterExerciseDifficulty difficulty;
  final int position;
  final bool isPublished;

  String statementFor(String languageCode) =>
      languageCode == 'en' ? statementEn : statementFr;

  String get difficultyLabelFr => switch (difficulty) {
        ChapterExerciseDifficulty.easy => 'Facile',
        ChapterExerciseDifficulty.medium => 'Moyen',
        ChapterExerciseDifficulty.hard => 'Difficile',
      };

  String get difficultyLabelEn => switch (difficulty) {
        ChapterExerciseDifficulty.easy => 'Easy',
        ChapterExerciseDifficulty.medium => 'Medium',
        ChapterExerciseDifficulty.hard => 'Hard',
      };

  factory ChapterLearningExercise.fromMap(
    Map<String, dynamic> map,
  ) {
    final rawDifficulty = map['difficulty'] as String? ?? 'medium';
    final difficulty = switch (rawDifficulty) {
      'easy' => ChapterExerciseDifficulty.easy,
      'hard' => ChapterExerciseDifficulty.hard,
      _ => ChapterExerciseDifficulty.medium,
    };

    return ChapterLearningExercise(
      id: map['id'] as String,
      chapterId: map['chapter_id'] as String,
      statementFr: map['statement_fr'] as String? ?? '',
      statementEn: map['statement_en'] as String? ?? '',
      difficulty: difficulty,
      position: _asInt(map['position']),
      isPublished: map['is_published'] as bool? ?? false,
    );
  }
}

class ChapterLearningQuiz {
  const ChapterLearningQuiz({
    required this.id,
    required this.chapterId,
    required this.titleFr,
    required this.titleEn,
    required this.position,
    required this.isPublished,
    this.descriptionFr,
    this.descriptionEn,
    this.questionCount = 0,
  });

  final String id;
  final String chapterId;
  final String titleFr;
  final String titleEn;
  final String? descriptionFr;
  final String? descriptionEn;
  final int position;
  final bool isPublished;

  /// Calculé par la requête qui charge le quiz, pas stocké en dur.
  final int questionCount;

  String titleFor(String languageCode) =>
      languageCode == 'en' ? titleEn : titleFr;

  String? descriptionFor(String languageCode) =>
      languageCode == 'en' ? descriptionEn : descriptionFr;

  factory ChapterLearningQuiz.fromMap(
    Map<String, dynamic> map, {
    int questionCount = 0,
  }) {
    return ChapterLearningQuiz(
      id: map['id'] as String,
      chapterId: map['chapter_id'] as String,
      titleFr: map['title_fr'] as String? ?? '',
      titleEn: map['title_en'] as String? ?? '',
      descriptionFr: map['description_fr'] as String?,
      descriptionEn: map['description_en'] as String?,
      position: _asInt(map['position']),
      isPublished: map['is_published'] as bool? ?? false,
      questionCount: questionCount,
    );
  }
}

class ChapterLearningQuizQuestion {
  const ChapterLearningQuizQuestion({
    required this.id,
    required this.quizId,
    required this.promptFr,
    required this.promptEn,
    required this.optionsFr,
    required this.optionsEn,
    required this.position,
  });

  final String id;
  final String quizId;
  final String promptFr;
  final String promptEn;
  final List<String> optionsFr;
  final List<String> optionsEn;
  final int position;

  String promptFor(String languageCode) =>
      languageCode == 'en' ? promptEn : promptFr;

  List<String> optionsFor(String languageCode) =>
      languageCode == 'en' ? optionsEn : optionsFr;

  factory ChapterLearningQuizQuestion.fromMap(
    Map<String, dynamic> map,
  ) {
    return ChapterLearningQuizQuestion(
      id: map['id'] as String,
      quizId: map['quiz_id'] as String,
      promptFr: map['prompt_fr'] as String? ?? '',
      promptEn: map['prompt_en'] as String? ?? '',
      optionsFr: _stringList(map['options_fr']),
      optionsEn: _stringList(map['options_en']),
      position: _asInt(map['position']),
    );
  }
}

class ChapterLearningProgress {
  const ChapterLearningProgress({
    required this.id,
    required this.studentId,
    required this.chapterId,
    required this.courseRead,
    this.courseReadAt,
    this.lastOpenedAt,
    this.updatedAt,
  });

  final String id;
  final String studentId;
  final String chapterId;
  final bool courseRead;
  final DateTime? courseReadAt;
  final DateTime? lastOpenedAt;
  final DateTime? updatedAt;

  factory ChapterLearningProgress.fromMap(
    Map<String, dynamic> map,
  ) {
    return ChapterLearningProgress(
      id: map['id'] as String,
      studentId: map['student_id'] as String,
      chapterId: map['chapter_id'] as String,
      courseRead: map['course_read'] as bool? ?? false,
      courseReadAt: _asDate(map['course_read_at']),
      lastOpenedAt: _asDate(map['last_opened_at']),
      updatedAt: _asDate(map['updated_at']),
    );
  }
}

class ChapterExerciseProgress {
  const ChapterExerciseProgress({
    required this.id,
    required this.studentId,
    required this.exerciseId,
    required this.completed,
    this.completedAt,
    this.updatedAt,
  });

  final String id;
  final String studentId;
  final String exerciseId;
  final bool completed;
  final DateTime? completedAt;
  final DateTime? updatedAt;

  factory ChapterExerciseProgress.fromMap(
    Map<String, dynamic> map,
  ) {
    return ChapterExerciseProgress(
      id: map['id'] as String,
      studentId: map['student_id'] as String,
      exerciseId: map['exercise_id'] as String,
      completed: map['completed'] as bool? ?? false,
      completedAt: _asDate(map['completed_at']),
      updatedAt: _asDate(map['updated_at']),
    );
  }
}

class ChapterQuizAttempt {
  const ChapterQuizAttempt({
    required this.id,
    required this.studentId,
    required this.quizId,
    required this.attemptNumber,
    required this.answers,
    required this.submittedAt,
    this.score,
    this.corrections,
  });

  final String id;
  final String studentId;
  final String quizId;
  final int attemptNumber;
  final int? score;
  final Map<String, dynamic> answers;
  final Map<String, dynamic>? corrections;
  final DateTime submittedAt;

  factory ChapterQuizAttempt.fromMap(
    Map<String, dynamic> map,
  ) {
    return ChapterQuizAttempt(
      id: map['id'] as String,
      studentId: map['student_id'] as String,
      quizId: map['quiz_id'] as String,
      attemptNumber: _asInt(map['attempt_no'], fallback: 1),
      score: map['score'] == null ? null : _asInt(map['score']),
      answers: _stringMap(map['answers']),
      corrections: map['corrections'] == null
          ? null
          : _stringMap(map['corrections']),
      submittedAt: _asDate(map['submitted_at']) ?? DateTime.now(),
    );
  }
}

int _asInt(Object? value, {int fallback = 0}) =>
    value is num ? value.toInt() : fallback;

DateTime? _asDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value.map((item) => item.toString()).toList(growable: false);
}

Map<String, dynamic> _stringMap(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return <String, dynamic>{};
}
