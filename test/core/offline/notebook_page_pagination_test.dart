import 'package:flutter_test/flutter_test.dart';
import 'package:fise_school/core/offline/notebook_page_pagination.dart';

void main() {
  group('NotebookPagePagination', () {
    test('reflows manually created text pages for larger font sizes', () {
      final text = List<String>.generate(
        8,
        (index) => 'Paragraphe ${index + 1}. ' + List<String>.filled(35, 'chimie').join(' '),
      ).join('\n\n');
      final source = [
        {
          'id': 'page-1',
          'position': 1,
          'format': 'A4',
          'blocks': [
            {'type': 'text', 'text_fr': text, 'text_en': text},
          ],
        },
      ];

      final small = NotebookPagePagination.expandLegacyPages(source, fontSize: 14);
      final large = NotebookPagePagination.expandLegacyPages(source, fontSize: 28);

      expect(large.length, greaterThan(small.length));
      expect(
        large.map((page) => (page['blocks'] as List).first['text_fr']).join('\n\n'),
        contains('Paragraphe 1.'),
      );
      expect(
        large.map((page) => (page['blocks'] as List).first['text_fr']).join(' '),
        contains('Paragraphe 8.'),
      );
    });

    test('keeps equations, tables and images in reading order', () {
      final source = [
        {
          'id': 'manual-page',
          'position': 1,
          'format': 'A4',
          'blocks': [
            {'type': 'text', 'text_fr': r'$$H_3O^+$$', 'text_en': r'$$H_3O^+$$'},
            {'type': 'table', 'rows': [['Acide', 'Base']]},
            {'type': 'image', 'storage_path': 'chapter/image.png'},
          ],
        },
      ];

      final pages = NotebookPagePagination.expandLegacyPages(source, fontSize: 28);
      final blocks = pages.expand((page) => page['blocks'] as List).toList();

      expect(blocks.map((block) => block['type']).toList(),
          ['text', 'table', 'image']);
      expect(blocks.last['storage_path'], 'chapter/image.png');
    });
  });
}
