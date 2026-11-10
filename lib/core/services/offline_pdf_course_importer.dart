import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart';

class OfflinePdfCourseImporter {
  static const int maxPages = 500;
  static const int batchSize = 10;

  Future<List<Map<String, dynamic>>> importFile(
    Uint8List bytes, {
    required void Function(int done, int total) onProgress,
  }) async {
    if (bytes.isEmpty) throw const FormatException('Le fichier PDF est vide ou illisible.');
    final pageCount = await compute(_countPdfPages, bytes);
    if (pageCount < 1) throw const FormatException('Le PDF ne contient aucune page.');
    if (pageCount > maxPages) {
      throw FormatException('Ce PDF contient $pageCount pages. La limite est de $maxPages pages.');
    }

    final blocks = <Map<String, dynamic>>[];
    final document = await pdfx.PdfDocument.openData(bytes);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      for (var start = 0; start < pageCount; start += batchSize) {
        final end = (start + batchSize).clamp(0, pageCount).toInt();
        final extracted = await compute(_extractPdfTextBatch, {
          'bytes': bytes,
          'start': start,
          'end': end,
        });
        for (var index = 0; index < extracted.length; index++) {
          final pageIndex = start + index;
          var text = (extracted[index]['text'] ?? '').toString().trim();
          final needsOcr = text.replaceAll(RegExp(r'\\s+'), '').length < 35;
          // Keep a visual copy of pages likely to contain scientific figures,
          // diagrams or scanned content. This is a full-page render, not a
          // cropped embedded-image object; the administrator chooses whether
          // to keep it in the editable course.
          final hasVisualCue = RegExp(
            r'(figure|fig\\.?|schéma|schema|diagramme|graphique|illustration|photo|image|planche)',
            caseSensitive: false,
          ).hasMatch(text) || text.length < 900;
          Uint8List? pageImage;
          if (needsOcr || hasVisualCue) {
            pageImage = await _renderPage(document, pageIndex);
            if (needsOcr && pageImage != null) {
              final directory = await getTemporaryDirectory();
              final imageFile = File('${directory.path}/fise_pdf_ocr_${pageIndex + 1}.jpg');
              await imageFile.writeAsBytes(pageImage, flush: true);
              try {
                final recognized = await recognizer.processImage(InputImage.fromFilePath(imageFile.path));
                if (recognized.text.trim().isNotEmpty) text = recognized.text.trim();
              } finally {
                if (await imageFile.exists()) await imageFile.delete();
              }
            }
          }

          final pageBlocks = _blocksFromText(text, pageIndex + 1, (extracted[index]['lines'] as List?) ?? const []);
          blocks.addAll(pageBlocks);
          // Preserve scanned pages and pages with likely scientific visuals.
          // These are optional full-page images in the preview; admins can
          // deselect or remove pages that do not contain useful illustrations.
          if (pageImage != null && (needsOcr || hasVisualCue)) {
            final compressed = _compressPage(pageImage);
            if (compressed != null) {
              blocks.add({
                'type': 'image',
                'page': pageIndex + 1,
                'data': 'data:image/jpeg;base64,${base64Encode(compressed)}',
                'label': needsOcr
                    ? 'Page scannée ${pageIndex + 1} (image de référence)'
                    : 'Page ${pageIndex + 1} (schéma/illustration à conserver si utile)',
                'selected': needsOcr && pageBlocks.isEmpty,
              });
            }
          }
        }
        onProgress(end, pageCount);
      }
      return _removeRepeatedPageHeaders(blocks);
    } on Exception catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('password') || message.contains('encrypt')) {
        throw const FormatException('Ce PDF est protégé par mot de passe. Déverrouillez-le puis réessayez.');
      }
      if (e is FormatException) rethrow;
      throw FormatException('PDF corrompu ou impossible à lire : $e');
    } finally {
      await recognizer.close();
      await document.close();
    }
  }

  Future<Uint8List?> _renderPage(pdfx.PdfDocument document, int index) async {
    pdfx.PdfPage? page;
    try {
      page = await document.getPage(index + 1);
      final rendered = await page.render(
        width: (page.width * (1000 / page.width).clamp(0.5, 1.0)).toDouble(),
        height: (page.height * (1000 / page.width).clamp(0.5, 1.0)).toDouble(),
        format: pdfx.PdfPageImageFormat.jpeg,
        quality: 70,
      );
      return rendered?.bytes;
    } catch (_) {
      return null;
    } finally {
      await page?.close();
    }
  }

  Uint8List? _compressPage(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final resized = decoded.width > 1000
        ? img.copyResize(decoded, width: 1000)
        : decoded;
    return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
  }

  List<Map<String, dynamic>> _blocksFromText(String text, int page, List<dynamic> lineMetadata) {
    final result = <Map<String, dynamic>>[];
    final lines = text.split(RegExp(r'\r?\n'));
    final sizes = lineMetadata.whereType<Map>()
        .map((line) => (line['fontSize'] as num?)?.toDouble() ?? 0)
        .where((size) => size > 0).toList()..sort();
    final medianFont = sizes.isEmpty ? 0.0 : sizes[sizes.length ~/ 2];
    final fontByText = <String, double>{
      for (final line in lineMetadata.whereType<Map>())
        (line['text']?.toString().trim() ?? ''):
            (line['fontSize'] as num?)?.toDouble() ?? 0,
    };
    final buffer = <String>[];
    final tableRows = <List<String>>[];
    void flushTable() {
      if (tableRows.length >= 2) {
        result.add({
          'type': 'table',
          'cells': tableRows.map((row) => List<String>.from(row)).toList(),
          'firstRowHeader': true,
          'page': page,
          'selected': true,
        });
      } else if (tableRows.isNotEmpty) {
        buffer.add(tableRows.first.join(' '));
      }
      tableRows.clear();
    }
    List<String>? splitColumns(String value) {
      final parts = value.split(RegExp(r'\t|\s{2,}')).map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
      return parts.length >= 2 ? parts : null;
    }
    void flush() {
      final value = buffer.join(' ').trim();
      if (value.isNotEmpty) {
        result.add({'type': 'paragraph', 'text': value, 'page': page, 'selected': true});
      }
      buffer.clear();
    }

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) {
        flushTable();
        flush();
        continue;
      }
      final columns = splitColumns(raw);
      if (columns != null) {
        if (tableRows.isEmpty) flush();
        final sameWidth = tableRows.isEmpty || tableRows.first.length == columns.length;
        if (!sameWidth) {
          flushTable();
          flush();
        }
        tableRows.add(columns);
        continue;
      } else {
        flushTable();
      }
      final bullet = RegExp(r'^(?:[•●▪◦‣–—-])\s+(.+)$').firstMatch(line);
      final numbered = RegExp(r'^(?:\d+[.)]|[a-zA-Z][.)])\s+(.+)$').firstMatch(line);
      if (bullet != null || numbered != null) {
        flush();
        result.add({
          'type': 'list',
          'text': bullet?.group(1) ?? numbered!.group(1)!,
          'ordered': numbered != null,
          'page': page,
          'selected': true,
        });
        continue;
      }
      final fontSize = fontByText[line] ?? 0;
      final fontHeading = medianFont > 0 && fontSize >= medianFont * 1.22;
      final headingLike = (fontHeading || (line.length <= 90 &&
          !line.endsWith('.') &&
          (line == line.toUpperCase() || RegExp(r'^(CHAPITRE|LEÇON|SECTION|I{1,3}[.)]|[0-9]+[.)])\b', caseSensitive: false).hasMatch(line))));
      if (headingLike) {
        flush();
        final level = fontHeading && medianFont > 0 ? (fontSize >= medianFont * 1.65 ? 1 : fontSize >= medianFont * 1.35 ? 2 : 3) : (line.length < 35 ? 1 : line.length < 65 ? 2 : 3);
        result.add({'type': 'heading', 'level': level, 'text': line, 'page': page, 'selected': true});
      } else {
        buffer.add(line);
      }
    }
    flushTable();
    flush();
    return result;
  }

  List<Map<String, dynamic>> _removeRepeatedPageHeaders(List<Map<String, dynamic>> blocks) {
    final frequency = <String, int>{};
    for (final block in blocks) {
      final text = block['text']?.toString().trim() ?? '';
      if (text.isNotEmpty && text.length < 70) {
        frequency[text] = (frequency[text] ?? 0) + 1;
      }
    }
    return blocks.where((block) {
      final text = block['text']?.toString().trim() ?? '';
      return text.isEmpty || (frequency[text] ?? 0) < 3;
    }).toList();
  }
}

int _countPdfPages(Uint8List bytes) {
  final document = PdfDocument(inputBytes: bytes);
  try {
    return document.pages.count;
  } finally {
    document.dispose();
  }
}

List<Map<String, dynamic>> _extractPdfTextBatch(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final start = args['start'] as int;
  final end = args['end'] as int;
  final document = PdfDocument(inputBytes: bytes);
  try {
    final extractor = PdfTextExtractor(document);
    final result = <Map<String, dynamic>>[];
    for (var page = start; page < end; page++) {
      final text = extractor.extractText(startPageIndex: page, endPageIndex: page);
      final lines = extractor.extractTextLines(startPageIndex: page, endPageIndex: page);
      result.add({
        'page': page + 1,
        'text': text,
        'lines': lines.map((line) => {
          'text': line.text,
          'fontSize': line.fontSize,
          'left': line.bounds.left,
          'top': line.bounds.top,
        }).toList(),
      });
    }
    return result;
  } finally {
    document.dispose();
  }
}
