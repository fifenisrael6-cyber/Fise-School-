import 'package:flutter/material.dart';

/// Pagination automatique des cours au format A4.
///
/// La hauteur des paragraphes est mesurée avec TextPainter (métriques Flutter)
/// au lieu d'une limite arbitraire de caractères. Les blocs non textuels
/// conservent leur ordre de lecture.
class NotebookPagePagination {
  static const double _contentWidth = 660;
  static const double _contentHeight = 900;
  static const double _lineHeight = 1.75;

  static List<Map<String, dynamic>> expandLegacyPages(
    List<Map<String, dynamic>> pages, {
    double fontSize = 16,
    double contentWidth = _contentWidth,
    double contentHeight = _contentHeight,
  }) {
    final safeFontSize = fontSize.clamp(14.0, 30.0).toDouble();
    final result = <Map<String, dynamic>>[];

    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final pageResultStart = result.length;
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
            'page-${pageIndex + 1}';
        result.add({
          'id': '$sourceId-reflow-${result.length + 1}',
          'position': result.length + 1,
          'format': sourcePage['format'] ?? 'A4',
          'blocks': currentBlocks,
        });
        currentBlocks = <Map<String, dynamic>>[];
      }

      for (final block in blocks) {
        if (block['type'] != 'text') {
          currentBlocks.add(block);
          continue;
        }

        final french = (block['text_fr'] ?? block['text'] ?? '').toString();
        final english = (block['text_en'] ?? french).toString();
        final frenchChunks = _splitText(french, safeFontSize, contentWidth, contentHeight);
        final englishChunks = _splitText(english, safeFontSize, contentWidth, contentHeight);
        final count = frenchChunks.length > englishChunks.length
            ? frenchChunks.length
            : englishChunks.length;

        if (count <= 1) {
          if (french.trim().isNotEmpty || english.trim().isNotEmpty) {
            currentBlocks.add(block);
          }
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
      if (result.length == pageResultStart) {
        result.add({
          ...sourcePage,
          'position': result.length + 1,
          'blocks': const <Map<String, dynamic>>[],
        });
      }
    }

    return result;
  }

  static List<String> _splitText(
    String text,
    double fontSize,
    double contentWidth,
    double contentHeight,
  ) {
    if (text.trim().isEmpty) return const <String>[];

    final paragraphs = text
        .replaceAll('\r\n', '\n')
        .split(RegExp(r'\n\s*\n'));
    final pages = <String>[];
    var current = '';

    void flush() {
      if (current.trim().isNotEmpty) pages.add(current.trim());
      current = '';
    }

    for (final rawParagraph in paragraphs) {
      final paragraph = rawParagraph.trim();
      if (paragraph.isEmpty) continue;

      final candidate = current.isEmpty ? paragraph : '$current\n\n$paragraph';
      if (_fits(candidate, fontSize, contentWidth, contentHeight)) {
        current = candidate;
        continue;
      }

      flush();
      if (_fits(paragraph, fontSize, contentWidth, contentHeight)) {
        current = paragraph;
        continue;
      }

      // Long tables are split only between rows, never inside a row.
      final lines = paragraph.split('\n');
      if (lines.length > 1 && lines.any((line) => line.trimLeft().startsWith('|'))) {
        var tableChunk = '';
        for (final line in lines) {
          final next = tableChunk.isEmpty ? line : '$tableChunk\n$line';
          if (tableChunk.isNotEmpty && !_fits(next, fontSize, contentWidth, contentHeight)) {
            pages.add(tableChunk.trim());
            tableChunk = line;
          } else {
            tableChunk = next;
          }
        }
        if (tableChunk.trim().isNotEmpty) current = tableChunk.trim();
        continue;
      }

      // Split an oversized paragraph at word boundaries using actual rendered
      // line heights. A single unusually long token remains intact.
      // Keep inline and display LaTeX expressions atomic. Splitting a
      // formula between pages would make the mathematical notation invalid.
      final tokens = RegExp(r'\$\$[\s\S]*?\$\$|\$[^$\n]+\$|\S+')
          .allMatches(paragraph)
          .map((match) => match.group(0)!)
          .toList(growable: false);
      var chunk = '';
      for (final word in tokens) {
        final next = chunk.isEmpty ? word : '$chunk $word';
        if (chunk.isNotEmpty && !_fits(next, fontSize, contentWidth, contentHeight)) {
          pages.add(chunk.trim());
          chunk = word;
        } else {
          chunk = next;
        }
      }
      if (chunk.trim().isNotEmpty) current = chunk.trim();
    }

    flush();
    return pages.isEmpty ? <String>[text.trim()] : pages;
  }

  static bool _fits(
    String text,
    double fontSize,
    double contentWidth,
    double contentHeight,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, height: _lineHeight),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: contentWidth.clamp(120.0, 1200.0).toDouble());
    return painter.height <= contentHeight.clamp(120.0, 1800.0);
  }
}
