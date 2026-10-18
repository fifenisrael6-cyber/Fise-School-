import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/search_result.dart';

/// Recherche globale : catalogue, cours, leçons, chapitres, fichiers (titres,
/// noms et contenu indexé des PDF), annales, devoirs et forum.
///
/// Chaque source est interrogée séparément : si une table est inaccessible
/// (droits RLS, migration non appliquée), les autres résultats restent affichés.
class SearchService {
  final SupabaseClient _client;

  SearchService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static const int _perSource = 20;

  Future<List<SearchResult>> search(String query) async {
    final terms = _terms(query);
    if (terms.isEmpty) return const [];

    // Le filtre serveur utilise le mot le plus long ; le classement
    // côté application vérifie ensuite tous les mots saisis.
    final key = ([...terms]..sort((a, b) => b.length.compareTo(a.length))).first;

    final groups = await Future.wait<List<SearchResult>>([
      _exams(key, terms),
      _classes(key, terms),
      _subjects(key, terms),
      _courses(key, terms),
      _lessons(key, terms),
      _chapters(key, terms),
      _chapterContents(key, terms),
      _resources(key, terms),
      _chunks(key, terms),
      _pastPapers(key, terms),
      _assignments(key, terms),
      _forumTopics(key, terms),
    ]);

    final all = groups.expand((g) => g).toList();
    all.sort((a, b) => b.score.compareTo(a.score));
    return all;
  }

  // ── Sources ───────────────────────────────────────────────────────────────

  Future<List<SearchResult>> _exams(String key, List<String> terms) => _run(
    () async {
      final rows = await _client
          .from('exams')
          .select('id, name_fr, name_en')
          .eq('active', true)
          .or(_or(['name_fr', 'name_en'], key))
          .limit(_perSource);
      return rows
          .map(
            (r) => _build(
              r,
              terms,
              type: SearchResultType.exam,
              title: [r['name_fr'], r['name_en']],
              subtitle: r['name_en'],
            ),
          )
          .toList();
    },
  );

  Future<List<SearchResult>> _classes(String key, List<String> terms) => _run(
    () async {
      final rows = await _client
          .from('school_classes')
          .select('id, name, display_name')
          .eq('is_active', true)
          .or(_or(['name', 'display_name'], key))
          .limit(_perSource);
      return rows
          .map(
            (r) => _build(
              r,
              terms,
              type: SearchResultType.classItem,
              title: [r['display_name'], r['name']],
              subtitle: r['name'],
            ),
          )
          .toList();
    },
  );

  Future<List<SearchResult>> _subjects(String key, List<String> terms) => _run(
    () async {
      final rows = await _client
          .from('subjects')
          .select('id, name_fr, name_en')
          .eq('is_active', true)
          .or(_or(['name_fr', 'name_en'], key))
          .limit(_perSource);
      return rows
          .map(
            (r) => _build(
              r,
              terms,
              type: SearchResultType.subject,
              title: [r['name_fr'], r['name_en']],
              subtitle: r['name_en'],
            ),
          )
          .toList();
    },
  );

  Future<List<SearchResult>> _courses(String key, List<String> terms) => _run(
    () async {
      final rows = await _client
          .from('courses')
          .select(
            'id, title_fr, title_en, description_fr, description_en, content_fr, content_en',
          )
          .eq('status', 'published')
          .or(
            _or([
              'title_fr',
              'title_en',
              'description_fr',
              'description_en',
              'content_fr',
              'content_en',
            ], key),
          )
          .limit(_perSource);
      return rows
          .map(
            (r) => _build(
              r,
              terms,
              type: SearchResultType.course,
              title: [r['title_fr'], r['title_en']],
              body: [
                r['description_fr'],
                r['description_en'],
                r['content_fr'],
                r['content_en'],
              ],
              courseId: r['id'].toString(),
            ),
          )
          .toList();
    },
  );

  Future<List<SearchResult>> _lessons(String key, List<String> terms) => _run(
    () async {
      final rows = await _client
          .from('lessons')
          .select(
            'id, course_id, title_fr, title_en, content_fr, content_en, '
            'objectives_fr, objectives_en, examples_fr, examples_en, '
            'summary_fr, summary_en',
          )
          .eq('is_published', true)
          .or(
            _or([
              'title_fr',
              'title_en',
              'content_fr',
              'content_en',
              'objectives_fr',
              'objectives_en',
              'examples_fr',
              'examples_en',
              'summary_fr',
              'summary_en',
            ], key),
          )
          .limit(_perSource);
      return rows
          .map(
            (r) => _build(
              r,
              terms,
              type: SearchResultType.lesson,
              title: [r['title_fr'], r['title_en']],
              body: [
                r['content_fr'],
                r['content_en'],
                r['objectives_fr'],
                r['objectives_en'],
                r['examples_fr'],
                r['examples_en'],
                r['summary_fr'],
                r['summary_en'],
              ],
              courseId: r['course_id']?.toString(),
              lessonId: r['id'].toString(),
            ),
          )
          .toList();
    },
  );

  Future<List<SearchResult>> _chapters(String key, List<String> terms) => _run(
    () async {
      final rows = await _client
          .from('course_chapters')
          .select('id, title_fr, title_en, description_fr, description_en')
          .eq('is_active', true)
          .or(
            _or([
              'title_fr',
              'title_en',
              'description_fr',
              'description_en',
            ], key),
          )
          .limit(_perSource);
      return rows
          .map(
            (r) => _build(
              r,
              terms,
              type: SearchResultType.chapter,
              title: [r['title_fr'], r['title_en']],
              body: [r['description_fr'], r['description_en']],
            ),
          )
          .toList();
    },
  );

  Future<List<SearchResult>> _chapterContents(String key, List<String> terms) =>
      _run(() async {
        final rows = await _client
            .from('chapter_content_items')
            .select('id, content_type, title_fr, title_en, body_text_fr, body_text_en')
            .eq('is_published', true)
            .or(
              _or([
                'title_fr',
                'title_en',
                'body_text_fr',
                'body_text_en',
              ], key),
            )
            .limit(_perSource);
        return rows
            .map(
              (r) => _build(
                r,
                terms,
                type: SearchResultType.chapterContent,
                title: [r['title_fr'], r['title_en']],
                body: [r['body_text_fr'], r['body_text_en']],
                subtitle: r['content_type']?.toString(),
              ),
            )
            .toList();
      });

  /// Fichiers joints aux cours : titre, nom de fichier et aperçu indexé.
  Future<List<SearchResult>> _resources(String key, List<String> terms) => _run(
    () async {
      final rows = await _client
          .from('course_resources')
          .select(
            'id, course_id, resource_type, file_name, title_fr, title_en, index_preview',
          )
          .or(
            _or([
              'title_fr',
              'title_en',
              'file_name',
              'index_preview',
            ], key),
          )
          .limit(_perSource);
      return rows
          .map(
            (r) => _build(
              r,
              terms,
              type: SearchResultType.resource,
              title: [r['title_fr'], r['title_en'], r['file_name']],
              body: [r['index_preview']],
              subtitle: r['file_name']?.toString(),
              courseId: r['course_id']?.toString(),
            ),
          )
          .toList();
    },
  );

  /// Texte complet extrait des PDF et images indexés (course_chunks).
  Future<List<SearchResult>> _chunks(String key, List<String> terms) => _run(
    () async {
      final rows = await _client
          .from('course_chunks')
          .select('id, course_id, title, content')
          .ilike('content', '%$key%')
          .limit(_perSource);
      return rows
          .map(
            (r) => _build(
              r,
              terms,
              type: SearchResultType.fileContent,
              title: [r['title']],
              body: [r['content']],
              courseId: r['course_id']?.toString(),
            ),
          )
          .toList();
    },
  );

  Future<List<SearchResult>> _pastPapers(String key, List<String> terms) =>
      _run(() async {
        final rows = await _client
            .from('past_papers')
            .select(
              'id, exam_year, session_label, subject_fr, subject_en, kind, file_name',
            )
            .eq('is_published', true)
            .or(
              _or([
                'subject_fr',
                'subject_en',
                'file_name',
                'session_label',
              ], key),
            )
            .limit(_perSource);
        return rows.map((r) {
          final kind = r['kind'] == 'correction' ? 'Corrigé' : 'Sujet';
          return _build(
            r,
            terms,
            type: SearchResultType.pastPaper,
            title: [r['subject_fr'], r['subject_en'], r['file_name']],
            subtitle: '$kind · ${r['exam_year']}',
          );
        }).toList();
      });

  Future<List<SearchResult>> _assignments(String key, List<String> terms) =>
      _run(() async {
        final rows = await _client
            .from('assignments')
            .select('id, title_fr, title_en, instructions_fr, instructions_en')
            .eq('status', 'published')
            .or(
              _or([
                'title_fr',
                'title_en',
                'instructions_fr',
                'instructions_en',
              ], key),
            )
            .limit(_perSource);
        return rows
            .map(
              (r) => _build(
                r,
                terms,
                type: SearchResultType.assignment,
                title: [r['title_fr'], r['title_en']],
                body: [r['instructions_fr'], r['instructions_en']],
              ),
            )
            .toList();
      });

  Future<List<SearchResult>> _forumTopics(String key, List<String> terms) =>
      _run(() async {
        final rows = await _client
            .from('forum_topics')
            .select('id, title, description')
            .or(_or(['title', 'description'], key))
            .limit(_perSource);
        return rows
            .map(
              (r) => _build(
                r,
                terms,
                type: SearchResultType.forum,
                title: [r['title']],
                body: [r['description']],
              ),
            )
            .toList();
      });

  // ── Utilitaires ───────────────────────────────────────────────────────────

  Future<List<SearchResult>> _run(
    Future<List<SearchResult>> Function() action,
  ) async {
    try {
      return await action();
    } catch (_) {
      return const [];
    }
  }

  /// Mots de la requête, sans caractères qui casseraient le filtre PostgREST.
  List<String> _terms(String query) {
    final cleaned = query
        .replaceAll(RegExp(r'[,()%*"\\:]'), ' ')
        .trim()
        .toLowerCase();
    return cleaned
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 2)
        .toSet()
        .toList();
  }

  String _or(List<String> columns, String key) =>
      columns.map((c) => '$c.ilike.%$key%').join(',');

  SearchResult _build(
    Map<String, dynamic> row, {
    required List<String> terms,
    required SearchResultType type,
    required List<dynamic> title,
    List<dynamic> body = const [],
    dynamic subtitle,
    String? courseId,
    String? lessonId,
  }) {
    final titles = title.map(_text).where((t) => t.isNotEmpty).toList();
    final bodies = body.map(_text).where((t) => t.isNotEmpty).toList();
    final shownTitle = titles.isEmpty ? '—' : titles.first;
    final titleBlob = titles.join(' ').toLowerCase();
    final bodyBlob = bodies.join(' ').toLowerCase();

    var score = 0;
    for (final t in terms) {
      if (titleBlob.contains(t)) score += 10;
      if (bodyBlob.contains(t)) score += 3;
    }
    if (titleBlob.contains(terms.join(' '))) score += 5;

    String? snippet;
    for (final text in bodies) {
      snippet = _snippet(text, terms);
      if (snippet != null) break;
    }

    final sub = _text(subtitle);
    return SearchResult(
      id: row['id'].toString(),
      title: shownTitle,
      subtitle: sub.isEmpty || sub == shownTitle ? null : sub,
      snippet: snippet,
      type: type,
      courseId: courseId,
      lessonId: lessonId,
      score: score,
    );
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';

  /// Court extrait autour du premier mot trouvé.
  String? _snippet(String text, List<String> terms) {
    final lower = text.toLowerCase();
    var index = -1;
    for (final t in terms) {
      final i = lower.indexOf(t);
      if (i >= 0 && (index < 0 || i < index)) index = i;
    }
    if (index < 0) return null;
    final start = index - 60 < 0 ? 0 : index - 60;
    final end = index + 120 > text.length ? text.length : index + 120;
    final piece = text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ');
    return '${start > 0 ? '…' : ''}$piece${end < text.length ? '…' : ''}';
  }
}
