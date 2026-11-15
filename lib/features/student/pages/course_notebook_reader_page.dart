import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/offline/app_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdfx/pdfx.dart';

import '../../../core/widgets/rich_lesson_text.dart';
import '../../../core/widgets/lesson_content_renderer.dart';
import '../../../core/offline/notebook_image_cache.dart';
import '../../../core/offline/notebook_page_pagination.dart';
import '../../../models/chapter_learning_content.dart';
import '../../../core/services/chapter_learning_service.dart';

/// Palette commune au lecteur, indépendante des couleurs générales de l'application.
abstract final class CourseReaderTheme {
  static const navy = Color(0xFF17365D);
  static const blue = Color(0xFF2476D2);
  static const paleBlue = Color(0xFFEAF3FF);
  static const paleGreen = Color(0xFFEAF7EF);
  static const text = Color(0xFF1E293B);
  static const border = Color(0xFFB9D7FA);
}

/// Lecteur de cahier : une page indépendante à la fois, avec navigation horizontale.
class CourseNotebookReaderPage extends StatefulWidget {
  const CourseNotebookReaderPage({
    super.key,
    required this.item,
    required this.locale,
  });

  final ChapterLearningContentItem item;
  final Locale locale;

  @override
  State<CourseNotebookReaderPage> createState() => _CourseNotebookReaderPageState();
}

class _CourseNotebookReaderPageState extends State<CourseNotebookReaderPage> {
  final PageController _controller = PageController();
  int _index = 0;
  double _fontSize = 18;
  bool _isFullscreen = false;
  final AppDatabase _localDb = AppDatabase();
  String? _userId;
  List<Map<String, dynamic>> _pdfPages = const [];
  final Map<int, Object> _pageErrors = {};

  bool get _en => widget.locale.languageCode == 'en';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    unawaited(_initializeReader());
  }

  Future<void> _initializeReader() async {
    await _restoreReaderState();
    await _loadCoursePages();
  }

  Future<void> _restoreReaderState() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    _userId = userId;
    if (userId == null) return;
    try {
      final saved = await _localDb.getCourseReaderState(userId, widget.item.id);
      if (!mounted || saved == null) return;
      final savedSize = (saved['font_size'] as num?)?.toDouble() ?? 18;
      final savedPage = (saved['page_number'] as num?)?.toInt() ?? 0;
      final target = savedPage.clamp(0, _pages.length - 1).toInt();
      setState(() => _fontSize = savedSize.clamp(16, 30).toDouble());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) {
          _controller.jumpToPage(target);
          setState(() => _index = target);
        }
      });
    } catch (_) {
      // A local preference read failure must not prevent course reading.
    }
  }

  /// Keep editable lesson blocks as the primary source. Raster PDF pages are
  /// used only when no structured lesson text/blocks are available.
  List<Map<String, dynamic>> get _structuredPages {
    final result = <Map<String, dynamic>>[];
    for (final page in widget.item.pages) {
      final raw = page['blocks'];
      if (raw is! List) continue;
      final blocks = raw.whereType<Map>().map((value) {
        return Map<String, dynamic>.from(value);
      }).where((block) {
        final type = (block['type'] ?? '').toString().toLowerCase();
        return type != 'raster' &&
            type != 'raster-pending' &&
            type != 'raster-error';
      }).toList(growable: false);
      if (blocks.isNotEmpty) {
        result.add({...page, 'blocks': blocks});
      }
    }
    return result;
  }

  bool get _hasStructuredContent {
    if (_structuredPages.isNotEmpty) return true;
    return (widget.item.bodyFor('fr') ?? '').trim().isNotEmpty ||
        (widget.item.bodyFor('en') ?? '').trim().isNotEmpty;
  }

  Future<void> _loadCoursePages({bool forceRetry = false}) async {
    // Structured pages are the primary representation for every subject and
    // chapter. Raster pages are only a safety fallback for legacy/unparsed files.
    if (_hasStructuredContent) return;
    final hasPdfSource = (widget.item.sourcePdfPath ?? '').trim().isNotEmpty;
    if (widget.item.pageCourseId == null && !hasPdfSource) return;
    final userId = _userId ?? Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final pageCourseId = widget.item.pageCourseId ?? widget.item.id;

    try {
      var remoteAvailable = false;
      var rows = <Map<String, dynamic>>[];
      try {
        final remoteRows = await Supabase.instance.client
            .from('course_pages')
            .select('page_number,image_url,updated_at')
            .eq('course_id', pageCourseId)
            .order('page_number');
        rows = remoteRows
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
        remoteAvailable = true;
      } catch (_) {
        // Drift is the offline source of truth when Supabase cannot be reached.
      }

      final cachedRows = await _localDb.getCachedCoursePages(userId, pageCourseId);
      if (rows.isEmpty && cachedRows.isNotEmpty) {
        rows = cachedRows;
        remoteAvailable = false;
      }

      if (rows.isEmpty) {
        if (hasPdfSource) {
          await _renderOriginalPagesFromLocalSource(pageCourseId, userId);
          return;
        }
        if (!mounted) return;
        setState(() => _pdfPages = [
          {
            'id': 'course-pages-pending',
            'position': 1,
            'blocks': [{'type': 'raster-pending'}],
          },
        ]);
        return;
      }

      final pages = <Map<String, dynamic>>[];
      for (final row in rows) {
        final number = (row['page_number'] as num).toInt();
        final path = row['image_url']?.toString() ?? '';
        final sourceUpdatedAt = (row['updated_at'] ?? row['source_updated_at'])?.toString();
        Uint8List? bytes;
        try {
          if (!forceRetry || !remoteAvailable) {
            bytes = await _localDb.getCachedCoursePageImage(userId, pageCourseId, number);
            if (bytes != null && remoteAvailable && sourceUpdatedAt != null) {
              final cachedVersion = await _localDb.getCachedCoursePageImageUpdatedAt(
                userId, pageCourseId, number,
              );
              if (cachedVersion != sourceUpdatedAt) bytes = null;
            }
          }
          if (bytes == null && remoteAvailable && path.isNotEmpty) {
            try {
              bytes = await Supabase.instance.client.storage
                  .from('course-pages').download(path);
            } catch (_) {
              // One automatic retry for a temporary storage/network failure.
              bytes = await Supabase.instance.client.storage
                  .from('course-pages').download(path);
            }
            await _localDb.cacheCoursePageImage(
              userId: userId,
              courseId: pageCourseId,
              pageNumber: number,
              bytes: bytes,
              sourceUpdatedAt: sourceUpdatedAt,
            );
          }
          if (bytes == null || bytes.isEmpty) {
            throw StateError('Image de la page $number indisponible.');
          }
          pages.add({
            'id': 'pdf-page-$number',
            'position': number,
            'blocks': [{'type': 'raster', 'bytes': bytes}],
          });
          _pageErrors.remove(number);
        } catch (error) {
          _pageErrors[number] = error;
          pages.add({
            'id': 'pdf-page-$number',
            'position': number,
            'blocks': [{'type': 'raster-error', 'page_number': number}],
          });
        }
      }

      if (!mounted) return;
      setState(() => _pdfPages = pages);
      final saved = await _localDb.getCourseReaderState(userId, widget.item.id);
      final page = ((saved?['page_number'] as num?)?.toInt() ?? 0)
          .clamp(0, pages.length - 1)
          .toInt();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) {
          _controller.jumpToPage(page);
          setState(() => _index = page);
        }
      });
    } catch (error) {
      final expectsRasterPages = widget.item.pageCourseId != null ||
          (widget.item.sourcePdfPath ?? '').trim().isNotEmpty;
      if (!expectsRasterPages || !mounted) return;
      setState(() => _pdfPages = [
        {
          'id': 'course-pages-load-error',
          'position': 1,
          'blocks': [
            {'type': 'raster-pending', 'message': error.toString()},
          ],
        },
      ]);
    }
  }

  Future<void> _renderOriginalPagesFromLocalSource(
    String pageCourseId,
    String userId,
  ) async {
    PdfDocument? document;
    try {
      final sourceBytes = await ChapterLearningService()
          .loadOriginalPdfBytes(widget.item);
      document = await PdfDocument.openData(sourceBytes);
      final first = (widget.item.sourcePageStart ?? 1)
          .clamp(1, document.pagesCount).toInt();
      final last = (widget.item.sourcePageEnd ?? document.pagesCount)
          .clamp(first, document.pagesCount).toInt();
      final pages = <Map<String, dynamic>>[];
      for (var sourceNumber = first; sourceNumber <= last; sourceNumber++) {
        final pageNumber = sourceNumber - first + 1;
        final page = await document.getPage(sourceNumber);
        try {
          final rendered = await page.render(
            width: page.width * 120 / 72,
            height: page.height * 120 / 72,
            format: PdfPageImageFormat.png,
          );
          if (rendered == null || rendered.bytes.isEmpty) {
            throw StateError('Page image unavailable');
          }
          final bytes = rendered.bytes;
          await _localDb.cacheCoursePageImage(
            userId: userId,
            courseId: pageCourseId,
            pageNumber: pageNumber,
            bytes: bytes,
            sourceUpdatedAt: null,
          );
          pages.add({
            'id': 'source-page-$pageNumber',
            'position': pageNumber,
            'blocks': [{'type': 'raster', 'bytes': bytes}],
          });
        } finally {
          await page.close();
        }
      }
      if (mounted && pages.isNotEmpty) {
        setState(() => _pdfPages = pages);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _pdfPages = [
        {
          'id': 'course-pages-pending',
          'position': 1,
          'blocks': [{'type': 'raster-pending'}],
        },
      ]);
    } finally {
      await document?.close();
    }
  }

  Future<void> _retryCoursePage(int pageNumber) async {
    try {
      final userId = _userId ?? Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw StateError('Session utilisateur absente.');
      final pageCourseId = widget.item.pageCourseId ?? widget.item.id;
      final rows = await Supabase.instance.client
          .from('course_pages')
          .select('image_url,updated_at')
          .eq('course_id', pageCourseId)
          .eq('page_number', pageNumber)
          .limit(1);
      if (rows.isEmpty) throw StateError('Page introuvable.');
      final path = rows.first['image_url'].toString();
      final bytes = await Supabase.instance.client.storage
          .from('course-pages').download(path);
      await _localDb.cacheCoursePageImage(
        userId: userId,
        courseId: pageCourseId,
        pageNumber: pageNumber,
        bytes: bytes,
        sourceUpdatedAt: rows.first['updated_at']?.toString(),
      );
      if (!mounted) return;
      setState(() {
        _pageErrors.remove(pageNumber);
        final index = _pdfPages.indexWhere((p) => p['position'] == pageNumber);
        if (index >= 0) {
          _pdfPages[index] = {
            'id': 'pdf-page-$pageNumber',
            'position': pageNumber,
            'blocks': [{'type': 'raster', 'bytes': bytes}],
          };
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _pageErrors[pageNumber] = error);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_en ? 'Page retry failed: $error' : 'Nouvel essai impossible : $error'),
      ));
    }
  }

  Future<void> _saveReaderState() async {
    final userId = _userId ?? Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _localDb.saveCourseReaderState(
        userId: userId,
        courseId: widget.item.id,
        pageNumber: _index,
        fontSize: _fontSize,
      );
    } catch (_) {
      // The current reading session remains usable if local persistence fails.
    }
  }

  Future<void> _showFontControls() async {
    var selected = _fontSize;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, updateSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_en ? 'Text size' : 'Taille du texte',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                Row(children: [
                  TextButton(onPressed: () => updateSheet(() => selected = (selected - 1).clamp(16, 30).toDouble()), child: const Text('A−')),
                  Expanded(child: Slider(
                    min: 16, max: 30, divisions: 14, value: selected,
                    label: selected.round().toString(),
                    onChanged: (value) => updateSheet(() => selected = value),
                  )),
                  TextButton(onPressed: () => updateSheet(() => selected = (selected + 1).clamp(16, 30).toDouble()), child: const Text('A+')),
                ]),
                Text('${selected.round()} pt'),
                FilledButton(
                  onPressed: () {
                    setState(() => _fontSize = selected);
                    Navigator.pop(sheetContext);
                    unawaited(_saveReaderState());
                  },
                  child: Text(_en ? 'Apply' : 'Appliquer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _looksLikeQuillDelta(String value) {
    try {
      final decoded = jsonDecode(value);
      final operations = decoded is List
          ? decoded
          : decoded is Map
              ? decoded['ops']
              : null;
      return operations is List &&
          operations.any((operation) =>
              operation is Map && operation.containsKey('insert'));
    } catch (_) {
      return false;
    }
  }

  List<Map<String, dynamic>> get _pages {
    if (_pdfPages.isNotEmpty) return _pdfPages;
    final source = _structuredPages.isNotEmpty
        ? _structuredPages
        : [
            {
              'id': 'legacy-course-content',
              'position': 1,
              'blocks': [
                {
                  'type': 'text',
                  'text_fr': widget.item.bodyFor('fr') ?? '',
                  'text_en': widget.item.bodyFor('en') ?? widget.item.bodyFor('fr') ?? '',
                },
              ],
            },
          ];
    return NotebookPagePagination.expandLegacyPages(source, fontSize: _fontSize);
  }

  Future<Object?> _resolveImage(String path) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      final cached = await NotebookImageCache.getCached(userId: userId, storagePath: path);
      if (cached != null) return cached;
      final downloaded = await NotebookImageCache.download(userId: userId, storagePath: path);
      if (downloaded != null) return downloaded;
    }
    try {
      return await Supabase.instance.client.storage.from('chapter-content').createSignedUrl(path, 900);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openImageGallery(String selectedPath) async {
    final paths = <String>[];
    for (final page in widget.item.pages) {
      final raw = page['blocks'];
      if (raw is! List) continue;
      for (final block in raw.whereType<Map>()) {
        if (block['type'] != 'image') continue;
        final path = block['storage_path']?.toString().trim() ?? '';
        if (path.isNotEmpty && !paths.contains(path)) paths.add(path);
      }
    }
    if (paths.isEmpty) paths.add(selectedPath);
    final providers = <ImageProvider<Object>>[];
    final tags = <String>[];
    for (final path in paths) {
      final resolved = await _resolveImage(path);
      if (resolved is File) {
        providers.add(FileImage(resolved));
      } else if (resolved is String) {
        providers.add(NetworkImage(resolved));
      }
      if (resolved is File || resolved is String) {
        tags.add('course-image-${widget.item.id}-$path');
      }
    }
    if (!mounted || providers.isEmpty) return;
    final selectedIndex = paths.indexOf(selectedPath).clamp(0, providers.length - 1).toInt();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _CourseImageFullscreenPage(
        images: providers,
        heroTags: tags,
        initialIndex: selectedIndex,
      ),
    ));
  }


  Widget _buildTextWithDiagrams(String value) {
    final children = <Widget>[];
    final buffer = StringBuffer();
    final token = RegExp(r'^\\[\\[diagram:([a-z0-9_]+)\\]\\]
    final rawBlocks = page['blocks'];
    final blocks = rawBlocks is List
        ? rawBlocks.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];

    Widget renderBlock(Map<String, dynamic> block) {
      final rawType = (block['type'] ?? '').toString().toLowerCase();
      final type = switch (rawType) {
        'text' || 'paragraph' || 'texte' => 'text',
        'title' || 'heading' || 'titre' => 'title',
        'section' || 'section_title' => 'section',
        'subtitle' || 'subheading' || 'sous_titre' => 'subtitle',
        'bullet' || 'list_item' || 'puce' => 'bullet',
        'key_phrase' || 'keyphrase' || 'phrase_cle' => 'key',
        'formula' || 'equation' => 'formula',
        'table' => 'table',
        'diagram' || 'schema' || 'schéma' => 'diagram',
        'image' || 'figure' => 'image',
        'raster' => 'raster',
        'quill' || 'delta' => 'quill',
        'raster-pending' || 'raster-error' => rawType,
        _ => rawType,
      };
      final text = (block[_en ? 'text_en' : 'text_fr'] ??
              block['text'] ??
              block['content'] ??
              block['label'] ??
              '').toString();
      const navy = Color(0xFF123B70);
      const paleBlue = Color(0xFFEAF3FF);
      const paleGreen = Color(0xFFEAF8EF);

      switch (type) {
        case 'title':
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(text, style: TextStyle(
              fontSize: _fontSize + 4, height: 1.2,
              fontWeight: FontWeight.w900, color: navy,
            )),
          );
        case 'section':
          return Container(
            margin: const EdgeInsets.only(top: 12, bottom: 9),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: paleBlue, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFB9D7FA)),
            ),
            child: Text(text, style: TextStyle(
              fontSize: _fontSize + 1, height: 1.25,
              fontWeight: FontWeight.w800, color: navy,
            )),
          );
        case 'subtitle':
          return Container(
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: paleGreen, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFC7E9D1)),
            ),
            child: Text(text, style: TextStyle(
              fontSize: _fontSize, height: 1.3,
              fontWeight: FontWeight.w800, color: const Color(0xFF17633B),
            )),
          );
        case 'bullet':
          return Padding(
            padding: const EdgeInsets.only(left: 5, bottom: 7),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 7, right: 9),
                child: Icon(Icons.circle, size: 7, color: Color(0xFF2476D2)),
              ),
              Expanded(child: RichLessonText(
                text: text,
                style: TextStyle(fontSize: _fontSize, height: 1.4, color: const Color(0xFF1E293B)),
              )),
            ]),
          );
        case 'key':
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: RichLessonText(
              text: text,
              style: TextStyle(fontSize: _fontSize, height: 1.4,
                fontWeight: FontWeight.w800, color: navy),
            ),
          );
        case 'formula':
          final formula = (block['latex'] ?? block['formula'] ?? text).toString();
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: paleBlue, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFB9D7FA)),
            ),
            child: Center(child: RichLessonText(
              text: formula.startsWith(r'$') ? formula : r'$$' + formula + r'$$',
              style: TextStyle(fontSize: _fontSize + 1, height: 1.5,
                fontWeight: FontWeight.w600, color: navy),
            )),
          );
        case 'table':
          final rawRows = block['rows'] ?? block['data'];
          final rows = rawRows is List ? rawRows : const [];
          final cells = rows.map((row) {
            if (row is List) return row.map((v) => v.toString()).toList();
            if (row is Map) return row.values.map((v) => v.toString()).toList();
            return <String>[row.toString()];
          }).toList();
          if (cells.isEmpty) {
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFCBD5E1))),
              child: RichLessonText(text: text, style: TextStyle(fontSize: _fontSize, height: 1.4)),
            );
          }
          final columnCount = cells.fold<int>(0, (n, row) => row.length > n ? row.length : n).clamp(1, 8);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder.all(color: const Color(0xFF9DB6D3)),
              children: [
                for (var ri = 0; ri < cells.length; ri++)
                  TableRow(
                    decoration: ri == 0 ? const BoxDecoration(color: paleBlue) : null,
                    children: [
                      for (var ci = 0; ci < columnCount; ci++)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(ci < cells[ri].length ? cells[ri][ci] : '',
                            style: TextStyle(fontSize: _fontSize - 1, height: 1.3,
                              fontWeight: ri == 0 ? FontWeight.w800 : FontWeight.w400)),
                        ),
                    ],
                  ),
              ],
            ),
          );
        case 'image' || 'diagram':
          final imagePath = (block['storage_path'] ?? block['path'] ?? '').toString();
          if (imagePath.isEmpty) return const SizedBox.shrink();
          return FutureBuilder<Object?>(
            future: _resolveImage(imagePath),
            builder: (context, snapshot) {
              final resolved = snapshot.data;
              if (resolved == null) {
                return const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final image = resolved is File
                  ? Image.file(resolved, fit: BoxFit.contain)
                  : Image.network(resolved.toString(), fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink());
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: 10),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(children: [
                  GestureDetector(
                    onTap: () => _openImageGallery(imagePath),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: image,
                    ),
                  ),
                  if ((block['caption'] ?? '').toString().trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Text(block['caption'].toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: _fontSize - 2, color: Colors.black54)),
                    ),
                ]),
              );
            },
          );
        case 'raster':
          final bytes = block['bytes'];
          if (bytes is! Uint8List) return const SizedBox.shrink();
          return GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => Dialog.fullscreen(
                child: Stack(children: [
                  Center(child: InteractiveViewer(
                    minScale: 0.7, maxScale: 5,
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  )),
                  Positioned(top: 18, right: 12, child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  )),
                ]),
              ),
            ),
            child: Image.memory(bytes, width: double.infinity, fit: BoxFit.fitWidth),
          );
        case 'raster-pending':
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(
              _en ? 'This lesson is being prepared. Please try again later.' :
                'Ce cours est en cours de préparation. Réessayez plus tard.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: _fontSize, color: const Color(0xFF475569)),
            )),
          );
        case 'raster-error':
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Center(child: OutlinedButton.icon(
              onPressed: () => _retryCoursePage((block['page_number'] as num).toInt()),
              icon: const Icon(Icons.refresh),
              label: Text(_en ? 'Reload this page' : 'Recharger cette page'),
            )),
          );
        case 'text':
          if (text.trim().isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _looksLikeQuillDelta(text)
                ? LessonContentRenderer(
                    text: text,
                    style: TextStyle(fontSize: _fontSize, height: 1.5, color: const Color(0xFF1E293B)),
                  )
                : _buildTextWithDiagrams(text),
          );
        case 'quill':
          return LessonContentRenderer(
            text: text,
            style: TextStyle(fontSize: _fontSize, height: 1.5, color: const Color(0xFF1E293B)),
          );
        default:
          if (text.trim().isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: RichLessonText(text: text,
              style: TextStyle(fontSize: _fontSize, height: 1.4, color: const Color(0xFF1E293B))),
          );
      }
    }

    if (blocks.length == 1 && blocks.first['type'] == 'raster' &&
        blocks.first['bytes'] is Uint8List) {
      return ColoredBox(
        color: Colors.white,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, _isFullscreen ? 12 : 70, 16, _isFullscreen ? 16 : 24),
          child: renderBlock(blocks.first),
        ),
      );
    }

    return ColoredBox(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, _isFullscreen ? 12 : 70, 16, _isFullscreen ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              decoration: BoxDecoration(
                color: const Color(0xFF123B70),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.item.titleFor(widget.locale.languageCode),
                style: TextStyle(fontSize: _fontSize + 3, height: 1.2,
                  fontWeight: FontWeight.w900, color: Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            for (final block in blocks) renderBlock(block),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    unawaited(_localDb.closeDatabase());
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  List<Map<String, dynamic>> _pagesForLayout(double width, double height) {
    if (_pdfPages.isNotEmpty) return _pdfPages;
    final source = _structuredPages.isNotEmpty
        ? _structuredPages
        : [
            {
              'id': 'legacy-page-1',
              'position': 1,
              'format': 'A4',
              'blocks': [
                {
                  'type': 'text',
                  'text_fr': widget.item.bodyFor('fr') ?? '',
                  'text_en': widget.item.bodyFor('en') ?? widget.item.bodyFor('fr') ?? '',
                },
              ],
            },
          ];
    // Quill Delta is a structured document, not plain text: never split its
    // JSON payload into arbitrary page fragments.
    final containsQuillDelta = source.any((page) {
      final raw = page['blocks'];
      if (raw is! List) return false;
      return raw.whereType<Map>().any((block) {
        final value = (block['text_fr'] ?? block['text'] ?? block['content'] ?? '').toString();
        return _looksLikeQuillDelta(value);
      });
    });
    if (containsQuillDelta) return source;

    return NotebookPagePagination.expandLegacyPages(
      source,
      fontSize: _fontSize,
      contentWidth: width,
      contentHeight: height,
    );
  }


  Widget _readerNavButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: enabled ? const Color(0xE6166534) : const Color(0x66888888),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: enabled ? onPressed : null,
        color: Colors.white,
        disabledColor: Colors.white54,
        icon: Icon(icon, size: 30),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pagesForLayout(
      MediaQuery.sizeOf(context).width - 32,
      MediaQuery.sizeOf(context).height - 120,
    );
    // Flatten the structured page blocks into one continuous lesson. Page
    // boundaries and PDF-style page navigation are intentionally not exposed
    // to students.
    final continuousBlocks = <Map<String, dynamic>>[];
    for (final page in pages) {
      final raw = page['blocks'];
      if (raw is List) {
        continuousBlocks.addAll(
          raw.whereType<Map>().map((block) => Map<String, dynamic>.from(block)),
        );
      }
    }
    final continuousPage = <String, dynamic>{'blocks': continuousBlocks};

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: _buildPage(continuousPage, 1, 1),
          ),
          if (!_isFullscreen)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  color: const Color(0xF5FFFFFF),
                  child: Row(children: [
                    IconButton(
                      tooltip: _en ? 'Back' : 'Retour',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF123B70)),
                    ),
                    Expanded(
                      child: Text(
                        widget.item.titleFor(widget.locale.languageCode),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF123B70)),
                      ),
                    ),
                    IconButton(
                      tooltip: 'A−',
                      onPressed: () {
                        setState(() => _fontSize = (_fontSize - 1).clamp(16, 30).toDouble());
                        unawaited(_saveReaderState());
                      },
                      icon: const Icon(Icons.text_decrease, color: Color(0xFF123B70)),
                    ),
                    IconButton(
                      tooltip: 'A+',
                      onPressed: () {
                        setState(() => _fontSize = (_fontSize + 1).clamp(16, 30).toDouble());
                        unawaited(_saveReaderState());
                      },
                      icon: const Icon(Icons.text_increase, color: Color(0xFF123B70)),
                    ),
                    IconButton(
                      tooltip: _en ? 'Full screen' : 'Plein écran',
                      onPressed: () {
                        setState(() => _isFullscreen = true);
                        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
                      },
                      icon: const Icon(Icons.fullscreen, color: Color(0xFF123B70)),
                    ),
                  ]),
                ),
              ),
            ),
          if (_isFullscreen)
            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: Material(
                  color: const Color(0xCC123B70),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: _en ? 'Exit full screen' : 'Quitter le plein écran',
                    onPressed: () {
                      setState(() => _isFullscreen = false);
                      SystemChrome.setEnabledSystemUIMode(
                        SystemUiMode.edgeToEdge,
                        overlays: SystemUiOverlay.values,
                      );
                    },
                    icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

}

class _CourseImageFullscreenPage extends StatefulWidget {
  const _CourseImageFullscreenPage({
    required this.images,
    required this.heroTags,
    required this.initialIndex,
  });

  final List<ImageProvider<Object>> images;
  final List<String> heroTags;
  final int initialIndex;

  @override
  State<_CourseImageFullscreenPage> createState() => _CourseImageFullscreenPageState();
}

class _CourseImageFullscreenPageState extends State<_CourseImageFullscreenPage> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  final TransformationController _zoomController = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _controller.dispose();
    _zoomController.dispose();
    // The parent course reader remains immersive after the image gallery closes.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: GestureDetector(
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 350) Navigator.of(context).pop();
      },
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.images.length,
            itemBuilder: (context, index) => Center(
              child: Hero(
                tag: widget.heroTags[index],
                child: GestureDetector(
                  onDoubleTap: () {
                    setState(() {
                      _zoomed = !_zoomed;
                      _zoomController.value = _zoomed
                          ? (Matrix4.identity()..scale(2.0))
                          : Matrix4.identity();
                    });
                  },
                  child: InteractiveViewer(
                    transformationController: _zoomController,
                    minScale: 1,
                    maxScale: 5,
                    child: Image(
                      image: widget.images[index],
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 12,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
            ),
          ),
          if (widget.images.length > 1)
            Positioned(
              bottom: MediaQuery.paddingOf(context).bottom + 18,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Balayer pour changer d’image',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Lecteur A4 des cours stockés dans la table historique `courses`.
class CourseRecordNotebookReaderPage extends StatefulWidget {
  const CourseRecordNotebookReaderPage({
    super.key,
    required this.title,
    required this.pages,
    required this.fallbackText,
    required this.locale,
  });

  final String title;
  final List<Map<String, dynamic>> pages;
  final String fallbackText;
  final Locale locale;

  @override
  State<CourseRecordNotebookReaderPage> createState() => _CourseRecordNotebookReaderPageState();
}

class _CourseRecordNotebookReaderPageState extends State<CourseRecordNotebookReaderPage> {
  @override
  Widget build(BuildContext context) {
    final pages = widget.pages.isNotEmpty
        ? widget.pages
        : <Map<String, dynamic>>[
            {
              'id': 'legacy-page-1',
              'position': 1,
              'blocks': [
                {
                  'type': 'text',
                  'text_fr': widget.fallbackText,
                  'text_en': widget.fallbackText,
                },
              ],
            },
          ];
    final item = ChapterLearningContentItem(
      id: 'legacy-course-record-${widget.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}',
      chapterId: 'legacy-course-record',
      type: ChapterLearningContentType.course,
      titleFr: widget.title,
      titleEn: widget.title,
      position: 0,
      isPublished: true,
      bodyTextFr: widget.fallbackText,
      bodyTextEn: widget.fallbackText,
      pages: pages,
    );
    return CourseNotebookReaderPage(item: item, locale: widget.locale);
  }
}
);
    void flush() {
      final text = buffer.toString().trim();
      if (text.isNotEmpty) {
        children.add(RichLessonText(
          text: text,
          style: TextStyle(fontSize: _fontSize, height: 1.5, color: const Color(0xFF1E293B)),
        ));
      }
      buffer.clear();
    }

    for (final line in value.replaceAll('\\r\\n', '\\n').split('\\n')) {
      final match = token.firstMatch(line.trim());
      if (match == null) {
        buffer.writeln(line);
        continue;
      }
      flush();
      final kind = match.group(1)!;
      children.add(_courseDiagramCard(kind));
    }
    flush();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _courseDiagramCard(String kind) {
    const titles = <String, String>{
      'gravity_pair': 'Attraction gravitationnelle entre deux corps',
      'gravity_altitude': 'Champ gravitationnel autour de la Terre',
      'weight': 'Poids d’un corps',
      'geom_triangle': 'Triangle et éléments géométriques',
      'geom_right_triangle': 'Triangle rectangle',
      'geom_circle': 'Cercle et rayon',
      'geom_square': 'Carré et diagonales',
      'geom_parallel': 'Configuration de Thalès',
      'geom_coordinate': 'Repère cartésien',
      'geom_cube': 'Cube en perspective',
      'geom_pyramid': 'Pyramide à base carrée',
      'geom_cylinder': 'Cylindre',
      'geom_prism': 'Prisme droit',
      'graph_line': 'Représentation graphique d’une droite',
      'stats_bar': 'Diagramme en bâtons',
      'svt_cell': 'Échanges à travers la membrane cellulaire',
      'svt_neuron': 'Structure d’un neurone',
      'svt_synapse': 'Transmission au niveau d’une synapse',
    };
    const englishTitles = <String, String>{
      'gravity_pair': 'Gravitational attraction between two bodies',
      'gravity_altitude': 'Gravitational field around Earth',
      'weight': 'Weight of a body',
      'geom_triangle': 'Triangle and its elements',
      'geom_right_triangle': 'Right-angled triangle',
      'geom_circle': 'Circle and radius',
      'geom_square': 'Square and diagonals',
      'geom_parallel': 'Thales configuration',
      'geom_coordinate': 'Cartesian coordinate plane',
      'geom_cube': 'Cube in perspective',
      'geom_pyramid': 'Square-based pyramid',
      'geom_cylinder': 'Cylinder',
      'geom_prism': 'Right prism',
      'graph_line': 'Graph of a straight line',
      'stats_bar': 'Bar chart',
      'svt_cell': 'Cell membrane exchanges',
      'svt_neuron': 'Structure of a neuron',
      'svt_synapse': 'Synaptic transmission',
    };
    const formulas = <String, String>{
      'gravity_pair': 'F = G × m₁ × m₂ / r²',
      'gravity_altitude': 'g(h) = G × Mₜ / (Rₜ + h)²',
      'weight': 'P = m × g',
      'geom_triangle': 'A = (base × hauteur) / 2',
      'geom_right_triangle': 'c² = a² + b²',
      'geom_circle': 'P = 2πr  •  A = πr²',
      'geom_square': 'A = c²  •  diagonale = c√2',
      'geom_parallel': 'MN ∥ BC  ⇒  AM/AB = AN/AC',
      'geom_coordinate': 'Point A(x ; y)',
      'geom_cube': 'V = a³  •  A totale = 6a²',
      'geom_pyramid': 'V = (A base × hauteur) / 3',
      'geom_cylinder': 'V = πr²h',
      'geom_prism': 'V = A base × hauteur',
      'graph_line': 'y = ax + b',
      'stats_bar': 'Hauteur des barres proportionnelle aux effectifs',
      'svt_cell': 'Entrées : eau, ions, nutriments, O₂  •  Sorties : CO₂ et déchets',
      'svt_neuron': 'Dendrites → corps cellulaire → axone → terminaisons',
      'svt_synapse': 'Message électrique → neurotransmetteurs → récepteurs',
    };
    final title = _en ? englishTitles[kind] : titles[kind];
    if (title == null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Text(title, textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF164E63), fontSize: 14)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 190,
          child: CustomPaint(painter: _CourseReaderDiagramPainter(kind)),
        ),
        const SizedBox(height: 6),
        Text(formulas[kind] ?? '', textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1D4ED8), fontSize: 14)),
      ]),
    );
  }

  Widget _buildPage(Map<String, dynamic> page, int number, int totalPages) {
    final rawBlocks = page['blocks'];
    final blocks = rawBlocks is List
        ? rawBlocks.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];

    Widget renderBlock(Map<String, dynamic> block) {
      final rawType = (block['type'] ?? '').toString().toLowerCase();
      final type = switch (rawType) {
        'text' || 'paragraph' || 'texte' => 'text',
        'title' || 'heading' || 'titre' => 'title',
        'section' || 'section_title' => 'section',
        'subtitle' || 'subheading' || 'sous_titre' => 'subtitle',
        'bullet' || 'list_item' || 'puce' => 'bullet',
        'key_phrase' || 'keyphrase' || 'phrase_cle' => 'key',
        'formula' || 'equation' => 'formula',
        'table' => 'table',
        'diagram' || 'schema' || 'schéma' => 'diagram',
        'image' || 'figure' => 'image',
        'raster' => 'raster',
        'quill' || 'delta' => 'quill',
        'raster-pending' || 'raster-error' => rawType,
        _ => rawType,
      };
      final text = (block[_en ? 'text_en' : 'text_fr'] ??
              block['text'] ??
              block['content'] ??
              block['label'] ??
              '').toString();
      const navy = Color(0xFF123B70);
      const paleBlue = Color(0xFFEAF3FF);
      const paleGreen = Color(0xFFEAF8EF);

      switch (type) {
        case 'title':
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(text, style: TextStyle(
              fontSize: _fontSize + 4, height: 1.2,
              fontWeight: FontWeight.w900, color: navy,
            )),
          );
        case 'section':
          return Container(
            margin: const EdgeInsets.only(top: 12, bottom: 9),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: paleBlue, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFB9D7FA)),
            ),
            child: Text(text, style: TextStyle(
              fontSize: _fontSize + 1, height: 1.25,
              fontWeight: FontWeight.w800, color: navy,
            )),
          );
        case 'subtitle':
          return Container(
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: paleGreen, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFC7E9D1)),
            ),
            child: Text(text, style: TextStyle(
              fontSize: _fontSize, height: 1.3,
              fontWeight: FontWeight.w800, color: const Color(0xFF17633B),
            )),
          );
        case 'bullet':
          return Padding(
            padding: const EdgeInsets.only(left: 5, bottom: 7),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 7, right: 9),
                child: Icon(Icons.circle, size: 7, color: Color(0xFF2476D2)),
              ),
              Expanded(child: RichLessonText(
                text: text,
                style: TextStyle(fontSize: _fontSize, height: 1.4, color: const Color(0xFF1E293B)),
              )),
            ]),
          );
        case 'key':
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: RichLessonText(
              text: text,
              style: TextStyle(fontSize: _fontSize, height: 1.4,
                fontWeight: FontWeight.w800, color: navy),
            ),
          );
        case 'formula':
          final formula = (block['latex'] ?? block['formula'] ?? text).toString();
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: paleBlue, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFB9D7FA)),
            ),
            child: Center(child: RichLessonText(
              text: formula.startsWith(r'$') ? formula : r'$$' + formula + r'$$',
              style: TextStyle(fontSize: _fontSize + 1, height: 1.5,
                fontWeight: FontWeight.w600, color: navy),
            )),
          );
        case 'table':
          final rawRows = block['rows'] ?? block['data'];
          final rows = rawRows is List ? rawRows : const [];
          final cells = rows.map((row) {
            if (row is List) return row.map((v) => v.toString()).toList();
            if (row is Map) return row.values.map((v) => v.toString()).toList();
            return <String>[row.toString()];
          }).toList();
          if (cells.isEmpty) {
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFCBD5E1))),
              child: RichLessonText(text: text, style: TextStyle(fontSize: _fontSize, height: 1.4)),
            );
          }
          final columnCount = cells.fold<int>(0, (n, row) => row.length > n ? row.length : n).clamp(1, 8);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder.all(color: const Color(0xFF9DB6D3)),
              children: [
                for (var ri = 0; ri < cells.length; ri++)
                  TableRow(
                    decoration: ri == 0 ? const BoxDecoration(color: paleBlue) : null,
                    children: [
                      for (var ci = 0; ci < columnCount; ci++)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(ci < cells[ri].length ? cells[ri][ci] : '',
                            style: TextStyle(fontSize: _fontSize - 1, height: 1.3,
                              fontWeight: ri == 0 ? FontWeight.w800 : FontWeight.w400)),
                        ),
                    ],
                  ),
              ],
            ),
          );
        case 'image' || 'diagram':
          final imagePath = (block['storage_path'] ?? block['path'] ?? '').toString();
          if (imagePath.isEmpty) return const SizedBox.shrink();
          return FutureBuilder<Object?>(
            future: _resolveImage(imagePath),
            builder: (context, snapshot) {
              final resolved = snapshot.data;
              if (resolved == null) {
                return const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final image = resolved is File
                  ? Image.file(resolved, fit: BoxFit.contain)
                  : Image.network(resolved.toString(), fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink());
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: 10),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(children: [
                  GestureDetector(
                    onTap: () => _openImageGallery(imagePath),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: image,
                    ),
                  ),
                  if ((block['caption'] ?? '').toString().trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Text(block['caption'].toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: _fontSize - 2, color: Colors.black54)),
                    ),
                ]),
              );
            },
          );
        case 'raster':
          final bytes = block['bytes'];
          if (bytes is! Uint8List) return const SizedBox.shrink();
          return GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => Dialog.fullscreen(
                child: Stack(children: [
                  Center(child: InteractiveViewer(
                    minScale: 0.7, maxScale: 5,
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  )),
                  Positioned(top: 18, right: 12, child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  )),
                ]),
              ),
            ),
            child: Image.memory(bytes, width: double.infinity, fit: BoxFit.fitWidth),
          );
        case 'raster-pending':
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(
              _en ? 'This lesson is being prepared. Please try again later.' :
                'Ce cours est en cours de préparation. Réessayez plus tard.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: _fontSize, color: const Color(0xFF475569)),
            )),
          );
        case 'raster-error':
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Center(child: OutlinedButton.icon(
              onPressed: () => _retryCoursePage((block['page_number'] as num).toInt()),
              icon: const Icon(Icons.refresh),
              label: Text(_en ? 'Reload this page' : 'Recharger cette page'),
            )),
          );
        case 'text':
          if (text.trim().isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _looksLikeQuillDelta(text)
                ? LessonContentRenderer(
                    text: text,
                    style: TextStyle(fontSize: _fontSize, height: 1.5, color: const Color(0xFF1E293B)),
                  )
                : RichLessonText(
                    text: text,
                    style: TextStyle(fontSize: _fontSize, height: 1.4, color: const Color(0xFF1E293B)),
                  ),
          );
        case 'quill':
          return LessonContentRenderer(
            text: text,
            style: TextStyle(fontSize: _fontSize, height: 1.5, color: const Color(0xFF1E293B)),
          );
        default:
          if (text.trim().isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: RichLessonText(text: text,
              style: TextStyle(fontSize: _fontSize, height: 1.4, color: const Color(0xFF1E293B))),
          );
      }
    }

    if (blocks.length == 1 && blocks.first['type'] == 'raster' &&
        blocks.first['bytes'] is Uint8List) {
      return ColoredBox(
        color: Colors.white,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, _isFullscreen ? 12 : 70, 16, _isFullscreen ? 16 : 24),
          child: renderBlock(blocks.first),
        ),
      );
    }

    return ColoredBox(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, _isFullscreen ? 12 : 70, 16, _isFullscreen ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              decoration: BoxDecoration(
                color: const Color(0xFF123B70),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.item.titleFor(widget.locale.languageCode),
                style: TextStyle(fontSize: _fontSize + 3, height: 1.2,
                  fontWeight: FontWeight.w900, color: Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            for (final block in blocks) renderBlock(block),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    unawaited(_localDb.closeDatabase());
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  List<Map<String, dynamic>> _pagesForLayout(double width, double height) {
    if (_pdfPages.isNotEmpty) return _pdfPages;
    final source = _structuredPages.isNotEmpty
        ? _structuredPages
        : [
            {
              'id': 'legacy-page-1',
              'position': 1,
              'format': 'A4',
              'blocks': [
                {
                  'type': 'text',
                  'text_fr': widget.item.bodyFor('fr') ?? '',
                  'text_en': widget.item.bodyFor('en') ?? widget.item.bodyFor('fr') ?? '',
                },
              ],
            },
          ];
    // Quill Delta is a structured document, not plain text: never split its
    // JSON payload into arbitrary page fragments.
    final containsQuillDelta = source.any((page) {
      final raw = page['blocks'];
      if (raw is! List) return false;
      return raw.whereType<Map>().any((block) {
        final value = (block['text_fr'] ?? block['text'] ?? block['content'] ?? '').toString();
        return _looksLikeQuillDelta(value);
      });
    });
    if (containsQuillDelta) return source;

    return NotebookPagePagination.expandLegacyPages(
      source,
      fontSize: _fontSize,
      contentWidth: width,
      contentHeight: height,
    );
  }


  Widget _readerNavButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: enabled ? const Color(0xE6166534) : const Color(0x66888888),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: enabled ? onPressed : null,
        color: Colors.white,
        disabledColor: Colors.white54,
        icon: Icon(icon, size: 30),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pagesForLayout(
      MediaQuery.sizeOf(context).width - 32,
      MediaQuery.sizeOf(context).height - 120,
    );
    // Flatten the structured page blocks into one continuous lesson. Page
    // boundaries and PDF-style page navigation are intentionally not exposed
    // to students.
    final continuousBlocks = <Map<String, dynamic>>[];
    for (final page in pages) {
      final raw = page['blocks'];
      if (raw is List) {
        continuousBlocks.addAll(
          raw.whereType<Map>().map((block) => Map<String, dynamic>.from(block)),
        );
      }
    }
    final continuousPage = <String, dynamic>{'blocks': continuousBlocks};

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: _buildPage(continuousPage, 1, 1),
          ),
          if (!_isFullscreen)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  color: const Color(0xF5FFFFFF),
                  child: Row(children: [
                    IconButton(
                      tooltip: _en ? 'Back' : 'Retour',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF123B70)),
                    ),
                    Expanded(
                      child: Text(
                        widget.item.titleFor(widget.locale.languageCode),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF123B70)),
                      ),
                    ),
                    IconButton(
                      tooltip: 'A−',
                      onPressed: () {
                        setState(() => _fontSize = (_fontSize - 1).clamp(16, 30).toDouble());
                        unawaited(_saveReaderState());
                      },
                      icon: const Icon(Icons.text_decrease, color: Color(0xFF123B70)),
                    ),
                    IconButton(
                      tooltip: 'A+',
                      onPressed: () {
                        setState(() => _fontSize = (_fontSize + 1).clamp(16, 30).toDouble());
                        unawaited(_saveReaderState());
                      },
                      icon: const Icon(Icons.text_increase, color: Color(0xFF123B70)),
                    ),
                    IconButton(
                      tooltip: _en ? 'Full screen' : 'Plein écran',
                      onPressed: () {
                        setState(() => _isFullscreen = true);
                        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
                      },
                      icon: const Icon(Icons.fullscreen, color: Color(0xFF123B70)),
                    ),
                  ]),
                ),
              ),
            ),
          if (_isFullscreen)
            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: Material(
                  color: const Color(0xCC123B70),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: _en ? 'Exit full screen' : 'Quitter le plein écran',
                    onPressed: () {
                      setState(() => _isFullscreen = false);
                      SystemChrome.setEnabledSystemUIMode(
                        SystemUiMode.edgeToEdge,
                        overlays: SystemUiOverlay.values,
                      );
                    },
                    icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

}

class _CourseImageFullscreenPage extends StatefulWidget {
  const _CourseImageFullscreenPage({
    required this.images,
    required this.heroTags,
    required this.initialIndex,
  });

  final List<ImageProvider<Object>> images;
  final List<String> heroTags;
  final int initialIndex;

  @override
  State<_CourseImageFullscreenPage> createState() => _CourseImageFullscreenPageState();
}

class _CourseImageFullscreenPageState extends State<_CourseImageFullscreenPage> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  final TransformationController _zoomController = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _controller.dispose();
    _zoomController.dispose();
    // The parent course reader remains immersive after the image gallery closes.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: GestureDetector(
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 350) Navigator.of(context).pop();
      },
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.images.length,
            itemBuilder: (context, index) => Center(
              child: Hero(
                tag: widget.heroTags[index],
                child: GestureDetector(
                  onDoubleTap: () {
                    setState(() {
                      _zoomed = !_zoomed;
                      _zoomController.value = _zoomed
                          ? (Matrix4.identity()..scale(2.0))
                          : Matrix4.identity();
                    });
                  },
                  child: InteractiveViewer(
                    transformationController: _zoomController,
                    minScale: 1,
                    maxScale: 5,
                    child: Image(
                      image: widget.images[index],
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 12,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
            ),
          ),
          if (widget.images.length > 1)
            Positioned(
              bottom: MediaQuery.paddingOf(context).bottom + 18,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Balayer pour changer d’image',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Lecteur A4 des cours stockés dans la table historique `courses`.
class CourseRecordNotebookReaderPage extends StatefulWidget {
  const CourseRecordNotebookReaderPage({
    super.key,
    required this.title,
    required this.pages,
    required this.fallbackText,
    required this.locale,
  });

  final String title;
  final List<Map<String, dynamic>> pages;
  final String fallbackText;
  final Locale locale;

  @override
  State<CourseRecordNotebookReaderPage> createState() => _CourseRecordNotebookReaderPageState();
}

class _CourseRecordNotebookReaderPageState extends State<CourseRecordNotebookReaderPage> {
  @override
  Widget build(BuildContext context) {
    final pages = widget.pages.isNotEmpty
        ? widget.pages
        : <Map<String, dynamic>>[
            {
              'id': 'legacy-page-1',
              'position': 1,
              'blocks': [
                {
                  'type': 'text',
                  'text_fr': widget.fallbackText,
                  'text_en': widget.fallbackText,
                },
              ],
            },
          ];
    final item = ChapterLearningContentItem(
      id: 'legacy-course-record-${widget.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}',
      chapterId: 'legacy-course-record',
      type: ChapterLearningContentType.course,
      titleFr: widget.title,
      titleEn: widget.title,
      position: 0,
      isPublished: true,
      bodyTextFr: widget.fallbackText,
      bodyTextEn: widget.fallbackText,
      pages: pages,
    );
    return CourseNotebookReaderPage(item: item, locale: widget.locale);
  }
}\n\nclass _CourseReaderDiagramPainter extends CustomPainter {
  final String kind;
  _CourseReaderDiagramPainter(this.kind);

  static const blue = Color(0xFF2563EB);
  static const orange = Color(0xFFF97316);
  static const red = Color(0xFFDC2626);
  static const green = Color(0xFF16A34A);
  static const ink = Color(0xFF0F172A);
  static const grey = Color(0xFF64748B);

  void _text(Canvas c, String value, Offset at, {double size = 12, Color color = ink, bool bold = false}) {
    final p = TextPainter(
      text: TextSpan(text: value, style: TextStyle(fontSize: size, color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 180);
    p.paint(c, at);
  }

  void _line(Canvas c, Offset a, Offset b, Color color, {double width = 2, bool dashed = false}) {
    final paint = Paint()..color = color..strokeWidth = width..style = PaintingStyle.stroke;
    if (!dashed) { c.drawLine(a, b, paint); return; }
    final delta = b - a;
    final length = delta.distance;
    if (length == 0) return;
    final unit = delta / length;
    for (double d = 0; d < length; d += 10) {
      c.drawLine(a + unit * d, a + unit * math.min(d + 5, length).toDouble(), paint);
    }
  }

  void _arrow(Canvas c, Offset a, Offset b, Color color) {
    _line(c, a, b, color, width: 2.5);
    final angle = (b - a).direction;
    const head = 9.0;
    _line(c, b, b - Offset(head * math.cos(angle - .5), head * math.sin(angle - .5)), color);
    _line(c, b, b - Offset(head * math.cos(angle + .5), head * math.sin(angle + .5)), color);
  }

  void _point(Canvas c, Offset p, String label, {Color color = red}) {
    c.drawCircle(p, 3.5, Paint()..color = color);
    _text(c, label, p + const Offset(5, -17), size: 11, color: ink, bold: true);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final center = Offset(w * .5, h * .52);

    if (kind == 'gravity_pair') {
      final y = h * .43;
      canvas.drawCircle(Offset(w * .22, y), 27, Paint()..color = blue);
      canvas.drawCircle(Offset(w * .78, y), 35, Paint()..color = orange);
      _text(canvas, 'm₁', Offset(w * .22 - 9, y - 7), color: Colors.white, bold: true);
      _text(canvas, 'm₂', Offset(w * .78 - 10, y - 7), color: Colors.white, bold: true);
      _arrow(canvas, Offset(w * .43, y - 13), Offset(w * .30, y - 13), red);
      _arrow(canvas, Offset(w * .57, y + 13), Offset(w * .69, y + 13), red);
      _text(canvas, 'F₂₁', Offset(w * .33, y - 36), color: red, bold: true);
      _text(canvas, 'F₁₂', Offset(w * .61, y + 20), color: red, bold: true);
      _line(canvas, Offset(w * .22, y + 49), Offset(w * .78, y + 49), grey);
      _text(canvas, 'distance r', Offset(w * .43, y + 54), size: 11);
    } else if (kind == 'gravity_altitude') {
      final earth = Offset(w * .34, h * .53);
      canvas.drawCircle(earth, 53, Paint()..color = blue);
      _text(canvas, 'Terre', earth - const Offset(18, 7), size: 11, color: Colors.white, bold: true);
      canvas.drawCircle(earth, 82, Paint()..color = grey..style = PaintingStyle.stroke..strokeWidth = 1.5);
      final sat = Offset(earth.dx + 82, earth.dy - 8);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: sat, width: 22, height: 14), const Radius.circular(3)), Paint()..color = orange);
      _arrow(canvas, earth, Offset(earth.dx + 82, earth.dy), green);
      _text(canvas, 'Rₜ', earth + const Offset(-43, 25), color: Colors.white, bold: true);
      _text(canvas, 'h', earth + const Offset(43, -37), color: green, bold: true);
      _text(canvas, 'Satellite', sat + const Offset(-26, -29), size: 11, bold: true);
      _text(canvas, 'r = Rₜ + h', Offset(w * .58, h * .46), size: 14, color: blue, bold: true);
    } else if (kind == 'weight') {
      final groundY = h * .72;
      _line(canvas, Offset(8, groundY), Offset(w - 8, groundY), green, width: 4);
      canvas.drawCircle(Offset(w * .5, groundY - 48), 18, Paint()..color = orange);
      _arrow(canvas, Offset(w * .5, groundY - 25), Offset(w * .5, groundY - 2), red);
      _text(canvas, 'm', Offset(w * .5 + 24, groundY - 56), bold: true);
      _text(canvas, 'P', Offset(w * .5 + 13, groundY - 25), color: red, bold: true);
      _text(canvas, 'Sol', Offset(w * .5 - 12, groundY + 7), size: 11, color: green, bold: true);
    } else if (kind == 'geom_triangle' || kind == 'geom_right_triangle') {
      final a = Offset(w * .22, h * .78), b = Offset(w * .78, h * .78);
      final c = kind == 'geom_right_triangle' ? Offset(w * .22, h * .18) : Offset(w * .53, h * .18);
      final p = Path()..moveTo(a.dx,a.dy)..lineTo(b.dx,b.dy)..lineTo(c.dx,c.dy)..close();
      canvas.drawPath(p, Paint()..color = const Color(0x332563EB)..style = PaintingStyle.fill);
      canvas.drawPath(p, Paint()..color = blue..style = PaintingStyle.stroke..strokeWidth = 3);
      _point(canvas,a,'A'); _point(canvas,b,'B'); _point(canvas,c,'C');
      if (kind == 'geom_right_triangle') {
        _line(canvas, a + const Offset(0,-16), a + const Offset(16,-16), green);
        _line(canvas, a + const Offset(16,-16), a + const Offset(16,0), green);
        _text(canvas,'angle droit',Offset(w*.28,h*.58),size:10,color:green);
      } else {
        _line(canvas, Offset((a.dx+b.dx)/2,h*.70), Offset((a.dx+b.dx)/2,h*.78), red);
        _text(canvas,'base',Offset(w*.44,h*.82),size:11,color:red);
        _line(canvas,c,Offset(c.dx,h*.78),green,dashed:true);
        _text(canvas,'hauteur',Offset(c.dx+5,h*.48),size:10,color:green);
      }
    } else if (kind == 'geom_circle') {
      final r = math.min(w,h).toDouble()*.31;
      canvas.drawCircle(center,r,Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=3);
      canvas.drawCircle(center,4,Paint()..color=red);
      final edge=center+Offset(r*.78,-r*.63);
      _line(canvas,center,edge,red,width:3);
      _text(canvas,'O',center+const Offset(-17,7),bold:true);
      _text(canvas,'r',center+Offset(r*.35,-r*.42),color:red,bold:true);
    } else if (kind == 'geom_square') {
      final side=math.min(w,h).toDouble()*.62;
      final rect=Rect.fromCenter(center:center,width:side,height:side);
      canvas.drawRect(rect,Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=3);
      _line(canvas,rect.topLeft,rect.bottomRight,red,width:2.5);
      _line(canvas,rect.topRight,rect.bottomLeft,green,width:2.5);
      _text(canvas,'c',Offset(rect.left-18,center.dy),color:blue,bold:true);
    } else if (kind == 'geom_parallel') {
      final a=Offset(w*.20,h*.78), b=Offset(w*.82,h*.78);
      final c=Offset(w*.31,h*.24), d=Offset(w*.70,h*.24);
      _line(canvas,a,b,blue,width:3); _line(canvas,c,d,blue,width:3);
      _line(canvas,Offset(w*.40,h*.08),Offset(w*.54,h*.94),red,width:2.5);
      _line(canvas,Offset(w*.68,h*.08),Offset(w*.78,h*.94),red,width:2.5);
      _point(canvas,Offset(w*.40,h*.64),'M'); _point(canvas,Offset(w*.54,h*.64),'N');
      _point(canvas,Offset(w*.20,h*.78),'B'); _point(canvas,Offset(w*.82,h*.78),'C');
      _text(canvas,'(MN) ∥ (BC)',Offset(w*.35,h*.06),color:green,bold:true);
    } else if (kind == 'geom_coordinate' || kind == 'graph_line') {
      final origin=Offset(w*.18,h*.82);
      _arrow(canvas,Offset(w*.08,origin.dy),Offset(w*.92,origin.dy),ink);
      _arrow(canvas,Offset(origin.dx,h*.92),Offset(origin.dx,h*.08),ink);
      for (int i=1;i<=6;i++) {
        final x=origin.dx+i*w*.105;
        _line(canvas,Offset(x,origin.dy-4),Offset(x,origin.dy+4),grey);
        final y=origin.dy-i*h*.105;
        _line(canvas,Offset(origin.dx-4,y),Offset(origin.dx+4,y),grey);
      }
      if (kind=='geom_coordinate') {
        final a=Offset(w*.60,h*.30);
        _line(canvas,a,Offset(a.dx,origin.dy),green,dashed:true);
        _line(canvas,a,Offset(origin.dx,a.dy),orange,dashed:true);
        _point(canvas,a,'A(x ; y)');
      } else {
        final a=Offset(w*.24,h*.72),b=Offset(w*.82,h*.18);
        _line(canvas,a,b,red,width:3);
        _point(canvas,a,''); _point(canvas,b,'');
      }
      _text(canvas,'x',Offset(w*.92,origin.dy+5),bold:true);
      _text(canvas,'y',Offset(origin.dx+7,h*.05),bold:true);
    } else if (kind == 'geom_cube' || kind == 'geom_prism') {
      final dx=w*.18,dy=h*.17;
      final x=w*.24,y=h*.30,bw=w*.43,bh=h*.43;
      final f=Offset(dx,-dy);
      final p1=Offset(x,y),p2=Offset(x+bw,y),p3=Offset(x+bw,y+bh),p4=Offset(x,y+bh);
      final q1=p1+f,q2=p2+f,q3=p3+f,q4=p4+f;
      for(final pair in <List<Offset>>[[p1,p2],[p2,p3],[p3,p4],[p4,p1],[q1,q2],[q2,q3],[q3,q4],[q4,q1],[p1,q1],[p2,q2],[p3,q3],[p4,q4]]) {
        _line(canvas,pair[0],pair[1],blue,width:2.5);
      }
      _text(canvas,kind=='geom_cube'?'a':'h',Offset(x+bw+dx+3,y+bh*.5),color:red,bold:true);
    } else if (kind == 'geom_pyramid') {
      final apex=Offset(w*.52,h*.12),a=Offset(w*.20,h*.72),b=Offset(w*.78,h*.72),c=Offset(w*.88,h*.48),d=Offset(w*.32,h*.48);
      _line(canvas,a,b,blue,width:2.5); _line(canvas,b,c,blue,width:2.5); _line(canvas,c,d,blue,width:2.5); _line(canvas,d,a,blue,width:2.5);
      for(final p in [a,b,c,d]) _line(canvas,apex,p,red,width:2.5);
      _line(canvas,apex,Offset(w*.54,h*.59),green,dashed:true);
      _text(canvas,'S',apex+const Offset(4,-12),bold:true); _text(canvas,'H',Offset(w*.54,h*.60),color:green,bold:true);
    } else if (kind == 'geom_cylinder') {
      final left=w*.25,right=w*.75,top=h*.20,bottom=h*.78,ry=h*.10;
      canvas.drawOval(Rect.fromLTRB(left,top-ry,right,top+ry),Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=2.5);
      _line(canvas,Offset(left,top),Offset(left,bottom),blue,width:2.5);
      _line(canvas,Offset(right,top),Offset(right,bottom),blue,width:2.5);
      canvas.drawArc(Rect.fromLTRB(left,bottom-ry,right,bottom+ry),0,math.pi, false,Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=2.5);
      canvas.drawArc(Rect.fromLTRB(left,bottom-ry,right,bottom+ry),math.pi,math.pi,false,Paint()..color=grey..style=PaintingStyle.stroke..strokeWidth=1.5);
      _line(canvas,center,Offset(w*.72,h*.42),red,width:2.5);
      _text(canvas,'r',Offset(w*.61,h*.40),color:red,bold:true); _text(canvas,'h',Offset(right+7,h*.47),color:green,bold:true);
    } else if (kind == 'svt_cell') {
      final cell=Rect.fromCenter(center:center,width:w*.48,height:h*.68);
      canvas.drawOval(cell,Paint()..color=const Color(0x3322C55E)..style=PaintingStyle.fill);
      canvas.drawOval(cell,Paint()..color=green..style=PaintingStyle.stroke..strokeWidth=3);
      canvas.drawCircle(center,24,Paint()..color=const Color(0xFF93C5FD));
      canvas.drawCircle(center,24,Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=2);
      _text(canvas,'Noyau',center+const Offset(28,-8),size:10,color:blue,bold:true);
      _text(canvas,'Membrane',Offset(w*.34,h*.12),size:10,color:green,bold:true);
      _arrow(canvas,Offset(5,h*.40),Offset(w*.25,h*.40),blue);
      _arrow(canvas,Offset(5,h*.58),Offset(w*.25,h*.58),orange);
      _arrow(canvas,Offset(w*.75,h*.47),Offset(w-5,h*.47),red);
      _text(canvas,'Entrées',Offset(3,h*.24),size:10,color:blue,bold:true);
      _text(canvas,'Sorties',Offset(w*.78,h*.27),size:10,color:red,bold:true);
    } else if (kind == 'svt_neuron') {
      final soma=Offset(w*.28,h*.50);
      canvas.drawCircle(soma,27,Paint()..color=const Color(0xFFFDE68A));
      canvas.drawCircle(soma,27,Paint()..color=orange..style=PaintingStyle.stroke..strokeWidth=2);
      canvas.drawCircle(soma,9,Paint()..color=blue);
      for(final end in [Offset(w*.08,h*.20),Offset(w*.07,h*.48),Offset(w*.10,h*.82),Offset(w*.25,h*.12),Offset(w*.34,h*.10)]) {
        _line(canvas,soma,end,green,width:2.5);
      }
      final axonStart=Offset(w*.43,h*.50), axonEnd=Offset(w*.88,h*.50);
      _line(canvas,axonStart,axonEnd,blue,width:4);
      for(int i=0;i<4;i++) {
        final x=w*(.48+i*.095);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x,h*.43,w*.065,h*.14),const Radius.circular(8)),Paint()..color=const Color(0xFFBFDBFE));
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x,h*.43,w*.065,h*.14),const Radius.circular(8)),Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=1.5);
      }
      _line(canvas,axonEnd,Offset(w*.94,h*.34),red,width:2);
      _line(canvas,axonEnd,Offset(w*.95,h*.50),red,width:2);
      _line(canvas,axonEnd,Offset(w*.94,h*.66),red,width:2);
      _text(canvas,'Dendrites',Offset(2,h*.04),size:10,color:green,bold:true);
      _text(canvas,'Corps cellulaire',Offset(w*.18,h*.78),size:10,bold:true);
      _text(canvas,'Axone + myéline',Offset(w*.48,h*.23),size:10,color:blue,bold:true);
      _text(canvas,'Terminaisons',Offset(w*.72,h*.78),size:10,color:red,bold:true);
    } else if (kind == 'svt_synapse') {
      final pre=Rect.fromLTWH(w*.12,h*.20,w*.30,h*.30);
      final post=Rect.fromLTWH(w*.58,h*.58,w*.30,h*.22);
      canvas.drawRRect(RRect.fromRectAndRadius(pre,const Radius.circular(25)),Paint()..color=const Color(0xFFBFDBFE));
      canvas.drawRRect(RRect.fromRectAndRadius(pre,const Radius.circular(25)),Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=2);
      canvas.drawRRect(RRect.fromRectAndRadius(post,const Radius.circular(18)),Paint()..color=const Color(0xFFDCFCE7));
      canvas.drawRRect(RRect.fromRectAndRadius(post,const Radius.circular(18)),Paint()..color=green..style=PaintingStyle.stroke..strokeWidth=2);
      for(int i=0;i<5;i++) {
        canvas.drawCircle(Offset(w*(.20+i*.045),h*.38),4,Paint()..color=orange);
        canvas.drawCircle(Offset(w*(.48+i*.035),h*(.48+(i%2)*.05)),3,Paint()..color=orange);
      }
      _arrow(canvas,Offset(w*.43,h*.42),Offset(w*.58,h*.62),red);
      _text(canvas,'Bouton présynaptique',Offset(w*.08,h*.06),size:10,color:blue,bold:true);
      _text(canvas,'Fente synaptique',Offset(w*.39,h*.80),size:10,color:orange,bold:true);
      _text(canvas,'Récepteurs',Offset(w*.62,h*.84),size:10,color:green,bold:true);
    } else if (kind == 'stats_bar') {
      final base=h*.82;
      _line(canvas,Offset(w*.12,base),Offset(w*.92,base),ink);
      final vals=[.28,.52,.40,.72,.60];
      for(int i=0;i<vals.length;i++) {
        final x=w*(.20+i*.14);
        canvas.drawRect(Rect.fromLTWH(x,base-h*vals[i]*.72,w*.075,h*vals[i]*.72),Paint()..color=[blue,green,orange,red,Color(0xFF7C3AED)][i]);
      }
      _text(canvas,'Catégories',Offset(w*.42,base+8),size:10);
      _text(canvas,'Effectif',Offset(3,h*.12),size:10);
    }
  }

  @override
  bool shouldRepaint(covariant _CourseReaderDiagramPainter oldDelegate) => oldDelegate.kind != kind;
}\n