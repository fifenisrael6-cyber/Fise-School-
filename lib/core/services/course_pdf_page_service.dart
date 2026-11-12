import 'dart:typed_data';

import 'package:pdfx/pdfx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Converts an administrator-selected chapter PDF into private PNG pages.
/// The original PDF remains untouched in the chapter-content bucket.
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
    var uploaded = 0;
    try {
      for (var pageNumber = 1; pageNumber <= document.pagesCount; pageNumber++) {
        final page = await document.getPage(pageNumber);
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
          final path = '$courseId/page-${pageNumber.toString().padLeft(4, '0')}.png';
          await _client.storage.from(_pagesBucket).uploadBinary(
            path,
            rendered.bytes,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: true,
            ),
          );
          await _client.from('course_pages').upsert({
            'course_id': courseId,
            'page_number': pageNumber,
            // Private bucket object path, not a short-lived signed URL.
            'image_url': path,
          }, onConflict: 'course_id,page_number');
          uploaded++;
        } finally {
          await page.close();
        }
      }
      await _client.from('course_pages')
          .delete()
          .eq('course_id', courseId)
          .gt('page_number', document.pagesCount);
      return uploaded;
    } finally {
      await document.close();
    }
  }
}
