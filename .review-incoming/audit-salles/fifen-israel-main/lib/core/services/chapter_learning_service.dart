import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../offline/app_database.dart';

import '../../models/chapter_learning_content.dart';
import '../../models/pedagogy.dart';
import '../../models/user_profile.dart';

class ChapterLearningCounts {
  const ChapterLearningCounts({
    this.lessons = 0,
    this.videos = 0,
    this.pdfs = 0,
    this.images = 0,
    this.audios = 0,
    this.quizzes = 0,
    this.exercises = 0,
  });

  final int lessons;
  final int videos;
  final int pdfs;
  final int images;
  final int audios;
  final int quizzes;
  final int exercises;

  int get total => lessons + videos + pdfs + images + audios + quizzes + exercises;
}

class ChapterExerciseCorrection {
  const ChapterExerciseCorrection({
    required this.correctionFr,
    required this.correctionEn,
    this.explanationFr,
    this.explanationEn,
  });

  final String correctionFr;
  final String correctionEn;
  final String? explanationFr;
  final String? explanationEn;

  factory ChapterExerciseCorrection.fromMap(Map<String, dynamic> map) {
    return ChapterExerciseCorrection(
      correctionFr: map['correction_fr'] as String? ?? '',
      correctionEn: map['correction_en'] as String? ?? '',
      explanationFr: map['explanation_fr'] as String?,
      explanationEn: map['explanation_en'] as String?,
    );
  }

  String correctionFor(String languageCode) =>
      languageCode == 'en' ? correctionEn : correctionFr;

  String? explanationFor(String languageCode) =>
      languageCode == 'en' ? explanationEn : explanationFr;
}

/// Accès aux contenus de chapitre publiés. Les contrôles d'accès réels sont
/// appliqués par les politiques RLS Supabase, pas seulement par l'interface.
class ChapterLearningService {
  static final Map<String, DateTime> _lastCacheRefresh = <String, DateTime>{};

  final SupabaseClient _client;
  final AppDatabase _database;

  ChapterLearningService({SupabaseClient? client, AppDatabase? database})
      : _client = client ?? Supabase.instance.client,
        _database = database ?? AppDatabase();

  String get _cacheUserId => _client.auth.currentUser?.id ?? 'offline-guest';

  Future<List<Map<String, dynamic>>> _cachedRows(
    String cacheKey,
    Future<List<Map<String, dynamic>>> Function() fetch,
  ) async {
    // Keep the cache owner fixed for the whole operation so a background
    // refresh cannot write one account's data into another account's cache.
    final userId = _cacheUserId;
    final cachedJson = await _database.getOfflineCatalogCache(userId, cacheKey);
    if (cachedJson != null) {
      try {
        final decoded = jsonDecode(cachedJson) as List<dynamic>;
        final cached = decoded
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(growable: false);
        final refreshKey = '$userId:$cacheKey';
        final lastRefresh = _lastCacheRefresh[refreshKey];
        if (lastRefresh == null ||
            DateTime.now().difference(lastRefresh) > const Duration(minutes: 2)) {
          _lastCacheRefresh[refreshKey] = DateTime.now();
          unawaited(_refreshRows(userId, cacheKey, fetch));
        }
        return cached;
      } catch (_) {
        // Ignore a malformed cache and rebuild it from the server.
      }
    }
    try {
      final rows = await fetch().timeout(const Duration(seconds: 5));
      await _database.saveOfflineCatalogCache(userId, cacheKey, jsonEncode(rows));
      return rows;
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> _refreshRows(
    String userId,
    String cacheKey,
    Future<List<Map<String, dynamic>>> Function() fetch,
  ) async {
    try {
      final rows = await fetch().timeout(const Duration(seconds: 5));
      await _database.saveOfflineCatalogCache(userId, cacheKey, jsonEncode(rows));
    } catch (_) {
      // Keep the last successful local copy when offline.
    }
  }

  /// Loads this chapter's own content plus media from genuinely equivalent
  /// chapters in another stream. RLS independently verifies each source chapter.
  Future<List<Map<String, dynamic>>> _contentRowsForChapter(String chapterId) =>
      _cachedRows('chapter-content:$chapterId', () => _fetchContentRowsForChapter(chapterId));

  Future<List<Map<String, dynamic>>> _fetchContentRowsForChapter(
    String chapterId,
  ) async {
    final currentRows = await _client
        .from('course_chapters')
        .select('id,title_fr,title_en,position')
        .eq('id', chapterId)
        .eq('is_active', true)
        .limit(1);
    if (currentRows.isEmpty) return const <Map<String, dynamic>>[];

    final current = Map<String, dynamic>.from(currentRows.first);
    final chapterRows = await _client
        .from('course_chapters')
        .select('id,title_fr,title_en,position')
        .eq('position', current['position'])
        .eq('is_active', true);

    final titleFr = (current['title_fr']?.toString() ?? '').trim().toLowerCase();
    final titleEn = (current['title_en']?.toString() ?? '').trim().toLowerCase();
    final chapterIds = chapterRows
        .where((raw) {
          final row = Map<String, dynamic>.from(raw);
          return (row['title_fr']?.toString() ?? '').trim().toLowerCase() == titleFr &&
              (row['title_en']?.toString() ?? '').trim().toLowerCase() == titleEn;
        })
        .map((row) => row['id'].toString())
        .toSet()
        .toList(growable: true);
    if (!chapterIds.contains(chapterId)) chapterIds.add(chapterId);

    final rows = await _client
        .from('chapter_content_items')
        .select()
        .inFilter('chapter_id', chapterIds)
        .eq('is_published', true)
        .order('position');

    return rows
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) =>
            row['chapter_id'] == chapterId ||
            const ['video', 'pdf', 'image', 'audio'].contains(row['content_type']))
        .toList(growable: false);
  }

  Future<List<ChapterLearningContentItem>> listContent(String chapterId) async {
    final rows = await _contentRowsForChapter(chapterId);
    return rows
        .map(ChapterLearningContentItem.fromMap)
        .toList(growable: false);
  }

  Future<List<ChapterLearningExercise>> listExercises(String chapterId) async {
    final rows = await _cachedRows('chapter-exercises:$chapterId', () async {
      final result = await _client
          .from('chapter_exercises')
          .select()
          .eq('chapter_id', chapterId)
          .eq('is_published', true)
          .order('position');
      return result.map((row) => Map<String, dynamic>.from(row)).toList();
    });
    return rows.map(ChapterLearningExercise.fromMap).toList(growable: false);
  }

  Future<List<ChapterLearningQuiz>> listQuizzes(String chapterId) async {
    final rows = await _cachedRows('chapter-quizzes:$chapterId', () async {
      final result = await _client
          .from('chapter_quizzes')
          .select()
          .eq('chapter_id', chapterId)
          .eq('is_published', true)
          .isFilter('created_by', null)
          .order('position');
      final maps = result.map((row) => Map<String, dynamic>.from(row)).toList();
      return Future.wait(maps.map((map) async {
        final quizId = map['id'].toString();
        final questions = await _client
            .from('chapter_quiz_questions')
            .select()
            .eq('quiz_id', quizId)
            .order('position');
        final questionMaps = questions
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
        await _database.saveOfflineCatalogCache(
          _cacheUserId,
          'chapter-quiz-questions:$quizId',
          jsonEncode(questionMaps),
        );
        return <String, dynamic>{...map, 'question_count': questions.length};
      }));
    });
    return rows
        .map((map) => ChapterLearningQuiz.fromMap(
              map,
              questionCount: (map['question_count'] as num?)?.toInt() ?? 0,
            ))
        .toList(growable: false);
  }

  Future<List<ChapterLearningQuizQuestion>> listQuizQuestions(String quizId) async {
    final rows = await _cachedRows('chapter-quiz-questions:$quizId', () async {
      final result = await _client
          .from('chapter_quiz_questions')
          .select()
          .eq('quiz_id', quizId)
          .order('position');
      return result.map((row) => Map<String, dynamic>.from(row)).toList();
    });
    return rows.map(ChapterLearningQuizQuestion.fromMap).toList(growable: false);
  }

  /// Le serveur vérifie les réponses à partir de la table privée des clés.
  Future<Map<String, dynamic>> submitQuiz({
    required String quizId,
    required Map<String, int> answers,
  }) async {
    final result = await _client.rpc(
      'submit_chapter_quiz',
      params: {
        'p_quiz_id': quizId,
        'p_answers': answers.map((key, value) => MapEntry(key, value)),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<ChapterLearningCounts> getCounts(String chapterId) async {
    final results = await Future.wait<dynamic>([
      listContent(chapterId),
      listExercises(chapterId),
      _cachedRows('chapter-count-quizzes:$chapterId', () async {
        final rows = await _client
            .from('chapter_quizzes')
            .select('id')
            .eq('chapter_id', chapterId)
            .eq('is_published', true);
        return rows.map((row) => Map<String, dynamic>.from(row)).toList();
      }),
    ]);
    final content = results[0] as List<ChapterLearningContentItem>;
    final exercises = results[1] as List<ChapterLearningExercise>;
    final quizRows = results[2] as List<Map<String, dynamic>>;
    return ChapterLearningCounts(
      lessons: content.where((item) => item.type == ChapterLearningContentType.course).length,
      videos: content.where((item) => item.type == ChapterLearningContentType.video).length,
      pdfs: content.where((item) => item.type == ChapterLearningContentType.pdf).length,
      images: content.where((item) => item.type == ChapterLearningContentType.image).length,
      audios: content.where((item) => item.type == ChapterLearningContentType.audio).length,
      exercises: exercises.length,
      quizzes: quizRows.length,
    );
  }

  Future<ChapterLearningProgress?> getProgress({
    required String studentId,
    required String chapterId,
  }) async {
    final rows = await _cachedRows('chapter-progress:$studentId:$chapterId', () async {
      final result = await _client
          .from('chapter_learning_progress')
          .select()
          .eq('student_id', studentId)
          .eq('chapter_id', chapterId)
          .limit(1);
      return result.map((row) => Map<String, dynamic>.from(row)).toList();
    });
    if (rows.isEmpty) return null;
    return ChapterLearningProgress.fromMap(rows.first);
  }

  Future<void> markCourseRead({
    required String studentId,
    required String chapterId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('chapter_learning_progress').upsert({
      'student_id': studentId,
      'chapter_id': chapterId,
      'course_read': true,
      'course_read_at': now,
      'last_opened_at': now,
      'updated_at': now,
    }, onConflict: 'student_id,chapter_id');
  }

  Future<Set<String>> completedExerciseIds({
    required String studentId,
    required List<String> exerciseIds,
  }) async {
    if (exerciseIds.isEmpty) return <String>{};
    final ids = exerciseIds.toList()..sort();
    final rows = await _cachedRows('completed-exercises:$studentId:${ids.join(',')}', () async {
      final result = await _client
          .from('chapter_exercise_progress')
          .select('exercise_id')
          .eq('student_id', studentId)
          .eq('completed', true)
          .inFilter('exercise_id', exerciseIds);
      return result.map((row) => Map<String, dynamic>.from(row)).toList();
    });
    return rows.map((row) => row['exercise_id'].toString()).toSet();
  }

  Future<void> markExerciseCompleted({
    required String studentId,
    required String exerciseId,
    required bool completed,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('chapter_exercise_progress').upsert({
      'student_id': studentId,
      'exercise_id': exerciseId,
      'completed': completed,
      'completed_at': completed ? now : null,
      'updated_at': now,
    }, onConflict: 'student_id,exercise_id');
  }

  Future<ChapterExerciseCorrection?> getExerciseCorrection(
    String exerciseId,
  ) async {
    final rows = await _client.rpc(
      'get_chapter_exercise_correction',
      params: {'p_exercise_id': exerciseId},
    ) as List;
    if (rows.isEmpty) return null;
    return ChapterExerciseCorrection.fromMap(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  Future<int> countPublishedLessonsForSubject(String subjectId) async {
    final curricula = await _client
        .from('curricula')
        .select('id')
        .eq('subject_id', subjectId)
        .eq('is_active', true);
    if (curricula.isEmpty) return 0;

    final curriculumIds = curricula.map((row) => row['id'] as String).toList();
    final chapters = await _client
        .from('course_chapters')
        .select('id')
        .inFilter('curriculum_id', curriculumIds)
        .eq('is_active', true);
    if (chapters.isEmpty) return 0;

    final chapterIds = chapters.map((row) => row['id'] as String).toList();
    final content = await _client
        .from('chapter_content_items')
        .select('id')
        .inFilter('chapter_id', chapterIds)
        .eq('content_type', 'course')
        .eq('is_published', true);
    return content.length;
  }

  Future<List<Curriculum>> listCurricula(
    String subjectId, {
    UserProfile? profile,
  }) async {
    final profileKey = profile?.id ?? _cacheUserId;
    final rows = await _cachedRows(
      'curricula:$profileKey:$subjectId',
      () => _fetchCurriculumRows(subjectId, profile: profile),
    );
    return rows.map(Curriculum.fromMap).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _fetchCurriculumRows(
    String subjectId, {
    UserProfile? profile,
  }) async {
    final rows = await _client
        .from('curricula')
        .select()
        .eq('subject_id', subjectId)
        .eq('is_active', true)
        .order('title_fr');

    var filtered = rows.map((row) => Map<String, dynamic>.from(row)).toList();

    // Student view: only show programmes matching an active class membership
    // and the subject assigned to that class. RLS remains the final authority.
    if (profile != null) {
      final memberships = await _client
          .from('class_students')
          .select('class_id')
          .eq('student_id', profile.id)
          .eq('is_active', true);
      final memberClassIds = memberships
          .map((row) => row['class_id'])
          .whereType<String>()
          .toSet()
          .toList(growable: false);
      if (memberClassIds.isEmpty) return const <Map<String, dynamic>>[];

      final assignedRows = await _client
          .from('class_subjects')
          .select('class_id')
          .eq('subject_id', subjectId)
          .eq('is_active', true)
          .inFilter('class_id', memberClassIds);
      final assignedClassIds = assignedRows
          .map((row) => row['class_id'])
          .whereType<String>()
          .toSet()
          .toList(growable: false);
      if (assignedClassIds.isEmpty) return const <Map<String, dynamic>>[];

      final classRows = await _client
          .from('school_classes')
          .select('id,subsystem,sector,exam_level_id,series_id,specialty_id')
          .inFilter('id', assignedClassIds)
          .eq('is_active', true);
      final activeClasses =
          classRows.map((row) => Map<String, dynamic>.from(row)).toList();

      filtered = filtered.where((curriculum) {
        return activeClasses.any((schoolClass) =>
            curriculum['subsystem'] == schoolClass['subsystem'] &&
            curriculum['sector'] == schoolClass['sector'] &&
            (curriculum['exam_level_id'] == null ||
                curriculum['exam_level_id'] == schoolClass['exam_level_id']) &&
            (curriculum['series_id'] == null ||
                curriculum['series_id'] == schoolClass['series_id']) &&
            (curriculum['specialty_id'] == null ||
                curriculum['specialty_id'] == schoolClass['specialty_id']));
      }).toList(growable: false);
    }

    return filtered;
  }

  Future<List<CourseChapter>> listChapters(String curriculumId) async {
    final rows = await _cachedRows('chapters:$curriculumId', () async {
      final result = await _client
          .from('course_chapters')
          .select()
          .eq('curriculum_id', curriculumId)
          .eq('is_active', true)
          .order('position');
      return result.map((row) => Map<String, dynamic>.from(row)).toList();
    });
    return rows.map(CourseChapter.fromMap).toList(growable: false);
  }
}
