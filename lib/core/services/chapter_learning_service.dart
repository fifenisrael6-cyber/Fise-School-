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
    Future<List<Map<String, dynamic>>> Function() fetch, {
    bool forceRefresh = false,
  }) async {
    // Keep the cache owner fixed for the whole operation so a background
    // refresh cannot write one account's data into another account's cache.
    final userId = _cacheUserId;
    if (forceRefresh) {
      try {
        final rows = await fetch().timeout(const Duration(seconds: 12));
        await _database.saveOfflineCatalogCache(userId, cacheKey, jsonEncode(rows));
        _lastCacheRefresh['$userId:$cacheKey'] = DateTime.now();
        return rows;
      } catch (_) {
        // If offline, keep the last known-good cache available to the student.
        final staleJson = await _database.getOfflineCatalogCache(userId, cacheKey);
        if (staleJson != null) {
          try {
            return (jsonDecode(staleJson) as List<dynamic>)
                .map((row) => Map<String, dynamic>.from(row as Map))
                .toList(growable: false);
          } catch (_) {}
        }
        return const <Map<String, dynamic>>[];
      }
    }
    final cachedJson = await _database.getOfflineCatalogCache(userId, cacheKey);
    if (cachedJson != null) {
      try {
        final decoded = jsonDecode(cachedJson) as List<dynamic>;
        final cached = decoded
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(growable: false);

        // An empty cached catalogue is not authoritative: earlier app builds
        // could cache an empty result when the class/subject mapping was being
        // repaired. Returning that empty list immediately keeps the page empty
        // even after the server now has chapters. Re-fetch empty caches in this
        // same request so the student sees the current programme without
        // needing to clear app data or wait for a hidden background refresh.
        if (cached.isNotEmpty) {
          final refreshKey = '$userId:$cacheKey';
          final lastRefresh = _lastCacheRefresh[refreshKey];
          if (lastRefresh == null ||
              DateTime.now().difference(lastRefresh) > const Duration(minutes: 2)) {
            _lastCacheRefresh[refreshKey] = DateTime.now();
            unawaited(_refreshRows(userId, cacheKey, fetch));
          }
          return cached;
        }
        // Fall through to a synchronous network fetch below for empty cache.

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
  Future<List<Map<String, dynamic>>> _contentRowsForChapter(
    String chapterId, {
    bool forceRefresh = false,
  }) =>
      _cachedRows(
        'chapter-content:$chapterId',
        () => _fetchContentRowsForChapter(chapterId),
        forceRefresh: forceRefresh,
      );

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

    // First load only this chapter's own published content. Never merge files
    // from another chapter merely because the titles or positions match.
    final rows = await _client
        .from('chapter_content_items')
        .select()
        .eq('chapter_id', chapterId)
        .eq('is_published', true)
        .order('position');
    final content = rows.map((row) => Map<String, dynamic>.from(row)).toList();

    // Restore legacy courses and lessons that were already linked to this
    // chapter before the chapter-folder catalogue was introduced.
    List<Map<String, dynamic>> courses = <Map<String, dynamic>>[];
    try {
      final legacyCourses = await _client
          .from('courses')
          .select('id,title_fr,title_en,content_fr,content_en')
          .eq('chapter_id', chapterId)
          .eq('status', 'published');
      courses = legacyCourses
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    } catch (_) {
      // Some deployments may not expose legacy course rows to this account.
    }

    final courseIds = courses.map((row) => row['id'].toString()).toList();
    for (final course in courses) {
      final bodyFr = course['content_fr']?.toString();
      final bodyEn = course['content_en']?.toString();
      if ((bodyFr ?? '').trim().isEmpty && (bodyEn ?? '').trim().isEmpty) {
        continue;
      }
      content.add({
        'id': 'legacy-course-${course['id']}',
        'chapter_id': chapterId,
        'content_type': 'course',
        'title_fr': course['title_fr']?.toString() ?? 'Cours',
        'title_en': course['title_en']?.toString() ?? 'Course',
        'body_text_fr': bodyFr,
        'body_text_en': bodyEn,
        'position': 0,
        'is_published': true,
      });
    }

    if (courseIds.isNotEmpty) {
      try {
        final lessons = await _client
            .from('lessons')
            .select('id,course_id,title_fr,title_en,content_fr,content_en,position')
            .inFilter('course_id', courseIds)
            .eq('is_published', true)
            .order('position');
        for (final raw in lessons) {
          final lesson = Map<String, dynamic>.from(raw);
          final bodyFr = lesson['content_fr']?.toString();
          final bodyEn = lesson['content_en']?.toString();
          content.add({
            'id': 'legacy-lesson-${lesson['id']}',
            'chapter_id': chapterId,
            'content_type': 'course',
            'title_fr': lesson['title_fr']?.toString() ?? 'Leçon',
            'title_en': lesson['title_en']?.toString() ?? 'Lesson',
            'body_text_fr': bodyFr,
            'body_text_en': bodyEn,
            'position': (lesson['position'] as num?)?.toInt() ?? 0,
            'is_published': true,
          });
        }
      } catch (_) {
        // Keep chapter content and course bodies visible if legacy lessons
        // are not available under the current account's RLS policies.
      }

      try {
        final resources = await _client
            .from('course_resources')
            .select('id,course_id,resource_type,storage_path,file_name,title_fr,title_en,mime_type,position')
            .inFilter('course_id', courseIds)
            .order('position');
        for (final raw in resources) {
          final resource = Map<String, dynamic>.from(raw);
          final storagePath = resource['storage_path']?.toString() ?? '';
          if (storagePath.isEmpty) continue;
          final resourceType = (resource['resource_type']?.toString() ?? '').toLowerCase();
          final mimeType = (resource['mime_type']?.toString() ?? '').toLowerCase();
          final fileName = resource['file_name']?.toString() ?? 'Fichier';
          final extension = fileName.contains('.')
              ? fileName.split('.').last.toLowerCase()
              : '';
          String? type;
          if (resourceType.contains('video') || mimeType.startsWith('video/') ||
              const ['mp4', 'mov', 'webm', 'm4v'].contains(extension)) {
            type = 'video';
          } else if (resourceType.contains('audio') || mimeType.startsWith('audio/') ||
              const ['mp3', 'm4a', 'wav', 'ogg', 'aac'].contains(extension)) {
            type = 'audio';
          } else if (resourceType.contains('image') || mimeType.startsWith('image/') ||
              const ['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(extension)) {
            type = 'image';
          } else if (resourceType.contains('pdf') || mimeType == 'application/pdf' ||
              extension == 'pdf') {
            type = 'pdf';
          } else {
            // Keep unknown document types out of PDF/image/audio/video readers.
            continue;
          }
          content.add({
            'id': 'legacy-resource-${resource['id']}',
            'chapter_id': chapterId,
            'content_type': type,
            'title_fr': resource['title_fr']?.toString().trim().isNotEmpty == true
                ? resource['title_fr'].toString()
                : fileName,
            'title_en': resource['title_en']?.toString().trim().isNotEmpty == true
                ? resource['title_en'].toString()
                : fileName,
            'storage_path': 'legacy-course-resource:$storagePath',
            'position': (resource['position'] as num?)?.toInt() ?? 0,
            'is_published': true,
          });
        }
      } catch (_) {
        // Legacy media is optional; it must not hide the chapter's own content.
      }
    }

    content.sort((a, b) =>
        ((a['position'] as num?)?.toInt() ?? 0)
            .compareTo((b['position'] as num?)?.toInt() ?? 0));
    return content;
  }

  Future<List<ChapterLearningContentItem>> listContent(
    String chapterId, {
    bool forceRefresh = false,
  }) async {
    final rows = await _contentRowsForChapter(
      chapterId,
      forceRefresh: forceRefresh,
    );
    return rows
        .map(ChapterLearningContentItem.fromMap)
        .toList(growable: false);
  }

  Future<List<ChapterLearningExercise>> listExercises(
    String chapterId, {
    bool forceRefresh = false,
  }) async {
    final rows = await _cachedRows('chapter-exercises:$chapterId', () async {
      final result = await _client
          .from('chapter_exercises')
          .select()
          .eq('chapter_id', chapterId)
          .eq('is_published', true)
          .order('position');
      return result.map((row) => Map<String, dynamic>.from(row)).toList();
    }, forceRefresh: forceRefresh);
    return rows.map(ChapterLearningExercise.fromMap).toList(growable: false);
  }

  Future<Map<String, dynamic>> generateSmartQuiz(String chapterId) async {
    final response = await _client.functions.invoke(
      'chapter-quiz',
      body: {'chapter_id': chapterId},
    ).timeout(const Duration(seconds: 50));
    if (response.status < 200 || response.status >= 300) {
      final payload = response.data;
      final message = payload is Map
          ? (payload['error']?.toString() ?? payload['message']?.toString())
          : null;
      throw StateError(message?.isNotEmpty == true
          ? message!
          : 'Impossible de générer le QCM intelligent.');
    }
    if (response.data is! Map) {
      throw StateError('Réponse invalide du service QCM intelligent.');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<ChapterLearningQuiz>> listQuizzes(
    String chapterId, {
    bool forceRefresh = false,
  }) async {
    Future<List<Map<String, dynamic>>> fetchRows() async {
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
    }

    final cacheKey = 'chapter-quizzes:$chapterId';
    final rows = forceRefresh
        ? await fetchRows()
        : await _cachedRows(cacheKey, fetchRows);
    if (forceRefresh) {
      await _database.saveOfflineCatalogCache(
        _cacheUserId,
        cacheKey,
        jsonEncode(rows),
      );
    }
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

  Future<ChapterLearningCounts> getCounts(
    String chapterId, {
    bool forceRefresh = false,
  }) async {
    final results = await Future.wait<dynamic>([
      listContent(chapterId, forceRefresh: forceRefresh),
      listExercises(chapterId, forceRefresh: forceRefresh),
      _cachedRows('chapter-count-quizzes:$chapterId', () async {
        final rows = await _client
            .from('chapter_quizzes')
            .select('id')
            .eq('chapter_id', chapterId)
            .eq('is_published', true);
        return rows.map((row) => Map<String, dynamic>.from(row)).toList();
      }, forceRefresh: forceRefresh),
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

  /// Counts the official chapter titles available for this student's class/subject.
  /// This count intentionally includes title-only MINESEC catalogue chapters,
  /// even when the lesson content has not yet been uploaded.
  Future<int> countChaptersForSubject(
    String subjectId, {
    UserProfile? profile,
    String? classId,
  }) async {
    final curricula = await listCurricula(
      subjectId,
      profile: profile,
      classId: classId,
    );
    if (curricula.isEmpty) return 0;
    final chapterLists = await Future.wait(
      curricula.map((curriculum) => listChapters(curriculum.id)),
    );
    return chapterLists.fold<int>(0, (total, chapters) => total + chapters.length);
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
    String? classId,
    bool forceRefresh = false,
  }) async {
    final profileKey = profile?.id ?? _cacheUserId;
    final roomKey = classId ?? 'all-classes';
    final rows = await _cachedRows(
      'chapter-catalog-v2:curricula:$profileKey:$roomKey:$subjectId',
      () => _fetchCurriculumRows(
        subjectId,
        profile: profile,
        classId: classId,
      ),
      forceRefresh: forceRefresh,
    );
    return rows.map(Curriculum.fromMap).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _fetchCurriculumRows(
    String subjectId, {
    UserProfile? profile,
    String? classId,
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
      final activeMemberClassIds = memberships
          .map((row) => row['class_id'])
          .whereType<String>()
          .toSet();
      // When a room is passed by the course page, only use that exact active
      // membership. This keeps both the titles and their resources room-scoped.
      final memberClassIds = classId == null
          ? activeMemberClassIds.toList(growable: false)
          : (activeMemberClassIds.contains(classId) ? <String>[classId] : <String>[]);
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

    // Prefer the canonical chapter-title catalogue, but only when it actually
    // contains active chapter rows. A title-only container can be created before
    // its chapter seed is applied; selecting it unconditionally hides older
    // curricula that already contain chapters and makes the student page look
    // empty. Fall back to the compatible curricula until the catalogue is seeded.
    final containers = filtered
        .where((curriculum) => curriculum['is_catalog_container'] == true)
        .toList(growable: false);
    if (containers.isNotEmpty) {
      final containerIds = containers
          .map((curriculum) => curriculum['id'])
          .whereType<String>()
          .toList(growable: false);
      var populatedContainerIds = <String>{};
      if (containerIds.isNotEmpty) {
        try {
          final chapterRows = await _client
              .from('course_chapters')
              .select('curriculum_id')
              .inFilter('curriculum_id', containerIds)
              .eq('is_active', true);
          populatedContainerIds = chapterRows
              .map((row) => row['curriculum_id'])
              .whereType<String>()
              .toSet();
        } catch (_) {
          // If this lookup is temporarily unavailable, keep the canonical
          // containers rather than exposing duplicate programme cards.
          return containers;
        }
      }
      if (populatedContainerIds.isNotEmpty) {
        filtered = containers
            .where((curriculum) =>
                populatedContainerIds.contains(curriculum['id']))
            .toList(growable: false);
      } else {
        filtered = filtered
            .where((curriculum) => curriculum['is_catalog_container'] != true)
            .toList(growable: false);
      }
    } else {
      filtered = filtered
          .where((curriculum) => curriculum['is_catalog_container'] != true)
          .toList(growable: false);
    }

    return filtered;
  }

  Future<List<CourseChapter>> listChapters(
    String curriculumId, {
    bool forceRefresh = false,
  }) async {
    final rows = await _cachedRows(
      'chapter-catalog-v2:chapters:$curriculumId',
      () async {
        final result = await _client
            .from('course_chapters')
            .select()
            .eq('curriculum_id', curriculumId)
            .eq('is_active', true)
            .order('position');
        return result.map((row) => Map<String, dynamic>.from(row)).toList();
      },
      forceRefresh: forceRefresh,
    );
    // source_title records provenance/verification notes, not the chapter
    // heading. Many valid named chapters have a provisional-source note while
    // official MINESEC/GCE confirmation is pending. Filtering that note hid
    // most of the catalogue from students. Hide only genuinely blank or
    // generic placeholder headings; CourseChapter.needsTitleVerification
    // still flags provisional titles in the student UI.
    const placeholders = <String>{
      'structure provisoire',
      'chapitre à définir',
      'chapitre a definir',
      'chapitre à compléter',
      'chapitre a completer',
      'titre à confirmer',
      'titre a confirmer',
      'provisional structure',
      'chapter to be defined',
      'chapter title pending',
      'to be completed',
    };
    bool hasRealTitle(Object? value) {
      final title = (value?.toString() ?? '').trim().toLowerCase();
      return title.isNotEmpty && !placeholders.contains(title);
    }

    final titledRows = rows.where((row) =>
        hasRealTitle(row['title_fr']) || hasRealTitle(row['title_en']));
    return titledRows.map(CourseChapter.fromMap).toList(growable: false);
  }
}
