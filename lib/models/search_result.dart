enum SearchResultType {
  exam,
  classItem,
  subject,
  course,
  lesson,
  chapter,
  chapterContent,
  resource,
  fileContent,
  pastPaper,
  assignment,
  forum,
}

class SearchResult {
  final String id;
  final String title;
  final String? subtitle;

  /// Extrait du texte où le mot recherché a été trouvé.
  final String? snippet;
  final SearchResultType type;

  /// Cours parent (pour ouvrir un cours, une leçon ou un fichier).
  final String? courseId;
  final String? lessonId;
  final int score;

  const SearchResult({
    required this.id,
    required this.title,
    required this.type,
    this.subtitle,
    this.snippet,
    this.courseId,
    this.lessonId,
    this.score = 0,
  });
}
