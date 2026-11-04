import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// Affiche un texte de cours ou une réponse de l'IA avec :
///  - formules LaTeX : `$...$` (dans la ligne) et `$$...$$` (centrées) ;
///  - mise en forme simple : `## Titre`, `**gras**`, listes `-`, `*`, `1.`.
///
/// Un texte sans aucune de ces marques s'affiche comme un paragraphe normal,
/// donc les anciens cours ne changent pas d'apparence.
/// Si une formule est invalide, elle est affichée telle quelle (pas de plantage).
class RichLessonText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final bool selectable;

  const RichLessonText({
    super.key,
    required this.text,
    this.style = const TextStyle(
      fontSize: 16,
      height: 1.65,
      color: Color(0xFF334155),
    ),
    this.selectable = true,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(_normalize(text));
    final children = <Widget>[];

    for (final block in blocks) {
      switch (block.kind) {
        case _BlockKind.displayMath:
          children.add(_buildDisplayMath(block.text));
        case _BlockKind.table:
          children.add(_buildTable(block.text));
        case _BlockKind.heading:
          children.add(
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Text.rich(
                TextSpan(
                  children: _inlineSpans(
                    block.text,
                    style.copyWith(
                      fontSize: (style.fontSize ?? 16) + 2,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF166534),
                    ),
                  ),
                ),
              ),
            ),
          );
        case _BlockKind.bullet:
          children.add(_buildListItem('•', block.text));
        case _BlockKind.numbered:
          children.add(_buildListItem(block.marker, block.text));
        case _BlockKind.paragraph:
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text.rich(
                TextSpan(children: _inlineSpans(block.text, style)),
              ),
            ),
          );
      }
    }

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );

    return selectable ? SelectionArea(child: column) : column;
  }

  Widget _buildDisplayMath(String tex) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(
          tex,
          mathStyle: MathStyle.display,
          textStyle: style.copyWith(fontSize: (style.fontSize ?? 16) + 1),
          onErrorFallback: (_) => Text(tex, style: style),
        ),
      ),
    );
  }

  Widget _buildListItem(String marker, String content) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text(marker, style: style.copyWith(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Text.rich(TextSpan(children: _inlineSpans(content, style))),
          ),
        ],
      ),
    );
  }

  /// Convertit `\( \)` et `\[ \]` (souvent produits par l'IA) en `$` / `$$`.
  static String _normalize(String raw) {
    return raw
        .replaceAll('\r\n', '\n')
        .replaceAll(r'\[', r'$$')
        .replaceAll(r'\]', r'$$')
        .replaceAll(r'\(', r'$')
        .replaceAll(r'\)', r'$');
  }

  static List<_Block> _parseBlocks(String input) {
    final blocks = <_Block>[];
    final lines = input.split('\n');
    final paragraph = StringBuffer();

    void flushParagraph() {
      final value = paragraph.toString().trim();
      if (value.isNotEmpty) {
        blocks.add(_Block(_BlockKind.paragraph, value));
      }
      paragraph.clear();
    }

    var index = 0;
    while (index < lines.length) {
      final line = lines[index];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        flushParagraph();
        index++;
        continue;
      }

      // Tableau Markdown : ligne d'en-tête, séparateur, puis lignes de données.
      if (_isMarkdownTableStart(lines, index)) {
        flushParagraph();
        final tableLines = <String>[trimmed];
        index += 2; // en-tête + séparateur
        while (index < lines.length && _isMarkdownTableRow(lines[index].trim())) {
          tableLines.add(lines[index].trim());
          index++;
        }
        blocks.add(_Block(_BlockKind.table, tableLines.join('\n')));
        continue;
      }

      // Formule centrée : $ ... $ (sur une ou plusieurs lignes).
      if (trimmed.startsWith(r'$$')) {
        flushParagraph();
        var body = trimmed.substring(2);
        if (body.endsWith(r'$$') && body.length >= 2) {
          body = body.substring(0, body.length - 2);
          index++;
        } else {
          final buffer = StringBuffer(body);
          index++;
          while (index < lines.length) {
            final next = lines[index].trim();
            index++;
            if (next.endsWith(r'$$')) {
              buffer.write(' ${next.substring(0, next.length - 2)}');
              break;
            }
            buffer.write(' $next');
          }
          body = buffer.toString();
        }
        final tex = body.trim();
        if (tex.isNotEmpty) {
          blocks.add(_Block(_BlockKind.displayMath, tex));
        }
        continue;
      }

      final heading = RegExp(r'^#{1,4}\s+(.+)$').firstMatch(trimmed);
      if (heading != null) {
        flushParagraph();
        blocks.add(_Block(_BlockKind.heading, heading.group(1)!.trim()));
        index++;
        continue;
      }

      final bullet = RegExp(r'^[-*•]\s+(.+)$').firstMatch(trimmed);
      if (bullet != null) {
        flushParagraph();
        blocks.add(_Block(_BlockKind.bullet, bullet.group(1)!.trim()));
        index++;
        continue;
      }

      final numbered = RegExp(r'^(\d{1,2}[.)])\s+(.+)$').firstMatch(trimmed);
      if (numbered != null) {
        flushParagraph();
        blocks.add(
          _Block(
            _BlockKind.numbered,
            numbered.group(2)!.trim(),
            marker: numbered.group(1)!,
          ),
        );
        index++;
        continue;
      }

      if (paragraph.isNotEmpty) {
        paragraph.write('\n');
      }
      paragraph.write(trimmed);
      index++;
    }
    flushParagraph();
    return blocks;
  }

  bool _isMarkdownTableStart(List<String> lines, int index) {
    if (index + 1 >= lines.length) return false;
    final header = lines[index].trim();
    final separator = lines[index + 1].trim();
    return _isMarkdownTableRow(header) &&
        _isMarkdownTableRow(separator) &&
        RegExp(r'^[|:\\-\\s]+
  List<InlineSpan> _inlineSpans(String rawInput, TextStyle base) {
    final spans = <InlineSpan>[];
    // Une formule $$...$$ au milieu d'une phrase est traitée comme $...$.
    final input = rawInput.replaceAllMapped(
      RegExp(r'\$\$(.+?)\$\$'),
      (match) => '\$${match.group(1)}\$',
    );
    // $formule$ : pas d'espace juste après le premier $ ni juste avant le
    // dernier, pour ne pas confondre avec un prix ("5 $ ... 7 $").
    final pattern = RegExp(r'\$(?!\s)([^$\n]+?)(?<!\s)\$|\*\*(.+?)\*\*');
    var cursor = 0;

    for (final match in pattern.allMatches(input)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: input.substring(cursor, match.start), style: base));
      }
      final tex = match.group(1);
      final bold = match.group(2);
      if (tex != null) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Math.tex(
              tex,
              mathStyle: MathStyle.text,
              textStyle: base,
              onErrorFallback: (_) => Text(tex, style: base),
            ),
          ),
        );
      } else if (bold != null) {
        spans.add(
          TextSpan(
            text: bold,
            style: base.copyWith(fontWeight: FontWeight.w800),
          ),
        );
      }
      cursor = match.end;
    }

    if (cursor < input.length) {
      spans.add(TextSpan(text: input.substring(cursor), style: base));
    }
    return spans;
  }
}

enum _BlockKind { paragraph, heading, bullet, numbered, displayMath, table }

class _Block {
  final _BlockKind kind;
  final String text;
  final String marker;

  const _Block(this.kind, this.text, {this.marker = ''});
}
).hasMatch(separator);
  }

  bool _isMarkdownTableRow(String line) =>
      line.startsWith('|') && line.endsWith('|') && line.split('|').length >= 3;

  Widget _buildTable(String rawTable) {
    final rows = rawTable.split('\n').map((line) => line
        .split('|').skip(1).take(line.split('|').length - 2)
        .map((cell) => cell.trim()).toList()).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    final columnCount = rows.map((row) => row.length)
        .fold<int>(0, (max, count) => count > max ? count : max);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFB8CBE8)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder(
              horizontalInside: BorderSide(color: const Color(0xFFD7E2F2)),
              verticalInside: BorderSide(color: const Color(0xFFD7E2F2)),
            ),
            children: List.generate(rows.length, (rowIndex) {
              final isHeader = rowIndex == 0;
              return TableRow(
                decoration: BoxDecoration(
                  color: isHeader
                      ? const Color(0xFF2457A7)
                      : rowIndex.isEven
                          ? const Color(0xFFF1F6FF)
                          : Colors.white,
                ),
                children: List.generate(columnCount, (columnIndex) {
                  final value = columnIndex < rows[rowIndex].length
                      ? rows[rowIndex][columnIndex]
                      : '';
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    child: Text(value, style: TextStyle(
                      color: isHeader ? Colors.white : const Color(0xFF263238),
                      fontWeight: isHeader ? FontWeight.w800 : FontWeight.w500,
                      fontSize: 14,
                    )),
                  );
                }),
              );
            }),
          ),
        ),
      ),
    );
  }

  /// Transforme une ligne en morceaux : texte, **gras**, formule `$...import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// Affiche un texte de cours ou une réponse de l'IA avec :
///  - formules LaTeX : `$...$` (dans la ligne) et `$$...$$` (centrées) ;
///  - mise en forme simple : `## Titre`, `**gras**`, listes `-`, `*`, `1.`.
///
/// Un texte sans aucune de ces marques s'affiche comme un paragraphe normal,
/// donc les anciens cours ne changent pas d'apparence.
/// Si une formule est invalide, elle est affichée telle quelle (pas de plantage).
class RichLessonText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final bool selectable;

  const RichLessonText({
    super.key,
    required this.text,
    this.style = const TextStyle(
      fontSize: 16,
      height: 1.65,
      color: Color(0xFF334155),
    ),
    this.selectable = true,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(_normalize(text));
    final children = <Widget>[];

    for (final block in blocks) {
      switch (block.kind) {
        case _BlockKind.displayMath:
          children.add(_buildDisplayMath(block.text));
        case _BlockKind.table:
          children.add(_buildTable(block.text));
        case _BlockKind.heading:
          children.add(
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Text.rich(
                TextSpan(
                  children: _inlineSpans(
                    block.text,
                    style.copyWith(
                      fontSize: (style.fontSize ?? 16) + 2,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF166534),
                    ),
                  ),
                ),
              ),
            ),
          );
        case _BlockKind.bullet:
          children.add(_buildListItem('•', block.text));
        case _BlockKind.numbered:
          children.add(_buildListItem(block.marker, block.text));
        case _BlockKind.paragraph:
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text.rich(
                TextSpan(children: _inlineSpans(block.text, style)),
              ),
            ),
          );
      }
    }

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );

    return selectable ? SelectionArea(child: column) : column;
  }

  Widget _buildDisplayMath(String tex) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(
          tex,
          mathStyle: MathStyle.display,
          textStyle: style.copyWith(fontSize: (style.fontSize ?? 16) + 1),
          onErrorFallback: (_) => Text(tex, style: style),
        ),
      ),
    );
  }

  Widget _buildListItem(String marker, String content) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text(marker, style: style.copyWith(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Text.rich(TextSpan(children: _inlineSpans(content, style))),
          ),
        ],
      ),
    );
  }

  /// Convertit `\( \)` et `\[ \]` (souvent produits par l'IA) en `$` / `$$`.
  static String _normalize(String raw) {
    return raw
        .replaceAll('\r\n', '\n')
        .replaceAll(r'\[', r'$$')
        .replaceAll(r'\]', r'$$')
        .replaceAll(r'\(', r'$')
        .replaceAll(r'\)', r'$');
  }

  static List<_Block> _parseBlocks(String input) {
    final blocks = <_Block>[];
    final lines = input.split('\n');
    final paragraph = StringBuffer();

    void flushParagraph() {
      final value = paragraph.toString().trim();
      if (value.isNotEmpty) {
        blocks.add(_Block(_BlockKind.paragraph, value));
      }
      paragraph.clear();
    }

    var index = 0;
    while (index < lines.length) {
      final line = lines[index];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        flushParagraph();
        index++;
        continue;
      }

      // Tableau Markdown : ligne d'en-tête, séparateur, puis lignes de données.
      if (_isMarkdownTableStart(lines, index)) {
        flushParagraph();
        final tableLines = <String>[trimmed];
        index += 2; // en-tête + séparateur
        while (index < lines.length && _isMarkdownTableRow(lines[index].trim())) {
          tableLines.add(lines[index].trim());
          index++;
        }
        blocks.add(_Block(_BlockKind.table, tableLines.join('\\n')));
        continue;
      }

      // Formule centrée : $ ... $ (sur une ou plusieurs lignes).
      if (trimmed.startsWith(r'$$')) {
        flushParagraph();
        var body = trimmed.substring(2);
        if (body.endsWith(r'$$') && body.length >= 2) {
          body = body.substring(0, body.length - 2);
          index++;
        } else {
          final buffer = StringBuffer(body);
          index++;
          while (index < lines.length) {
            final next = lines[index].trim();
            index++;
            if (next.endsWith(r'$$')) {
              buffer.write(' ${next.substring(0, next.length - 2)}');
              break;
            }
            buffer.write(' $next');
          }
          body = buffer.toString();
        }
        final tex = body.trim();
        if (tex.isNotEmpty) {
          blocks.add(_Block(_BlockKind.displayMath, tex));
        }
        continue;
      }

      final heading = RegExp(r'^#{1,4}\s+(.+)$').firstMatch(trimmed);
      if (heading != null) {
        flushParagraph();
        blocks.add(_Block(_BlockKind.heading, heading.group(1)!.trim()));
        index++;
        continue;
      }

      final bullet = RegExp(r'^[-*•]\s+(.+)$').firstMatch(trimmed);
      if (bullet != null) {
        flushParagraph();
        blocks.add(_Block(_BlockKind.bullet, bullet.group(1)!.trim()));
        index++;
        continue;
      }

      final numbered = RegExp(r'^(\d{1,2}[.)])\s+(.+)$').firstMatch(trimmed);
      if (numbered != null) {
        flushParagraph();
        blocks.add(
          _Block(
            _BlockKind.numbered,
            numbered.group(2)!.trim(),
            marker: numbered.group(1)!,
          ),
        );
        index++;
        continue;
      }

      if (paragraph.isNotEmpty) {
        paragraph.write('\n');
      }
      paragraph.write(trimmed);
      index++;
    }
    flushParagraph();
    return blocks;
  }

.
  List<InlineSpan> _inlineSpans(String rawInput, TextStyle base) {
    final spans = <InlineSpan>[];
    // Une formule $$...$$ au milieu d'une phrase est traitée comme $...$.
    final input = rawInput.replaceAllMapped(
      RegExp(r'\$\$(.+?)\$\$'),
      (match) => '\$${match.group(1)}\$',
    );
    // $formule$ : pas d'espace juste après le premier $ ni juste avant le
    // dernier, pour ne pas confondre avec un prix ("5 $ ... 7 $").
    final pattern = RegExp(r'\$(?!\s)([^$\n]+?)(?<!\s)\$|\*\*(.+?)\*\*');
    var cursor = 0;

    for (final match in pattern.allMatches(input)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: input.substring(cursor, match.start), style: base));
      }
      final tex = match.group(1);
      final bold = match.group(2);
      if (tex != null) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Math.tex(
              tex,
              mathStyle: MathStyle.text,
              textStyle: base,
              onErrorFallback: (_) => Text(tex, style: base),
            ),
          ),
        );
      } else if (bold != null) {
        spans.add(
          TextSpan(
            text: bold,
            style: base.copyWith(fontWeight: FontWeight.w800),
          ),
        );
      }
      cursor = match.end;
    }

    if (cursor < input.length) {
      spans.add(TextSpan(text: input.substring(cursor), style: base));
    }
    return spans;
  }
}

enum _BlockKind { paragraph, heading, bullet, numbered, displayMath }

class _Block {
  final _BlockKind kind;
  final String text;
  final String marker;

  const _Block(this.kind, this.text, {this.marker = ''});
}
