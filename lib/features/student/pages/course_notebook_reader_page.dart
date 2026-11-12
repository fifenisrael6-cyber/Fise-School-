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
  double _fontSize = 20;
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
      final savedSize = (saved['font_size'] as num?)?.toDouble() ?? 20;
      final savedPage = (saved['page_number'] as num?)?.toInt() ?? 0;
      final target = savedPage.clamp(0, _pages.length - 1).toInt();
      setState(() => _fontSize = savedSize.clamp(18, 30).toDouble());
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
                  TextButton(onPressed: () => updateSheet(() => selected = (selected - 1).clamp(18, 30).toDouble()), child: const Text('A−')),
                  Expanded(child: Slider(
                    min: 18, max: 30, divisions: 12, value: selected,
                    label: selected.round().toString(),
                    onChanged: (value) => updateSheet(() => selected = value),
                  )),
                  TextButton(onPressed: () => updateSheet(() => selected = (selected + 1).clamp(18, 30).toDouble()), child: const Text('A+')),
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
    if (blocks.length == 1 &&
        blocks.first['type'] == 'raster' &&
        blocks.first['bytes'] is Uint8List) {
      return ColoredBox(
        color: Colors.white,
        child: SizedBox.expand(
          child: Image.memory(
            blocks.first['bytes'] as Uint8List,
            fit: BoxFit.contain,
            alignment: Alignment.center,
          ),
        ),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final horizontalPadding = constraints.maxWidth < 420 ? 20.0 : 28.0;
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(horizontalPadding, 58, horizontalPadding, 54),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.item.titleFor(widget.locale.languageCode),
              style: TextStyle(fontSize: _fontSize + 5, height: 1.2, fontWeight: FontWeight.w900, color: const Color(0xFF14532D))),
            const Divider(height: 24, color: Color(0xFF16A34A)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final block in blocks) ...[
                    if (block['type'] == 'text')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: RichLessonText(
                          text: (block[_en ? 'text_en' : 'text_fr'] ?? block['text'] ?? '').toString(),
                          style: TextStyle(fontSize: _fontSize, height: 1.55, color: const Color(0xFF1E293B)),
                        ),
                      ),
                    if (block['type'] == 'raster' && block['bytes'] is Uint8List)
                      Expanded(child: Image.memory(block['bytes'] as Uint8List, fit: BoxFit.contain)),
                    if (block['type'] == 'raster-pending')
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text((block['message'] ??
                                (_en ? 'Course pages are not available yet.' : 'Les pages du cours ne sont pas encore disponibles.')).toString(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Color(0xFF475569))),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: () => _loadCoursePages(forceRetry: true),
                                icon: const Icon(Icons.refresh),
                                label: Text(_en ? 'Retry' : 'Réessayer'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (block['type'] == 'raster-error')
                      Expanded(
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
                          ? const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
                          : Flexible(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
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
                      ),
                  ],
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Text('Page ' + number.toString() + ' / ' + totalPages.toString(),
                style: const TextStyle(fontSize: 11, color: Colors.black45)),
            ),
          ],
        ),
      );
    });
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
      contentWidth: width - 60,
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final pages = _pagesForLayout(
            constraints.maxWidth - 40,
            constraints.maxHeight - 106,
          );
          final safeIndex = _index.clamp(0, pages.length - 1).toInt();
          if (_controller.hasClients &&
              _controller.page != null &&
              _controller.page!.round() != safeIndex) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _controller.hasClients &&
                  (_controller.page?.round() ?? safeIndex) != safeIndex) {
                _controller.jumpToPage(safeIndex);
              }
            });
          }
          return Stack(
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
                itemBuilder: (context, index) =>
                    _buildPage(pages[index], index + 1, pages.length),
              ),
              Positioned(
                top: 8,
                right: 10,
                child: Material(
                  color: const Color(0xCC166534),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: _en ? 'Text settings' : 'Taille du texte',
                    onPressed: _showFontControls,
                    icon: const Icon(Icons.text_fields, color: Colors.white),
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _readerNavButton(
                      icon: Icons.chevron_left_rounded,
                      enabled: safeIndex > 0,
                      onPressed: () => _controller.previousPage(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeInOut,
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xE6166534),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                        child: Text(
                          'Page ' + (safeIndex + 1).toString() + ' / ' + pages.length.toString(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    _readerNavButton(
                      icon: Icons.chevron_right_rounded,
                      enabled: safeIndex < pages.length - 1,
                      onPressed: () => _controller.nextPage(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeInOut,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

}
