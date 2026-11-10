import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

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
    if (_isUnreadablePayload(text)) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          border: Border.all(color: const Color(0xFFFED7AA)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: Color(0xFF9A3412)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Ce contenu est illisible et doit être corrigé par l’enseignant.',
                style: TextStyle(color: Color(0xFF7C2D12), height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    final blocks = _parseBlocks(_normalize(text));
    final children = <Widget>[];

    for (final block in blocks) {
      if (block.kind == _BlockKind.displayMath) {
        children.add(_buildDisplayMath(block.text));
      } else if (block.kind == _BlockKind.table) {
        children.add(_buildTable(block.text));
      } else if (block.kind == _BlockKind.heading) {
        final headingStyle = style.copyWith(
          fontSize: (style.fontSize ?? 16) + 2,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF166534),
        );
        children.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Text.rich(
            TextSpan(children: _inlineSpans(block.text, headingStyle)),
          ),
        ));
      } else if (block.kind == _BlockKind.bullet) {
        children.add(_buildListItem('•', block.text));
      } else if (block.kind == _BlockKind.numbered) {
        children.add(_buildListItem(block.marker, block.text));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text.rich(
            TextSpan(children: _inlineSpans(block.text, style)),
          ),
        ));
      }
    }

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
    return selectable ? SelectionArea(child: column) : column;
  }

  Widget _buildDisplayMath(String source) {
    final tex = _toTex(source);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        border: Border.all(color: const Color(0xFFB8D2FA), width: 1.2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Center(
          child: Math.tex(
            tex,
            mathStyle: MathStyle.display,
            textStyle: style.copyWith(
              fontSize: (style.fontSize ?? 16) + 4,
              color: const Color(0xFF123B78),
            ),
            onErrorFallback: (_) => Text(
              'Formule à vérifier dans le cours',
              style: style.copyWith(
                color: const Color(0xFF9A3412),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _toTex(String source) {
    var value = source.trim()
        .replaceAll('→', r'\to ')
        .replaceAll('≤', r'\le ')
        .replaceAll('≥', r'\ge ')
        .replaceAll('≠', r'\ne ')
        .replaceAll('∞', r'\infty ')
        .replaceAll('×', r'\times ')
        .replaceAll('÷', r'\div ')
        .replaceAll('π', r'\pi ')
        .replaceAll('Δ', r'\Delta ')
        .replaceAll('λ', r'\lambda ')
        .replaceAll('μ', r'\mu ')
        .replaceAll('Ω', r'\Omega ')
        .replaceAll('²', r'^{2}')
        .replaceAll('³', r'^{3}')
        .replaceAll('⁴', r'^{4}')
        .replaceAll('₀', r'_{0}')
        .replaceAll('₁', r'_{1}')
        .replaceAll('₂', r'_{2}')
        .replaceAll('₃', r'_{3}')
        .replaceAll('₄', r'_{4}')
        .replaceAll('₅', r'_{5}')
        .replaceAll('₆', r'_{6}')
        .replaceAll('₇', r'_{7}')
        .replaceAll('₈', r'_{8}')
        .replaceAll('₉', r'_{9}');
    value = value.replaceAllMapped(
      RegExp(r'√\s*([A-Za-z0-9]+)'),
      (match) => r'\sqrt{' + match.group(1)! + '}',
    );
    value = value.replaceAllMapped(
      RegExp(r'([A-Za-z])([0-9]+)'),
      (match) => match.group(1)! + '_{' + match.group(2)! + '}',
    );
    return value;
  }

  static bool _isStandaloneMath(String line) {
    if (line.length > 150 || line.contains(String.fromCharCode(36))) {
      return false;
    }
    final hasMathNotation = RegExp(
      r'(\\frac|\\sqrt|\\int|\\sum|\\lim|\\prod|'
      r'\\Delta|\\theta|\\pi|[=<>≤≥≠∞→±×÷√∫∑])|'
      r'([_^]|\\to|\\infty)',
    ).hasMatch(line);
    final chemicalFormula = RegExp(
      r'^[A-Z][a-z]?[0-9]+(?:[A-Z][a-z]?[0-9]*)+$',
    ).hasMatch(line);
    if (!hasMathNotation && !chemicalFormula) return false;
    final words = RegExp(r'[A-Za-zÀ-ÿ]{3,}').allMatches(line).length;
    return words <= 5;
  }

  Widget _buildListItem(String marker, String content) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              marker,
              style: style.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(children: _inlineSpans(content, style)),
            ),
          ),
        ],
      ),
    );
  }

  static bool _isUnreadablePayload(String raw) {
    final value = raw.trimLeft();
    if (value.isEmpty) return false;
    final serializedEditorData = RegExp(
      r'^(?:\{\s*"?ops"?\s*:|\[\s*\{\s*"?insert"?\s*:)',
    ).hasMatch(value);
    final replacementCharacters =
        RegExp('\uFFFD').allMatches(raw).length;
    return serializedEditorData || replacementCharacters >= 3;
  }

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
      final trimmed = lines[index].trim();

      if (trimmed.isEmpty) {
        flushParagraph();
        index++;
        continue;
      }

      if (_isMarkdownTableStart(lines, index)) {
        flushParagraph();
        final tableLines = <String>[trimmed];
        index += 2;
        while (index < lines.length &&
            _isMarkdownTableRow(lines[index].trim())) {
          tableLines.add(lines[index].trim());
          index++;
        }
        blocks.add(_Block(_BlockKind.table, tableLines.join('\n')));
        continue;
      }

      if (_isStandaloneMath(trimmed)) {
        flushParagraph();
        blocks.add(_Block(_BlockKind.displayMath, trimmed));
        index++;
        continue;
      }

      if (trimmed.startsWith(r'$')) {
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

      // Recognize Markdown headings and the Roman-numeral / lettered
      // section titles used in traditional Cameroonian classroom notes.
      final heading = RegExp(
        r'^(?:#{1,4}\s+(.+)|([IVXLCDM]{1,6})\.\s+(.+)|([A-Z])\)\s+(.+))$',
      ).firstMatch(trimmed);
      if (heading != null) {
        flushParagraph();
        final headingText = heading.group(1) ??
            (heading.group(2) != null
                ? '${heading.group(2)}. ${heading.group(3)}'
                : '${heading.group(4)}) ${heading.group(5)}');
        blocks.add(_Block(_BlockKind.heading, headingText.trim()));
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

      final numbered = RegExp(r'^(\d{1,2}[.)])\s+(.+)$')
          .firstMatch(trimmed);
      if (numbered != null) {
        flushParagraph();
        blocks.add(_Block(
          _BlockKind.numbered,
          numbered.group(2)!.trim(),
          marker: numbered.group(1)!,
        ));
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

  static bool _isMarkdownTableStart(List<String> lines, int index) {
    if (index + 1 >= lines.length) return false;
    final header = lines[index].trim();
    final separator = lines[index + 1].trim();
    return _isMarkdownTableRow(header) &&
        _isMarkdownTableRow(separator) &&
        RegExp(r'^\|?[\s:|\-]+\|?$').hasMatch(separator);
  }

  static bool _isMarkdownTableRow(String line) {
    return line.startsWith('|') &&
        line.endsWith('|') &&
        line.split('|').length >= 3;
  }

  Widget _buildTable(String rawTable) {
    final rows = rawTable.split('\n').map((line) {
      final cells = line.split('|');
      return cells
          .skip(1)
          .take(cells.length - 2)
          .map((cell) => cell.trim())
          .toList();
    }).toList();

    if (rows.isEmpty) return const SizedBox.shrink();
    final columnCount = rows.fold<int>(
      0,
      (maximum, row) => row.length > maximum ? row.length : maximum,
    );
    if (columnCount == 0) return const SizedBox.shrink();

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
              horizontalInside:
                  const BorderSide(color: Color(0xFFD7E2F2)),
              verticalInside:
                  const BorderSide(color: Color(0xFFD7E2F2)),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    child: Text(
                      value,
                      style: TextStyle(
                        color: isHeader
                            ? Colors.white
                            : const Color(0xFF263238),
                        fontWeight:
                            isHeader ? FontWeight.w800 : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  );
                }),
              );
            }),
          ),
        ),
      ),
    );
  }

  List<InlineSpan> _inlineSpans(String rawInput, TextStyle base) {
    final spans = <InlineSpan>[];
    final input = rawInput.replaceAllMapped(
      RegExp(r'\$\$(.+?)\$\$'),
      (match) => r'$' + match.group(1)! + r'$',
    );
    final pattern =
        RegExp(r'\$(?!\s)([^$\n]+?)(?<!\s)\$|\*\*(.+?)\*\*');

    var cursor = 0;
    for (final match in pattern.allMatches(input)) {
      if (match.start > cursor) {
        spans.add(TextSpan(
          text: input.substring(cursor, match.start),
          style: base,
        ));
      }

      final tex = match.group(1);
      final bold = match.group(2);
      if (tex != null) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Math.tex(
            tex,
            mathStyle: MathStyle.text,
            textStyle: base,
            onErrorFallback: (_) => Text(tex, style: base),
          ),
        ));
      } else if (bold != null) {
        spans.add(TextSpan(
          text: bold,
          style: base.copyWith(fontWeight: FontWeight.w800),
        ));
      }
      cursor = match.end;
    }

    if (cursor < input.length) {
      spans.add(TextSpan(text: input.substring(cursor), style: base));
    }
    return spans;
  }
}

enum _BlockKind {
  paragraph,
  heading,
  bullet,
  numbered,
  displayMath,
  table,
}

class _Block {
  final _BlockKind kind;
  final String text;
  final String marker;

  const _Block(this.kind, this.text, {this.marker = ''});
}