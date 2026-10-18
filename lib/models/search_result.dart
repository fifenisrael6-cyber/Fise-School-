enum SearchResultType { exam, classItem, subject, course, lesson }

class SearchResult {
  final String id;
  final String title;
  final String? subtitle;
  final SearchResultType type;

  const SearchResult({
    required this.id,
    required this.title,
    required this.type,
    this.subtitle,
  });
}
