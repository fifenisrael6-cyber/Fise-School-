/// Modèles additifs pour les chapitres pédagogiques.
—
/// Ils utilisent les tables Supabase déjà présentes et ne remplacent aucun
/// modèle Course/Lesson existant.
class LearningChapter {
  final String id;
  final String curriculumId;
  final String titleFr;
  final String titleEn;
  final String? descriptionFr;
  final String? descriptionEn;
  final int position;
  final bool isActive;
  final int lessonCount;
  final int videoCount;
  final int pdfCount;
  final int quizCount;
  final int exerciseCount;
  final bool courseRead;
  final int completedExercises;

  const LearningChapter({
    required this.id,
    required this.curriculumId,
    required this.titleFr,
    required this.titleEn,
    this.descriptionFr,
    this.descriptionEn,
    required this.position,
    required this.isActive,
    this.lessonCount = 0,
    this.videoCount = 0,
    this.pdfCount = 0,
    this.quizCount = 0,
    this.exerciseCount = 0,
    this.courseRead = false,
    this.completedExercises = 0,
  });

  String labelFor(String languageCode) {
    final primary = languageCode == 'en' ? titleEn : titleFr;
    final fallback = languageCode == 'en' ? titleFr : titleEn;
    return primary.trim().isNotEmpty ? primary.trim() : fallback.trim();
  }

  factory LearningChapter.fromMap(
    Map<String, dynamic> row, {
    int lessonCount = 0,
    int videoCount = 0,
    int pdfCount = 0,
    int quizCount = 0,
    int exerciseCount = 0,
    bool courseRead = false,
    int completedExercises = 0,
  }) {
    return LearningChapter(
      id: row['id'].toString(),
      curriculumId: row['curriculum_id'].toString(),
      titleFr: row['title_fr']?.toString() ?? '',
      titleEn: row['title_en']?.toString() ?? '',
      descriptionFr: row['description_fr']?.toString(),
      descriptionEn: row['description_en']?.toString(),
      position: (row['position'] as num?)?.toInt() ?? 0,
      isActive: row['is_active'] as bool? ?? true,
      lessonCount: lessonCount,
      videoCount: videoCount,
      pdfCount: pdfCount,
      quizCount: quizCount,
      exerciseCount: exerciseCount,
      courseRead: courseRead,
      completedExercises: completedExercises,
    );
  }
}

class ChapterContentItem {
  final String id;
  final String chapterId;
  final String type;
  final String titleFr;
  final String titleEn;
  final String? bodyTextFr;
  final String? bodyTextEn;
  final String? externalUrl;
  final String? storagePath;
  final int position;
  final bool isPublished;

  const ChapterContentItem({
    required this.id,
    required this.chapterId,
    required this.type,
    required this.titleFr,
    required this.titleEn,
    this.bodyTextFr,
    this.bodyTextEn,
    this.externalUrl,
    this.storagePath,
    required this.position,
    required this.isPublished,
  });

  String labelFor(String languageCode) {
    final primary = languageCode == 'en' ? titleEn : titleFr;
    final fallback = languageCode == 'en' ? titleFr : titleEn;
    return primary.trim().isNotEmpty ? primary.trim() : fallback.trim();
  }

  String? bodyFor(String languageCode) {
    final primary = languageCode == 'en' ? bodyTextEn : bodyTextFr;
    final fallback = languageCode == 'en' ? bodyTextFr : bodyTextEn;
    if (primary != null && primary.trim().isNotEmpty) return primary;
    return fallback;
  }

  factory ChapterContentItem.fromMap(Map<String, dynamic> row) =>
      ChapterContentItem(
        id: row['id'].toString(),
        chapterId: row['chapter_id'].toString(),
        type: row['content_type']?.toString() ?? 'text',
        titleFr: row['title_fr']?.toString() ?? '',
        titleEn: row['title_en']?.toString() ?? '',
        bodyTextFr: row['body_text_fr']?.toString(),
        bodyTextEn: row['body_text_en']?.toString(),
        externalUrl: row['external_url']?.toString(),
        storagePath: row['storage_path']?.toString(),
        position: (row['position'] as num?)?.toInt() ?? 0,
        isPublished: row['is_published'] as bool? ?? false,
      );
}

class ChapterExercise {
  final String id;
  final String chapterId;
  final String statementFr;
  final String statementEn;
  final String difficulty;
  final int position;
  final bool isPublished;
  final bool completed;

  const ChapterExercise({
    required this.id,
    required this.chapterId,
    required this.statementFr,
    required this.statementEn,
    required this.difficulty,
    required this.position,
    required this.isPublished,
    this.completed = false,
  });

  String statementFor(String languageCode) {
    final primary = languageCode == 'en' ? statementEn : statementFr;
    final fallback = languageCode == 'en' ? statementFr : statementEn;
    return primary.trim().isNotEmpty ? primary.trim() : fallback.trim();
  }

  String difficultyFor(String languageCode) {
    switch (difficulty.toLowerCase()) {
      case 'easy':
      case 'facile':
        return languageCode == 'en' ? 'Easy' : 'Facile';
      case 'hard':
      case 'difficile':
        return languageCode == 'en' ? 'Hard' : 'Difficile';
      default:
        return languageCode == 'en' ? 'Medium' : 'Moyen';
    }
  }

  factory ChapterExercise.fromMap(
    Map<String, dynamic> row, {
    bool completed = false,
  }) =>
      ChapterExercise(
        id: row['id'].toString(),
        chapterId: row['chapter_id'].toString(),
        statementFr: row['statement_fr']?.toString() ?? '',
        statementEn: row['statement_en']?.toString() ?? '',
        difficulty: row['difficulty']?.toString() ?? 'medium',
        position: (row['position'] as num?)?.toInt() ?? 0,
        isPublished: row['is_published'] as bool? ?? false,
        completed: completed,
      );
}

class ChapterQuiz {
  final String id;
  final String chapterId;
  final String titleFr;
  final String titleEn;
  final String? descriptionFr;
  final String? descriptionEn;
  final int position;
  final bool isPublished;

  const ChapterQuiz({
    required this.id,
    required this.chapterId,
    required this.titleFr,
    required this.titleEn,
    this.descriptionFr,
    this.descriptionEn,
    required this.position,
    required this.isPublished,
  });

  String labelFor(String languageCode) {
    final primary = languageCode == 'en' ? titleEn : titleFr;
    final fallback = languageCode == 'en' ? titleFr : titleEn;
    return primary.trim().isNotEmpty ? primary.trim() : fallback.trim();
  }

  factory ChapterQuiz.fromMap(Map<String, dynamic> row) => ChapterQuiz(
        id: row['id'].toString(),
        chapterId: row['chapter_id'].toString(),
        titleFr: row['title_fr']?.toString() ?? '',
        titleEn: row['title_en']?.toString() ?? '',
        descriptionFr: row['description_fr']?.toString(),
        descriptionEn: row['description_en']?.toString(),
        position: (row['position'] as num?)?.toInt() ?? 0,
        isPublished: row['is_published'] as bool? ?? false,
      );
}

class ChapterQuizQuestion {
  final String id;
  final String quizId;
  final String promptFr;
  final String promptEn;
  final List<String> optionsFr;
  final List<String> optionsEn;
  final int position;

  const ChapterQuizQuestion({
    required this.id,
    required this.quizId,
    required this.promptFr,
    required this.promptEn,
    required this.optionsFr,
    required this.optionsEn,
    required this.position,
  });

  String promptFor(String languageCode) {
    final primary = languageCode == 'en' ? promptEn : promptFr;
    final fallback = languageCode == 'en' ? promptFr : promptEn;
    return primary.trim().isNotEmpty ? primary.trim() : fallback.trim();
  }

  List<String> optionsFor(String languageCode) =>
      languageCode == 'en' ? optionsEn : optionsFr;

  factory ChapterQuizQuestion.fromMap(Map<String, dynamic> row) {
    List<String> strings(dynamic value) {
      if (value is List) return value.map((e) => e.toString()).toList();
      return const <String>[];
    }

    return ChapterQuizQuestion(
      id: row['id'].toString(),
      quizId: row['quiz_id'].toString(),
      promptFr: row['prompt_fr']?.toString() ?? '',
      promptEn: row['prompt_en']?.toString() ?? '',
      optionsFr: strings(row['options_fr']),
      optionsEn: strings(row['options_en']),
      position: (row['position'] as num?)?.toInt() ?? 0,
    );
  }
}
