import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/offline/app_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdfx/pdfx.dart';

import '../../../core/widgets/rich_lesson_text.dart';
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
  double _zoomScale = 1;
  bool _isFullscreen = false;
  String? _readerMetadata;
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
    unawaited(_loadReaderMetadata());
  }

  Future<void> _loadReaderMetadata() async {
    String? subjectName;
    String? className;
    String? levelName;
    String? teacherName;
    try {
      String? subjectId;
      String? levelId;
      String? teacherId;
      if ((widget.item.pageCourseId ?? '').trim().isNotEmpty) {
        final course = await Supabase.instance.client
            .from('courses')
            .select('subject_id,teacher_id,class_id')
            .eq('id', widget.item.pageCourseId!)
            .maybeSingle();
        subjectId = course?['subject_id']?.toString();
        teacherId = course?['teacher_id']?.toString();
        final classId = course?['class_id']?.toString();
        if (classId != null && classId.isNotEmpty) {
          final room = await Supabase.instance.client
              .from('school_classes')
              .select('display_name,name,exam_level_id')
              .eq('id', classId)
              .maybeSingle();
          className = (room?['display_name'] ?? room?['name'])?.toString();
          levelId = room?['exam_level_id']?.toString();
        }
      } else {
        final chapter = await Supabase.instance.client
            .from('course_chapters')
            .select('curriculum_id')
            .eq('id', widget.item.chapterId)
            .maybeSingle();
        final curriculumId = chapter?['curriculum_id']?.toString();
        if (curriculumId != null && curriculumId.isNotEmpty) {
          final curriculum = await Supabase.instance.client
              .from('curricula')
              .select('subject_id,exam_level_id')
              .eq('id', curriculumId)
              .maybeSingle();
          subjectId = curriculum?['subject_id']?.toString();
          levelId = curriculum?['exam_level_id']?.toString();
        }
        final item = await Supabase.instance.client
            .from('chapter_content_items')
            .select('created_by')
            .eq('id', widget.item.id)
            .maybeSingle();
        teacherId = item?['created_by']?.toString();
      }
      if (subjectId != null && subjectId.isNotEmpty) {
        final subject = await Supabase.instance.client
            .from('subjects')
            .select('name_fr,name_en')
            .eq('id', subjectId)
            .maybeSingle();
        subjectName = (widget.locale.languageCode == 'en'
            ? subject?['name_en'] ?? subject?['name_fr']
            : subject?['name_fr'] ?? subject?['name_en'])?.toString();
      }
      if (levelId != null && levelId.isNotEmpty) {
        final level = await Supabase.instance.client
            .from('exam_levels')
            .select('level_name_fr,level_name_en')
            .eq('id', levelId)
            .maybeSingle();
        levelName = (widget.locale.languageCode == 'en'
            ? level?['level_name_en'] ?? level?['level_name_fr']
            : level?['level_name_fr'] ?? level?['level_name_en'])?.toString();
      }
      if (teacherId != null && teacherId.isNotEmpty) {
        final teacher = await Supabase.instance.client
            .from('profiles')
            .select('first_name,last_name')
            .eq('id', teacherId)
            .maybeSingle();
        teacherName = [teacher?['first_name'], teacher?['last_name']]
            .where((value) => value != null && value.toString().trim().isNotEmpty)
            .join(' ');
      }
    } catch (_) {
      // Metadata is optional: offline reading must never wait for it.
    }
    final details = [subjectName, levelName, className, teacherName]
        .where((value) => value != null && value.trim().isNotEmpty)
        .join(' • ');
    if (!mounted || details.isEmpty) return;
    setState(() => _readerMetadata = details);
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

  Future<void> _loadCoursePages({bool forceRetry = false}) async {
    // Structured pages are primary. If a legacy/scanned document has no
    // meaningful text blocks, use the cached high-resolution page images.
    final hasReadableBlocks = widget.item.pages.any((page) {
      final raw = page['blocks'];
      if (raw is! List) return false;
      return raw.whereType<Map>().any((block) {
        final type = (block['type'] ?? '').toString().toLowerCase();
        if (type == 'image' || type == 'diagram') {
          return (block['storage_path'] ?? block['path'] ?? '').toString().trim().isNotEmpty;
        }
        if (type == 'table') return (block['rows'] is List) && (block['rows'] as List).isNotEmpty;
        if (type == 'formula') return (block['latex'] ?? block['formula'] ?? '').toString().trim().isNotEmpty;
        return (block['text_fr'] ?? block['text_en'] ?? block['text'] ?? block['content'] ?? '').toString().trim().isNotEmpty;
      });
    });
    if (hasReadableBlocks) return;
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

  List<Map<String, dynamic>> get _pages {
    if (_pdfPages.isNotEmpty) return _pdfPages;
    final source = widget.item.pages.isNotEmpty
        ? widget.item.pages
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
            child: RichLessonText(
              text: text,
              style: TextStyle(fontSize: _fontSize, height: 1.4, color: const Color(0xFF1E293B)),
            ),
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
          padding: EdgeInsets.fromLTRB(10, _isFullscreen ? 10 : 72, 10, _isFullscreen ? 12 : 90),
          child: renderBlock(blocks.first),
        ),
      );
    }

    return ColoredBox(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(10, _isFullscreen ? 10 : 68, 10, _isFullscreen ? 12 : 92),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.item.titleFor(widget.locale.languageCode),
                    style: TextStyle(fontSize: _fontSize + 3, height: 1.2,
                      fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                  if ((_readerMetadata ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(_readerMetadata!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: _fontSize - 5, height: 1.2,
                        color: Colors.white70, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final block in blocks) renderBlock(block),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Text('$number / $totalPages',
                style: const TextStyle(fontSize: 11, color: Colors.black45)),
            ),
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
    final source = widget.item.pages.isNotEmpty
        ? widget.item.pages
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
      MediaQuery.sizeOf(context).width - 20,
      MediaQuery.sizeOf(context).height - 150,
    );
    final safeIndex = _index.clamp(0, pages.length - 1).toInt();
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: pages.length,
            physics: const PageScrollPhysics(),
            onPageChanged: (index) {
              setState(() => _index = index);
              unawaited(_saveReaderState());
            },
            itemBuilder: (context, index) => ClipRect(
              child: Transform.scale(
                scale: _zoomScale,
                alignment: Alignment.topCenter,
                child: _buildPage(pages[index], index + 1, pages.length),
              ),
            ),
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
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF123B70)),
                      ),
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
                      tooltip: 'A−',
                      onPressed: () {
                        setState(() => _fontSize = (_fontSize - 1).clamp(16, 30).toDouble());
                        unawaited(_saveReaderState());
                      },
                      icon: const Icon(Icons.text_decrease, color: Color(0xFF123B70)),
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
                      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge, overlays: SystemUiOverlay.values);
                    },
                    icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                  ),
                ),
              ),
            ),
          if (!_isFullscreen)
            Positioned(
              left: 10,
              right: 10,
              bottom: 8,
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xF5FFFFFF),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: const Color(0xFFD9E5F2)),
                    boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 12, offset: Offset(0, 3))],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _readerNavButton(
                        icon: Icons.chevron_left_rounded,
                        enabled: safeIndex > 0,
                        onPressed: () => _controller.previousPage(duration: const Duration(milliseconds: 240), curve: Curves.easeInOut),
                      ),
                      IconButton(
                        tooltip: _en ? 'Zoom out' : 'Réduire le zoom',
                        onPressed: () => setState(() => _zoomScale = (_zoomScale - 0.1).clamp(0.8, 2.0).toDouble()),
                        icon: const Icon(Icons.zoom_out, color: Color(0xFF123B70)),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(color: const Color(0xFF123B70), borderRadius: BorderRadius.circular(22)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.description_outlined, size: 17, color: Colors.white),
                            const SizedBox(width: 6),
                            Text('\${safeIndex + 1} / \${pages.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                          ]),
                        ),
                      ),
                      IconButton(
                        tooltip: _en ? 'Zoom in' : 'Agrandir le zoom',
                        onPressed: () => setState(() => _zoomScale = (_zoomScale + 0.1).clamp(0.8, 2.0).toDouble()),
                        icon: const Icon(Icons.zoom_in, color: Color(0xFF123B70)),
                      ),
                      _readerNavButton(
                        icon: Icons.chevron_right_rounded,
                        enabled: safeIndex < pages.length - 1,
                        onPressed: () => _controller.nextPage(duration: const Duration(milliseconds: 240), curve: Curves.easeInOut),
                      ),
                    ],
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
    this.readerId,
    this.pageCourseId,
    this.chapterId,
    required this.title,
    required this.pages,
    required this.fallbackText,
    required this.locale,
  });

  final String? readerId;
  final String? pageCourseId;
  final String? chapterId;
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
      id: widget.readerId ?? 'legacy-course-record-${widget.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}',
      chapterId: widget.chapterId ?? 'legacy-course-record',
      type: ChapterLearningContentType.course,
      titleFr: widget.title,
      titleEn: widget.title,
      position: 0,
      isPublished: true,
      bodyTextFr: widget.fallbackText,
      bodyTextEn: widget.fallbackText,
      pageCourseId: widget.pageCourseId,
      pages: pages,
    );
    return CourseNotebookReaderPage(item: item, locale: widget.locale);
  }
}
