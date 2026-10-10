import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/chapter_learning.dart';
import '../../models/user_profile.dart';

/// Accès Supabase au nouveau parcours Chapitre > Cours > Quiz > Exercices.
/// Les autorisations effectives restent celles des politiques RLS de Supabase.
class ChapterLearningService {
  ChapterLearningService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const String storageBucket = 'chapter-content';

  String _clean(String? value) => (value ?? '').trim().toLowerCase();

  /// Renvoie les chapitres publiables de la matière choisie, adaptés au profil.
  /// Les compteurs sont calculés depuis les contenus publiés, jamais codés en dur.
  Future<List<LearningChapter>> listChaptersForSubject({
    required String subjectId,
    required UserProfile profile,
  }) async {
    var curriculumQuery = _client
        .from('curricula')
        .select(
          'id,subject_id,subsystem,sector,exam_level_id,series_id,specialty_id',
        )
        .eq('subject_id', subjectId)
        .eq('is_active', true);

    final subsystem = _clean(profile.subsystem);
    final sector = _clean(profile.sector);
    if (subsystem.isNotEmpty) curriculumQuery = curriculumQuery.eq('subsystem', subsystem);
    if (sector.isNotEmpty) curriculumQuery = curriculumQuery.eq('sector', sector);

    final curriculumRows = List<Map<String, dynamic>>.from(await curriculumQuery);
    final matching = curriculumRows.where((row) {
      bool matchesOptionalId(String key, String? profileId) {
        final curriculumId = row[key]?.toString();
        return curriculumId == null ||
            curriculumId.isEmpty ||
            profileId == null ||
            profileId.isEmpty ||
            curriculumId == profileId;
      }

      return matchesOptionalId('exam_level_id', profile.examLevelId) &&
          matchesOptionalId('series_id', profile.seriesId) &&
          matchesOptionalId('specialty_id', profile.specialtyId);
    }).toList();

    if (matching.isEmpty) return const <LearningChapter>[];
    final curriculumIds = matching.map((row) => row['id'].toString()).toList();

    final chapterRows = List<Map<String, dynamic>>.from(
      await _client
          .from('course_chapters')
          .select()
          .inFilter('curriculum_id', curriculumIds)
          .eq('is_active', true)
          .order('position'),
    );
    if (chapterRows.isEmpty) return const <LearningChapter>[];

    final chapterIds = chapterRows.map((row) => row['id'].toString()).toList();
    final results = await Future.wait<dynamic>([
      _client
          .from('chapter_content_items')
          .select('chapter_id,content_type')
          .inFilter('chapter_id', chapterIds)
          .eq('is_published', true)
          .order('position'),
      _client
          .from('chapter_exercises')
          .select('id,chapter_id')
          .inFilter('chapter_id', chapterIds)
          .eq('is_published', true),
      _client
          .from('chapter_quizzes')
          .select('id,chapter_id')
          .inFilter('chapter_id', chapterIds)
          .eq('is_published', true),
      _client
          .from('chapter_learning_progress')
          .select('chapter_id,course_read')
          .eq('student_id', profile.id)
          .inFilter('chapter_id', chapterIds),
      _client
          .from('chapter_exercise_progress')
          .select('exercise_id,completed')
          .eq('student_id', profile.id)
          .eq('completed', true),
    ]);

    final contentRows = List<Map<String, dynamic>>.from(results[0] as List);
    final exerciseRows = List<Map<String, dynamic>>.from(results[1] as List);
    final quizRows = List<Map<String, dynamic>>.from(results[2] as List);
    final progressRows = List<Map<String, dynamic>>.from(results[3] as List);
    final completedExerciseIds = List<Map<String, dynamic>>.from(results[4] as List)
        .map((row) => row['exercise_id'].toString())
        .toSet();

    final curriculumById = <String, Map<String, dynamic>>{
      for (final row in matching) row['id'].toString(): row,
    };

    return chapterRows.map((row) {
      final chapterId = row['id'].toString();
      final types = contentRows
          .where((item) => item['chapter_id'].toString() == chapterId)
          .map((item) => _clean(item['content_type']?.toString()))
          .toList();
      final chapterExercises = exerciseRows
          .where((item) => item['chapter_id'].toString() == chapterId)
          .toList();
      final progress = progressRows.where(
        (item) => item['chapter_id'].toString() == chapterId,
      );
      final read = progress.isNotEmpty && progress.first['course_read'] == true;
      final completed = chapterExercises
          .where((item) => completedExerciseIds.contains(item['id'].toString()))
          .length;
      final curriculumId = row['curriculum_id'].toString();
      // The curriculum lookup ensures that the chapter belongs to a curriculum
      // matched to the selected subject/profile.
      if (!curriculumById.containsKey(curriculumId)) {
        return LearningChapter.fromMap(row);
      }
      return LearningChapter.fromMap(
        row,
        lessonCount: types.where((type) => type == 'text' || type == 'lesson' || type == 'course').length,
        videoCount: types.where((type) => type == 'video').length,
        pdfCount: types.where((type) => type == 'pdf').length,
        quizCount: quizRows.where((item) => item['chapter_id'].toString() == chapterId).length,
        exerciseCount: chapterExercises.length,
        courseRead: read,
        completedExercises: completed,
      );
    }).toList();
  }

  Future<List<ChapterContentItem>> listContent(String chapterId) async {
    final rows = await _client
        .from('chapter_content_items')
        .select()
        .eq('chapter_id', chapterId)
        .eq('is_published', true)
        .order('position');
    return List<Map<String, dynamic>>.from(rows)
        .map(ChapterContentItem.fromMap)
        .toList();
  }

  Future<List<ChapterExercise>> listExercises({
    required String chapterId,
    required String studentId,
  }) async {
    final rows = await _client
        .from('chapter_exercises')
        .select()
        .eq('chapter_id', chapterId)
        .eq('is_published', true)
        .order('position');
    final exerciseRows = List<Map<String, dynamic>>.from(rows);
    if (exerciseRows.isEmpty) return const <ChapterExercise>[];

    final progressRows = List<Map<String, dynamic>>.from(
      await _client
          .from('chapter_exercise_progress')
          .select('exercise_id,completed')
          .eq('student_id', studentId)
          .inFilter('exercise_id', exerciseRows.map((e) => e['id'].toString()).toList()),
    );
    final completed = progressRows
        .where((row) => row['completed'] == true)
        .map((row) => row['exercise_id'].toString())
        .toSet();

    return exerciseRows
        .map((row) => ChapterExercise.fromMap(
              row,
              completed: completed.contains(row['id'].toString()),
            ))
        .toList();
  }

  Future<List<ChapterQuiz>> listQuizzes(String chapterId) async {
    var rows = await _client
        .from('chapter_quizzes')
        .select()
        .eq('chapter_id', chapterId)
        .eq('is_published', true)
        .order('position');

    // Official content and teacher-authored quizzes use the same chapter flow.
    // If no published quiz exists, ask the authenticated student-only Edge
    // Function to generate one from the chapter's published text. This is
    // additive: existing quizzes are never overwritten or regenerated.
    if ((rows as List).isEmpty && _client.auth.currentUser != null) {
      try {
        final response = await _client.functions.invoke(
          'chapter-quiz',
          body: {'chapter_id': chapterId},
        );
        final data = response.data;
        if (data is Map && data['error'] != null) {
          throw StateError(data['error'].toString());
        }
        rows = await _client
            .from('chapter_quizzes')
            .select()
            .eq('chapter_id', chapterId)
            .eq('is_published', true)
            .order('position');
      } catch (error) {
        // Keep the chapter readable if AI is unavailable or its source text is
        // too short. The next visit can retry without changing existing data.
        debugPrint('Smart chapter quiz unavailable: $error');
      }
    }

    return List<Map<String, dynamic>>.from(rows)
        .map(ChapterQuiz.fromMap)
        .toList();
  }

  /// Cette méthode ne sélectionne volontairement jamais la table des réponses.
  Future<List<ChapterQuizQuestion>> listQuizQuestions(String quizId) async {
    final rows = await _client
        .from('chapter_quiz_questions')
        .select('id,quiz_id,prompt_fr,prompt_en,options_fr,options_en,position')
        .eq('quiz_id', quizId)
        .order('position');
    return List<Map<String, dynamic>>.from(rows)
        .map(ChapterQuizQuestion.fromMap)
        .toList();
  }

  Future<Map<String, dynamic>> getProgress({
    required String chapterId,
    required String studentId,
  }) async {
    final row = await _client
        .from('chapter_learning_progress')
        .select()
        .eq('chapter_id', chapterId)
        .eq('student_id', studentId)
        .maybeSingle();
    return row == null ? <String, dynamic>{} : Map<String, dynamic>.from(row);
  }

  Future<void> markCourseRead({
    required String chapterId,
    required String studentId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('chapter_learning_progress').upsert(
      {
        'chapter_id': chapterId,
        'student_id': studentId,
        'course_read': true,
        'course_read_at': now,
        'last_opened_at': now,
        'updated_at': now,
      },
      onConflict: 'student_id,chapter_id',
    );
  }

  Future<void> markExerciseCompleted({
    required String exerciseId,
    required String studentId,
    required bool completed,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('chapter_exercise_progress').upsert(
      {
        'exercise_id': exerciseId,
        'student_id': studentId,
        'completed': completed,
        'completed_at': completed ? now : null,
        'updated_at': now,
      },
      onConflict: 'student_id,exercise_id',
    );
  }

  Future<Map<String, dynamic>> getExerciseCorrection(String exerciseId) async {
    final result = await _client.rpc(
      'get_chapter_exercise_correction',
      params: {'p_exercise_id': exerciseId},
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    if (result is List && result.isNotEmpty && result.first is Map) {
      return Map<String, dynamic>.from(result.first as Map);
    }
    return <String, dynamic>{};
  }

  Future<dynamic> submitQuiz({
    required String quizId,
    required Map<String, int> answers,
  }) {
    return _client.rpc(
      'submit_chapter_quiz',
      params: {'p_quiz_id': quizId, 'p_answers': answers},
    );
  }

  /// Upload privé ; le bucket et ses politiques RLS existent déjà dans Supabase.
  Future<String> uploadContentFile({
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final safePath = path.replaceAll(RegExp(r'[^a-zA-Z0-9_./-]'), '_');
    await _client.storage.from(storageBucket).uploadBinary(
      safePath,
      bytes,
      fileOptions: FileOptions(
        contentType: contentType,
        upsert: false,
      ),
    );
    return safePath;
  }

  Future<String> createSignedUrl(String storagePath, {int expiresIn = 900}) {
    return _client.storage.from(storageBucket).createSignedUrl(
      storagePath,
      expiresIn,
    );
  }

  // CRUD admin : les politiques RLS Supabase n'autorisent que l'administrateur.
  Future<Map<String, dynamic>> saveChapter({
    String? id,
    required String curriculumId,
    required String titleFr,
    required String titleEn,
    String? descriptionFr,
    String? descriptionEn,
    required int position,
    required bool isActive,
  }) async {
    final values = <String, dynamic>{
      'curriculum_id': curriculumId,
      'title_fr': titleFr.trim(),
      'title_en': titleEn.trim(),
      'description_fr': descriptionFr?.trim(),
      'description_en': descriptionEn?.trim(),
      'position': position,
      'is_active': isActive,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final row = id == null
        ? await _client.from('course_chapters').insert(values).select().single()
        : await _client.from('course_chapters').update(values).eq('id', id).select().single();
    return Map<String, dynamic>.from(row);
  }

  Future<void> setChapterVisible(String chapterId, bool visible) async {
    await _client.from('course_chapters').update({
      'is_active': visible,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', chapterId);
  }

  Future<void> deleteChapter(String chapterId) async {
    await _client.from('course_chapters').delete().eq('id', chapterId);
  }

  Future<Map<String, dynamic>> saveContent({
    String? id,
    required String chapterId,
    required String type,
    required String titleFr,
    required String titleEn,
    String? bodyTextFr,
    String? bodyTextEn,
    String? externalUrl,
    String? storagePath,
    required int position,
    required bool visible,
    required String createdBy,
  }) async {
    final values = <String, dynamic>{
      'chapter_id': chapterId,
      'content_type': type,
      'title_fr': titleFr.trim(),
      'title_en': titleEn.trim(),
      'body_text_fr': bodyTextFr,
      'body_text_en': bodyTextEn,
      'external_url': externalUrl,
      'storage_path': storagePath,
      'position': position,
      'is_published': visible,
      'created_by': createdBy,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final row = id == null
        ? await _client.from('chapter_content_items').insert(values).select().single()
        : await _client.from('chapter_content_items').update(values).eq('id', id).select().single();
    return Map<String, dynamic>.from(row);
  }

  Future<void> setContentVisible(String contentId, bool visible) async {
    await _client.from('chapter_content_items').update({
      'is_published': visible,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', contentId);
  }

  Future<void> deleteContent(String contentId) async {
    await _client.from('chapter_content_items').delete().eq('id', contentId);
  }

  Future<Map<String, dynamic>> saveExercise({
    String? id,
    required String chapterId,
    required String statementFr,
    required String statementEn,
    required String difficulty,
    required int position,
    required bool visible,
    required String createdBy,
    required String correctionFr,
    required String correctionEn,
    String? explanationFr,
    String? explanationEn,
  }) async {
    final values = <String, dynamic>{
      'chapter_id': chapterId,
      'statement_fr': statementFr.trim(),
      'statement_en': statementEn.trim(),
      'difficulty': difficulty,
      'position': position,
      'is_published': visible,
      'created_by': createdBy,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final row = id == null
        ? await _client.from('chapter_exercises').insert(values).select().single()
        : await _client.from('chapter_exercises').update(values).eq('id', id).select().single();
    final exercise = Map<String, dynamic>.from(row);
    await _client.from('chapter_exercise_corrections').upsert({
      'exercise_id': exercise['id'],
      'correction_fr': correctionFr.trim(),
      'correction_en': correctionEn.trim(),
      'explanation_fr': explanationFr?.trim(),
      'explanation_en': explanationEn?.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'exercise_id');
    return exercise;
  }

  Future<void> setExerciseVisible(String exerciseId, bool visible) async {
    await _client.from('chapter_exercises').update({
      'is_published': visible,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', exerciseId);
  }

  Future<void> deleteExercise(String exerciseId) async {
    await _client.from('chapter_exercises').delete().eq('id', exerciseId);
  }

  Future<Map<String, dynamic>> saveQuiz({
    String? id,
    required String chapterId,
    required String titleFr,
    required String titleEn,
    String? descriptionFr,
    String? descriptionEn,
    required int position,
    required bool visible,
    required String createdBy,
  }) async {
    final values = <String, dynamic>{
      'chapter_id': chapterId,
      'title_fr': titleFr.trim(),
      'title_en': titleEn.trim(),
      'description_fr': descriptionFr?.trim(),
      'description_en': descriptionEn?.trim(),
      'position': position,
      'is_published': visible,
      'created_by': createdBy,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final row = id == null
        ? await _client.from('chapter_quizzes').insert(values).select().single()
        : await _client.from('chapter_quizzes').update(values).eq('id', id).select().single();
    return Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>> saveQuizQuestion({
    String? id,
    required String quizId,
    required String promptFr,
    required String promptEn,
    required List<String> optionsFr,
    required List<String> optionsEn,
    required int correctOptionIndex,
    String? explanationFr,
    String? explanationEn,
    required int position,
  }) async {
    if (optionsFr.length < 2 || optionsEn.length != optionsFr.length) {
      throw ArgumentError('Le QCM doit contenir au moins deux choix par langue.');
    }
    if (correctOptionIndex < 0 || correctOptionIndex >= optionsFr.length) {
      throw ArgumentError.value(correctOptionIndex, 'correctOptionIndex');
    }
    final values = <String, dynamic>{
      'quiz_id': quizId,
      'prompt_fr': promptFr.trim(),
      'prompt_en': promptEn.trim(),
      'options_fr': optionsFr,
      'options_en': optionsEn,
      'position': position,
    };
    final row = id == null
        ? await _client.from('chapter_quiz_questions').insert(values).select().single()
        : await _client.from('chapter_quiz_questions').update(values).eq('id', id).select().single();
    final question = Map<String, dynamic>.from(row);
    await _client.from('chapter_quiz_answer_keys').upsert({
      'question_id': question['id'],
      'correct_option_index': correctOptionIndex,
      'explanation_fr': explanationFr?.trim(),
      'explanation_en': explanationEn?.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'question_id');
    return question;
  }

  Future<void> setQuizVisible(String quizId, bool visible) async {
    await _client.from('chapter_quizzes').update({
      'is_published': visible,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', quizId);
  }

  Future<void> deleteQuiz(String quizId) async {
    await _client.from('chapter_quizzes').delete().eq('id', quizId);
  }
}
