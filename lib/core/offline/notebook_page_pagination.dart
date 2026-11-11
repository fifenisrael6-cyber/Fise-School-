/// Pagination automatique des anciens textes longs lors de leur première lecture
/// en cahier. Les pages créées par l'éditeur ne sont jamais repaginées.
class NotebookPagePagination {
  static const int _baseCharactersPerPage = 2100;

  static List<Map<String, dynamic>> expandLegacyPages(
    List<Map<String, dynamic>> pages, {
    double fontSize = 16,
  }) {
    final targetCharactersPerPage = (_baseCharactersPerPage * 16 / fontSize.clamp(14, 28)).round().clamp(900, 2400);
    if (pages.length != 1 || pages.first['id'] != 'legacy-page-1') {
      return pages;
    }
    final rawBlocks = pages.first['blocks'];
    if (rawBlocks is! List || rawBlocks.length != 1 || rawBlocks.first is! Map) {
      return pages;
    }
    final block = Map<String, dynamic>.from(rawBlocks.first as Map);
    if (block['type'] != 'text') return pages;
    final french = (block['text_fr'] ?? block['text'] ?? '').toString();
    final english = (block['text_en'] ?? french).toString();
    final frenchPages = _splitText(french, targetCharactersPerPage);
    final englishPages = _splitText(english, targetCharactersPerPage);
    final count = frenchPages.length > englishPages.length
        ? frenchPages.length
        : englishPages.length;
    if (count <= 1) return pages;
    return List<Map<String, dynamic>>.generate(count, (index) {
      final fr = index < frenchPages.length ? frenchPages[index] : '';
      final en = index < englishPages.length ? englishPages[index] : '';
      return {
        'id': 'legacy-page-${index + 1}',
        'position': index + 1,
        'format': 'A4',
        'blocks': [
          if (fr.isNotEmpty || en.isNotEmpty)
            {
              'type': 'text',
              'text_fr': fr.isEmpty ? en : fr,
              'text_en': en.isEmpty ? fr : en,
            },
        ],
      };
    });
  }

  static List<String> _splitText(String text, int targetCharactersPerPage) {
    if (text.trim().isEmpty) return const <String>[];
    final paragraphs = text.split(RegExp(r'\n\s*\n'));
    final result = <String>[];
    var current = '';
    void flush() {
      if (current.trim().isNotEmpty) result.add(current.trim());
      current = '';
    }

    for (final rawParagraph in paragraphs) {
      final paragraph = rawParagraph.trim();
      if (paragraph.isEmpty) continue;
      if (paragraph.length > targetCharactersPerPage) {
        flush();
        final words = paragraph.split(RegExp(r'\s+'));
        var longChunk = '';
        for (final word in words) {
          if (longChunk.isNotEmpty &&
              longChunk.length + word.length + 1 > _targetCharactersPerPage) {
            result.add(longChunk);
            longChunk = '';
          }
          longChunk = longChunk.isEmpty ? word : '$longChunk $word';
        }
        if (longChunk.isNotEmpty) result.add(longChunk);
        continue;
      }
      if (current.isNotEmpty &&
          current.length + paragraph.length + 2 > _targetCharactersPerPage) {
        flush();
      }
      current = current.isEmpty ? paragraph : '$current\n\n$paragraph';
    }
    flush();
    return result.isEmpty ? <String>[text.trim()] : result;
  }
}
