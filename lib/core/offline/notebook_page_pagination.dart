/// Pagination adaptative des pages de cahier.
///
/// Les blocs non textuels (images, tableaux dédiés, formules et médias)
/// restent dans le même ordre. Seuls les blocs texte trop longs sont répartis.
class NotebookPagePagination {
  static const int _baseCharactersPerPage = 2100;

  static List<Map<String, dynamic>> expandLegacyPages(
    List<Map<String, dynamic>> pages, {
    double fontSize = 16,
  }) {
    final normalizedFontSize = fontSize.clamp(14.0, 28.0);
    final targetCharactersPerPage =
        (_baseCharactersPerPage * 16 / normalizedFontSize)
            .round()
            .clamp(900, 2400);

    final result = <Map<String, dynamic>>[];

    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final sourcePage = Map<String, dynamic>.from(pages[pageIndex]);
      final rawBlocks = sourcePage['blocks'];
      final blocks = rawBlocks is List
          ? rawBlocks.whereType<Map>()
              .map((block) => Map<String, dynamic>.from(block))
              .toList()
          : <Map<String, dynamic>>[];

      var currentBlocks = <Map<String, dynamic>>[];

      void flushPage() {
        if (currentBlocks.isEmpty) return;
        final sourceId = sourcePage['id']?.toString() ??
            'page-' + (pageIndex + 1).toString();
        result.add({
          'id': sourceId + '-reflow-' + (result.length + 1).toString(),
          'position': result.length + 1,
          'format': sourcePage['format'] ?? 'A4',
          'blocks': currentBlocks,
        });
        currentBlocks = <Map<String, dynamic>>[];
      }

      for (final block in blocks) {
        if (block['type'] != 'text') {
          // Keep every non-text block anchored in its original reading order.
          currentBlocks.add(block);
          continue;
        }

        final french = (block['text_fr'] ?? block['text'] ?? '').toString();
        final english = (block['text_en'] ?? french).toString();
        final frenchChunks = _splitText(french, targetCharactersPerPage);
        final englishChunks = _splitText(english, targetCharactersPerPage);
        final count = frenchChunks.length > englishChunks.length
            ? frenchChunks.length
            : englishChunks.length;

        if (count <= 1) {
          currentBlocks.add(block);
          continue;
        }

        for (var chunkIndex = 0; chunkIndex < count; chunkIndex++) {
          if (chunkIndex > 0) flushPage();
          final fr = chunkIndex < frenchChunks.length
              ? frenchChunks[chunkIndex]
              : '';
          final en = chunkIndex < englishChunks.length
              ? englishChunks[chunkIndex]
              : '';
          currentBlocks.add({
            ...block,
            'text_fr': fr.isEmpty ? en : fr,
            'text_en': en.isEmpty ? fr : en,
          });
        }
      }

      flushPage();
      if (blocks.isEmpty) {
        result.add({
          ...sourcePage,
          'position': result.length + 1,
          'blocks': const <Map<String, dynamic>>[],
        });
      }
    }

    return result;
  }

  static List<String> _splitText(String text, int targetCharactersPerPage) {
    if (text.trim().isEmpty) return const <String>[];

    final paragraphs = text
        .replaceAll('\r\n', '\n')
        .split(RegExp(r'\n\s*\n'));
    final result = <String>[];
    var current = '';

    void flush() {
      if (current.trim().isNotEmpty) result.add(current.trim());
      current = '';
    }

    for (final rawParagraph in paragraphs) {
      final paragraph = rawParagraph.trim();
      if (paragraph.isEmpty) continue;

      // Keep mathematical expressions and Markdown tables intact.
      final containsMath = paragraph.contains(String.fromCharCode(36)) ||
          paragraph.contains(r'\(') ||
          paragraph.contains(r'\[') ||
          paragraph.contains(r'\begin{');
      final containsTable = paragraph
          .split('\n')
          .any((line) => line.trimLeft().startsWith('|'));

      if (paragraph.length > targetCharactersPerPage &&
          !containsMath &&
          !containsTable) {
        flush();
        final words = paragraph.split(RegExp(r'\s+'));
        var longChunk = '';
        for (final word in words) {
          if (longChunk.isNotEmpty &&
              longChunk.length + word.length + 1 > targetCharactersPerPage) {
            result.add(longChunk);
            longChunk = '';
          }
          longChunk = longChunk.isEmpty ? word : '$longChunk $word';
        }
        if (longChunk.isNotEmpty) result.add(longChunk);
        continue;
      }

      if (current.isNotEmpty &&
          current.length + paragraph.length + 2 > targetCharactersPerPage) {
        flush();
      }
      current = current.isEmpty ? paragraph : '$current\n\n$paragraph';
    }

    flush();
    return result.isEmpty ? <String>[text.trim()] : result;
  }
}
