import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/search_result.dart';

class SearchService {
  final SupabaseClient _client;

  SearchService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<List<SearchResult>> search(String query) async {
    final text = query.trim();
    if (text.isEmpty) {
      return const [];
    }

    final exams = await _client
        .from('exams')
        .select('id, name_fr, name_en')
        .eq('active', true)
        .or('name_fr.ilike.%$text%,name_en.ilike.%$text%')
        .limit(20);
    final classes = await _client
        .from('school_classes')
        .select('id, name, display_name')
        .eq('is_active', true)
        .or('name.ilike.%$text%,display_name.ilike.%$text%')
        .limit(20);
    final subjects = await _client
        .from('subjects')
        .select('id, name_fr, name_en')
        .eq('is_active', true)
        .or('name_fr.ilike.%$text%,name_en.ilike.%$text%')
        .limit(20);
    final courses = await _client
        .from('courses')
        .select('id, title_fr, title_en')
        .eq('status', 'published')
        .or('title_fr.ilike.%$text%,title_en.ilike.%$text%')
        .limit(20);
    final lessons = await _client
        .from('lessons')
        .select('id, title_fr, title_en')
        .eq('is_published', true)
        .or('title_fr.ilike.%$text%,title_en.ilike.%$text%')
        .limit(20);

    return [
      ...exams.map(
        (row) => SearchResult(
          id: row['id'] as String,
          title: row['name_fr'] as String,
          subtitle: row['name_en'] as String,
          type: SearchResultType.exam,
        ),
      ),
      ...classes.map(
        (row) => SearchResult(
          id: row['id'] as String,
          title: row['display_name'] as String,
          subtitle: row['name'] as String,
          type: SearchResultType.classItem,
        ),
      ),
      ...subjects.map(
        (row) => SearchResult(
          id: row['id'] as String,
          title: row['name_fr'] as String,
          subtitle: row['name_en'] as String,
          type: SearchResultType.subject,
        ),
      ),
      ...courses.map(
        (row) => SearchResult(
          id: row['id'] as String,
          title: row['title_fr'] as String,
          subtitle: row['title_en'] as String,
          type: SearchResultType.course,
        ),
      ),
      ...lessons.map(
        (row) => SearchResult(
          id: row['id'] as String,
          title: row['title_fr'] as String,
          subtitle: row['title_en'] as String,
          type: SearchResultType.lesson,
        ),
      ),
    ];
  }
}
