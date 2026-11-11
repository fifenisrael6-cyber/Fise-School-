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
      final target = savedPage.clamp(0, _pages.length - 1);
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
    try {
      final rows = await Supabase.instance.client
          .from('course_pages')
          .select('page_number,image_url')
          .eq('course_id', widget.item.id)
          .order('page_number');
      if (rows.isEmpty) return;
      final pages = <Map<String, dynamic>>[];
      for (final row in rows) {
        final number = (row['page_number'] as num).toInt();
        final path = row['image_url']?.toString() ?? '';
        Uint8List? bytes;
        try {
          if (!forceRetry) {
            bytes = await _localDb.getCachedCoursePageImage(widget.item.id, number);
          }
          if (bytes == null) {
            try {
              bytes = await Supabase.instance.client.storage
                  .from('course-pages').download(path);
            } catch (_) {
              // One automatic retry for transient storage/network failures.
              bytes = await Supabase.instance.client.storage
                  .from('course-pages').download(path);
            }
            await _localDb.cacheCoursePageImage(
              courseId: widget.item.id,
              pageNumber: number,
              bytes: bytes,
            );
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
      final userId = _userId ?? Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        final saved = await _localDb.getCourseReaderState(userId, widget.item.id);
        final page = ((saved?['page_number'] as num?)?.toInt() ?? 0)
            .clamp(0, pages.length - 1);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _controller.hasClients) {
            _controller.jumpToPage(page);
            setState(() => _index = page);
          }
        });
      }
    } catch (_) {
      // Keep the text/notebook version available if no raster pages exist.
    }
  }

  Future<void> _retryCoursePage(int pageNumber) async {
    try {
      final rows = await Supabase.instance.client
          .from('course_pages')
          .select('image_url')
          .eq('course_id', widget.item.id)
          .eq('page_number', pageNumber)
          .limit(1);
      if (rows.isEmpty) throw StateError('Page introuvable.');
      final path = rows.first['image_url'].toString();
      final bytes = await Supabase.instance.client.storage
          .from('course-pages').download(path);
      await _localDb.cacheCoursePageImage(
        courseId: widget.item.id,
        pageNumber: pageNumber,
        bytes: bytes,
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
                                    child: snapshot.data is File
                                        ? Image.file(snapshot.data as File, fit: BoxFit.contain)
                                        : Image.network(snapshot.data.toString(), fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) => Text(_en ? 'Image unavailable' : 'Image indisponible')),
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
