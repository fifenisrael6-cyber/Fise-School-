import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/offline/app_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/rich_lesson_text.dart';
import '../../../core/offline/notebook_image_cache.dart';
import '../../../core/offline/notebook_page_pagination.dart';
import '../../../models/chapter_learning_content.dart';

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
  double _fontSize = 16;
  final AppDatabase _localDb = AppDatabase();
  String? _userId;
  List<Map<String, dynamic>> _pdfPages = const [];
  final Map<int, Object> _pageErrors = {};

  bool get _en => widget.locale.languageCode == 'en';

  Future<void> _restoreReaderState() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    _userId = userId;
    if (userId == null) return;
    try {
      final saved = await _localDb.getCourseReaderState(userId, widget.item.id);
      if (!mounted || saved == null) return;
      final savedSize = (saved['font_size'] as num?)?.toDouble() ?? 16;
      final savedPage = (saved['page_number'] as num?)?.toInt() ?? 0;
      final target = savedPage.clamp(0, _pages.length - 1).toInt();
      setState(() => _fontSize = savedSize.clamp(14, 28).toDouble());
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
        final expectsRasterPages = widget.item.pageCourseId != null ||
            (widget.item.sourcePdfPath ?? '').trim().isNotEmpty;
        if (!expectsRasterPages || !mounted) return;
        setState(() => _pdfPages = [
          {
            'id': 'course-pages-pending',
            'position': 1,
            'blocks': [
              {
                'type': 'raster-pending',
                'message': widget.item.pageCourseId == null
                    ? (_en ? 'No prepared pages are available.' : 'Aucune page préparée n’est disponible.')
                    : (_en
                        ? 'The administrator must prepare this course pages first.'
                        : 'L’administrateur doit d’abord préparer les pages de ce cours.'),
              },
            ],
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
                  TextButton(onPressed: () => updateSheet(() => selected = (selected - 1).clamp(14, 28).toDouble()), child: const Text('A−')),
                  Expanded(child: Slider(
                    min: 14, max: 28, divisions: 14, value: selected,
                    label: selected.round().toString(),
                    onChanged: (value) => updateSheet(() => selected = value),
                  )),
                  TextButton(onPressed: () => updateSheet(() => selected = (selected + 1).clamp(14, 28).toDouble()), child: const Text('A+')),
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

  Widget _buildPage(Map<String, dynamic> page, int number) {
    final rawBlocks = page['blocks'];
    final blocks = rawBlocks is List
        ? rawBlocks.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    return LayoutBuilder(builder: (context, constraints) {
      final availableWidth = constraints.maxWidth - 28;
      final heightLimitedWidth = (constraints.maxHeight - 28) * 210 / 297;
      final width = (availableWidth < heightLimitedWidth ? availableWidth : heightLimitedWidth).clamp(200.0, 794.0).toDouble();
      return Center(
        child: SizedBox(
          width: width,
          child: AspectRatio(
            aspectRatio: 210 / 297,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.fromLTRB(30, 34, 30, 28),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [BoxShadow(color: Color(0x16000000), blurRadius: 12, offset: Offset(0, 4))],
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.item.titleFor(widget.locale.languageCode),
                      style: const TextStyle(fontSize: 22, height: 1.25, fontWeight: FontWeight.w900, color: Color(0xFF14532D))),
                    const Divider(height: 28, color: Color(0xFF16A34A)),
                    for (final block in blocks) ...[
                      if (block['type'] == 'text')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: RichLessonText(
                            text: (block[_en ? 'text_en' : 'text_fr'] ?? block['text'] ?? '').toString(),
                            style: TextStyle(fontSize: _fontSize, height: 1.75, color: const Color(0xFF1E293B)),
                          ),
                        ),
                      if (block['type'] == 'raster' && block['bytes'] is Uint8List)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Image.memory(block['bytes'] as Uint8List, fit: BoxFit.contain),
                        ),
                      if (block['type'] == 'raster-pending')
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              (block['message'] ??
                                  (_en
                                      ? 'Course pages are not available yet.'
                                      : 'Les pages du cours ne sont pas encore disponibles.')).toString(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFF475569)),
                            ),
                          ),
                        ),
                      if (block['type'] == 'raster-pending')
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Center(
                            child: OutlinedButton.icon(
                              onPressed: () => _loadCoursePages(forceRetry: true),
                              icon: const Icon(Icons.refresh),
                              label: Text(_en ? 'Retry' : 'Réessayer'),
                            ),
                          ),
                        ),
                      if (block['type'] == 'raster-error')
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_en ? 'This page could not be loaded.' : 'Cette page n’a pas pu être chargée.'),
                                const SizedBox(height: 8),
                                FilledButton.icon(
                                  onPressed: () => _retryCoursePage((block['page_number'] as num).toInt()),
                                  icon: const Icon(Icons.refresh),
                                  label: Text(_en ? 'Retry' : 'Réessayer'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (block['type'] == 'image' && (block['storage_path'] ?? '').toString().isNotEmpty)
                        FutureBuilder<Object?>(
                          future: _resolveImage(block['storage_path'].toString()),
                          builder: (context, snapshot) => snapshot.data == null
                              ? const Padding(padding: EdgeInsets.all(14), child: Center(child: CircularProgressIndicator()))
                              : Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: InteractiveViewer(
                                    child: GestureDetector(
                                    onTap: () => _openImageGallery(block['storage_path'].toString()),
                                    child: Hero(
                                      tag: 'course-image-${widget.item.id}-${block['storage_path']}',
                                      child: snapshot.data is File
                                          ? Image.file(snapshot.data as File, fit: BoxFit.contain)
                                          : Image.network(snapshot.data.toString(), fit: BoxFit.contain,
                                              errorBuilder: (_, __, ___) => Text(_en ? 'Image unavailable' : 'Image indisponible')),
                                    ),
                                  ),
                                  ),
                                ),
                        ),
                    ],
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Text('${_en ? 'Page' : 'Page'} $number / ${_pages.length}',
                        style: const TextStyle(fontSize: 10, color: Colors.black45)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    unawaited(_localDb.closeDatabase());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    return Scaffold(
      backgroundColor: const Color(0xFFE9EEE9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
        title: Text(widget.item.titleFor(widget.locale.languageCode)),
        actions: [TextButton(onPressed: _showFontControls, child: const Text('Aa', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)))],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: pages.length,
              onPageChanged: (index) {
                setState(() => _index = index);
                unawaited(_saveReaderState());
              },
              itemBuilder: (context, index) => _buildPage(pages[index], index + 1),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: _index == 0 ? null : () => _controller.previousPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Text('${_en ? 'Page' : 'Page'} ${_index + 1} / ${pages.length}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF166534))),
                  IconButton(
                    onPressed: _index >= pages.length - 1 ? null : () => _controller.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
  final PageController _controller = PageController();
  int _index = 0;
  bool get _en => widget.locale.languageCode == 'en';

  List<Map<String, dynamic>> get _pages => widget.pages.isNotEmpty
      ? NotebookPagePagination.expandLegacyPages(widget.pages)
      : [
          {'id': 'legacy-page-1', 'position': 1, 'format': 'A4', 'blocks': [{'type': 'text', 'text_fr': widget.fallbackText, 'text_en': widget.fallbackText}]},
        ];

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

  Widget _page(Map<String, dynamic> page, int number) {
    final raw = page['blocks'];
    final blocks = raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    return LayoutBuilder(builder: (context, constraints) {
      final availableWidth = constraints.maxWidth - 28;
      final heightLimitedWidth = (constraints.maxHeight - 28) * 210 / 297;
      final width = (availableWidth < heightLimitedWidth ? availableWidth : heightLimitedWidth).clamp(200.0, 794.0).toDouble();
      return Center(
        child: SizedBox(
          width: width,
          child: AspectRatio(
            aspectRatio: 210 / 297,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.fromLTRB(30, 34, 30, 28),
              color: Colors.white,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF14532D))),
                    const Divider(height: 28, color: Color(0xFF16A34A)),
                    for (final block in blocks) ...[
                      if (block['type'] == 'text')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: RichLessonText(
                            text: (block[_en ? 'text_en' : 'text_fr'] ?? block['text'] ?? '').toString(),
                            style: const TextStyle(fontSize: 15.5, height: 1.75, color: Color(0xFF1E293B)),
                          ),
                        ),
                      if (block['type'] == 'image' && (block['storage_path'] ?? '').toString().isNotEmpty)
                        FutureBuilder<Object?>(
                          future: _resolveImage(block['storage_path'].toString()),
                          builder: (context, snapshot) => snapshot.data == null
                              ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())
                              : Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: snapshot.data is File ? Image.file(snapshot.data as File, fit: BoxFit.contain) : Image.network(snapshot.data.toString(), fit: BoxFit.contain),
                                ),
                        ),
                    ],
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Text('${_en ? 'Page' : 'Page'} $number / ${_pages.length}',
                        style: const TextStyle(fontSize: 10, color: Colors.black45)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    return Scaffold(
      backgroundColor: const Color(0xFFE9EEE9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: Column(children: [
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: pages.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) => _page(pages[index], index + 1),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: _index == 0 ? null : () => _controller.previousPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Text('${_en ? 'Page' : 'Page'} ${_index + 1} / ${pages.length}',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF166534))),
                IconButton(
                  onPressed: _index >= pages.length - 1 ? null : () => _controller.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
