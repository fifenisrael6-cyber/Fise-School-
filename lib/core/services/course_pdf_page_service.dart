import 'dart:typed_data';

import 'package:pdfx/pdfx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Converts an administrator-selected course PDF into private PNG pages.
/// The source PDF remains untouched in its original Storage bucket.
class CoursePdfPageService {
  CoursePdfPageService(this._client);

  final SupabaseClient _client;
  static const String _defaultSourceBucket = 'chapter-content';
  static const String _pagesBucket = 'course-pages';

  Future<int> regenerate(Map<String, dynamic> course) async {
    final courseId = (course['course_id'] ?? course['id'])?.toString() ?? '';
    final sourcePath = (course['storage_path'] ?? course['source_pdf_path'])?.toString().trim() ?? '';
    final sourceBucket = course['source_bucket']?.toString() ?? _defaultSourceBucket;
    if (courseId.isEmpty || sourcePath.isEmpty) {
      throw StateError('Le cours ne possède pas de PDF source.');
    }

    final pdfBytes = await _client.storage.from(sourceBucket).download(sourcePath);
    if (pdfBytes.length < 5 ||
        String.fromCharCodes(pdfBytes.take(5)) != '%PDF-') {
      throw const FormatException('Le fichier source téléchargé ne possède pas une signature PDF valide.');
    }

    final document = await PdfDocument.openData(Uint8List.fromList(pdfBytes));
    if (document.pagesCount <= 0) {
      await document.close();
      throw const FormatException('Le document PDF ne contient aucune page.');
    }
    final sourceStart = (course['source_page_start'] as num?)?.toInt() ?? 1;
    final sourceEnd = (course['source_page_end'] as num?)?.toInt() ?? document.pagesCount;
    if (sourceStart < 1 ||
        sourceEnd < sourceStart ||
        sourceEnd > document.pagesCount) {
      await document.close();
      throw FormatException(
        'Intervalle PDF invalide : pages ' +
            sourceStart.toString() +
            ' à ' +
            sourceEnd.toString() +
            ' sur ' +
            document.pagesCount.toString() +
            '.',
      );
    }
    final selectedPageCount = sourceEnd - sourceStart + 1;
    try {
      final generation = DateTime.now().microsecondsSinceEpoch.toString();
      final updatedAt = DateTime.now().toUtc().toIso8601String();
      final pageRows = <Map<String, dynamic>>[];

      // Render only the original pages belonging to this lesson. Store them
      // with local numbering (1..N) while retaining the original PDF untouched.
      for (var sourcePageNumber = sourceStart;
          sourcePageNumber <= sourceEnd;
          sourcePageNumber++) {
        final pageNumber = sourcePageNumber - sourceStart + 1;
        final page = await document.getPage(sourcePageNumber);
        try {
          // PDF points use 72 dpi. Rendering at 150 dpi preserves legibility.
          final rendered = await page.render(
            width: page.width * 150 / 72,
            height: page.height * 150 / 72,
            format: PdfPageImageFormat.png,
          );
          if (rendered == null || rendered.bytes.isEmpty) {
            throw StateError('Le rendu de la page $pageNumber est vide.');
          }
          final path = '$courseId/$generation/page-${pageNumber.toString().padLeft(4, '0')}.png';
          await _client.storage.from(_pagesBucket).uploadBinary(
            path,
            rendered.bytes,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: false,
            ),
          );
          pageRows.add({
            'course_id': courseId,
            'page_number': pageNumber,
            'image_url': path,
            'updated_at': updatedAt,
          });
        } finally {
          await page.close();
        }
      }

      // Publish the new page set in one database upsert. Old pages remain
      // readable if any rendering or upload step above fails.
      await _client.from('course_pages').upsert(
        pageRows,
        onConflict: 'course_id,page_number',
      );
      await _client.from('course_pages')
          .delete()
          .eq('course_id', courseId)
          .gt('page_number', selectedPageCount);
      uploaded = pageRows.length;
      return uploaded;
    } finally {
      await document.close();
    }
  }
}
